import 'dart:math';
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

class GraveStakesGame extends FlameGame with HasKeyboardHandlerComponents, HasCollisionDetection {
  // Optional room ID so party members can queue into a shared private room
  String roomId;
  final bool isGunner;
  final String mapName;
  
  // 1. Make sources nullable and add a status flag
  AudioSource? scareSource;
  AudioSource? footstepSource;
  AudioSource? powerupSource;
  AudioSource? tickSource;

  bool isAudioReady = false;
  
  GraveStakesGame({this.roomId = 'public_match', 
  this.isGunner = false,
  this.mapName = 'L1T1V1.0.0',});

  late final JoystickComponent leftJoystick;
  late final JoystickComponent rightJoystick;
  late final Player player;

  // true multiplayer, with switchable host control rather than central api
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

  // ==========================================
  // NEW: Dedicated Audio Init Method
  // ==========================================
  Future<void> initAudioEngine() async {
    if (isAudioReady) return;

    try {
      await SoLoud.instance.init();      
      scareSource = await SoLoud.instance.loadAsset('assets/audio/ElevenLabs_Impact.mp3');
      footstepSource = await SoLoud.instance.loadAsset('assets/audio/footstep.mp3'); 
      powerupSource = await SoLoud.instance.loadAsset('assets/audio/ElevenLabs_Scary_stinger.mp3');
      tickSource = await SoLoud.instance.loadAsset('assets/audio/tick.mp3');
      isAudioReady = true; 
      debugPrint('SoLoud Web Audio engine initialized successfully!');
    } catch (e) {
      debugPrint('AUDIO INIT FAILED: $e');
      isAudioReady = false;
    }
  }

