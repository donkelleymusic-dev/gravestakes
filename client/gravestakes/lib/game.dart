import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/palette.dart';
import 'package:flutter/painting.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'player.dart';
import 'remote_player.dart';
import 'bot_player.dart'; 
import 'game_map.dart';
import 'darkness_overlay.dart';
import 'jump_scare_effect.dart';
import 'score_hud.dart';
import 'game_timer.dart';
import 'start_button.dart';
import 'attack_button.dart';
import 'player_hud.dart';

class GraveStakesGame extends FlameGame with HasKeyboardHandlerComponents {
  // Optional room ID so party members can queue into a shared private room
  final String roomId;
  final bool isGunner;
  
  GraveStakesGame({this.roomId = 'public_match', this.isGunner = false});

  late final JoystickComponent leftJoystick;
  late final JoystickComponent rightJoystick;
  late final Player player;

  // true multiplayer, with switchable host control rather than central api
  late final String mySessionId; 
  bool isHost = false; 
  Map<String, RemotePlayer> networkPlayers = {}; // Tracks all other players in the room

  late final JumpScareEffect jumpScareEffect;
  late final GameMap gameMap; // Map reference

  late final GameTimer gameTimer;
  late final ScoreHud scoreHud;
  bool gameStarted = false;
  
  final List<BotPlayer> bots = [];
  late final RealtimeChannel myChannel;

  // 1. DEFINE STANDARD SAFE SPAWN POINTS
  final List<Vector2> baseSpawnPoints = [
    Vector2(0, 0),         // Center
    Vector2(800, 800),     // Bottom Right
    Vector2(-800, -800),   // Top Left
    Vector2(800, -800),    // Top Right
    Vector2(-800, 800),    // Bottom Left
    Vector2(1200, 0),      // Far Right
    Vector2(-1200, 0),     // Far Left
    Vector2(0, 1200),      // Far Bottom
  ];

  @override
  Future<void> onLoad() async {
    // Initialize session ID and channel using the passed roomId
    mySessionId = DateTime.now().millisecondsSinceEpoch.toString();
    myChannel = Supabase.instance.client.channel('room_$roomId');

    camera.viewfinder.anchor = Anchor.topLeft;
    
    await FlameAudio.audioCache.load('ElevenLabs_Scary_stinger.mp3');

    // Center the physical player hitbox to match the flashlight:
    camera.viewfinder.anchor = Anchor.center;

    // 1. BUILD THE JOYSTICKS FIRST
    final knobPaint = BasicPalette.white.withAlpha(100).paint();
    final backgroundPaint = BasicPalette.white.withAlpha(40).paint();

    // LEFT JOYSTICK (Movement)
    leftJoystick = JoystickComponent(
      knob: CircleComponent(radius: 20, paint: knobPaint),
      background: CircleComponent(radius: 60, paint: backgroundPaint),
      margin: const EdgeInsets.only(left: 40, bottom: 40),
      priority: 100,
    );

    // RIGHT JOYSTICK (Aiming)
    rightJoystick = JoystickComponent(
      knob: CircleComponent(radius: 20, paint: Paint()..color = Colors.redAccent.withAlpha(204)),
      background: CircleComponent(radius: 60, paint: backgroundPaint),
      margin: const EdgeInsets.only(right: 40, bottom: 40),
      priority: 100,
    );

    // 2. Initialize map and world items
    gameMap = GameMap();
    world.add(gameMap);

    // 3. SAFE SPAWNING
    List<Vector2> availableSpawns = List.from(baseSpawnPoints)..shuffle();
    final mySpawnPoint = availableSpawns.removeAt(0);

    // Pass both joysticks and the role flag to the player
    player = Player(leftJoystick, rightJoystick, myChannel, isGunner: isGunner)..position = mySpawnPoint;
    jumpScareEffect = JumpScareEffect();

    world.add(player);
    
    // We defer spawning bots until the host is established in the network listener!
    camera.follow(player);

    // ==========================================
    // 3. VIEWPORT & UI LAYER 
    // ==========================================
    camera.viewport.add(DarknessOverlay(player)); 
    camera.viewport.add(jumpScareEffect);

    // === DYNAMIC JOYSTICKS ===
    if (isGunner) {
      // Gunners cannot move, they only get the aiming stick
      camera.viewport.add(rightJoystick);
    } else {
      // Drivers and Solo players get the movement stick
      camera.viewport.add(leftJoystick);
    }

    camera.viewport.add(ScoreHud());
    camera.viewport.add(gameTimer = GameTimer());
    camera.viewport.add(StartButton());
    camera.viewport.add(AttackButton());

    camera.viewport.add(PlayerHud());

    _setupSupabaseListener();
  }

