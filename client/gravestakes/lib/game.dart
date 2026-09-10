import 'dart:math';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/palette.dart';
import 'package:flutter/painting.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'player.dart';
import 'remote_player.dart';
import 'floating_text.dart';
import 'bot_player.dart'; 
import 'game_map.dart';
import 'darkness_overlay.dart';
import 'jump_scare_effect.dart';
import 'score_hud.dart';
import 'game_timer.dart';
import 'start_button.dart';
import 'attack_button.dart';
import 'defense_button.dart';
import 'player_hud.dart';
import 'scare_blast.dart';
import 'level_manager.dart';
import 'tutorial_manager.dart';
import 'power_up.dart';
import 'power_up_hud.dart';
import 'spooky_box.dart';
import 'special_button.dart';
import 'chest_reward.dart';
import 'mask_data.dart';
import 'flying_scare_blast.dart';
import 'critter.dart';
import 'vessel_opener_overlay.dart';
import 'scare_manager.dart';
import 'flashlight_hud.dart';
import 'siren_blast.dart';
import 'map_overlay.dart';
import 'map_button.dart';
import 'fps_viewport_overlay.dart';
import 'mode_toggle_button.dart';
import 'fps_touch_controls.dart';
import 'audio_manager.dart';
import 'character_asset_manager.dart';

class ScareSnapshot {
  final String attackerName;
  final String attackerCharId;
  final String attackerMaskId;
  final String victimName;
  final String victimCharId;
  final int timestamp; // To show "Scare occurred at 2:14"
  final double mapX;
  final double mapY;

  ScareSnapshot({
    required this.attackerName,
    required this.attackerCharId,
    required this.attackerMaskId,
    required this.victimName,
    required this.victimCharId,
    required this.timestamp,
    required this.mapX,
    required this.mapY,
  });
}

class GraveStakesGame extends FlameGame with HasKeyboardHandlerComponents, HasCollisionDetection {
  static List<ScareSnapshot> lastMatchPhotos = [];
  String roomId;
  final bool isGunner;
  final String matchMode; 
  final String mapName;
  final int targetPlayers;
  final bool isGuildScrimmage;
  final String? scrimmageMessageId;
  String guildActiveDoctrine = 'none';

  bool isWaitingInLobby = true;

  bool matchHasHunter = false;
  bool hunterHasSpawned = false;

  String matchPhase = 'searching'; 
  double lobbyTimer = 10.0;
  double countdownTimer = 3.0;
  int _lastTick = 3;
  
  static Map<String, Map<String, ui.Image>> characterImagesCache = {};
  static Map<String, Map<String, dynamic>> characterRigCache = {};
  
  Map<String, ui.Image> loadedAssetImages = {};
  Map<String, dynamic>? loadedRigData;
  bool isFpsMode = false;

  Map<String, int> playerTeams = {};

  bool _matchesDoctrine(dynamic target) {
    if (guildActiveDoctrine == 'none') return false;
    String targetSpecies = 'humanoid'; 
    try {
      targetSpecies = target.species ?? 'humanoid';
    } catch (_) {
      targetSpecies = 'humanoid';
    }
    return targetSpecies == guildActiveDoctrine;
  }

  int getEntityTeam(dynamic entity) {
    if (matchMode != '2v2') return 0; 
    
    if (entity is Player) return playerTeams[mySessionId] ?? 1;
    if (entity is BotPlayer) return entity.teamId;
    if (entity is String) return playerTeams[entity] ?? 0; 
    
    if (entity is RemotePlayer) {
      String? remoteId;
      networkPlayers.forEach((key, val) { if (val == entity) remoteId = key; });
      return playerTeams[remoteId] ?? 0;
    }
    return 0;
  }
  
  GraveStakesGame({
    this.roomId = 'public_match', 
    this.isGunner = false,
    this.mapName = 'L1T1V1.0.0',
    this.matchMode = 'casual',
    this.targetPlayers = 8,
    this.isGuildScrimmage = false,
    this.scrimmageMessageId,
  });

  late final JoystickComponent leftJoystick;
  late final JoystickComponent rightJoystick;
  late final Player player;
  late final ScareManager scareManager;

  late final String mySessionId; 
  bool isHost = false; 
  Map<String, RemotePlayer> networkPlayers = {}; 

  late final JumpScareEffect jumpScareEffect;
  late final GameMap gameMap; 

  late MapOverlay mapOverlay;

  late final GameTimer gameTimer;
  late final ScoreHud scoreHud;
  bool gameStarted = false;
  int myPlayerLevel = 1; 
  
  final List<BotPlayer> bots = [];
  final List<ScareSnapshot> matchPhotos = [];

  final int maxMatchPhotos = Random().nextDouble() < 0.20 ? 2 : 1;

  void logScareSnapshot(ScareSnapshot snapshot, {required bool isHuman}) {
    // 1. One snapshot max per victim ID to prevent duplicates of the same player
    if (matchPhotos.any((p) => p.victimName == snapshot.victimName)) return;

    // 2. Add normally if under capacity
    if (matchPhotos.length < maxMatchPhotos) {
      matchPhotos.add(snapshot);
      return;
    }

    // 3. If full, a human scare will overwrite an existing bot scare
    if (isHuman) {
      int botIndex = matchPhotos.indexWhere((p) => !p.victimName.startsWith('Player '));
      if (botIndex != -1) {
        matchPhotos[botIndex] = snapshot;
      }
    }
  }

