import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'dart:math';
import 'game_map.dart';
import 'mask_data.dart';
import 'flying_scare_blast.dart';
import 'critter.dart';
import 'scare_blast.dart';

// ==========================================
// 1. FLUTTER UI: ROOM SELECTOR
// ==========================================
class SpectatorLobbyScreen extends StatefulWidget {
  const SpectatorLobbyScreen({super.key});

  @override
  State<SpectatorLobbyScreen> createState() => _SpectatorLobbyScreenState();
}

class _SpectatorLobbyScreenState extends State<SpectatorLobbyScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _activeRooms = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRooms();
  }

  Future<void> _fetchRooms() async {
    try {
      // 1. Calculate the cutoff time for 5 minutes ago (UTC)
      final fiveMinutesAgo = DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String();

      // 2. Query Supabase, filtering for rooms modified or created within the last 5 minutes
      final response = await supabase
          .from('active_matches')
          .select('id, player_count, status, created_at, updated_at, map_name')
          .gte('created_at', fiveMinutesAgo) // Ignore anything older than 5 mins
          .order('created_at', ascending: false)
          .limit(20);
      
      if (mounted) {
        final allRooms = List<Map<String, dynamic>>.from(response);
        final liveRooms = allRooms.where((room) {
          return room['status'] == 'waiting' || room['status'] == 'playing';
        }).toList();

        setState(() {
          _activeRooms = liveRooms;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching spectator rooms: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SPECTATE: Live Matches', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchRooms),
        ],
      ),
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
          : ListView.builder(
              itemCount: _activeRooms.length,
              itemBuilder: (context, index) {
                final room = _activeRooms[index];
                return ListTile(
                  title: Text('Room: ${room['id']}', style: const TextStyle(color: Colors.white)),
                  subtitle: Text('Players: ${room['player_count']} | Status: ${room['status']}', style: const TextStyle(color: Colors.grey)),
                  trailing: const Icon(Icons.remove_red_eye, color: Colors.redAccent),
                  onTap: () {
                    // NEW: The Stack implementation with the Back Button Overlay
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => Scaffold(
                          body: Stack(
                            children: [
                              // Layer 1: The Flame Game
                              GameWidget<SpectatorGame>(
                                game: SpectatorGame(
                                  roomId: room['id'], 
                                  mapName: room['map_name'] ?? 'L1T1V1.0.0', 
                                ),
                                overlayBuilderMap: {
                                  'spectator_summary': (context, SpectatorGame game) => SpectatorSummaryOverlay(game: game),
                                },
                              ),
                              // Layer 2: The Flutter Back Button
                              Positioned(
                                top: 40, // Keeps it below the physical notch on most phones
                                left: 20,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
                                    onPressed: () => Navigator.of(context).pop(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

// ==========================================
// 2. FLAME ENGINE: SPECTATOR CLIENT
// ==========================================
class SpectatorGame extends FlameGame with PanDetector {
  final String roomId;
  final String mapName; // 1. Add the variable

  // 2. Add it to the constructor (Default to Map 1 for now)
  SpectatorGame({required this.roomId, this.mapName = 'L1T1V1.0.0'});

  late final GameMap gameMap;
  late final RealtimeChannel ghostChannel;

  Map<String, SpectatorDot> humanPlayers = {};
  Map<int, SpectatorDot> botPlayers = {};

  @override
  Future<void> onLoad() async {
    // 3. Pass BOTH variables to GameMap
    gameMap = GameMap(roomId: roomId, mapName: mapName);
    await world.add(gameMap);
    
    // ... the rest of the onLoad method stays exactly the same!

    final mapWidth = gameMap.gridWidth * gameMap.tileSize;
    final mapHeight = gameMap.gridHeight * gameMap.tileSize;
    camera.viewfinder.position = Vector2(mapWidth / 2, mapHeight / 2);
    camera.viewfinder.anchor = Anchor.center;
    
    // NEW: Zoom out to see the map
    camera.viewfinder.zoom = 0.35; 

    // Connect as a silent ghost (Do not send presence sync events)
    ghostChannel = Supabase.instance.client.channel('room_$roomId');

    ghostChannel
      .onBroadcast(
        event: 'move',
        callback: (payload) {
          final id = payload['id'] as String;
          final x = payload['x'] as double;
          final y = payload['y'] as double;
          final colorStr = payload['c'] as String?;
          final score = payload['s'] as int?; 

          if (!humanPlayers.containsKey(id)) {
            final newDot = SpectatorDot(isBot: false)..position = Vector2(x, y);
            humanPlayers[id] = newDot;
            world.add(newDot);
          } else {
            humanPlayers[id]!.updatePosition(x, y);
            if (colorStr != null) humanPlayers[id]!.setCosmeticColor(colorStr);
            if (score != null) humanPlayers[id]!.updateScore(score);
          }
        },
      )
      .onBroadcast(
        event: 'sync_bots',
        callback: (payload) {
          final botList = payload['bots'] as List<dynamic>;
          
          for (int i = 0; i < botList.length; i++) {
            final data = botList[i] as Map<String, dynamic>;
            final x = data['x'] as double;
            final y = data['y'] as double;

            if (!botPlayers.containsKey(i)) {
              final newDot = SpectatorDot(isBot: true)..position = Vector2(x, y);
              botPlayers[i] = newDot;
              world.add(newDot);
            } else {
              botPlayers[i]!.updatePosition(x, y);
            }
          }
        },
      )
      .onBroadcast(
        event: 'stun',
        callback: (payload) {
          final victimId = payload['id'] as String?;
          final attackerId = payload['attacker_id'] as String?;

          // Flash the victim Cyan
          if (victimId != null && humanPlayers.containsKey(victimId)) {
            humanPlayers[victimId]!.triggerFlash(Colors.cyanAccent);
          }
          // Flash the successful attacker Yellow!
          if (attackerId != null && humanPlayers.containsKey(attackerId)) {
            humanPlayers[attackerId]!.triggerFlash(Colors.yellowAccent);
          }
        },
      )
      .onBroadcast(
        event: 'scare',
        callback: (payload) {
          final id = payload['id'] as String?;
          final attackerId = payload['attacker_id'] as String?;

          // Spawning the blasts for spectators!
          if (id != null && humanPlayers.containsKey(id)) {
            final remote = humanPlayers[id]!;
            final angle = payload['a'] as double;
            final maskId = payload['mask_id'] as String? ?? 'standard';
            final seed = payload['seed'] as int? ?? 0;

            if (maskId == 'flying') {
              world.add(FlyingScareBlast(position: remote.position.clone(), angle: angle));
            } else if (maskId == 'vermin') {
              for (int i = 0; i < 15; i++) {
                world.add(Critter(
                  position: remote.position.clone(),
                  behavior: SwarmBehavior.scatter,
                  seed: seed,
                  index: i,
                  initialAngle: angle,
                  ownerId: id, // Assign ownership
                ));
              }
            } else {
              world.add(ScareBlast(position: remote.position, angle: angle - (pi / 2)));
            }
          }

          // Visual flashes for the dots
          final victimId = payload['id'] as String?;
          if (victimId != null && humanPlayers.containsKey(victimId)) {
            humanPlayers[victimId]!.triggerFlash(Colors.cyanAccent);
          }
          if (attackerId != null && humanPlayers.containsKey(attackerId)) {
            humanPlayers[attackerId]!.triggerFlash(Colors.yellowAccent);
          }
        },
      )
      .onBroadcast(
        event: 'match_control',
        callback: (payload) {
          final action = payload['action'] as String;
          if (action == 'end') {
            overlays.add('spectator_summary');
          } else if (action == 'start') {
            overlays.remove('spectator_summary');
            // Clear the scores for the new round
            for (var human in humanPlayers.values) {
              human.updateScore(0);
            }
          }
        },
      )
      .subscribe();
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    // NEW: Divide by zoom so the pan speed matches the finger exactly
    camera.viewfinder.position -= (info.delta.global / camera.viewfinder.zoom);
  }

  @override
  void onRemove() {
    ghostChannel.unsubscribe();
    super.onRemove();
  }
}

// ==========================================
// 3. SPECTATOR RADAR DOT & UI
// ==========================================
class SpectatorDot extends CircleComponent {
  final bool isBot;
  double flashTimer = 0;
  Color baseColor;
  late TextComponent scoreText;

  int currentScore = 0;

  SpectatorDot({required this.isBot}) 
      : baseColor = isBot ? Colors.grey : Colors.redAccent,
        super(radius: 16.0, anchor: Anchor.center) {
    paint = Paint()..color = baseColor;
  }

  @override
  Future<void> onLoad() async {
    if (!isBot) {
      scoreText = TextComponent(
        text: '0',
        position: Vector2(radius, -10),
        anchor: Anchor.bottomCenter,
        textRenderer: TextPaint(
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
        ),
      );
      add(scoreText);
    }
  }

  void updatePosition(double newX, double newY) {
    position.x = newX;
    position.y = newY;
  }

  void updateScore(int score) {
    if (!isBot)  {
      currentScore = score;
      scoreText.text = score.toString();
    }    
  }

  void setCosmeticColor(String colorStr) {
    if (isBot) return;
    switch (colorStr) {
      case 'green': baseColor = Colors.greenAccent; break;
      case 'purple': baseColor = Colors.purpleAccent; break;
      case 'blue': baseColor = Colors.cyanAccent; break;
      case 'red':
      default: baseColor = Colors.redAccent; break;
    }
    if (flashTimer <= 0) paint.color = baseColor;
  }

  void triggerFlash(Color flashColor) {
    paint.color = flashColor;
    flashTimer = 0.5; 
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (flashTimer > 0) {
      flashTimer -= dt;
      if (flashTimer <= 0) {
        paint.color = baseColor; 
      }
    }
  }
}

// ==========================================
// 4. SPECTATOR SCOREBOARD OVERLAY
// ==========================================
class SpectatorSummaryOverlay extends StatelessWidget {
  final SpectatorGame game;

  const SpectatorSummaryOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> scores = [];
    
    game.humanPlayers.forEach((id, dot) {
      final shortId = id.length >= 4 ? id.substring(0, 4) : id;
      scores.add({'name': 'Player $shortId', 'score': dot.currentScore});
    });

    scores.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          width: 350,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.95),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.redAccent, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('MATCH RESULTS', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2)),
              const SizedBox(height: 24),
              
              if (scores.isEmpty)
                const Text('No humans connected.', style: TextStyle(color: Colors.grey)),
                
              ...scores.map((s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(s['name'], style: const TextStyle(color: Colors.white, fontSize: 18)),
                    Text('${s['score']}', style: const TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              )),
              
              const SizedBox(height: 32),
              const Text('WAITING FOR HOST TO RESTART...', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}