  // Method to safely spawn bots called by the Host once elected
  void _spawnBotsSafely() {
    if (bots.isNotEmpty) return; // Don't spawn twice
    
    List<Vector2> availableSpawns = List.from(baseSpawnPoints)..shuffle();
    const int numberOfBots = 5; 
      
    for (int i = 0; i < numberOfBots; i++) {
      Vector2 botSpawn;
      if (availableSpawns.isNotEmpty) {
        botSpawn = availableSpawns.removeAt(0);
      } else {
        botSpawn = Vector2(500.0 + (i * 100), 500.0); // Fallback if points run out
      }

      final bot = BotPlayer()..position = botSpawn;
      bots.add(bot);
      world.add(bot);
    }
  }

  Future<void> endGame() async {
    gameStarted = false; // Freeze gameplay

    // 1. Calculate Rewards (e.g., 100 score = 10 XP and 5 Shadows)
    final xpEarned = (player.score * 0.1).toInt();
    final shadowsEarned = (player.score * 0.05).toInt();

    // 2. Send to Supabase safely!
    if (player.score > 0) {
      try {
        await Supabase.instance.client.rpc(
          'process_match_rewards',
          params: {
            'xp_earned': xpEarned,
            'shadows_earned': shadowsEarned,
          },
        );
        print('Payout successful: $xpEarned XP, $shadowsEarned Shadows');
      } catch (e) {
        print('Failed to save rewards: $e');
      }
    }

    // 3. Reset local player state for the next round
    player.score = 0;
    
    // Pick a new safe spawn point for the next round
    List<Vector2> availableSpawns = List.from(baseSpawnPoints)..shuffle();
    player.position = availableSpawns.first;
    
    // 4. Bring the start button back!
    camera.viewport.add(StartButton()); 
    
    // 5. Tell the HUD to refresh the new totals on the screen!
    final hud = camera.viewport.children.whereType<PlayerHud>().firstOrNull;
    hud?.fetchPlayerData();
  }
  
  // Now accepts angle to calculate the directional cone
  int triggerLocalScare(Vector2 attackerPos, double attackerAngle) {
    int hitCount = 0;
    
    // Calculate the forward vector based on where the player is facing
    final forward = Vector2(cos(attackerAngle), sin(attackerAngle));
    const double scareRadius = 250.0;

    // 1. Check Bots
    for (var bot in bots) {
      final toBot = bot.position - attackerPos;
      final distance = toBot.length;

      if (distance < scareRadius) {
        toBot.normalize();
        final dot = forward.dot(toBot); // Measures alignment (-1 behind, +1 directly in front)

        if (dot > 0.1) {
          if (gameMap.hasLineOfSight(bot.position, attackerPos)) {
            bot.applyStun(4.0); 
            hitCount++;
          }
        }
      }
    }

    // 2. Check Remote Human Players
    for (var remotePlayer in networkPlayers.values) {
      final toPlayer = remotePlayer.position - attackerPos;
      final distance = toPlayer.length;

      if (distance < scareRadius) {
        toPlayer.normalize();
        final dot = forward.dot(toPlayer);

        if (dot > 0.3) {
          if (gameMap.hasLineOfSight(remotePlayer.position, attackerPos)) {
            hitCount++;
          }
        }
      }
    }

    return hitCount;
  }
  
  void triggerLocalStart() {
    gameStarted = true;
    gameTimer.start();
  }

  // The Start Button calls this to tell everyone to start
  void broadcastStartGame() {
    myChannel.sendBroadcastMessage(
      event: 'match_control',
      payload: {'action': 'start'},
    );
    triggerLocalStart(); // Start it for ourselves too
  }