  double hostBotSyncTick = 0;
  final double hostBotSyncRate = 0.12;

  late final RealtimeChannel myChannel;

  void broadcastStartGame() async {
    myChannel.sendBroadcastMessage(event: 'match_control', payload: {'action': 'start'});
    triggerLocalStart(); 
    try {
      await Supabase.instance.client.from('active_matches').update({'status': 'playing'}).eq('id', roomId);
    } catch (e) {}
  }

  void resetForNextRound() async {
    overlays.remove('summary'); 
    player.score = 0;
    player.hasExtendedRange = false; 
    player.isDisguised = false;      
    player.isInvisible = false;      

    for (var remote in networkPlayers.values) remote.score = 0; 
    
    List<Vector2> availableSpawns = List.from(baseSpawnPoints)..shuffle();
    player.position = gameMap.getSafeSpawnLocation(availableSpawns.first, Vector2.all(32.0));
    camera.viewport.add(StartButton()); 
    final hud = camera.viewport.children.whereType<PlayerHud>().firstOrNull;
    hud?.fetchPlayerData();

    if (isHost) {
      try {
        await Supabase.instance.client.from('active_matches').update({'status': 'waiting'}).eq('id', roomId);
      } catch (e) {}
    }
  }

  final List<Vector2> baseSpawnPoints = [
    Vector2(150, 150),     
    Vector2(1770, 1770),   
    Vector2(1770, 150),    
    Vector2(150, 1770),    
    Vector2(960, 150),     
    Vector2(960, 1770),    
    Vector2(150, 960),     
    Vector2(1770, 960),    
  ];

  Future<void> _loadVoxelAssets() async {
    try {
      // ONLY load the default base mesh on startup. Do not query the DB!
      final ByteData data = await rootBundle.load('assets/character_assets.zip');
      final List<int> bytes = data.buffer.asUint8List();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      for (final file in archive) {
        if (file.isFile) {
          if (file.name == 'rig.json') {
            final jsonStr = utf8.decode(file.content as List<int>);
            loadedRigData = jsonDecode(jsonStr);
          } else if (file.name.endsWith('.png')) {
            final ui.Codec codec = await ui.instantiateImageCodec(file.content as Uint8List);
            final ui.FrameInfo frameInfo = await codec.getNextFrame();
            loadedAssetImages[file.name] = frameInfo.image;
          }
        }
      }
      // Expose the default assets to the Polaroid Studio! ---
      if (loadedRigData != null) {
        characterRigCache['default'] = loadedRigData!;
        characterImagesCache['default'] = loadedAssetImages;
      }
    } catch (e) {
      debugPrint('CRITICAL: Default zip failed to load: $e');
    }
  }
  

