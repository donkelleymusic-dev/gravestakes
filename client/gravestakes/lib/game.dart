import 'dart:math';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';

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

class GraveStakesGame extends FlameGame with HasKeyboardHandlerComponents, HasCollisionDetection {
  String roomId;
  final bool isGunner;
  final String matchMode; // 'casual', '1v1', '2v2'
  final String mapName;
  final int targetPlayers;
  double lobbyTimer = 10.0;
  bool isWaitingInLobby = true;
  
  AudioSource? scareSource;
  AudioSource? footstepSource;
  AudioSource? powerupSource;
  AudioSource? tickSource;
  AudioSource? batScreechSource;
  AudioSource? ratScurrySource;

  bool isAudioReady = false;

  Map<String, Map<String, ui.Image>> characterImagesCache = {};
  Map<String, Map<String, dynamic>> characterRigCache = {};
  
  Map<String, ui.Image> loadedAssetImages = {};
  Map<String, dynamic>? loadedRigData;
  bool isFpsMode = false;
  
  GraveStakesGame({
    this.roomId = 'public_match', 
    this.isGunner = false,
    this.mapName = 'L1T1V1.0.0',
    this.matchMode = 'casual',
    this.targetPlayers = 8,
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

  late final GameTimer gameTimer;
  late final ScoreHud scoreHud;
  bool gameStarted = false;
  int myPlayerLevel = 1; 
  
  final List<BotPlayer> bots = [];

  double hostBotSyncTick = 0;
  final double hostBotSyncRate = 0.12;

  late final RealtimeChannel myChannel;

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

  Future<void> initAudioEngine() async {
    if (isAudioReady) return;
    try {
      await SoLoud.instance.init();      
      scareSource = await SoLoud.instance.loadAsset('assets/audio/ElevenLabs_Impact.mp3');
      footstepSource = await SoLoud.instance.loadAsset('assets/audio/footstep.mp3'); 
      powerupSource = await SoLoud.instance.loadAsset('assets/audio/ElevenLabs_Scary_stinger.mp3');
      tickSource = await SoLoud.instance.loadAsset('assets/audio/tick.mp3');
      batScreechSource = await SoLoud.instance.loadAsset('assets/audio/bat.mp3'); 
      ratScurrySource = await SoLoud.instance.loadAsset('assets/audio/bugs.mp3');     
      isAudioReady = true; 
    } catch (e) {
      debugPrint('AUDIO INIT FAILED: $e');
      isAudioReady = false;
    }
  }

  Future<void> _loadVoxelAssets() async {
    try {
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
      debugPrint('Base Voxel Assets Loaded Safely!');
    } catch (e) {
      debugPrint('CRITICAL: Default zip failed to load: $e');
    }

    try {
      final supabase = Supabase.instance.client;
      final charsRes = await supabase.from('characters').select('id, zip_asset_path');
      final chars = List<Map<String, dynamic>>.from(charsRes);

      for (var char in chars) {
        final charId = char['id'] as String;
        final zipPath = char['zip_asset_path'] as String;
        
        if (charId == 'default') continue; 

        try {
          final ByteData data = await rootBundle.load(zipPath);
          final List<int> bytes = data.buffer.asUint8List();
          final archive = ZipDecoder().decodeBytes(bytes);
          
          Map<String, ui.Image> images = {};
          Map<String, dynamic>? rig;

          for (final file in archive) {
            if (file.isFile) {
              if (file.name == 'rig.json') {
                final jsonStr = utf8.decode(file.content as List<int>);
                rig = jsonDecode(jsonStr);
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
            debugPrint('Dynamically loaded $charId from $zipPath');
          }
        } catch (e) {
          debugPrint('Failed to load dynamic zip for $charId at $zipPath: $e');
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch dynamic character paths from DB: $e');
    }
  }

  @override
  Future<void> onLoad() async {
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

    if (isGunner) {
      camera.viewport.add(rightJoystick);
    } else {
      camera.viewport.add(leftJoystick);
    }

    camera.viewport.add(ScoreHud());
    camera.viewport.add(gameTimer = GameTimer());

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

    camera.viewport.add(StartButton());
    camera.viewport.add(AttackButton());
    camera.viewport.add(PlayerHud());

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
    
    // --- NEW: THE MATCHMAKING LOBBY PHASE ---
    if (isWaitingInLobby) {
      if (isHost) {
        lobbyTimer -= dt;
        int totalHumans = 1 + networkPlayers.length;
        
        // If the lobby fills up naturally OR the 10 seconds expire
        if (totalHumans >= targetPlayers || lobbyTimer <= 0) {
          isWaitingInLobby = false;
          _spawnWorldEntities(); // This now calculates the deficit and spawns fake humans!
          broadcastStartGame();  // Tells all connected clients to drop the waiting screen
        }
      }
      return; // Do not process game physics while in the lobby!
    }
    // ----------------------------------------

    if (!gameStarted) return;

    if (isAudioReady) {
      const double audioScale = 50.0; 
      final pX = player.position.x / audioScale;
      final pY = player.position.y / audioScale;
      SoLoud.instance.set3dListenerPosition(pX, pY, 0.0);
      
      final forwardX = -sin(player.angle);
      final forwardY = -cos(player.angle);
      SoLoud.instance.set3dListenerAt(forwardX, forwardY, 0.0);
      SoLoud.instance.set3dListenerUp(0.0, 0.0, 1.0);
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
    myChannel.unsubscribe();
    try {
      Supabase.instance.client.rpc('leave_match', params: {'p_match_id': roomId});
    } catch (e) {}
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
      // --- CASUAL MODE (Endless Bots & Hunters) ---
      final config = LevelManager.getConfigForLevel(myPlayerLevel);
      bool spawnHunter = Random().nextDouble() < 0.40;
      int regularBotCount = spawnHunter ? config.botCount - 1 : config.botCount;
        
      for (int i = 0; i < regularBotCount; i++) {
        Vector2 safeBotSpawn = gameMap.getSafeSpawnLocation(availableSpawns.isNotEmpty ? availableSpawns.removeAt(0) : Vector2(500, 500), Vector2.all(32.0));
        bots.add(BotPlayer(isHunter: false)..position = safeBotSpawn..wanderSpeed = config.wanderSpeed..huntSpeed = config.huntSpeed);
      }
      if (spawnHunter && availableSpawns.isNotEmpty) {
        Vector2 safeBotSpawn = gameMap.getSafeSpawnLocation(availableSpawns.removeAt(0), Vector2.all(32.0));
        bots.add(BotPlayer(isHunter: true)..position = safeBotSpawn..wanderSpeed = config.wanderSpeed..huntSpeed = config.huntSpeed);
      }
      for (var b in bots) world.add(b);
      
    } else {
      // --- COMPETITIVE 1v1 & 2v2 MODE (Fake Human Fill) ---
      // Target players minus the host (1) and any connected remote players
      int missingPlayers = targetPlayers - (1 + networkPlayers.length);
      
      for (int i = 0; i < missingPlayers; i++) {
        if (availableSpawns.isEmpty) break;
        Vector2 safeSpawn = gameMap.getSafeSpawnLocation(availableSpawns.removeAt(0), Vector2.all(32.0));
        
        // Fake humans get standard bot stats but act as player substitutes
        final fakeHuman = BotPlayer(isHunter: false)
          ..position = safeSpawn
          ..wanderSpeed = 100.0 
          ..huntSpeed = 160.0; 
          
        bots.add(fakeHuman);
        world.add(fakeHuman);
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

    if (gameMap.potentialBoxSpawns.isNotEmpty) {
      List<Vector2> shuffledNodes = List.from(gameMap.potentialBoxSpawns)..shuffle();
      int boxesToSpawn = min(8, shuffledNodes.length);
      List<Map<String, dynamic>> boxPayload = [];

      for (int i = 0; i < boxesToSpawn; i++) {
        String boxId = 'spooky_box_${DateTime.now().millisecondsSinceEpoch}_$i';
        Vector2 pos = shuffledNodes[i];
        world.add(SpookyBox(id: boxId, position: pos));
        boxPayload.add({'id': boxId, 'x': pos.x, 'y': pos.y});
      }

      myChannel.sendBroadcastMessage(event: 'spawn_boxes', payload: {'boxes': boxPayload});
    }
  }

  Future<void> endGame() async {
    gameStarted = false; 
    final xpEarned = (player.score * 0.1).toInt();
    final shadowsEarned = (player.score * 0.05).toInt();
    final coinsEarned = player.coinsEarned; 

    if (player.score > 0 || player.coinsEarned > 0) {
      try {
        await Supabase.instance.client.rpc(
          'process_match_rewards',
          params: {'xp_earned': xpEarned, 'shadows_earned': shadowsEarned, 'coins_earned': player.coinsEarned},
        );
      } catch (e) {}
    }

    if (isHost) {
      try {
        await Supabase.instance.client.from('active_matches').update({'status': 'ended'}).eq('id', roomId);
      } catch (e) {}
      myChannel.sendBroadcastMessage(event: 'match_control', payload: {'action': 'end'});
    }

    if (buildContext != null) {
      VesselOpenerOverlay.show(buildContext!, 'shadow_reliquary');
    } else {
      debugPrint('Error: Could not find Flutter BuildContext to show overlay.');
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

    if (isAudioReady && powerupSource != null) SoLoud.instance.play(powerupSource!);

    if (playerId == mySessionId) {
      final rewards = [
        ChestReward(type: ChestRewardType.points, label: '+250 SOULS', value: 250),
        ChestReward(type: ChestRewardType.currency, label: '+10 COINS', value: 10),
        ChestReward(type: ChestRewardType.invisibility, label: 'INVISIBILITY!'),
        ChestReward(type: ChestRewardType.disguise, label: 'BUSH DISGUISE!'),
        ChestReward(type: ChestRewardType.rangeIncrease, label: 'RANGE EXTENDED!'),
        ChestReward(type: ChestRewardType.teleport, label: 'TELEPORTED!'),
      ];
      final selectedReward = rewards[Random().nextInt(rewards.length)];
      player.applyChestReward(selectedReward);
      camera.viewport.add(FloatingText(text: selectedReward.label, worldPosition: Vector2(boxPos.x - 20, boxPos.y - 40)));
    }
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
  
  int triggerLocalScare(Vector2 attackerPos, double attackerAngle, bool isPoweredUp, {bool hasExtendedRange = false, double range = 250.0, required String maskId}) {
    int hitCount = 0;
    final forward = Vector2(sin(attackerAngle), -cos(attackerAngle));
    
    // --- TEST MOD: Massive 2000px range for the Siren! ---
    final double scareRadius = maskId == 'siren' ? 2000.0 : (hasExtendedRange ? 600.0 : range);

    for (var bot in bots) {
      if (bot.isHunter) {
        bot.hearLoudNoise(attackerPos);
      }
    }

    // 1. Bot Logic
    for (var bot in bots) {
      if (bot.localImmunityToMe > 0) continue; 
      final toBot = bot.position - attackerPos;
      
      if (toBot.length < scareRadius) {
        toBot.normalize();
        final dot = forward.dot(toBot);

        if (maskId == 'siren') {
          // --- TEST MOD: Ignore Line of Sight, sound travels through walls! ---
          if (dot > 0.0) { 
            double duration = 15.0; // 15 SECOND CHARM!
            bot.applyCharm(duration, player);
            bot.localImmunityToMe = 16.0;
            hitCount++;
          }
        } 
        else {
          final coneThreshold = isPoweredUp ? -0.2 : 0.1;
          // Standard attacks still require Line of Sight
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
              bot.applyStun(4.0); 
              bot.localImmunityToMe = 7.0; 
              bot.triggerPrivateHighlight(); 
              hitCount++;
            }
          }
        }
      }
    }

    // 2. Remote Player Logic
    for (var remoteId in networkPlayers.keys) {
      var remotePlayer = networkPlayers[remoteId]!;
      if (remotePlayer.localImmunityToMe > 0) continue; 
      final toPlayer = remotePlayer.position - attackerPos;
      
      if (toPlayer.length < scareRadius) {
        toPlayer.normalize();
        final dot = forward.dot(toPlayer);

        if (maskId == 'siren') {
          // --- TEST MOD: Same wall-penetrating 15s logic for Multiplayer ---
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
            myChannel.sendBroadcastMessage(event: 'stun', payload: {'id': remoteId, 'duration': 2.0, 'attacker_id': mySessionId});
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

  void broadcastStartGame() async {
    myChannel.sendBroadcastMessage(event: 'match_control', payload: {'action': 'start'});
    triggerLocalStart(); 
    try {
      await Supabase.instance.client.from('active_matches').update({'status': 'playing'}).eq('id', roomId);
    } catch (e) {}
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

            if (!networkPlayers.containsKey(id)) {
              final newPlayer = RemotePlayer()..position = Vector2(x, y);
              networkPlayers[id] = newPlayer;
              world.add(newPlayer);
            }

            if (isGunner) {
              final driverBackward = Vector2(sin(angle + pi), -cos(angle + pi));
              player.position.x = x + (driverBackward.x * 20); 
              player.position.y = y + (driverBackward.y * 20);
            }

            networkPlayers[id]!.updatePosition(
              x, y, angle, 
              colorStr: colorStr, newScore: newScore,
              isDisguised: isDisguised, isMoving: isMoving, isInvisible: isInvisible,
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
            remote.angle = payload['a'] as double;
            
            final maskId = payload['mask_id'] as String? ?? 'standard'; 
            final seed = payload['seed'] as int? ?? 0;

            if (isAudioReady && scareSource != null) SoLoud.instance.play(scareSource!);

            if (maskId == 'flying') {
              scareManager.spawnBat(FlyingScareBlast(position: remote.position.clone(), angle: remote.angle));
            } else if (maskId == 'vermin') {
              for (int i = 0; i < 15; i++) { 
                scareManager.spawnCritter(Critter(
                  position: remote.position.clone(), behavior: SwarmBehavior.scatter,
                  seed: seed, index: i, initialAngle: remote.angle, ownerId: id,
                ));
              }
            } else {
              world.add(ScareBlast(position: remote.position.clone(), angle: remote.angle - (pi / 2))..priority = remote.priority + 5);
            }

            if (isHost && maskId != 'flying' && maskId != 'vermin') {
              final forward = Vector2(sin(remote.angle), -cos(remote.angle));
              for (var bot in bots) {
                if (bot.localImmunityToMe > 0) continue; 
                final toBot = bot.position - remote.position;
                if (toBot.length < 250.0) {
                  toBot.normalize();
                  if (forward.dot(toBot) > 0.1 && gameMap.hasLineOfSight(bot.position, remote.position)) {
                    bot.applyStun(4.0); 
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
            player.applyStun(duration);
            player.triggerPrivateHighlight();
            if (isAudioReady && scareSource != null) SoLoud.instance.play(scareSource!);
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
}