  void _setupSupabaseListener() {
    myChannel
      .onPresenceSync((payload) {
        final presenceState = myChannel.presenceState();
        List<Map<String, dynamic>> allUsers = [];
        
        // 1. Gather everyone currently connected
        for (final state in presenceState) {
          for (final presence in state.presences) {
            if (presence.payload != null && presence.payload.containsKey('id')) {
              allUsers.add({
                'id': presence.payload['id'],
                'joined_at': presence.payload['joined_at'],
              });
            }
          }
        }

        // 2. Sort by join time to find the "Eldest"
        allUsers.sort((a, b) => (a['joined_at'] as String).compareTo(b['joined_at'] as String));

        // 3. Crown the Host & Spawn Bots!
        if (allUsers.isNotEmpty && allUsers.first['id'] == mySessionId) {
          if (!isHost) {
            isHost = true;
            _spawnBotsSafely(); // Spawn bots now that we are officially the host
          }
        } else {
          isHost = false;
        }

        // 4. Spawn RemotePlayers for anyone new
        for (var user in allUsers) {
          final id = user['id'] as String;
          if (id != mySessionId && !networkPlayers.containsKey(id)) {
            final newPlayer = RemotePlayer()..position = Vector2(-100, -100);
            networkPlayers[id] = newPlayer;
            world.add(newPlayer);
          }
        }

        // 5. Destroy RemotePlayers who disconnected
        final activeIds = allUsers.map((u) => u['id']).toSet();
        networkPlayers.keys.toList().forEach((id) {
          if (!activeIds.contains(id)) {
            networkPlayers[id]?.removeFromParent();
            networkPlayers.remove(id);
          }
        });
      })
      .onBroadcast(
        event: 'move',
        callback: (payload) {
          final id = payload['id'] as String?;
          if (id != null && id != mySessionId) {
            final x = payload['x'] as double;
            final y = payload['y'] as double;
            final angle = payload['a'] as double;
            final colorStr = payload['c'] as String?; 

            // THE TETHER LOGIC FOR CO-OP
            // If I am the gunner, and the Driver moves, snap my position to their back!
            if (isGunner) {
              final driverBackward = Vector2(cos(angle + pi), sin(angle + pi));
              player.position.x = x + (driverBackward.x * 20); // 20 pixels behind
              player.position.y = y + (driverBackward.y * 20);
            }

            if (networkPlayers.containsKey(id)) {
              networkPlayers[id]!.updatePosition(x, y, angle, colorStr: colorStr);
            }
          }
        },
      )
      .onBroadcast(
        event: 'scare',
        callback: (payload) {
          final id = payload['id'] as String?;
          if (id != null && id != mySessionId && networkPlayers.containsKey(id)) {
            final remote = networkPlayers[id]!;
            remote.position.x = payload['x'] as double;
            remote.position.y = payload['y'] as double;
            remote.angle = payload['a'] as double;
          }
        },
      )
      .onBroadcast(
        event: 'match_control',
        callback: (payload) {
          final action = payload['action'] as String;
          if (action == 'start') {
            triggerLocalStart();
          } else if (action == 'end') {
            endGame();
          }
        },
      )
      .onBroadcast(
        event: 'request_sync',
        callback: (payload) {
          if (isHost) {
            myChannel.sendBroadcastMessage(
              event: 'sync_state',
              payload: {
                'gameStarted': gameStarted,
                'timeLeft': gameTimer.timeLeft,
              },
            );
          }
        },
      )
      .onBroadcast(
        event: 'bot_move',
        callback: (payload) {
          if (!isHost) {
            final index = payload['index'] as int;
            if (index >= 0 && index < bots.length) {
              bots[index].position.x = payload['x'] as double;
              bots[index].position.y = payload['y'] as double;
              bots[index].angle = payload['a'] as double;
            }
          }
        },
      )
      .onBroadcast(
        event: 'sync_state',
        callback: (payload) {
          if (!isHost) {
            final isRunning = payload['gameStarted'] as bool;
            final time = (payload['timeLeft'] as num).toDouble();
            
            gameTimer.timeLeft = time; 
            
            if (isRunning && !gameStarted) {
              triggerLocalStart();
              
              camera.viewport.children
                  .whereType<StartButton>()
                  .forEach((btn) => btn.removeFromParent());
                  
            } else if (!isRunning && gameStarted) {
              endGame();
            }
          }
        },
      )
      .subscribe((status, [error]) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await myChannel.track({
            'id': mySessionId, 
            'joined_at': DateTime.now().toUtc().toIso8601String()
          });

          myChannel.sendBroadcastMessage(
            event: 'request_sync',
            payload: {}, 
          );
        }
      });
  }

  @override
  void onRemove() {
    myChannel.unsubscribe();
    super.onRemove();
  }
}