  @override
  Future<void> onLoad() async {
    await images.load('Base_BaseChip_pipo.png');
    await images.loadAll([
      'standard_mask.png', 
      'flying_mask.png', 
      'vermin_mask.png', 
      'siren_mask.png'
    ]);

    await _loadVoxelAssets(); 

    mySessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final user = Supabase.instance.client.auth.currentUser;
    bool needsTutorial = false;

    if (user != null) {
      try {
        final profileRes = await Supabase.instance.client
            .from('profiles')
            .select('completed_tutorial, level')
            .eq('id', user.id)
            .maybeSingle();
            
        if (profileRes != null) {
          needsTutorial = !(profileRes['completed_tutorial'] ?? false);
          myPlayerLevel = profileRes['level'] as int? ?? 1;
        }

        final membership = await Supabase.instance.client
            .from('guild_members')
            .select('guild_id, guilds(active_doctrine)')
            .eq('user_id', user.id)
            .maybeSingle();
            
        if (membership != null && membership['guilds'] != null) {
          guildActiveDoctrine = membership['guilds']['active_doctrine'] ?? 'none';
        }
      } catch (e) {}
    }
    
    myChannel = Supabase.instance.client.channel('room_$roomId');
    camera.viewfinder.anchor = Anchor.center;

    final knobPaint = BasicPalette.white.withAlpha(100).paint();
    final backgroundPaint = BasicPalette.white.withAlpha(40).paint();

    leftJoystick = JoystickComponent(
      knob: CircleComponent(radius: 20, paint: knobPaint),
      background: CircleComponent(radius: 60, paint: backgroundPaint),
      margin: const EdgeInsets.only(left: 40, bottom: 40),
      priority: 100,
    );

    rightJoystick = JoystickComponent(
      knob: CircleComponent(radius: 20, paint: Paint()..color = Colors.redAccent.withAlpha(204)),
      background: CircleComponent(radius: 60, paint: backgroundPaint),
      margin: const EdgeInsets.only(right: 40, bottom: 40),
      priority: 100,
    );

    gameMap = GameMap(roomId: roomId, mapName: mapName); 
    await world.add(gameMap);

    scareManager = ScareManager();
    await world.add(scareManager);

    List<Vector2> availableSpawns = gameMap.playerSpawns.isNotEmpty 
        ? List<Vector2>.from(gameMap.playerSpawns)
        : [Vector2(150, 150), Vector2(400, 400)]; 
    
    availableSpawns.shuffle(); 
    final rawSpawnPoint = availableSpawns.removeAt(0);
    final safeSpawnPoint = gameMap.getSafeSpawnLocation(rawSpawnPoint, Vector2.all(32.0));

    player = Player(leftJoystick, rightJoystick, myChannel, isGunner: isGunner)..position = safeSpawnPoint;
    jumpScareEffect = JumpScareEffect();

    world.add(player);
    world.add(PowerUpHud(player: player));
    camera.follow(player);

    camera.viewport.add(jumpScareEffect);
    camera.viewport.add(DarknessOverlay(player));

    if (isGunner) {
      camera.viewport.add(rightJoystick);
    } else {
      camera.viewport.add(leftJoystick);
    }

    camera.viewport.add(ScoreHud());
    camera.viewport.add(gameTimer = GameTimer());
    await camera.viewport.add(FpsViewportOverlay());
    await camera.viewport.add(FpsTouchControls());
    await camera.viewport.add(ModeToggleButton());

    mapOverlay = MapOverlay();
    await camera.viewport.add(mapOverlay);
    await camera.viewport.add(MapButton());

    try {
      final logoSprite = await Sprite.load('lumen_breach_small.jpg');
      final logoComponent = SpriteComponent(
        sprite: logoSprite,
        size: Vector2(120, 60), 
        position: Vector2(camera.viewport.size.x / 2, camera.viewport.size.y - 20), 
        anchor: Anchor.bottomCenter,
        priority: 200, 
      );
      camera.viewport.add(logoComponent);
    } catch (e) {}

    if (matchMode == 'casual') {
      matchPhase = 'playing'; 
      camera.viewport.add(StartButton());
    } else {
      overlays.add('searching');
    }
    camera.viewport.add(AttackButton());
    camera.viewport.add(DefenseButton());
    camera.viewport.add(PlayerHud());
    camera.viewport.add(FlashlightHud());

    if (needsTutorial) {
      gameStarted = true;
      gameTimer.start();
      camera.viewport.children.whereType<StartButton>().toList().forEach((btn) => btn.removeFromParent());
      world.add(PowerUp(id: 'tutorial_spark', position: safeSpawnPoint + Vector2(100, 0)));
      camera.viewport.add(TutorialManager());
    }

    camera.viewport.add(SpecialButton());
    _setupSupabaseListener();
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    if (matchPhase == 'searching') {
      if (isHost) {
        lobbyTimer -= dt;

        if (isHost && gameStarted && matchHasHunter && !hunterHasSpawned) {
          if (gameTimer.timeLeft <= 60.0 && gameTimer.timeLeft > 0) {
            final eligibleBots = bots.where((b) => !b.isHunter).toList();
            if (eligibleBots.isNotEmpty) {
              hunterHasSpawned = true;
              final chosenBot = eligibleBots[Random().nextInt(eligibleBots.length)];
              final botIndex = bots.indexOf(chosenBot);

              chosenBot.transformToHunter();
              myChannel.sendBroadcastMessage(
                event: 'hunter_emerge',
                payload: {'bot_index': botIndex},
              );
            }
          }
        }
        
        int totalHumans = 1 + networkPlayers.length;
        
        bool shouldStart = totalHumans >= targetPlayers || (!isGuildScrimmage && lobbyTimer <= 0);
        
        if (shouldStart) {
          _spawnWorldEntities(); 
          matchPhase = 'countdown';
          overlays.remove('searching');
          overlays.add('countdown');
          myChannel.sendBroadcastMessage(
            event: 'start_countdown', 
            payload: {'teams': playerTeams}
          );
        }
      }
      return; 
    }

    if (matchPhase == 'countdown') {
      countdownTimer -= dt;
      int currentTick = countdownTimer.ceil();
      
      if (currentTick < _lastTick && currentTick > 0) {
        _lastTick = currentTick;
        if (AudioManager.instance.isInitialized && AudioManager.instance.tickSource != null) {
          SoLoud.instance.play(AudioManager.instance.tickSource!);
        }
        
        overlays.remove('countdown');
        overlays.add('countdown');
      }

      if (countdownTimer <= 0) {
        matchPhase = 'playing';
        gameStarted = true;
        overlays.remove('countdown');
        gameTimer.start(); 
        if (AudioManager.instance.isInitialized && AudioManager.instance.impactSource != null) {
          SoLoud.instance.play(AudioManager.instance.impactSource!);
        }
      }
      return; 
    }

    if (!gameStarted) return;

    if (AudioManager.instance.isInitialized) {
      const double audioScale = 50.0; 
      final pX = player.position.x / audioScale;
      final pY = player.position.y / audioScale;
      SoLoud.instance.set3dListenerPosition(pX, pY, 0.0);
      
      final forwardX = -sin(player.angle);
      final forwardY = -cos(player.angle);
      SoLoud.instance.set3dListenerAt(forwardX, forwardY, 0.0);
      SoLoud.instance.set3dListenerUp(0.0, 0.0, -1.0);
    }

    if (isHost && bots.isNotEmpty) {
      hostBotSyncTick += dt;
      if (hostBotSyncTick >= hostBotSyncRate) {
        hostBotSyncTick = 0;
        List<Map<String, dynamic>> botData = [];
        for (var bot in bots) {
          botData.add({'x': bot.position.x, 'y': bot.position.y, 'a': bot.angle});
        }
        myChannel.sendBroadcastMessage(event: 'sync_bots', payload: {'bots': botData});
      }
    }
  }

