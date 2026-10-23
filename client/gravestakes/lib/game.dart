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
import 'package:flame/effects.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import 'hallway_triggers.dart';
import 'puzzle_manager.dart';
import 'chat_bubble_component.dart';
import 'quick_chat_wheel.dart';
import 'tactical_entities.dart';

class ScareSnapshot {
  final String attackerName;
  final String attackerCharId;
  final String attackerMaskId;
  final String victimName;
  final String victimCharId;
  final String victimMaskId;
  final String? victimId;
  final int timestamp; 
  final double mapX;
  final double mapY;

  ScareSnapshot({
    required this.attackerName,
    required this.attackerCharId,
    required this.attackerMaskId,
    required this.victimName,
    required this.victimCharId,
    required this.victimMaskId,
    this.victimId,
    required this.timestamp,
    required this.mapX,
    required this.mapY,
  });
}

class GraveStakesGame extends FlameGame with HasKeyboardHandlerComponents, HasCollisionDetection {
  static List<ScareSnapshot> lastMatchPhotos = [];
  // --- Lumen & Match Reward Tracking ---
  int matchLumenDelta = 0;
  int lastMatchXpEarned = 0;
  int lastMatchShadowsEarned = 0;
  int lastMatchCoinsEarned = 0;

  String roomId;
  final bool isGunner;
  final String? driverId;
  final String? partyPartnerUserId;
  final bool hasGunner;
  final String matchMode; 
  final String mapName;
  final int targetPlayers;
  final bool isGuildScrimmage;
  final String? scrimmageMessageId;
  String? myGuildId;
  String guildActiveDoctrine = 'none';
  final String chaosModifier;
  final VoidCallback? onCinematicComplete;

  bool isPuzzleRoomOccupied = false;
  bool isHallwaySolved = false;

  bool isGlobalBlackout = false;
  double blackoutTimer = 0.0;

  double timeUntilNextBlackout = 60.0 + Random().nextDouble() * 60.0;
  bool willBlackoutHappen = Random().nextBool();
  bool hasBlackoutFired = false;

  bool isWaitingInLobby = true;

  bool matchHasHunter = false;
  bool hunterHasSpawned = false;

  String? activeCursedRelicBoxId;

  String matchPhase = 'searching'; 
  double lobbyTimer = 10.0;
  double countdownTimer = 3.0;
  int _lastTick = 4;

  double cinematicTimer = 0.0;
  bool cinematicStage1 = false, cinematicStage2 = false, cinematicStage3 = false, cinematicStage4 = false;
  BotPlayer? stuntDoubleHero;
  BotPlayer? cinematicMonster;
  TextComponent? cinematicStatusText;
  
  static Map<String, Map<String, ui.Image>> characterImagesCache = {};
  static Map<String, Map<String, dynamic>> characterRigCache = {};

  // --- CACHED CHARACTER CATALOG (ELIMINATES N+1 DB QUERIES) ---
  static List<Map<String, dynamic>>? _cachedCharacters;
  static Future<List<Map<String, dynamic>>>? _charactersLoadFuture;

  static Future<List<Map<String, dynamic>>> getEnabledCharacters() async {
    if (_cachedCharacters != null && _cachedCharacters!.isNotEmpty) {
      return _cachedCharacters!;
    }
    if (_charactersLoadFuture != null) {
      return _charactersLoadFuture!;
    }
    _charactersLoadFuture = _fetchCharactersFromSupabase();
    return _charactersLoadFuture!;
  }

  static Future<List<Map<String, dynamic>>> _fetchCharactersFromSupabase() async {
    try {
      final res = await Supabase.instance.client
          .from('characters')
          .select('*')
          .eq('enabled', true);
      if (res != null) {
        _cachedCharacters = List<Map<String, dynamic>>.from(res);
        return _cachedCharacters!;
      }
    } catch (e) {
      debugPrint('Error caching characters catalog: $e');
    } finally {
      _charactersLoadFuture = null;
    }
    return [];
  }
  
  Map<String, ui.Image> loadedAssetImages = {};
  Map<String, dynamic>? loadedRigData;
  bool isFpsMode = false;

  Map<String, int> playerTeams = {};

  bool _isFavoredPrey(String attackerSpecies, String victimSpecies) {
    final a = attackerSpecies.toLowerCase();
    final v = victimSpecies.toLowerCase();
    if (a.contains('ghost') && v.contains('humanoid')) return true;
    if (a.contains('humanoid') && v.contains('cybernetic')) return true;
    if (a.contains('cybernetic') && v.contains('alien')) return true;
    if (a.contains('alien') && v.contains('beast')) return true;
    if (a.contains('beast') && v.contains('ghost')) return true;
    return false;
  }

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