  @override
  Future<void> onLoad() async {
    // Initialize session ID and channel using the passed roomId
    mySessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final user = Supabase.instance.client.auth.currentUser;
    // Check if player needs the tutorial
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
      } catch (e) {
        debugPrint('Error fetching profile data: $e'); 
      }
    }
  
    
    myChannel = Supabase.instance.client.channel('room_$roomId');

    camera.viewfinder.anchor = Anchor.topLeft;
    
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
    gameMap = GameMap(roomId: roomId, mapName: mapName); // Pass the roomId here!
    await world.add(gameMap);

    // 3. SAFE SPAWNING (Dynamic based on the loaded map!)
    List<Vector2> availableSpawns = gameMap.playerSpawns.isNotEmpty 
        ? List<Vector2>.from(gameMap.playerSpawns)
        : [Vector2(150, 150), Vector2(400, 400)]; // Fallback if Tiled layer is missing
    
    availableSpawns.shuffle(); // Shuffle it safely on the next line!

    final rawSpawnPoint = availableSpawns.removeAt(0);

    // Run the coordinate through the safety check!
    final safeSpawnPoint = gameMap.getSafeSpawnLocation(rawSpawnPoint, Vector2.all(32.0));

    // Pass both joysticks and the role flag to the player
    player = Player(leftJoystick, rightJoystick, myChannel, isGunner: isGunner)..position = safeSpawnPoint;
    jumpScareEffect = JumpScareEffect();

    world.add(player);

    // Add the power-up tracking HUD to the world
    world.add(PowerUpHud(player: player));
    
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
    // ==========================================
    // BRANDING: In-Game Logo Watermark
    // ==========================================
    try {
      // Flame automatically looks inside the assets/images/ folder!
      final logoSprite = await Sprite.load('lumen_breach_small.jpg');
      
      final logoComponent = SpriteComponent(
        sprite: logoSprite,
        size: Vector2(120, 60), 
        // 1. Calculate the middle of the X axis, and the very bottom of the Y axis (minus a 20px pad)
        position: Vector2(camera.viewport.size.x / 2, camera.viewport.size.y - 20), 
        // 2. Change the anchor so it grows upward from the bottom edge
        anchor: Anchor.bottomCenter,
        priority: 200, 
      );
      
      camera.viewport.add(logoComponent);
    } catch (e) {
      debugPrint('Failed to load small logo: $e');
    }
    camera.viewport.add(StartButton());
    camera.viewport.add(AttackButton());

    camera.viewport.add(PlayerHud());

    if (needsTutorial) {
      // Force game to start immediately without waiting for StartButton
      gameStarted = true;
      gameTimer.start();
      
      // FIXED: Added .toList() before .forEach()
      camera.viewport.children
          .whereType<StartButton>()
          .toList() 
          .forEach((btn) => btn.removeFromParent());
      
      // Spawn a guaranteed tutorial power-up 100 pixels to the right
      world.add(PowerUp(id: 'tutorial_spark', position: safeSpawnPoint + Vector2(100, 0)));
      
      // Add the tutorial manager to the world
      camera.viewport.add(TutorialManager());
    }

    camera.viewport.add(SpecialButton());

    _setupSupabaseListener();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!gameStarted) return; 

    if (isAudioReady) {
      const double audioScale = 50.0; 
      
      // 1. Place listener at the player's world position (scaled down to meters)
      final pX = player.position.x / audioScale;
      final pY = player.position.y / audioScale;
      
      SoLoud.instance.set3dListenerPosition(pX, pY, 0.0);
      
      // 2. Calculate the exact forward vector based on your flashlight angle.
      // Since player.angle rotates your flashlight, this points where you are looking.
      // NEGATE FORWARD X to flip Left and Right relative to your flashlight
      final forwardX = -sin(player.angle);
      final forwardY = -cos(player.angle);
      
      SoLoud.instance.set3dListenerAt(forwardX, forwardY, 0.0);

      // 3. Set the 'Up' vector. 
      // To keep stereo panning locked to your shoulders while looking around a 2D plane,
      // the top of your head points "out of the screen" at you (Z = 1.0 or -1.0 depending on handedness).
      // Let's explicitly set the orthogonal 'Up' so left is left and right is right of your flashlight:
      SoLoud.instance.set3dListenerUp(0.0, 0.0, 1.0);
    }

    // ==========================================
    // NEW: UNIFIED HOST BOT SYNC
    // ==========================================
    if (isHost && bots.isNotEmpty) {
      hostBotSyncTick += dt;
      if (hostBotSyncTick >= hostBotSyncRate) {
        hostBotSyncTick = 0;
        
        List<Map<String, dynamic>> botData = [];
        for (var bot in bots) {
          botData.add({
            'x': bot.position.x,
            'y': bot.position.y,
            'a': bot.angle,
          });
        }
        
        myChannel.sendBroadcastMessage(
          event: 'sync_bots', 
          payload: {'bots': botData},
        );
      }
    }
  }

  @override
  void onRemove() {
    myChannel.unsubscribe();
    
    // We are leaving the SoLoud Web Worker running permanently!
    // Do NOT call deinit() or change isAudioReady here.
    
    try {
      Supabase.instance.client.rpc(
        'leave_match',
        params: {'p_match_id': roomId}, 
      );
    } catch (e) {
      debugPrint('Failed to clean up match on exit: $e');
    }

    super.onRemove();
  }

  // Method to safely spawn bots called by the Host once elected
  void _spawnWorldEntities() {
    if (bots.isNotEmpty) return; 
    
    final config = LevelManager.getConfigForLevel(myPlayerLevel);
    
    // CHANGED: Use the map's dynamic spawns for bots too!
    List<Vector2> availableSpawns = gameMap.playerSpawns.isNotEmpty 
        ? List<Vector2>.from(gameMap.playerSpawns)
        : [Vector2(150, 150), Vector2(400, 400)];
        
    availableSpawns.shuffle();
      
    // ==========================================
    // NEW: PREVENT SPAWN KILLING
    // Remove any spawn points within 300 pixels of the host
    // ==========================================
    availableSpawns.removeWhere((spawn) => spawn.distanceTo(player.position) < 300.0);
      
    // 1. Spawn Bots
    for (int i = 0; i < config.botCount; i++) {
      Vector2 rawBotSpawn = availableSpawns.isNotEmpty 
          ? availableSpawns.removeAt(0) 
          : Vector2(500.0 + (i * 100), 500.0); 

      // Run the bot coordinate through the safety check!
      Vector2 safeBotSpawn = gameMap.getSafeSpawnLocation(rawBotSpawn, Vector2.all(32.0));

      final bot = BotPlayer()
        ..position = safeBotSpawn
        ..wanderSpeed = config.wanderSpeed
        ..huntSpeed = config.huntSpeed;
        
      bots.add(bot);
      world.add(bot);
    }

    // 2. Spawn 4 Random Power-Ups
    final random = Random();
    for (int i = 0; i < 4; i++) {
      double x = (random.nextDouble() * 2400) - 1200;
      double y = (random.nextDouble() * 2400) - 1200;
      // Ensure they don't spawn inside a wall
      if (!gameMap.checkCollision(Vector2(x,y), Vector2.all(16))) {
        world.add(PowerUp(id: 'spark_$i', position: Vector2(x, y)));
      }
    }

    // ==========================================
    // THE SPOOKY BOX SPAWNER (Host Only)
    // ==========================================
    if (gameMap.potentialBoxSpawns.isNotEmpty) {
      // 1. Shuffle all possible spawn nodes
      List<Vector2> shuffledNodes = List.from(gameMap.potentialBoxSpawns)..shuffle();
      
      // 2. BUMPED UP: Spawn up to 8 chests (or as many as your map has nodes for)
      int boxesToSpawn = min(8, shuffledNodes.length);
      List<Map<String, dynamic>> boxPayload = [];

      // 3. Create them and prep the network payload
      for (int i = 0; i < boxesToSpawn; i++) {
        String boxId = 'spooky_box_${DateTime.now().millisecondsSinceEpoch}_$i';
        Vector2 pos = shuffledNodes[i];
        
        world.add(SpookyBox(id: boxId, position: pos));
        boxPayload.add({'id': boxId, 'x': pos.x, 'y': pos.y});
      }

      // 4. Tell all clients to spawn these exact boxes
      myChannel.sendBroadcastMessage(
        event: 'spawn_boxes',
        payload: {'boxes': boxPayload},
      );
    }
  }

  Future<void> endGame() async {
    gameStarted = false; // Freeze gameplay

    // 1. Calculate Rewards
    final xpEarned = (player.score * 0.1).toInt();
    final shadowsEarned = (player.score * 0.05).toInt();
    final coinsEarned = player.coinsEarned; // Grab the coins collected from chests!

    // 2. Send to Supabase safely!
    if (player.score > 0 || player.coinsEarned > 0) {
      try {
        await Supabase.instance.client.rpc(
          'process_match_rewards',
          params: {
            'xp_earned': xpEarned,
            'shadows_earned': shadowsEarned,
            'coins_earned': player.coinsEarned, // <--- This passes the looted coins to your DB!
          },
        );
        print('Payout successful!');
      } catch (e) {
        print('Failed to save rewards: $e');
      }
    }

    // NEW: Officially close the match in the database so Spectators stop seeing it!
    if (isHost) {
      try {
        await Supabase.instance.client
            .from('active_matches')
            .update({'status': 'ended'})
            .eq('id', roomId);
      } catch (e) {
        debugPrint('Failed to mark match as ended: $e');
      }
    }

    // 1. Send the broadcast FIRST so spectators always get it
    if (isHost) {
      myChannel.sendBroadcastMessage(
        event: 'match_control',
        payload: {'action': 'end'},
      );
    }

    // 2. Wrap the overlay in a try/catch to prevent fatal grey screens
    try {
      overlays.add('summary');
    } catch (e) {
      debugPrint('Failed to load summary overlay. Is it registered in the GameWidget? Error: $e');
    }
  }