  @override
  void onRemove() {
    lastMatchPhotos = List.from(matchPhotos);
    myChannel.unsubscribe();
    try {
      Supabase.instance.client.rpc('leave_match', params: {'p_match_id': roomId});
    } catch (e) {}

    AudioManager.instance.stopMusic(); 
    AudioManager.instance.playMenuMusic(); 

    super.onRemove();
  }

  void _spawnWorldEntities() {
    if (bots.isNotEmpty) return; 
    
    List<Vector2> availableSpawns = gameMap.playerSpawns.isNotEmpty 
        ? List<Vector2>.from(gameMap.playerSpawns)
        : [Vector2(150, 150), Vector2(400, 400)];
        
    availableSpawns.shuffle();
    availableSpawns.removeWhere((spawn) => spawn.distanceTo(player.position) < 300.0);

    if (matchMode == 'casual') {
      final config = LevelManager.getConfigForLevel(myPlayerLevel);
      matchHasHunter = Random().nextDouble() < 0.70;
      hunterHasSpawned = false;

      for (int i = 0; i < config.botCount; i++) {
        Vector2 safeBotSpawn = gameMap.getSafeSpawnLocation(
          availableSpawns.isNotEmpty ? availableSpawns.removeAt(0) : Vector2(500, 500), 
          Vector2.all(32.0),
        );
        bots.add(
          BotPlayer(isHunter: false)
            ..position = safeBotSpawn
            ..wanderSpeed = config.wanderSpeed
            ..huntSpeed = config.huntSpeed,
        );
      }
      for (var b in bots) world.add(b);

    } else {
      matchHasHunter = false;
      playerTeams[mySessionId] = 1; 
      if (matchMode == '2v2') player.applyTeamColor(1);

      int nextTeam = matchMode == '2v2' ? 2 : 0; 
      
      for (var remoteId in networkPlayers.keys) {
        playerTeams[remoteId] = nextTeam;
        if (matchMode == '2v2') {
          networkPlayers[remoteId]?.applyTeamColor(nextTeam);
          nextTeam = (nextTeam == 1) ? 2 : 1;
        }
      }

      int missingPlayers = targetPlayers - (1 + networkPlayers.length);
      
      for (int i = 0; i < missingPlayers; i++) {
        if (availableSpawns.isEmpty) break;
        Vector2 safeSpawn = gameMap.getSafeSpawnLocation(availableSpawns.removeAt(0), Vector2.all(32.0));
        
        final fakeHuman = BotPlayer(isHunter: false)
          ..position = safeSpawn
          ..wanderSpeed = 100.0 
          ..huntSpeed = 160.0
          ..teamId = (matchMode == '2v2') ? nextTeam : 0; 
          
        bots.add(fakeHuman);
        world.add(fakeHuman);

        if (matchMode == '2v2') nextTeam = (nextTeam == 1) ? 2 : 1; 
      }
    }

    final random = Random();
    for (int i = 0; i < 4; i++) {
      double x = (random.nextDouble() * 2400) - 1200;
      double y = (random.nextDouble() * 2400) - 1200;
      if (!gameMap.checkCollision(Vector2(x,y), Vector2.all(16))) {
        world.add(PowerUp(id: 'spark_$i', position: Vector2(x, y)));
      }
    }

    if (!isGuildScrimmage && gameMap.potentialBoxSpawns.isNotEmpty) {
      List<Vector2> boxNodes = gameMap.potentialBoxSpawns.isNotEmpty 
          ? List.from(gameMap.potentialBoxSpawns)
          : [Vector2(400, 400), Vector2(800, 800), Vector2(1200, 1200), Vector2(1600, 1600)];

      boxNodes.shuffle();
      int boxesToSpawn = min(8, boxNodes.length);
      List<Map<String, dynamic>> boxPayload = [];

      for (int i = 0; i < boxesToSpawn; i++) {
        String boxId = 'spooky_box_${DateTime.now().millisecondsSinceEpoch}_$i';
        Vector2 pos = boxNodes[i];
        world.add(SpookyBox(id: boxId, position: pos));
        boxPayload.add({'id': boxId, 'x': pos.x, 'y': pos.y});
      }

      myChannel.sendBroadcastMessage(event: 'spawn_boxes', payload: {'boxes': boxPayload});
    }
  }