  void dropCursedRelic(Vector2 dropPos) {
    activeCursedRelicBoxId = 'relic_${DateTime.now().millisecondsSinceEpoch}';
    
    world.add(SpookyBox(id: activeCursedRelicBoxId!, position: dropPos));
    
    myChannel.sendBroadcastMessage(event: 'spawn_boxes', payload: {
      'boxes': [{'id': activeCursedRelicBoxId, 'x': dropPos.x, 'y': dropPos.y}]
    });
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
    this.driverId,
    this.partyPartnerUserId,
    this.hasGunner = false,
    this.mapName = 'L1T1V1.0.0',
    this.matchMode = 'casual',
    this.targetPlayers = 8,
    this.isGuildScrimmage = false,
    this.scrimmageMessageId,
    this.chaosModifier = 'none',
    this.onCinematicComplete,
  });

  late final JoystickComponent leftJoystick;
  late final JoystickComponent rightJoystick;
  late final Player player;
  late final ScareManager scareManager;
  late final PuzzleManager puzzleManager;

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
  String myUsername = 'Ghost';
  
  final List<BotPlayer> bots = [];
  final List<ScareSnapshot> matchPhotos = [];

  final int maxMatchPhotos = Random().nextDouble() < 0.20 ? 2 : 1;

  @override
  void lifecycleStateChange(AppLifecycleState state) {
    super.lifecycleStateChange(state);

    if (!gameStarted || matchPhase != 'playing') return;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      player.applyDissonance(10.0);
      
      myChannel.sendBroadcastMessage(
        event: 'dissonance', 
        payload: {'id': mySessionId, 'duration': 10.0}
      );
    }
  }

  void logScareSnapshot(ScareSnapshot snapshot, {required bool isHuman}) {
    if (matchPhotos.any((p) => p.victimName == snapshot.victimName)) return;

    if (matchPhotos.length < maxMatchPhotos) {
      matchPhotos.add(snapshot);
      return;
    }

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
            .select('completed_tutorial, level, username')
            .eq('id', user.id)
            .maybeSingle();
            
        if (profileRes != null) {
          needsTutorial = !(profileRes['completed_tutorial'] ?? false);
          myPlayerLevel = profileRes['level'] as int? ?? 1;
          myUsername = profileRes['username'] as String? ?? 'Ghost';
        }

        final membership = await Supabase.instance.client
            .from('guild_members')
            .select('guild_id, guilds(active_doctrine)')
            .eq('user_id', user.id)
            .maybeSingle();
            
        if (membership != null && membership['guilds'] != null) {
          myGuildId = membership['guild_id'];
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

    puzzleManager = PuzzleManager();
    await world.add(puzzleManager);

    List<Vector2> availableSpawns = gameMap.playerSpawns.isNotEmpty 
        ? List<Vector2>.from(gameMap.playerSpawns)
        : [Vector2(150, 150), Vector2(400, 400)]; 
    
    availableSpawns.shuffle(); 
    final rawSpawnPoint = availableSpawns.removeAt(0);
    final safeSpawnPoint = gameMap.getSafeSpawnLocation(rawSpawnPoint, Vector2.all(32.0));

    player = Player(leftJoystick, rightJoystick, myChannel, isGunner: isGunner)..position = safeSpawnPoint;
    jumpScareEffect = JumpScareEffect();

    // --- INJECT LOCAL DUMMY FOR TESTING ---
    if (driverId == 'dummy_driver_123') {
      final dummyDriver = RemotePlayer()..position = safeSpawnPoint.clone() + Vector2(100, 0);
      dummyDriver.facingAngle = 0.0;
      dummyDriver.equippedCharacterId = 'default'; 
      dummyDriver.applyTeamColor(1);
      
      networkPlayers['dummy_driver_123'] = dummyDriver;
      world.add(dummyDriver);
      
      dummyDriver.add(MoveEffect.by(
        Vector2(400, 0), 
        EffectController(duration: 4.0, reverseDuration: 4.0, infinite: true)
      ));

      dummyDriver.add(TimerComponent(
        period: 2.0,
        repeat: true,
        onTick: () {
          dummyDriver.facingAngle += pi / 4;
        },
      ));

      camera.viewport.add(FloatingText(
        text: 'I AM THE DUMMY', 
        worldPosition: dummyDriver.position - Vector2(40, 60)
      ));
    }

    world.add(player);
    camera.follow(player);

    camera.viewport.add(jumpScareEffect);
    camera.viewport.add(DarknessOverlay(player));

    await camera.viewport.add(FpsViewportOverlay());

    gameTimer = GameTimer();

    // ==========================================
    // 2D/3D ALTERNATOR
    // ==========================================
    final prefs = await SharedPreferences.getInstance();
    bool lastWasFps = prefs.getBool('last_match_was_fps') ?? false;

    if (matchMode == 'casual') {
      isFpsMode = !lastWasFps;
      await prefs.setBool('last_match_was_fps', isFpsMode);
    }

    if (matchMode == 'cinematic') {
      matchPhase = 'cinematic';
      gameStarted = true;
      isFpsMode = true; 

      final stageX = 15 * 64.0; 
      final stageY = 15 * 64.0; 

      player.position = Vector2(stageX, stageY + 128); 
      player.facingAngle = 0.0; 
      player.isInvisible = true; 

      stuntDoubleHero = BotPlayer(isHunter: false)
        ..position = Vector2(stageX + 400, stageY - 64) 
        ..wanderSpeed = 0.0
        ..huntSpeed = 0.0
        ..priority = 10;
      stuntDoubleHero!.assignedCharacterId = player.equippedCharacterId;

      cinematicMonster = BotPlayer(isHunter: false) 
        ..position = Vector2(stageX + 800, stageY - 64) 
        ..wanderSpeed = 0.0
        ..huntSpeed = 0.0
        ..priority = 10;

      world.add(stuntDoubleHero!);
      world.add(cinematicMonster!);
      
      bots.add(stuntDoubleHero!);
      bots.add(cinematicMonster!);

      cinematicStatusText = TextComponent(
        text: '',
        position: Vector2(camera.viewport.size.x / 2, 20),
        anchor: Anchor.topCenter,
        priority: 500,
        textRenderer: TextPaint(
          style: const TextStyle(
            color: Colors.cyanAccent,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFamily: 'Courier',
            shadows: [Shadow(color: Colors.black, blurRadius: 6)],
          ),
        ),
      );
      // Uncomment the line below if you want to see debug timecodes while testing:
      // camera.viewport.add(cinematicStatusText!);

    } else {
      // --- NORMAL GAME UI & CONTROLS ---
      world.add(PowerUpHud(player: player));

      camera.viewport.add(leftJoystick);

      camera.viewport.add(ScoreHud());
      camera.viewport.add(gameTimer);
      
      await camera.viewport.add(FpsTouchControls());
      await camera.viewport.add(ModeToggleButton());

      camera.viewport.add(QuickChatWheel());

      mapOverlay = MapOverlay();
      await camera.viewport.add(mapOverlay);
      await camera.viewport.add(MapButton());

      try {
        final logoSprite = await Sprite.load('Lumen_Breach_small.jpg');
        final logoComponent = SpriteComponent(
          sprite: logoSprite,
          size: Vector2(120, 60), 
          position: Vector2((camera.viewport.size.x / 2) + 6, camera.viewport.size.y - 23), 
          anchor: Anchor.bottomCenter,
          priority: 50, 
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
      camera.viewport.add(SpecialButton());

      if (needsTutorial) {
        gameStarted = true;
        gameTimer.start();
        camera.viewport.children.whereType<StartButton>().toList().forEach((btn) => btn.removeFromParent());
        world.add(PowerUp(id: 'tutorial_spark', position: safeSpawnPoint + Vector2(100, 0)));
        camera.viewport.add(TutorialManager());
      }

      overlays.add('help_button');
    }

    _setupSupabaseListener();
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (matchPhase == 'cinematic') {
      if (stuntDoubleHero?.voxelComponent == null || cinematicMonster?.voxelComponent == null) {
        return; 
      }

      // =========================================================================
      // INITIAL STAGE & 3D RAYCASTER GRID SCULPTING (RUNS EXACTLY ONCE AT t = 0)
      // =========================================================================
      if (cinematicTimer == 0.0) {
        player.hasExtendedRange = true;
        player.flashlightBattery = 100.0;
        player.isFlashlightDead = false;
        player.isRecharging = false;
        player.isLightFlickeringOut = false;
        player.isInvisible = true;

        // Carve a deterministic L-shaped corridor directly into gameMap.mapGrid
        // so the 3D FPS Raycaster renders a long brick wall & corner every time!
        for (int gy = 11; gy <= 18; gy++) {
          for (int gx = 7; gx <= 24; gx++) {
            if (gy >= 0 && gy < gameMap.gridHeight && gx >= 0 && gx < gameMap.gridWidth) {
              gameMap.mapGrid[gy][gx] = 0;
            }
          }
        }
        // Long main wall to run beside (Row 14, X = 704 to 1408; Corner edge is at X = 704)
        for (int gx = 11; gx <= 22; gx++) {
          gameMap.mapGrid[14][gx] = 1;
        }
        // Corridor South back-wall (Row 17) & North alcove wall (Row 11)
        for (int gx = 8; gx <= 23; gx++) {
          gameMap.mapGrid[17][gx] = 1;
          gameMap.mapGrid[11][gx] = 1;
        }
        // West alley outer wall (Col 8)
        for (int gy = 11; gy <= 17; gy++) {
          gameMap.mapGrid[gy][8] = 1;
        }

        cinematicStage1 = false;
        cinematicStage2 = false;
        cinematicStage3 = false;
        cinematicStage4 = false;
      }

      final double prevTime = cinematicTimer;
      cinematicTimer += dt;
      bool crossed(double t) => prevTime < t && cinematicTimer >= t;

      double progress(double start, double end) =>
          ((cinematicTimer - start) / (end - start)).clamp(0.0, 1.0);

      for (final actor in [stuntDoubleHero!, cinematicMonster!]) {
        actor.attackCooldown = 999.0;
        actor.wanderSpeed = 0.0;
        actor.huntSpeed = 0.0;
        actor.isStunned = false;
        //actor.isCharmed = false;
      }
      try {
        cinematicMonster!.voxelComponent!.activeMaskImage ??= images.fromCache('siren_mask.png');
      } catch (_) {}

      if (AudioManager.instance.isInitialized) {
        const double audioScale = 50.0;
        SoLoud.instance.set3dListenerPosition(player.position.x / audioScale, player.position.y / audioScale, 0.0);
        SoLoud.instance.set3dListenerAt(sin(player.facingAngle), -cos(player.facingAngle), 0.0);
        SoLoud.instance.set3dListenerUp(0.0, 0.0, -1.0);
      }

      // =========================================================================
      // BEAT 1 (0.0s - 5.2s): STATIONARY CAMERA FLY-BY (HUMAN, THEN MONSTER)
      // =========================================================================
      if (cinematicTimer < 5.2) {
        cinematicStatusText?.text = 'BEAT 1: CORRIDOR CHASE [${cinematicTimer.toStringAsFixed(1)}s]';

        player.position.setValues(780.0, 1025.0);
        player.facingAngle = 72.0 * (pi / 180.0);

        // 1A. Human sprints West (X: 1120 -> 620) from 0.2s to 2.5s
        if (cinematicTimer >= 0.2 && cinematicTimer <= 2.5) {
          final double p = progress(0.2, 2.5);
          stuntDoubleHero!.position.setValues(1120.0 - (500.0 * p), 985.0);
          stuntDoubleHero!.facingAngle = -pi / 2;
          stuntDoubleHero!.voxelComponent!.isMoving = true;
          if ((prevTime * 4).floor() != (cinematicTimer * 4).floor()) {
            AudioManager.instance.playEntityFootstep(stuntDoubleHero!.assignedCharacterId, stuntDoubleHero!.position);
          }
        } else {
          stuntDoubleHero!.position.setValues(-9999, -9999);
          stuntDoubleHero!.voxelComponent!.isMoving = false;
        }

        // 1B. Monster chases West along the exact same wall 2.4s later (2.6s to 4.8s)
        if (cinematicTimer >= 2.6 && cinematicTimer <= 4.8) {
          final double p = progress(2.6, 4.8);
          cinematicMonster!.position.setValues(1120.0 - (500.0 * p), 985.0);
          cinematicMonster!.facingAngle = -pi / 2;
          cinematicMonster!.voxelComponent!.isMoving = true;
          if ((prevTime * 5).floor() != (cinematicTimer * 5).floor()) {
            AudioManager.instance.playEntityFootstep('default', cinematicMonster!.position);
          }
        } else {
          cinematicMonster!.position.setValues(-9999, -9999);
          cinematicMonster!.voxelComponent!.isMoving = false;
        }
      }

      // =========================================================================
      // BEAT 2 (5.2s - 9.2s): 3RD-PERSON CORNER ROUNDING & 180 PEEK BEHIND WALL
      // =========================================================================
      else if (cinematicTimer < 9.2) {
        cinematicStatusText?.text = 'BEAT 2: CORNER HIDE [${cinematicTimer.toStringAsFixed(1)}s]';
        cinematicMonster!.position.setValues(-9999, -9999);
        cinematicMonster!.voxelComponent!.isMoving = false;

        player.position.setValues(655.0, 1050.0);
        player.facingAngle = 14.0 * (pi / 180.0);

        if (cinematicTimer < 6.8) {
          final double p = progress(5.2, 6.8);
          stuntDoubleHero!.position.setValues(675.0, 990.0 - (105.0 * p));
          stuntDoubleHero!.facingAngle = 0.0;
          stuntDoubleHero!.voxelComponent!.isMoving = true;
        } else if (cinematicTimer < 7.8) {
          final double p = progress(6.8, 7.8);
          stuntDoubleHero!.position.setValues(675.0 + (37.0 * p), 885.0);
          stuntDoubleHero!.facingAngle = pi / 2;
          stuntDoubleHero!.voxelComponent!.isMoving = true;
        } else {
          final double p = progress(7.8, 8.6);
          stuntDoubleHero!.position.setValues(712.0, 885.0);
          stuntDoubleHero!.facingAngle = (pi / 2) + (p * (pi / 2));
          stuntDoubleHero!.voxelComponent!.isMoving = false;
        }
      }

      // =========================================================================
      // BEAT 3 (9.2s - 13.0s): 1ST-PERSON POV BEHIND CORNER — MONSTER RUNS PAST!
      // =========================================================================
      else if (cinematicTimer < 13.0) {
        cinematicStatusText?.text = 'BEAT 3: 1ST-PERSON PEEK [${cinematicTimer.toStringAsFixed(1)}s]';

        stuntDoubleHero!.position.setValues(-9999, -9999);
        stuntDoubleHero!.voxelComponent!.isMoving = false;

        player.position.setValues(688.0, 915.0);
        player.facingAngle = pi - 0.08;

        if (cinematicTimer >= 9.5 && cinematicTimer <= 12.6) {
          final double p = progress(9.5, 12.6);
          cinematicMonster!.position.setValues(920.0 - (350.0 * p), 1005.0);
          cinematicMonster!.facingAngle = -pi / 2;
          cinematicMonster!.voxelComponent!.isMoving = true;
          if ((prevTime * 5).floor() != (cinematicTimer * 5).floor()) {
            AudioManager.instance.playEntityFootstep('default', cinematicMonster!.position);
          }
        } else {
          cinematicMonster!.position.setValues(-9999, -9999);
          cinematicMonster!.voxelComponent!.isMoving = false;
        }
      }

      // =========================================================================
      // BEAT 4 (13.0s - 16.5s): FLICKER, BLACKOUT, HEAVY BREATHING & RECHARGE
      // =========================================================================
      else if (cinematicTimer < 16.5) {
        cinematicStatusText?.text = 'BEAT 4: BLACKOUT & RECHARGE [${cinematicTimer.toStringAsFixed(1)}s]';
        cinematicMonster!.position.setValues(-9999, -9999);

        if (cinematicTimer < 13.9) {
          player.isLightFlickeringOut = (sin(cinematicTimer * 45.0) > 0.0);
          player.flashlightBattery = 12.0;
        } else if (cinematicTimer < 15.2) {
          if (!cinematicStage1) {
            cinematicStage1 = true;
            if (AudioManager.instance.isInitialized && AudioManager.instance.heavyBreathingSource != null) {
              SoLoud.instance.play(AudioManager.instance.heavyBreathingSource!, volume: 0.85);
            }
          }
          player.isLightFlickeringOut = false;
          player.isFlashlightDead = true;
          player.isRecharging = false;
          player.flashlightBattery = 0.0;
        } else {
          final double p = progress(15.2, 16.5);
          player.isFlashlightDead = false;
          player.isRecharging = true;
          player.flashlightBattery = 10.0 + (65.0 * p);
        }
      }

      // =========================================================================
      // BEAT 5 (16.5s - 20.5s): SLOW TURN AWAY + HOLD BREATH + HEARTBEAT
      // =========================================================================
      else if (cinematicTimer < 20.5) {
        cinematicStatusText?.text = 'BEAT 5: CREEPING DREAD [${cinematicTimer.toStringAsFixed(1)}s]';
        player.isRecharging = false;
        player.flashlightBattery = 100.0;

        cinematicMonster!.position.setValues(688.0, 964.0);
        cinematicMonster!.facingAngle = 0.0;
        cinematicMonster!.voxelComponent!.isMoving = false;

        if (cinematicTimer < 19.0) {
          final double p = progress(16.5, 19.0);
          final double smoothP = p * p * (3.0 - 2.0 * p);
          player.facingAngle = pi - (smoothP * (pi / 2));
        } else {
          player.facingAngle = pi / 2;
          if (!cinematicStage2) {
            cinematicStage2 = true;
            AudioManager.instance.stopPhysiologyLoops();
            if (AudioManager.instance.isInitialized) {
              if (AudioManager.instance.gaspBreathSource != null) {
                SoLoud.instance.play(AudioManager.instance.gaspBreathSource!, volume: 0.9);
              }
              if (AudioManager.instance.heartBeatSource != null) {
                SoLoud.instance.play(AudioManager.instance.heartBeatSource!, volume: 1.0);
              }
            }
          }
        }
      }

      // =========================================================================
      // BEAT 6 (20.5s - 24.5s): PANIC BREATH, FAST 90° TURN RIGHT & JUMP SCARE!
      // =========================================================================
      else {
        cinematicStatusText?.text = 'BEAT 6: THE BREACH [${cinematicTimer.toStringAsFixed(1)}s]';

        if (!cinematicStage3) {
          cinematicStage3 = true;
          if (AudioManager.instance.isInitialized && AudioManager.instance.heavyBreathingSource != null) {
            SoLoud.instance.play(AudioManager.instance.heavyBreathingSource!, volume: 1.0);
          }
        }

        if (cinematicTimer < 20.8) {
          player.facingAngle = pi / 2;
        } else if (cinematicTimer < 21.15) {
          final double p = progress(20.8, 21.15);
          final double whipCurve = pow(p, 2.5).toDouble();
          player.facingAngle = (pi / 2) + (whipCurve * (pi / 2));
        } else {
          player.facingAngle = pi;
        }

        if (cinematicTimer >= 21.2 && cinematicTimer < 22.6) {
          if (!cinematicStage4) {
            cinematicStage4 = true;
            cinematicMonster!.voxelComponent!.triggerScareAnimation('siren');
            jumpScareEffect.trigger();
            if (AudioManager.instance.isInitialized) {
              AudioManager.instance.playMaskScare('siren');
              if (AudioManager.instance.powerupSource != null) {
                SoLoud.instance.play(AudioManager.instance.powerupSource!, volume: 1.0);
              }
            }
          }
          final double lungeP = progress(21.2, 21.55);
          cinematicMonster!.position.setValues(688.0, 964.0 - (27.0 * lungeP));
        }

        if (cinematicTimer >= 22.6) {
          player.flashlightBattery = 0.0;
          player.isFlashlightDead = true;
          cinematicStatusText?.text = '';
        }

        if (crossed(23.6)) {
          AudioManager.instance.stopPhysiologyLoops();
          AudioManager.instance.playMenuMusic();
          pauseEngine();
          onCinematicComplete?.call();
        }
      }
      return;
    }
    
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

    if (isHost && gameStarted && matchPhase == 'playing') {
      if (willBlackoutHappen && !hasBlackoutFired) {
        timeUntilNextBlackout -= dt;
        if (timeUntilNextBlackout <= 0) {
          hasBlackoutFired = true;
          isGlobalBlackout = true;
          blackoutTimer = 30.0;
          
          myChannel.sendBroadcastMessage(event: 'global_blackout', payload: {'active': true, 'duration': 30.0});
          if (!player.isInPuzzleRoom) {
            camera.viewport.add(FloatingText(
              text: 'TOTAL BLACKOUT!', 
              worldPosition: Vector2(player.position.x - 40, player.position.y - 60)
            ));
          }
        }
      }

      if (isGlobalBlackout) {
        blackoutTimer -= dt;
        if (blackoutTimer <= 0) {
          isGlobalBlackout = false;
          myChannel.sendBroadcastMessage(event: 'global_blackout', payload: {'active': false});
        }
      }
    }

    if (matchPhase == 'countdown') {
      countdownTimer -= dt;
      int currentTick = countdownTimer.ceil();
      
      if (currentTick < _lastTick && currentTick > 0) {
        _lastTick = currentTick;
        if (AudioManager.instance.isInitialized && AudioManager.instance.tickSource != null) {
          SoLoud.instance.play(AudioManager.instance.tickSource!);
        }

        if (AudioManager.instance.isInitialized) {
          AudioManager.instance.playRandomInGameTrack();
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
      
      final activeAngle = player.facingAngle + player.glanceOffset;
      final forwardX = sin(activeAngle);
      final forwardY = -cos(activeAngle);
      SoLoud.instance.set3dListenerAt(forwardX, forwardY, 0.0);
      SoLoud.instance.set3dListenerUp(0.0, 0.0, -1.0);
    }

    if (isHost && bots.isNotEmpty) {
      hostBotSyncTick += dt;
      if (hostBotSyncTick >= hostBotSyncRate) {
        hostBotSyncTick = 0;
        List<Map<String, dynamic>> botData = [];
        for (var bot in bots) {
          botData.add({'x': bot.position.x, 'y': bot.position.y, 'a': bot.facingAngle, 'i': bot.isInvisible});
        }
        myChannel.sendBroadcastMessage(event: 'sync_bots', payload: {'bots': botData});
      }
    }
  }

  @override
  void onRemove() {
    if (matchPhotos.isNotEmpty) {
      lastMatchPhotos = List.from(matchPhotos);
    }
    
    myChannel.unsubscribe();
    if (!roomId.startsWith('public') && !roomId.startsWith('scrimmage_') && !roomId.startsWith('fright_')) {
      try {
        Supabase.instance.client.rpc('leave_match', params: {'p_match_id': roomId});
      } catch (e) {}
    }

    AudioManager.instance.stopMusic(); 
    AudioManager.instance.playMenuMusic(); 

    super.onRemove();
  }

  void _spawnWorldEntities() {
    if (bots.isNotEmpty) return; 
    if (matchMode == 'cinematic') return;
    
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

      int team1Count = 1;
      int team2Count = 0;

      for (var entry in networkPlayers.entries) {
        final String remoteSessionId = entry.key;
        final RemotePlayer rp = entry.value;

        if (matchMode == '2v2') {
          final bool isMyAlly = (rp.userId != null && (rp.userId == driverId || rp.userId == partyPartnerUserId)) ||
              (myGuildId != null && rp.guildId == myGuildId);

          int assignedTeam;
          if (isMyAlly && team1Count < 2) {
            assignedTeam = 1;
            team1Count++;
          } else if (team2Count < 2) {
            assignedTeam = 2;
            team2Count++;
          } else {
            assignedTeam = 1;
            team1Count++;
          }

          playerTeams[remoteSessionId] = assignedTeam;
          rp.applyTeamColor(assignedTeam);
        } else {
          playerTeams[remoteSessionId] = 0;
        }
      }

      int nextTeam = team1Count < 2 ? 1 : 2;

      int missingPlayers = targetPlayers - (1 + networkPlayers.length);
      
      for (int i = 0; i < missingPlayers; i++) {
        if (availableSpawns.isEmpty) break;
        Vector2 safeSpawn = gameMap.getSafeSpawnLocation(availableSpawns.removeAt(0), Vector2.all(32.0));
        
        final fakeHuman = BotPlayer(isHunter: false)
          ..position = safeSpawn
          ..wanderSpeed = 100.0 
          ..huntSpeed = 160.0
          ..teamId = (matchMode == '2v2') ? nextTeam : 0
          ..isCompetitiveStandIn = true;
          
        bots.add(fakeHuman);
        world.add(fakeHuman);

        if (matchMode == '2v2') nextTeam = (nextTeam == 1) ? 2 : 1; 
      }

      // --- FRIGHT NIGHT CHAOS MODIFIERS ---
      if (matchMode == 'fright_night' && chaosModifier == 'swarm') {
        List<Map<String, dynamic>> swarmData = [];
        int baseSeed = roomId.hashCode;
        
        for (int i = 0; i < 25; i++) {
          if (availableSpawns.isEmpty) break;
          Vector2 spawnPos = gameMap.getSafeSpawnLocation(
            availableSpawns[Random().nextInt(availableSpawns.length)], 
            Vector2.all(16.0)
          );
          
          double startAngle = Random().nextDouble() * pi * 2;
          
          swarmData.add({
            'x': spawnPos.x,
            'y': spawnPos.y,
            'seed': baseSeed + i,
            'angle': startAngle
          });
          
          scareManager.spawnCritter(Critter(
            position: spawnPos, behavior: SwarmBehavior.scatter, 
            seed: baseSeed + i, index: i, initialAngle: startAngle, ownerId: 'server_swarm'
          ));
        }
        
        myChannel.sendBroadcastMessage(event: 'spawn_swarm', payload: {'swarm': swarmData});
      } else if (matchMode == 'fright_night' && chaosModifier == 'pitch_black') {
        isGlobalBlackout = true;
        blackoutTimer = 9999.0;
        myChannel.sendBroadcastMessage(event: 'global_blackout', payload: {'active': true, 'duration': 9999.0});
      } else if (matchMode == 'fright_night' && chaosModifier == 'juggernaut') {
        matchHasHunter = true;
        hunterHasSpawned = true;
        if (bots.isNotEmpty) {
          bots.first.transformToHunter();
          myChannel.sendBroadcastMessage(event: 'hunter_emerge', payload: {'bot_index': 0});
        }
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

    if (AudioManager.instance.isInitialized) {
      AudioManager.instance.stopPhysiologyLoops();
      player.stopAudio();
      
      for (var bot in bots) {
        bot.stopAudio();
      }
      for (var remote in networkPlayers.values) {
        remote.stopAudio();
      }
      
      AudioManager.instance.stopMusic();
    }

    // ==========================================
    // JUGGERNAUT SCORE POOLING
    // ==========================================
    if (isGunner || hasGunner) {
      RemotePlayer? partner;
      
      if (isGunner && driverId != null) {
        partner = networkPlayers[driverId];
        if (partner == null) {
          for (final rp in networkPlayers.values) {
            if (rp.userId == driverId) {
              partner = rp;
              break;
            }
          }
        }
      } else if (hasGunner) {
        for (var remote in networkPlayers.values) {
          if (remote.position.distanceTo(player.position) < 50.0) {
            partner = remote;
            break;
          }
        }
      }

      if (partner != null) {
        int combinedScore = player.score + partner.score;
        player.score = combinedScore;
        partner.score = combinedScore;
        
        camera.viewport.add(FloatingText(
          text: 'SQUAD SCORE MERGED!', 
          worldPosition: Vector2(player.position.x - 50, player.position.y - 80)
        ));
      }
    }

    overlays.add('summary');
    
    // --- 1. CALCULATE LUMEN PLACEMENT ---
    List<int> allScores = [player.score];
    networkPlayers.forEach((id, remote) => allScores.add(remote.score));
    allScores.sort((a, b) => b.compareTo(a)); 
    
    int highestScore = allScores.first;
    bool isTie = allScores.where((s) => s == highestScore).length > 1;
    
    int baseStake = 27 + Random().nextInt(16);

    if (player.score == 0) {
      matchLumenDelta = -(baseStake - 2); 
    } else if (player.score == highestScore) {
      matchLumenDelta = isTie ? 2 : baseStake;
    } else {
      matchLumenDelta = -(baseStake - 2);
    }

    // --- 2. TEAM SCORING LOGIC ---
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
        matchLumenDelta = baseStake; 
      } else if (myTeamScore < enemyTeamScore) {
        matchLumenDelta = -(baseStake - 2);
      } else {
        matchLumenDelta = 2;
      }
    }

    if (!isGuildScrimmage) {
      int xpEarned = (player.score * 0.1).toInt();
      int shadowsEarned = (player.score * 0.05).toInt();
      
      int finalCoins = player.coinsEarned;
      if (matchLumenDelta < 0) {
         finalCoins = 0;
         shadowsEarned = 10;
      }

      if (myPlayerLevel < 3) {
        xpEarned *= 3; 
        shadowsEarned += 2500; 
        finalCoins += 50; 
        
        camera.viewport.add(FloatingText(
          text: 'ROOKIE BONUS APPLIED!', 
          worldPosition: Vector2(player.position.x - 50, player.position.y - 100)
        ));
      }

      lastMatchXpEarned = xpEarned;
      lastMatchShadowsEarned = shadowsEarned;
      lastMatchCoinsEarned = finalCoins;

      if (player.score > 0 || player.coinsEarned > 0 || matchLumenDelta != 0 || myPlayerLevel < 3) {
        try {
          await Supabase.instance.client.rpc(
            'process_match_rewards',
            params: {
              'xp_earned': xpEarned, 
              'shadows_earned': shadowsEarned, 
              'coins_earned': finalCoins,
              'p_lumen_delta': matchLumenDelta, 
            },
          );
        } catch (e) {
          debugPrint('Reward error: $e');
        }
        try {
          await Supabase.instance.client.from('player_tactics_log').insert({
            'user_id': Supabase.instance.client.auth.currentUser!.id,
            'match_id': roomId,
            'scares_attempted': player.scaresAttempted,
            'scares_landed': player.scaresLanded, 
            'time_zero_energy': player.timeZeroEnergy,
            'times_stunned_standard': player.timesStunnedStandard,
            'times_charmed_siren': player.timesCharmedSiren,
            'times_hit_swarm': player.timesHitSwarm,
            'distance_sprinted': player.distanceSprinted,
            'distance_sneaked': player.distanceSneaked,
          });
        } catch (e) {
          debugPrint('Telemetry logging error: $e');
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

      if (matchMode == 'fright_night' && myGuildId != null) {
        try {
          String _short(String id) => id.length >= 4 ? id.substring(0, 4) : id;
          
          Map<String, int> finalResults = {
            'Host (You)': player.score,
          };
          networkPlayers.forEach((id, rp) {
            finalResults['Player ${_short(id)}'] = rp.score;
          });

          var sortedEntries = finalResults.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          Map<String, int> sortedResults = Map.fromEntries(sortedEntries);

          Map<String, dynamic>? highlightMeta;
          if (matchPhotos.isNotEmpty) {
            final snapshot = matchPhotos[Random().nextInt(matchPhotos.length)];
            highlightMeta = {
              'attacker': snapshot.attackerName,
              'victim': snapshot.victimName,
              'mask_id': snapshot.attackerMaskId,
              'time': snapshot.timestamp,
            };
          }

          await Supabase.instance.client.from('guild_messages').insert({
            'guild_id': myGuildId,
            'sender_id': Supabase.instance.client.auth.currentUser!.id,
            'message': 'The bloodbath has concluded.',
            'metadata': {
              'type': 'fright_night_results',
              'results': sortedResults,
              'highlight': highlightMeta, 
            }
          });
        } catch (e) {
          debugPrint('Failed to post Fright Night results to chat: $e');
        }
      }
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
      if (boxId == activeCursedRelicBoxId) {
        player.applyChestReward(ChestReward(type: ChestRewardType.cursedRelic, label: 'THE CURSED RELIC!'));
        activeCursedRelicBoxId = null;
        return;
      }
      List<ChestReward> rewards = [
        ChestReward(type: ChestRewardType.points, label: '+50 SOULS', value: 50),
        ChestReward(type: ChestRewardType.points, label: '+50 SOULS', value: 50),
        ChestReward(type: ChestRewardType.points, label: '+50 SOULS', value: 50),
        ChestReward(type: ChestRewardType.points, label: '+100 SOULS', value: 100),
        ChestReward(type: ChestRewardType.points, label: '+100 SOULS', value: 100),
        ChestReward(type: ChestRewardType.invisibility, label: 'INVISIBILITY!'),
        ChestReward(type: ChestRewardType.invisibility, label: 'INVISIBILITY!'),
        ChestReward(type: ChestRewardType.teleport, label: 'TELEPORTED!'),
        ChestReward(type: ChestRewardType.teleport, label: 'TELEPORTED!'),
        ChestReward(type: ChestRewardType.rangeIncrease, label: 'RANGE EXTENDED!'),
        ChestReward(type: ChestRewardType.rangeIncrease, label: 'RANGE EXTENDED!'),
        ChestReward(type: ChestRewardType.disguise, label: 'DISGUISE!'),
        ChestReward(type: ChestRewardType.cursedRelic, label: 'THE CURSED RELIC!'),
      ];

      if (myPlayerLevel < 4) {
        rewards.addAll([
          ChestReward(type: ChestRewardType.currency, label: '+3 COINS', value: 3),
          ChestReward(type: ChestRewardType.currency, label: '+3 COINS', value: 3),
          ChestReward(type: ChestRewardType.currency, label: '+5 COINS', value: 5),
          ChestReward(type: ChestRewardType.currency, label: '+5 COINS', value: 5),
        ]);
      } else {
        rewards.addAll([
          ChestReward(type: ChestRewardType.currency, label: '+1 COIN', value: 1),
          ChestReward(type: ChestRewardType.currency, label: '+1 COIN', value: 1),
          ChestReward(type: ChestRewardType.currency, label: '+2 COINS', value: 2),
        ]);
      }

      final selectedReward = rewards[Random().nextInt(rewards.length)];
      player.applyChestReward(selectedReward);
      camera.viewport.add(FloatingText(text: selectedReward.label, worldPosition: Vector2(boxPos.x - 20, boxPos.y - 40)));
    }
  }

  void claimSpookyBoxForBot(String boxId, BotPlayer bot) {
    final boxes = world.children.whereType<SpookyBox>().where((b) => b.id == boxId).toList();
    if (boxes.isEmpty) return;

    final boxPos = boxes.first.position.clone();
    for (var box in boxes) box.removeFromParent();

    myChannel.sendBroadcastMessage(event: 'claim_box', payload: {'player_id': 'bot_${bots.indexOf(bot)}', 'box_id': boxId});

    if (AudioManager.instance.isInitialized && AudioManager.instance.powerupSource != null) {
      SoLoud.instance.play(AudioManager.instance.powerupSource!);
    }

    bot.simulatedScore += 75;
    camera.viewport.add(FloatingText(text: '+75 SOULS', worldPosition: Vector2(boxPos.x - 20, boxPos.y - 40)));
  }
  
  int triggerLocalScare(Vector2 attackerPos, double attackerAngle, bool isPoweredUp, {bool hasExtendedRange = false, double range = 250.0, required String maskId}) {
    int hitCount = 0;
    final forward = Vector2(sin(attackerAngle), -cos(attackerAngle));
    
    double scareRadius = range;
    if (hasExtendedRange) scareRadius = 600.0;
    if (maskId == 'siren') scareRadius = 2000.0;
    if (maskId == 'gorgon') scareRadius = 1200.0;
    if (maskId == 'banshee') scareRadius = 1500.0;

    for (var bot in bots) {
      if (bot.isHunter) bot.hearLoudNoise(attackerPos);
    }

    // ==========================================
    // 1. BOT COLLISION LOOP
    // ==========================================
    for (var bot in bots) {
      if (matchMode == '2v2' && getEntityTeam(player) == getEntityTeam(bot)) continue; 
      if (bot.localImmunityToMe > 0) continue; 
      
      String vSpecies = bot.species ?? 'humanoid';
      bool isPrey = _isFavoredPrey(player.species, vSpecies);
      double effectiveRadius = scareRadius * (isPrey ? 1.15 : 1.0);

      final toBot = bot.position - attackerPos;
      if (toBot.length < effectiveRadius) {
        toBot.normalize();
        final dot = forward.dot(toBot);

        if (maskId == 'siren') {
          if (dot > 0.0) { 
            bot.applyCharm(15.0, player);
            bot.localImmunityToMe = 16.0;
            hitCount++;
            player.scaresLanded++;
          }
        } 
        else {
          bool isHit = false;
          
          if (maskId == 'banshee') {
             final rawVector = bot.position - attackerPos;
             final proj = rawVector.dot(forward);
             if (proj > 0) { 
               final perpDist = (rawVector - (forward * proj)).length;
               if (perpDist < 128.0) isHit = true;
             }
          } else {
             final coneThreshold = isPoweredUp ? -0.2 : 0.1;
             bool hasLOS = gameMap.hasLineOfSight(bot.position, attackerPos);
             if (dot > coneThreshold && hasLOS) isHit = true;
          }
          
          bool isLookingAtAttacker = true;
          if (maskId == 'gorgon') {
             final botForward = Vector2(sin(bot.facingAngle), -cos(bot.facingAngle));
             final botToAttacker = (attackerPos - bot.position).normalized();
             isLookingAtAttacker = botForward.dot(botToAttacker) > 0.2;
          }

          if (isHit && isLookingAtAttacker) {
            if (bot.isHunter) {
              if (bot.isCoreExposed) {
                bot.applyStun(8.0); bot.localImmunityToMe = 10.0; 
                hitCount++;
                player.scaresLanded++;                
                player.score += 2500; 
                camera.viewport.add(FloatingText(text: 'CRITICAL OVERLOAD! +2500', worldPosition: Vector2(bot.position.x - 40, bot.position.y - 60)));
              } else {
                bot.applyStun(0.1); 
                camera.viewport.add(FloatingText(text: 'ARMOR DEFLECTED!', worldPosition: Vector2(bot.position.x - 20, bot.position.y - 40)));
              }
            } else {
              double stunDuration = _matchesDoctrine(bot) ? 4.4 : 4.0;
              if (isPrey) stunDuration *= 1.15; 
              
              if (maskId == 'parasite') {
                stunDuration = 1.5;
                player.flashlightBattery = (player.flashlightBattery + 25.0).clamp(0.0, 100.0);
                player.energy = (player.energy + 3.0).clamp(0.0, player.maxEnergy);
              }
              
              bot.applyStun(stunDuration); bot.localImmunityToMe = 7.0; bot.triggerPrivateHighlight(); hitCount++;

              logScareSnapshot(ScareSnapshot(
                attackerName: player.score > 0 ? 'You' : 'Attacker', 
                attackerCharId: player.equippedCharacterId, attackerMaskId: maskId,
                victimName: bot.fakeUsername, victimCharId: bot.assignedCharacterId,
                victimMaskId: bot.currentMaskId,
                timestamp: gameTimer.timeLeft.toInt(), mapX: attackerPos.x, mapY: attackerPos.y,
              ), isHuman: false);

              camera.viewport.add(FloatingText(text: '+100 SOULS', worldPosition: Vector2(bot.position.x - 25, bot.position.y - 60)));
            }
          }
        }
      }
    }

    // ==========================================
    // 2. REMOTE PLAYER COLLISION LOOP
    // ==========================================
    for (var remoteId in networkPlayers.keys) {
      if ((isGunner || hasGunner) && (remoteId == driverId || networkPlayers[remoteId]?.userId == driverId || networkPlayers[remoteId]?.userId == partyPartnerUserId)) {
        continue;
      }
      if (matchMode == '2v2' && getEntityTeam(player) == getEntityTeam(remoteId)) continue; 
      
      var remotePlayer = networkPlayers[remoteId]!;
      if (remotePlayer.localImmunityToMe > 0) continue; 
      
      String vSpecies = 'humanoid';
      try { vSpecies = remotePlayer.species; } catch (_) {}
      bool isPrey = _isFavoredPrey(player.species, vSpecies);

      double effectiveRadius = scareRadius * (isPrey ? 1.15 : 1.0);
      
      final toPlayer = remotePlayer.position - attackerPos;
      if (toPlayer.length < effectiveRadius) {
        toPlayer.normalize();
        final dot = forward.dot(toPlayer);

        if (maskId == 'siren') {
          if (dot > 0.0) {
            remotePlayer.localImmunityToMe = 16.0; hitCount++;
            myChannel.sendBroadcastMessage(event: 'charm', payload: {'id': remoteId, 'duration': 15.0, 'charmer_x': attackerPos.x, 'charmer_y': attackerPos.y});
          }
        } else {
          bool isHit = false;
          
          if (maskId == 'banshee') {
             final rawVector = remotePlayer.position - attackerPos;
             final proj = rawVector.dot(forward);
             if (proj > 0) { 
               final perpDist = (rawVector - (forward * proj)).length;
               if (perpDist < 128.0) isHit = true;
             }
          } else {
             final coneThreshold = isPoweredUp ? -0.2 : 0.1;
             bool hasLOS = gameMap.hasLineOfSight(remotePlayer.position, attackerPos);
             if (dot > coneThreshold && hasLOS) isHit = true;
          }
          
          bool isLookingAtAttacker = true;
          if (maskId == 'gorgon') {
             final rpForward = Vector2(sin(remotePlayer.facingAngle), -cos(remotePlayer.facingAngle));
             final rpToAttacker = (attackerPos - remotePlayer.position).normalized();
             isLookingAtAttacker = rpForward.dot(rpToAttacker) > 0.2; 
          }

          if (isHit && isLookingAtAttacker) {
            hitCount++;
            player.scaresLanded++;
            remotePlayer.localImmunityToMe = 5.0; 
            remotePlayer.triggerPrivateHighlight(); 
            
            double stunDuration = _matchesDoctrine(remotePlayer) ? 2.2 : 2.0;
            if (isPrey) stunDuration *= 1.15;
            
            if (maskId == 'parasite') {
              stunDuration = 1.5; 
              player.flashlightBattery = (player.flashlightBattery + 25.0).clamp(0.0, 100.0);
              player.energy = (player.energy + 3.0).clamp(0.0, player.maxEnergy);
            }

            myChannel.sendBroadcastMessage(event: 'stun', payload: {
              'id': remoteId, 'duration': stunDuration, 
              'attacker_id': mySessionId, 'attacker_x': attackerPos.x, 'attacker_y': attackerPos.y,
              'mask_id': maskId
            });

            logScareSnapshot(ScareSnapshot(
              attackerName: 'You', attackerCharId: player.equippedCharacterId, attackerMaskId: maskId,
              victimName: remoteId.substring(0, 4), victimCharId: remotePlayer.equippedCharacterId,
              victimMaskId: remotePlayer.currentMaskId,
              victimId: remoteId, timestamp: gameTimer.timeLeft.toInt(), mapX: attackerPos.x, mapY: attackerPos.y,
            ), isHuman: true);

            camera.viewport.add(FloatingText(text: '+100 SOULS', worldPosition: Vector2(remotePlayer.position.x - 25, remotePlayer.position.y - 60)));
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
    if (AudioManager.instance.isInitialized) {
      AudioManager.instance.playRandomInGameTrack();
    }
  }

  void _setupSupabaseListener() {
    myChannel
      .onPresenceSync((payload) {
        final presenceState = myChannel.presenceState();
        List<Map<String, dynamic>> allUsers = [];
        for (final state in presenceState) {
          for (final presence in state.presences) {
            if (presence.payload != null && presence.payload.containsKey('id')) {
              allUsers.add({
                'id': presence.payload['id'], 
                'user_id': presence.payload['user_id'],
                'guild_id': presence.payload['guild_id'],
                'username': presence.payload['username'] ?? 'Player',
                'joined_at': presence.payload['joined_at']
              });
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
          if (id != mySessionId) {
            if (!networkPlayers.containsKey(id)) {
              if (matchPhase != 'searching') continue; 
              final newPlayer = RemotePlayer()..position = Vector2(-100, -100);
              networkPlayers[id] = newPlayer;
              world.add(newPlayer);
            }
            networkPlayers[id]!.username = (user['username'] as String?) ?? 'Player';
            networkPlayers[id]!.userId = user['user_id'] as String?;
            networkPlayers[id]!.guildId = user['guild_id'] as String?;
          }
        }

        final activeIds = allUsers.map((u) => u['id']).toSet();
        networkPlayers.keys.toList().forEach((id) {
          if (!activeIds.contains(id) && id != 'dummy_driver_123') {
            networkPlayers[id]?.removeFromParent();
            networkPlayers.remove(id);
          }
        });
      })
      .onBroadcast(
        event: 'spawn_swarm',
        callback: (payload) {
          if (!isHost) {
            final swarmList = payload['swarm'] as List<dynamic>;
            for (int i = 0; i < swarmList.length; i++) {
              final data = swarmList[i];
              scareManager.spawnCritter(Critter(
                position: Vector2((data['x'] as num).toDouble(), (data['y'] as num).toDouble()),
                behavior: SwarmBehavior.scatter,
                seed: (data['seed'] as num).toInt(),
                index: i,
                initialAngle: (data['angle'] as num).toDouble(),
                ownerId: 'server_swarm'
              ));
            }
          }
        },
      )
      .onBroadcast(
        event: 'hunter_emerge',
        callback: (payload) {
          if (!isHost) {
            final index = (payload['bot_index'] as num?)?.toInt();
            if (index != null && index >= 0 && index < bots.length) {
              bots[index].transformToHunter();
            }
          }
        },
      )
      .onBroadcast(
        event: 'bot_scare',
        callback: (payload) {
          if (!isHost) {
            final index = (payload['bot_index'] as num).toInt();
            if (index >= 0 && index < bots.length) {
              final bot = bots[index];
              bot.currentMaskId = payload['mask_id'] as String;
              bot.position.x = (payload['x'] as num).toDouble();
              bot.position.y = (payload['y'] as num).toDouble();
              bot.facingAngle = (payload['a'] as num).toDouble();
              
              if (bot.position.distanceTo(player.position) < 1000.0) {
                if (bot.voxelComponent != null) bot.voxelComponent!.triggerScareAnimation(bot.currentMaskId);
              }

              AudioManager.instance.playSpatialScare(bot.currentMaskId, bot.position);
              
              if (bot.currentMaskId == 'flying') {
                world.add(FlyingScareBlast(position: bot.position.clone(), angle: bot.facingAngle, ownerId: 'bot_$index'));
              } else if (bot.currentMaskId == 'vermin') {
                for (int i = 0; i < 15; i++) {
                  scareManager.spawnCritter(Critter(position: bot.position.clone(), behavior: SwarmBehavior.scatter, seed: DateTime.now().millisecondsSinceEpoch, index: i, initialAngle: bot.facingAngle, ownerId: 'bot_$index'));
                }
              } else if (bot.currentMaskId == 'siren') {
                bot.add(SirenBlast()..position = bot.size / 2);
              } else if (bot.currentMaskId == 'banshee') {
                world.add(BansheeBeam(position: bot.position.clone(), angle: bot.facingAngle));
              } else {
                world.add(ScareBlast(position: bot.position.clone(), angle: bot.facingAngle - (pi / 2))..priority = bot.priority + 5);
              }
            }
          }
        },
      )
      .onBroadcast(
        event: 'quick_chat',
        callback: (payload) {
          final senderId = payload['id'] as String?;
          final text = payload['text'] as String? ?? '';
          final colorValue = (payload['color'] as num).toInt();
          
          if (senderId == null || senderId == mySessionId) return;

          if (networkPlayers.containsKey(senderId)) {
            final remote = networkPlayers[senderId]!;
            remote.add(ChatBubbleComponent(
              text: text, 
              borderColor: Color(colorValue),
            ));
            
            if (AudioManager.instance.isInitialized && AudioManager.instance.tickSource != null) {
              SoLoud.instance.play(AudioManager.instance.tickSource!, volume: 0.8);
            }
          } 
          else if (senderId.startsWith('bot_')) {
            int botIndex = int.tryParse(senderId.split('_')[1]) ?? -1;
            if (botIndex >= 0 && botIndex < bots.length) {
              bots[botIndex].add(ChatBubbleComponent(text: text, borderColor: Color(colorValue)));
              
              if (AudioManager.instance.isInitialized && AudioManager.instance.tickSource != null) {
                SoLoud.instance.play(AudioManager.instance.tickSource!, volume: 0.8);
              }
            }
          }
        },
      )
      .onBroadcast(
        event: 'wall_hit',
        callback: (payload) {
          final id = payload['id'] as String?;
          if (id != null && networkPlayers.containsKey(id)) {
            final remote = networkPlayers[id]!;
            remote.position.x = (payload['x'] as num).toDouble();
            remote.position.y = (payload['y'] as num).toDouble();
            remote.triggerPrivateHighlight();
            
            if (AudioManager.instance.isInitialized && AudioManager.instance.impactSource != null) {
              SoLoud.instance.play(AudioManager.instance.impactSource!, volume: 0.6);
            }
          }
        },
      )
      .onBroadcast(
        event: 'move',
        callback: (payload) {
          final id = payload['id'] as String?;
          if (id == null || id == mySessionId) return;
          if (id != mySessionId) {
            final x = (payload['x'] as num).toDouble();
            final y = (payload['y'] as num).toDouble();
            final angle = (payload['a'] as num).toDouble();
            final colorStr = payload['c'] as String?; 
            final newScore = (payload['s'] as num?)?.toInt(); 
            final isDisguised = payload['d'] as bool? ?? false;
            final isMoving = payload['m'] as bool? ?? false;
            final isInvisible = payload['i'] as bool? ?? false;
            final fScale = (payload['f'] as num?)?.toDouble() ?? 1.0;
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
        event: 'global_blackout',
        callback: (payload) {
          isGlobalBlackout = payload['active'] as bool? ?? false;
        },
      )
      .onBroadcast(
        event: 'scare',
        callback: (payload) {
          final id = payload['id'] as String?;
          if (id == null || id == mySessionId || !networkPlayers.containsKey(id)) return;
          if (id != mySessionId && networkPlayers.containsKey(id)) {
            final remote = networkPlayers[id]!;
            remote.position.x = (payload['x'] as num).toDouble();
            remote.position.y = (payload['y'] as num).toDouble();
            remote.facingAngle = (payload['a'] as num).toDouble();
            
            final maskId = payload['mask_id'] as String? ?? 'standard'; 
            final seed = (payload['seed'] as num?)?.toInt() ?? 0;

            remote.currentMaskId = maskId;

            if (remote.position.distanceTo(player.position) < 1000.0) {
              if (remote.voxelComponent != null) remote.voxelComponent!.triggerScareAnimation(maskId);
            }

            AudioManager.instance.playSpatialScare(maskId, remote.position);

            if (maskId == 'flying') {
              world.add(FlyingScareBlast(position: remote.position.clone(), angle: remote.facingAngle, ownerId: payload['id']));
            } else if (maskId == 'vermin') {
              for (int i = 0; i < 15; i++) { 
                scareManager.spawnCritter(Critter(
                  position: remote.position.clone(), behavior: SwarmBehavior.scatter,
                  seed: seed, index: i, initialAngle: remote.facingAngle, ownerId: id,
                ));
              }
            } else if (maskId == 'siren') {
              remote.add(SirenBlast()..position = remote.size / 2);
            } else if (maskId == 'banshee') {
               world.add(BansheeBeam(position: remote.position.clone(), angle: remote.facingAngle));
            } else if (maskId == 'wendigo') {
               world.add(WendigoDecoy(
                 position: remote.position.clone(), 
                 angle: remote.facingAngle, 
                 ownerId: id, 
                 charId: remote.equippedCharacterId ?? 'default'
               ));
            } else if (maskId == 'poltergeist') {
               world.add(PoltergeistTrap(
                 position: remote.position.clone(), 
                 angle: remote.facingAngle, 
                 ownerId: id
               ));
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
        event: 'trap_detonate',
        callback: (payload) {
          final ownerId = payload['owner_id'] as String?;
          
          if (ownerId != null && ownerId != mySessionId) {
            final trapX = (payload['x'] as num).toDouble();
            final trapY = (payload['y'] as num).toDouble();
            final trapAngle = (payload['a'] as num).toDouble();
            final trapPos = Vector2(trapX, trapY);

            world.add(ScareBlast(position: trapPos.clone(), angle: trapAngle - (pi / 2))..priority = 1000);
            AudioManager.instance.playSpatialScare('standard', trapPos);
            
            camera.viewport.add(FloatingText(
              text: 'POLTERGEIST TRIGGERED!', 
              worldPosition: Vector2(trapX - 60, trapY - 60)
            ));
          }
        },
      )
      .onBroadcast(
        event: 'taunt',
        callback: (payload) {
          final id = payload['id'] as String?;
          if (id == null || id == mySessionId) return;
          
          final tauntId = payload['taunt_id'] as String? ?? 'default';
          final tauntPos = Vector2((payload['x'] as num).toDouble(), (payload['y'] as num).toDouble());

          AudioManager.instance.playSpatialTaunt(tauntId, tauntPos);

          if (networkPlayers.containsKey(id)) {
            camera.viewport.add(FloatingText(
              text: '*TAUNT*', 
              worldPosition: Vector2(tauntPos.x - 30, tauntPos.y - 60)
            ));
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
        event: 'dissonance',
        callback: (payload) {
          final id = payload['id'] as String?;
          if (id == mySessionId) {
            final duration = (payload['duration'] as num?)?.toDouble() ?? 3.0;
            player.applyDissonance(duration);
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
          final maskId = payload['mask_id'] as String? ?? 'standard';

          if (targetId == mySessionId) {
            jumpScareEffect.trigger();
            
            Vector2? atkPos;
            if (payload.containsKey('attacker_x') && payload.containsKey('attacker_y')) {
              atkPos = Vector2((payload['attacker_x'] as num).toDouble(), (payload['attacker_y'] as num).toDouble());
            }

            if (maskId == 'parasite') {
              player.flashlightBattery = (player.flashlightBattery - 25.0).clamp(0.0, 100.0);
              player.energy = (player.energy - 3.0).clamp(0.0, player.maxEnergy);
              camera.viewport.add(FloatingText(text: 'VAMPIRIZED!', worldPosition: Vector2(player.position.x - 20, player.position.y - 40)));
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
              world.add(SpookyBox(id: data['id'] as String, position: Vector2((data['x'] as num).toDouble(), (data['y'] as num).toDouble())));
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
                playerTeams[key] = (value as num).toInt();
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
        callback: (payload) {
          final boxId = payload['box_id'] as String?;
          final playerId = payload['player_id'] as String?;
          if (boxId != null && playerId != null) {
            _executeBoxClaim(boxId, playerId);
          }
        },
      )
      .onBroadcast(
        event: 'match_control',
        callback: (payload) {
          final action = payload['action'] as String?;
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
              bots[i].position.x = (data['x'] as num).toDouble();
              bots[i].position.y = (data['y'] as num).toDouble();
              bots[i].facingAngle = (data['a'] as num).toDouble();
              bots[i].isInvisible = data['i'] as bool? ?? false;
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
            gameTimer.matchEndTime = DateTime.now().add(Duration(milliseconds: (time * 1000).toInt()));
            
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
          final id = payload['id'] as String?;
          if (id != null) {
             world.children.whereType<PowerUp>().where((p) => p.id == id).toList().forEach((p) => p.removeFromParent());
          }
        },
      )
      .subscribe((status, [error]) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await myChannel.track({ 
            'id': mySessionId, 
            'user_id': Supabase.instance.client.auth.currentUser?.id,
            'guild_id': myGuildId,
            'username': myUsername, 
            'joined_at': DateTime.now().toUtc().toIso8601String()
          });
          myChannel.sendBroadcastMessage(event: 'request_sync', payload: {});
        }
      });
  }

  // Just-In-Time Asset Loader
  static Future<void> ensureCharacterLoaded(String charId) async {
    if (charId == 'default' || characterImagesCache.containsKey(charId)) return;

    try {
      final chars = await getEnabledCharacters();
      Map<String, dynamic>? charRes;
      for (final c in chars) {
        if (c['id'] == charId) {
          charRes = c;
          break;
        }
      }
      
      charRes ??= await Supabase.instance.client
          .from('characters').select('zip_asset_path').eq('id', charId).eq('enabled', true).maybeSingle();
      
      if (charRes == null || charRes['zip_asset_path'] == null) return;
      
      String zipPath = charRes['zip_asset_path'];
      
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
      debugPrint('Lazy load bypassed for missing asset $charId: $e');
    }
  }
}