void claimSpookyBox(String boxId) {
    // 1. Send the claim request to the network immediately
    myChannel.sendBroadcastMessage(
      event: 'claim_box',
      payload: {
        'player_id': mySessionId,
        'box_id': boxId,
      },
    );

    // 2. We can optionally execute the reward locally right away, 
    // or wait for a server confirmation if you want strict authority.
    // For fast-paced games, predicting the success locally feels best:
    _executeBoxClaim(boxId, mySessionId);
  }

  void _executeBoxClaim(String boxId, String playerId) {
    final boxes = world.children.whereType<SpookyBox>().where((b) => b.id == boxId).toList();
    if (boxes.isEmpty) return;

    final boxPos = boxes.first.position.clone();
    for (var box in boxes) {
      box.removeFromParent();
    }

    if (isAudioReady && powerupSource != null) {
      SoLoud.instance.play(powerupSource!);
    }

    if (playerId == mySessionId) {
      // 1. Roll Random Chest Reward
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

      // FIXED: Spawns to camera viewport and uses worldPosition
      camera.viewport.add(FloatingText(
        text: selectedReward.label,
        worldPosition: Vector2(boxPos.x - 20, boxPos.y - 40),
      ));
    }
  }

  // Called by the Flutter Overlay when the player clicks "CONTINUE"
  void resetForNextRound() async {
    overlays.remove('summary'); // Hide the scoreboard
    
    player.score = 0;
    player.hasExtendedRange = false; // <-- RESET IT ON THE PLAYER HERE!
    player.isDisguised = false;      // (Good idea to reset disguise too!)
    player.isInvisible = false;      // (And invisibility!)

    for (var remote in networkPlayers.values) {
      remote.score = 0; 
    }
    

    // Pick a new safe spawn point for the next round
    List<Vector2> availableSpawns = List.from(baseSpawnPoints)..shuffle();
    player.position = gameMap.getSafeSpawnLocation(availableSpawns.first, Vector2.all(32.0));
    
    // Bring the start button back!
    camera.viewport.add(StartButton()); 
    
    // Tell the HUD to refresh the new totals on the screen!
    final hud = camera.viewport.children.whereType<PlayerHud>().firstOrNull;
    hud?.fetchPlayerData();

    // NEW: Put the room back in "waiting" status for the next round
    if (isHost) {
      try {
        await Supabase.instance.client
            .from('active_matches')
            .update({'status': 'waiting'})
            .eq('id', roomId);
      } catch (e) {
        debugPrint('Failed to reset match status: $e');
      }
    }
  }
  
  int triggerLocalScare(Vector2 attackerPos, double attackerAngle, bool isPoweredUp, {bool hasExtendedRange = false}) {
    int hitCount = 0;
    
    final forward = Vector2(sin(attackerAngle), -cos(attackerAngle));
    final double scareRadius = hasExtendedRange ? 600.0 : 250.0;
    
    final double coneThreshold = isPoweredUp ? -0.2 : 0.1;

    // 1. Check Bots
    for (var bot in bots) {
      if (bot.localImmunityToMe > 0) continue; 

      final toBot = bot.position - attackerPos;
      if (toBot.length < scareRadius) {
        toBot.normalize();
        if (forward.dot(toBot) > coneThreshold) { 
          if (gameMap.hasLineOfSight(bot.position, attackerPos)) {
            bot.applyStun(4.0); 
            bot.localImmunityToMe = 7.0; 
            
            bot.triggerPrivateHighlight(); // NEW: Light up the bot locally
            hitCount++;
          }
        }
      }
    }

    // 2. Check Remote Human Players
    for (var remoteId in networkPlayers.keys) {
      var remotePlayer = networkPlayers[remoteId]!;
      if (remotePlayer.localImmunityToMe > 0) continue; 

      final toPlayer = remotePlayer.position - attackerPos;
      if (toPlayer.length < scareRadius) {
        toPlayer.normalize();
        if (forward.dot(toPlayer) > coneThreshold) { 
          if (gameMap.hasLineOfSight(remotePlayer.position, attackerPos)) {
            hitCount++;
            remotePlayer.localImmunityToMe = 5.0; 
            
            remotePlayer.triggerPrivateHighlight(); // NEW: Light up the remote player locally
            
            myChannel.sendBroadcastMessage(
              event: 'stun',
              payload: {
                'id': remoteId, 
                'duration': 2.0,
                'attacker_id': mySessionId // NEW: Tell them we are the attacker!
              },
            );
          }
        }
      }
    }

    // NEW: If we hit at least one victim, light ourselves up locally!
    if (hitCount > 0) {
      player.triggerPrivateHighlight();
    }

    return hitCount;
  }
  
  void triggerLocalStart() {
    gameStarted = true;
    gameTimer.start();

    // ==========================================
    // FORCE BROWSER AUDIO CONTEXT TO WAKE UP
    // ==========================================
    if (isAudioReady) {
      // SoLoud handles backend state, but triggering a quick dummy play 
      // or ensuring the engine is active forces the browser to unblock.
      debugPrint('Waking up audio engine on match start...');
    }

    // NEW: Ensure the start button is destroyed for EVERYONE when the game begins!
    camera.viewport.children
        .whereType<StartButton>()
        .toList()
        .forEach((btn) => btn.removeFromParent());
  }

  // The Start Button calls this to tell everyone to start
  void broadcastStartGame() async {
    myChannel.sendBroadcastMessage(
      event: 'match_control',
      payload: {'action': 'start'},
    );
    triggerLocalStart(); // Start it for ourselves too

    // NEW: Tell the database the match has officially started!
    try {
      await Supabase.instance.client
          .from('active_matches')
          .update({'status': 'playing'})
          .eq('id', roomId);
    } catch (e) {
      debugPrint('Failed to update match status: $e');
    }
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

        // 2. Sort alphabetically by user ID to guarantee 100% deterministic Host election across all devices!
        allUsers.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));

        // 3. Crown the Host & Spawn Bots!
        if (allUsers.isNotEmpty && allUsers.first['id'] == mySessionId) {
          if (!isHost) {
            isHost = true;
            _spawnWorldEntities(); // Spawn bots now that we are officially the host
          }
          
          // NEW: The Bouncer Logic. 
          // The Host forces the database to match the ACTUAL number of connected players.
          try {
            Supabase.instance.client
                .from('active_matches')
                .update({'player_count': allUsers.length})
                .eq('id', roomId);
          } catch (e) {
            debugPrint('Failed to sync player count: $e');
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
            final newScore = payload['s'] as int?; 
            
            // Extract the new disguise and movement flags
            final isDisguised = payload['d'] as bool? ?? false;
            final isMoving = payload['m'] as bool? ?? false;
            final isInvisible = payload['i'] as bool? ?? false;

            if (isGunner) {
              final driverBackward = Vector2(sin(angle + pi), -cos(angle + pi));
              player.position.x = x + (driverBackward.x * 20); 
              player.position.y = y + (driverBackward.y * 20);
            }

            if (networkPlayers.containsKey(id)) {
              // Pass the flags to the RemotePlayer
              networkPlayers[id]!.updatePosition(
                x, y, angle, 
                colorStr: colorStr, 
                newScore: newScore,
                isDisguised: isDisguised, // Update method call!
                isMoving: isMoving,       // Update method call!
                isInvisible: isInvisible,
              );
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
            
            if (isAudioReady && scareSource != null) {
              SoLoud.instance.play(scareSource!);
            }
            world.add(ScareBlast(position: remote.position, angle: remote.angle - (pi / 2)));

            // NEW: The Host MUST check if the remote player's attack hit any bots!
            if (isHost) {
              final forward = Vector2(sin(remote.angle), -cos(remote.angle));
              for (var bot in bots) {
                if (bot.localImmunityToMe > 0) continue; 
                
                final toBot = bot.position - remote.position;
                if (toBot.length < 250.0) {
                  toBot.normalize();
                  if (forward.dot(toBot) > 0.1) { // Standard cone threshold
                    if (gameMap.hasLineOfSight(bot.position, remote.position)) {
                      bot.applyStun(4.0); 
                      bot.localImmunityToMe = 7.0; 
                      bot.triggerPrivateHighlight(); 
                    }
                  }
                }
              }
            }
          }
        },
      )
      .onBroadcast(
        event: 'stun',
        callback: (payload) {
          final targetId = payload['id'] as String?;
          if (targetId == null) return;
          
          final duration = (payload['duration'] as num).toDouble();
          final attackerId = payload['attacker_id'] as String?; // NEW: Grab attacker ID

          if (targetId == mySessionId) {
            // NEW: If a friend hits US, trigger full screen, stun, and highlight!
            jumpScareEffect.trigger();
            player.applyStun(duration);
            player.triggerPrivateHighlight();

            // ==========================================
            // FIX: PLAY THE SCARE SOUND EFFECT HERE!
            // ==========================================
            if (isAudioReady && scareSource != null) {
              SoLoud.instance.play(scareSource!);
            }
            // ==========================================
            
            // NEW: Find the remote player who hit me and light them up locally!
            if (attackerId != null && networkPlayers.containsKey(attackerId)) {
              networkPlayers[attackerId]!.triggerPrivateHighlight();
            }
          } 
          else if (networkPlayers.containsKey(targetId)) {
            // Otherwise, just show the remote friend shaking
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
              world.add(SpookyBox(
                id: data['id'] as String,
                position: Vector2(data['x'] as double, data['y'] as double),
              ));
            }
          }
        },
      )
      .onBroadcast(
        event: 'claim_box',
        callback: (payload) {
          // Whenever ANYONE claims a box, execute the removal for everyone
          final boxId = payload['box_id'] as String;
          final playerId = payload['player_id'] as String;
          _executeBoxClaim(boxId, playerId);
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
              
              camera.viewport.children
                  .whereType<StartButton>()
                  .toList()
                  .forEach((btn) => btn.removeFromParent());
                  
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
          // Find the powerup with this ID and remove it so we can't grab it too
          world.children.whereType<PowerUp>().where((p) => p.id == id).toList().forEach((p) {
            p.removeFromParent();
          });
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

}