  Future<void> endGame() async {
    gameStarted = false; 
    
    int myTeamScore = player.score;
    int enemyTeamScore = 0;
    
    if (matchMode == '2v2') {
      int myTeamId = getEntityTeam(player);

      for (var bot in bots) {
        if (getEntityTeam(bot) == myTeamId) myTeamScore += bot.simulatedScore;
        else enemyTeamScore += bot.simulatedScore;
      }
      for (var entry in networkPlayers.entries) {
        if (getEntityTeam(entry.key) == myTeamId) myTeamScore += entry.value.score;
        else enemyTeamScore += entry.value.score;
      }

      if (myTeamScore > enemyTeamScore) {
        player.score += 1500; 
        camera.viewport.add(FloatingText(
          text: 'VICTORY BONUS! +1500', 
          worldPosition: Vector2(player.position.x - 40, player.position.y - 80)
        ));
      }
    }

    if (!isGuildScrimmage) {
      final xpEarned = (player.score * 0.1).toInt();
      final shadowsEarned = (player.score * 0.05).toInt();

      if (player.score > 0 || player.coinsEarned > 0) {
        try {
          await Supabase.instance.client.rpc(
            'process_match_rewards',
            params: {
              'xp_earned': xpEarned, 
              'shadows_earned': shadowsEarned, 
              'coins_earned': player.coinsEarned
            },
          );
        } catch (e) {
          debugPrint('Reward error: $e');
        }
      }
    }

    if (player.score > 0) {
      try {
        final userId = Supabase.instance.client.auth.currentUser?.id;
        if (userId != null) {
          final member = await Supabase.instance.client
              .from('guild_members')
              .select('guild_id')
              .eq('user_id', userId)
              .maybeSingle();

          if (member != null) {
            final activeNode = await Supabase.instance.client
                .from('guild_nodes')
                .select('id')
                .limit(1)
                .maybeSingle();

            if (activeNode != null) {
              await Supabase.instance.client.rpc('award_match_ip', params: {
                'p_user_id': userId,
                'p_guild_id': member['guild_id'],
                'p_node_id': activeNode['id'],
                'p_match_type': matchMode,
              });
            }
          }
        }
      } catch (e) {
        debugPrint('Guild IP award error: $e');
      }
    }

    if (isHost) {
      try {
        await Supabase.instance.client.from('active_matches').update({'status': 'ended'}).eq('id', roomId);
      } catch (e) {}
      
      myChannel.sendBroadcastMessage(event: 'match_control', payload: {'action': 'end'});

      if (isGuildScrimmage && scrimmageMessageId != null) {
        try {
          String _short(String id) => id.length >= 4 ? id.substring(0, 4) : id;
          
          Map<String, int> finalResults = {
            'Player ${_short(mySessionId)}': player.score,
          };
          networkPlayers.forEach((id, rp) {
            finalResults['Player ${_short(id)}'] = rp.score;
          });

          final msgRes = await Supabase.instance.client
              .from('guild_messages')
              .select('metadata')
              .eq('id', scrimmageMessageId!)
              .maybeSingle();

          if (msgRes != null) {
            Map<String, dynamic> meta = Map<String, dynamic>.from(msgRes['metadata'] ?? {});
            meta['status'] = 'finished';
            meta['results'] = finalResults;

            await Supabase.instance.client
                .from('guild_messages')
                .update({'metadata': meta})
                .eq('id', scrimmageMessageId!);
          }
        } catch (e) {
          debugPrint('Failed to post scrimmage results to chat: $e');
        }
      }
    }

    if (!isGuildScrimmage && buildContext != null) {
      VesselOpenerOverlay.show(buildContext!, 'shadow_reliquary');
    }
  }

  void claimSpookyBox(String boxId) {
    myChannel.sendBroadcastMessage(event: 'claim_box', payload: {'player_id': mySessionId, 'box_id': boxId});
    _executeBoxClaim(boxId, mySessionId);
  }

  void _executeBoxClaim(String boxId, String playerId) {
    final boxes = world.children.whereType<SpookyBox>().where((b) => b.id == boxId).toList();
    if (boxes.isEmpty) return;

    final boxPos = boxes.first.position.clone();
    for (var box in boxes) box.removeFromParent();

    if (AudioManager.instance.isInitialized && AudioManager.instance.powerupSource != null) {
      SoLoud.instance.play(AudioManager.instance.powerupSource!);
    }

    if (playerId == mySessionId) {
      final rewards = [
        ChestReward(type: ChestRewardType.points, label: '+250 SOULS', value: 250),
        ChestReward(type: ChestRewardType.currency, label: '+10 COINS', value: 10),
        ChestReward(type: ChestRewardType.invisibility, label: 'INVISIBILITY!'),
        ChestReward(type: ChestRewardType.disguise, label: 'DISGUISE!'),
        ChestReward(type: ChestRewardType.rangeIncrease, label: 'RANGE EXTENDED!'),
        ChestReward(type: ChestRewardType.teleport, label: 'TELEPORTED!'),
      ];
      final selectedReward = rewards[Random().nextInt(rewards.length)];
      player.applyChestReward(selectedReward);
      camera.viewport.add(FloatingText(text: selectedReward.label, worldPosition: Vector2(boxPos.x - 20, boxPos.y - 40)));
    }
  }
  
  int triggerLocalScare(Vector2 attackerPos, double attackerAngle, bool isPoweredUp, {bool hasExtendedRange = false, double range = 250.0, required String maskId}) {
    int hitCount = 0;
    final forward = Vector2(sin(attackerAngle), -cos(attackerAngle));
    
    final double scareRadius = maskId == 'siren' ? 2000.0 : (hasExtendedRange ? 600.0 : range);

    for (var bot in bots) {
      if (bot.isHunter) {
        bot.hearLoudNoise(attackerPos);
      }
    }

    for (var bot in bots) {
      if (matchMode == '2v2' && getEntityTeam(player) == getEntityTeam(bot)) continue; 
      if (bot.localImmunityToMe > 0) continue; 
      
      final toBot = bot.position - attackerPos;
      if (toBot.length < scareRadius) {
        toBot.normalize();
        final dot = forward.dot(toBot);

        if (maskId == 'siren') {
          if (dot > 0.0) { 
            double duration = 15.0; 
            bot.applyCharm(duration, player);
            bot.localImmunityToMe = 16.0;
            hitCount++;
          }
        } 
        else {
          final coneThreshold = isPoweredUp ? -0.2 : 0.1;
          if (dot > coneThreshold && gameMap.hasLineOfSight(bot.position, attackerPos)) {
            if (bot.isHunter) {
              if (bot.isCoreExposed) {
                bot.applyStun(8.0); 
                bot.localImmunityToMe = 10.0; 
                hitCount++;
                player.score += 2500; 
                camera.viewport.add(FloatingText(
                  text: 'CRITICAL OVERLOAD! +2500', 
                  worldPosition: Vector2(bot.position.x - 40, bot.position.y - 60),
                ));
              } else {
                bot.applyStun(0.1); 
                camera.viewport.add(FloatingText(
                  text: 'ARMOR DEFLECTED!', 
                  worldPosition: Vector2(bot.position.x - 20, bot.position.y - 40),
                ));
              }
            } else {
              double stunDuration = _matchesDoctrine(bot) ? 4.4 : 4.0;
              bot.applyStun(stunDuration); 
              bot.localImmunityToMe = 7.0; 
              bot.triggerPrivateHighlight(); 
              hitCount++;

              // --- TAKE THE POLAROID (BOT VICTIM) ---
              logScareSnapshot(ScareSnapshot(
                attackerName: player.score > 0 ? 'You' : 'Attacker', 
                attackerCharId: player.equippedCharacterId,
                attackerMaskId: maskId,
                victimName: bot.fakeUsername,
                victimCharId: bot.assignedCharacterId,
                timestamp: gameTimer.timeLeft.toInt(),
                mapX: attackerPos.x,
                mapY: attackerPos.y,
              ), isHuman: false);

              // SPAWN SCORE OVER BOT'S HEAD
              camera.viewport.add(FloatingText(
                text: '+100 SOULS',
                worldPosition: Vector2(bot.position.x - 25, bot.position.y - 60),
              ));
            }
          }
        }
      }
    }

    for (var remoteId in networkPlayers.keys) {
      if (matchMode == '2v2' && getEntityTeam(player) == getEntityTeam(remoteId)) continue; 
      
      var remotePlayer = networkPlayers[remoteId]!;
      if (remotePlayer.localImmunityToMe > 0) continue; 
      
      final toPlayer = remotePlayer.position - attackerPos;
      if (toPlayer.length < scareRadius) {
        toPlayer.normalize();
        final dot = forward.dot(toPlayer);

        if (maskId == 'siren') {
          if (dot > 0.0) {
            double duration = 15.0;
            remotePlayer.localImmunityToMe = 16.0;
            hitCount++;
            myChannel.sendBroadcastMessage(event: 'charm', payload: {
              'id': remoteId, 'duration': duration, 
              'charmer_x': attackerPos.x, 'charmer_y': attackerPos.y
            });
          }
        } else {
          final coneThreshold = isPoweredUp ? -0.2 : 0.1;
          if (dot > coneThreshold && gameMap.hasLineOfSight(remotePlayer.position, attackerPos)) {
            hitCount++;
            remotePlayer.localImmunityToMe = 5.0; 
            remotePlayer.triggerPrivateHighlight(); 
            
            double stunDuration = _matchesDoctrine(remotePlayer) ? 2.2 : 2.0;
            myChannel.sendBroadcastMessage(event: 'stun', payload: {
              'id': remoteId, 
              'duration': stunDuration, 
              'attacker_id': mySessionId,
              'attacker_x': attackerPos.x, // Send your position so they can recoil too!
              'attacker_y': attackerPos.y
            });

            // --- TAKE THE POLAROID (PLAYER VICTIM) ---
            logScareSnapshot(ScareSnapshot(
              attackerName: 'You',
              attackerCharId: player.equippedCharacterId,
              attackerMaskId: maskId,
              victimName: remoteId.substring(0, 4), 
              victimCharId: remotePlayer.equippedCharacterId,
              timestamp: gameTimer.timeLeft.toInt(),
              mapX: attackerPos.x,
              mapY: attackerPos.y,
            ), isHuman: true);

            // SPAWN SCORE OVER REMOTE PLAYER'S HEAD
            camera.viewport.add(FloatingText(
              text: '+100 SOULS',
              worldPosition: Vector2(remotePlayer.position.x - 25, remotePlayer.position.y - 60),
            ));
          }
        }
      }
    }
    if (hitCount > 0) player.triggerPrivateHighlight();
    return hitCount;
  }
  
  void triggerLocalStart() {
    gameStarted = true;
    gameTimer.start();
    camera.viewport.children.whereType<StartButton>().toList().forEach((btn) => btn.removeFromParent());
  }

  void _setupSupabaseListener() {
    myChannel
      .onPresenceSync((payload) {
        final presenceState = myChannel.presenceState();
        List<Map<String, dynamic>> allUsers = [];
        for (final state in presenceState) {
          for (final presence in state.presences) {
            if (presence.payload != null && presence.payload.containsKey('id')) {
              allUsers.add({'id': presence.payload['id'], 'joined_at': presence.payload['joined_at']});
            }
          }
        }

        allUsers.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));

        if (allUsers.isNotEmpty && allUsers.first['id'] == mySessionId) {
          if (!isHost) {
            isHost = true;
            _spawnWorldEntities(); 
          }
          try {
            Supabase.instance.client.from('active_matches').update({'player_count': allUsers.length}).eq('id', roomId);
          } catch (e) {}
        } else {
          isHost = false;
        }

        for (var user in allUsers) {
          final id = user['id'] as String;
          if (id != mySessionId && !networkPlayers.containsKey(id)) {
            if (matchPhase != 'searching') continue; 
            
            final newPlayer = RemotePlayer()..position = Vector2(-100, -100);
            networkPlayers[id] = newPlayer;
            world.add(newPlayer);
          }
        }

        final activeIds = allUsers.map((u) => u['id']).toSet();
        networkPlayers.keys.toList().forEach((id) {
          if (!activeIds.contains(id)) {
            networkPlayers[id]?.removeFromParent();
            networkPlayers.remove(id);
          }
        });
      })
      .onBroadcast(
        event: 'hunter_emerge',
        callback: (payload) {
          if (!isHost) {
            final index = payload['bot_index'] as int?;
            if (index != null && index >= 0 && index < bots.length) {
              bots[index].transformToHunter();
            }
          }
        },
      )
      .onBroadcast(
        event: 'move',
        callback: (payload) {
          final id = payload['id'] as String?;
          if (id != null && id != mySessionId) {
            final x = payload['x'] as double;
            final y = payload['y'] as double;
            final angle = payload['a'] as double;
            final colorStr = payload['c'] as String?; 
            final newScore = payload['s'] as int?; 
            final isDisguised = payload['d'] as bool? ?? false;
            final isMoving = payload['m'] as bool? ?? false;
            final isInvisible = payload['i'] as bool? ?? false;
            final fScale = payload['f'] as double? ?? 1.0;
            final sp = payload['sp'] as String? ?? 'humanoid';

            final maskId = payload['mask_id'] as String? ?? 'standard';

            if (!networkPlayers.containsKey(id)) {
              if (matchPhase != 'searching') return; 
              
              final newPlayer = RemotePlayer()..position = Vector2(x, y);
              networkPlayers[id] = newPlayer;
              world.add(newPlayer);
            }

            networkPlayers[id]!.updatePosition(
              x, y, angle, 
              colorStr: colorStr, newScore: newScore,
              isDisguised: isDisguised, isMoving: isMoving, isInvisible: isInvisible,
              fScale: fScale,
              maskId: maskId,
              species: sp,
            );
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
            remote.facingAngle = payload['a'] as double;
            
            final maskId = payload['mask_id'] as String? ?? 'standard'; 
            final seed = payload['seed'] as int? ?? 0;

            remote.currentMaskId = maskId;

            // Fire the visual animation instead of the old variable!
            if (remote.voxelComponent != null) remote.voxelComponent!.triggerScareAnimation();
            //remote.visualAttackCooldown = 0.6;

            AudioManager.instance.playSpatialScare(maskId, remote.position);

            if (maskId == 'flying') {
              scareManager.spawnBat(FlyingScareBlast(position: remote.position.clone(), angle: remote.facingAngle, ownerId: payload['id']));
            } else if (maskId == 'vermin') {
              for (int i = 0; i < 15; i++) { 
                scareManager.spawnCritter(Critter(
                  position: remote.position.clone(), behavior: SwarmBehavior.scatter,
                  seed: seed, index: i, initialAngle: remote.facingAngle, ownerId: id,
                ));
              }
            } else if (maskId == 'siren') {
              remote.add(SirenBlast()..position = remote.size / 2);
             } else {
              world.add(ScareBlast(position: remote.position.clone(), angle: remote.facingAngle - (pi / 2))..priority = remote.priority + 5);
            }

            if (isHost && maskId != 'flying' && maskId != 'vermin') {
              final forward = Vector2(sin(remote.facingAngle), -cos(remote.facingAngle));
              for (var bot in bots) {
                if (matchMode == '2v2' && getEntityTeam(id) == getEntityTeam(bot)) continue; 
                if (bot.localImmunityToMe > 0) continue; 
                
                final toBot = bot.position - remote.position;
                if (toBot.length < 250.0) {
                  toBot.normalize();
                  if (forward.dot(toBot) > 0.1 && gameMap.hasLineOfSight(bot.position, remote.position)) {
                    double stunDuration = _matchesDoctrine(bot) ? 4.4 : 4.0;
                    bot.applyStun(stunDuration); 
                    bot.localImmunityToMe = 7.0; 
                    bot.triggerPrivateHighlight(); 
                  }
                }
              }
            }
          }
        },
      )
      .onBroadcast(
        event: 'charm',
        callback: (payload) {
          final targetId = payload['id'] as String?;
          if (targetId == null) return;
          final duration = (payload['duration'] as num).toDouble();
          final charmerPos = Vector2((payload['charmer_x'] as num).toDouble(), (payload['charmer_y'] as num).toDouble());

          if (targetId == mySessionId) {
            player.applyCharm(duration, charmerPos);
          } 
        },
      )
      .onBroadcast(
        event: 'stun',
        callback: (payload) {
          final targetId = payload['id'] as String?;
          if (targetId == null) return;
          final duration = (payload['duration'] as num).toDouble();
          final attackerId = payload['attacker_id'] as String?;

          if (targetId == mySessionId) {
            jumpScareEffect.trigger();
            
            Vector2? atkPos;
            if (payload.containsKey('attacker_x') && payload.containsKey('attacker_y')) {
              atkPos = Vector2((payload['attacker_x'] as num).toDouble(), (payload['attacker_y'] as num).toDouble());
            }

            player.applyStun(duration, attackerPos: atkPos);
            player.triggerPrivateHighlight();
            
            if (AudioManager.instance.isInitialized && AudioManager.instance.impactSource != null) {
              SoLoud.instance.play(AudioManager.instance.impactSource!);
            }
            
            if (attackerId != null && networkPlayers.containsKey(attackerId)) {
              networkPlayers[attackerId]!.triggerPrivateHighlight();
            }
          } else if (networkPlayers.containsKey(targetId)) {
            networkPlayers[targetId]!.applyStun(duration);
          }
        },
      )
      .onBroadcast(
        event: 'spawn_boxes',
        callback: (payload) {
          if (!isHost) {
            final boxList = payload['boxes'] as List<dynamic>;
            for (var data in boxList) {
              world.add(SpookyBox(id: data['id'] as String, position: Vector2(data['x'] as double, data['y'] as double)));
            }
          }
        },
      )
      .onBroadcast(
        event: 'start_countdown',
        callback: (payload) {
          if (!isHost && matchPhase == 'searching') {
            if (payload.containsKey('teams')) {
              final teamsData = payload['teams'] as Map<String, dynamic>;
              teamsData.forEach((key, value) {
                playerTeams[key] = value as int;
              });

              if (matchMode == '2v2') {
                int myTeam = playerTeams[mySessionId] ?? 1;
                player.applyTeamColor(myTeam);

                for (var remoteId in networkPlayers.keys) {
                  int remoteTeam = playerTeams[remoteId] ?? 0;
                  networkPlayers[remoteId]?.applyTeamColor(remoteTeam);
                }
              }
            }
            
            matchPhase = 'countdown';
            overlays.remove('searching');
            overlays.add('countdown');
          }
        },
      )
      .onBroadcast(
        event: 'claim_box',
        callback: (payload) => _executeBoxClaim(payload['box_id'] as String, payload['player_id'] as String),
      )
      .onBroadcast(
        event: 'match_control',
        callback: (payload) {
          final action = payload['action'] as String;
          if (action == 'start') triggerLocalStart(); else if (action == 'end') endGame();
        },
      )
      .onBroadcast(
        event: 'request_sync',
        callback: (payload) {
          if (isHost) myChannel.sendBroadcastMessage(event: 'sync_state', payload: {'gameStarted': gameStarted, 'timeLeft': gameTimer.timeLeft});
        },
      )
      .onBroadcast(
        event: 'sync_bots',
        callback: (payload) {
          if (!isHost) {
            final botList = payload['bots'] as List<dynamic>;
            for (int i = 0; i < botList.length; i++) {
              final data = botList[i] as Map<String, dynamic>;
              while (bots.length <= i) {
                final dummyBot = BotPlayer()..position = Vector2(-1000, -1000);
                bots.add(dummyBot);
                world.add(dummyBot);
              }
              bots[i].position.x = data['x'] as double;
              bots[i].position.y = data['y'] as double;
              bots[i].angle = data['a'] as double;
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
            } else if (!isRunning && gameStarted) {
              endGame();
            }
          }
        },
      )
      .onBroadcast(
        event: 'consume_powerup',
        callback: (payload) {
          final id = payload['id'] as String;
          world.children.whereType<PowerUp>().where((p) => p.id == id).toList().forEach((p) => p.removeFromParent());
        },
      )
      .subscribe((status, [error]) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await myChannel.track({'id': mySessionId, 'joined_at': DateTime.now().toUtc().toIso8601String()});
          myChannel.sendBroadcastMessage(event: 'request_sync', payload: {});
        }
      });
  }

  // Just-In-Time Asset Loader
  static Future<void> ensureCharacterLoaded(String charId) async {
    if (charId == 'default' || characterImagesCache.containsKey(charId)) return;

    try {
      final charRes = await Supabase.instance.client
          .from('characters').select('zip_asset_path').eq('id', charId).maybeSingle();
      
      if (charRes == null || charRes['zip_asset_path'] == null) return;
      
      String zipPath = charRes['zip_asset_path'];
      
      // FIX: Strip the accidental double prefix if it exists in the database
      if (zipPath.startsWith('assets/assets/')) {
        zipPath = zipPath.replaceFirst('assets/assets/', 'assets/');
      }

      List<int> bytes = await CharacterAssetManager.getZipBytes(zipPath);
      final archive = ZipDecoder().decodeBytes(bytes);
      
      Map<String, ui.Image> images = {};
      Map<String, dynamic>? rig;

      for (final file in archive) {
        if (file.isFile) {
          if (file.name == 'rig.json') {
            rig = jsonDecode(utf8.decode(file.content as List<int>));
          } else if (file.name.endsWith('.png')) {
            final ui.Codec codec = await ui.instantiateImageCodec(file.content as Uint8List);
            final ui.FrameInfo frameInfo = await codec.getNextFrame();
            images[file.name] = frameInfo.image;
          }
        }
      }
      if (rig != null) {
        characterImagesCache[charId] = images;
        characterRigCache[charId] = rig;
      }
    } catch (e) {
      // Fails gracefully; engine will safely fallback to the default base mesh
      debugPrint('Lazy load bypassed for missing asset $charId: $e');
    }
  }
}