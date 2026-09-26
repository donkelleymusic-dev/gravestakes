import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'game.dart';
import 'scare_blast.dart';
import 'voxel_character_component.dart';
import 'floating_text.dart';
import 'audio_manager.dart';
import 'player.dart';
import 'remote_player.dart';
import 'mask_data.dart';
import 'critter.dart';
import 'flying_scare_blast.dart';
import 'siren_blast.dart';
import 'spooky_box.dart';

enum BotState { wander, hunt, investigate, charmed, flee }
enum BotPersonality { grunt, stalker, phantom, trapdoor }

class BotPlayer extends PositionComponent with HasGameReference<GraveStakesGame> {

  BotPersonality personality = BotPersonality.grunt;
  late TextComponent debugLabel;

  bool isHunter; 
  double wanderSpeed = 80.0;
  double huntSpeed = 130.0; 
  double visualScale = 1.0;
  String assignedCharacterId = 'default';
  String species = 'humanoid';
  
  int teamId = 0;
  
  double _footstepTimer = 0.0;
  final double _audioScale = 50.0;   

  double recoveryTimer = 0.0;

  BotState currentState = BotState.wander;
  PositionComponent? currentTarget;
  PositionComponent? charmerTarget; 
  Vector2? lastKnownPosition; 

  bool isStunned = false;
  double stunTimer = 0;
  double charmTimer = 0; 
  double attackCooldown = 0;
  double localImmunityToMe = 0;
  double directionTimer = 0;
  double evasionTimer = 0; 
  Vector2 movementDelta = Vector2.zero();
  
  double facingAngle = 0.0;
  String currentMaskId = 'standard';
  bool isInvisible = false;

  VoxelCharacterComponent? voxelComponent;
  RectangleComponent? _fallbackSprite;
  
  final Random _random = Random();
  double highlightTimer = 0;

  double coreCycleTimer = 0.0;
  bool isCoreExposed = false;
  Vector2? acousticAggroTarget;
  double acousticAggroTimer = 0.0;
  List<Vector2> _hunterPath = [];
  double _pathRecalcTimer = 0.0;

  static const List<String> _fakeNames = [
    'ShadowWalker99', 'GraveDigger', 'LumenThief', 'SpookyToast', 
    'NightTerrors', 'xX_Vamp_Xx', 'Echo_Location', 'SirenBait'
  ];
  
  bool isCompetitiveStandIn = false;
  late final String fakeUsername;
  int simulatedScore = 0; 
  
  void transformToHunter() {
    if (isHunter) return;
    isHunter = true;
    personality = BotPersonality.grunt; // The Goliath just hunts blindly
    
    if (parent != null) {
      debugLabel.text = '[GOLIATH]';
      debugLabel.textRenderer = TextPaint(style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontFamily: 'Courier'));
    }

    String goliathId = 'the_goliath';
    if (!GraveStakesGame.characterRigCache.containsKey(goliathId)) {
      if (GraveStakesGame.characterRigCache.containsKey('goliath')) {
        goliathId = 'goliath';
      }
    }
    assignedCharacterId = goliathId;
    species = 'alien';

    visualScale *= 1.4;
    huntSpeed *= 1.35;
    scale = Vector2.all(visualScale);

    // Async load Goliath so it doesn't stutter the game!
    GraveStakesGame.ensureCharacterLoaded(assignedCharacterId).then((_) {
      if (voxelComponent != null) voxelComponent!.removeFromParent();

      final rig = GraveStakesGame.characterRigCache[assignedCharacterId] ?? game.loadedRigData;
      if (rig != null) {
        voxelComponent = VoxelCharacterComponent(
          images: GraveStakesGame.characterImagesCache[assignedCharacterId] ?? game.loadedAssetImages,
          rigData: rig,
          hitboxSize: size,
        )
          ..anchor = Anchor.bottomCenter
          ..position = Vector2(size.x / 2, size.y);
        add(voxelComponent!);
      }
    });

    if (voxelComponent != null) {
      voxelComponent!.removeFromParent();
    }

    final rig = GraveStakesGame.characterRigCache[assignedCharacterId] ?? game.loadedRigData;
    if (rig != null) {
      voxelComponent = VoxelCharacterComponent(
        images: GraveStakesGame.characterImagesCache[assignedCharacterId] ?? game.loadedAssetImages,
        rigData: rig,
        hitboxSize: size,
      )
        ..anchor = Anchor.bottomCenter
        ..position = Vector2(size.x / 2, size.y);
      add(voxelComponent!);
    }

    if (_fallbackSprite != null) {
      _fallbackSprite!.paint.color = Colors.redAccent;
    }

    triggerPrivateHighlight();

    game.camera.viewport.add(FloatingText(
      text: 'THE GOLIATH HAS AWOKEN!',
      worldPosition: Vector2(position.x - 60, position.y - 80),
    ));

    if (AudioManager.instance.isInitialized && AudioManager.instance.powerupSource != null) {
      SoLoud.instance.play(AudioManager.instance.powerupSource!, volume: 1.0);
    }
  }

  void hearLoudNoise(Vector2 noisePos) {
    if (isHunter) {
      acousticAggroTarget = noisePos.clone();
      acousticAggroTimer = 8.0; 
    }
  }

  void triggerPrivateHighlight() {
    highlightTimer = 1.0; 
    if (_fallbackSprite != null) _fallbackSprite!.paint.color = Colors.white; 
  }

  BotPlayer({this.isHunter = false}) : super(size: Vector2.all(32.0), anchor: Anchor.center) {
    fakeUsername = _fakeNames[_random.nextInt(_fakeNames.length)];
  }

  void _updatePhantomLogic(double dt) {
    PositionComponent? prey = _getAbsoluteClosestPlayer();

    if (prey != null) {
      currentState = BotState.hunt;

      // 1. Relentless Pathfinding (Ignores Line of Sight)
      _pathRecalcTimer -= dt;
      if (_pathRecalcTimer <= 0) {
        _hunterPath = game.gameMap.findPath(position, prey.position);
        _pathRecalcTimer = 0.5; 
      }

      if (_hunterPath.isNotEmpty) {
        if (position.distanceTo(_hunterPath.first) < 15.0) _hunterPath.removeAt(0);
        if (_hunterPath.isNotEmpty) {
          movementDelta = (_hunterPath.first - position).normalized();
        } else {
          movementDelta = (prey.position - position).normalized();
        }
      } else {
        movementDelta = (prey.position - position).normalized();
      }
      facingAngle = movementDelta.screenAngle();

      // 2. The Dissonance Aura (AoE Scramble)
      if (attackCooldown <= 0 && position.distanceTo(prey.position) < 250.0) {
        game.camera.viewport.add(FloatingText(
          text: 'DISRUPTED!', 
          worldPosition: Vector2(position.x - 35, position.y - 60),
        ));

        if (prey == game.player) {
          game.player.applyDissonance(3.0);
        } else if (prey is RemotePlayer) {
          String? targetId;
          game.networkPlayers.forEach((key, val) { if (val == prey) targetId = key; });
          if (targetId != null) {
            game.myChannel.sendBroadcastMessage(event: 'dissonance', payload: {'id': targetId, 'duration': 3.0});
          }
        }
        
        triggerPrivateHighlight();
        if (AudioManager.instance.isInitialized && AudioManager.instance.tickSource != null) {
          SoLoud.instance.play(AudioManager.instance.tickSource!, volume: 1.0);
        }
        
        attackCooldown = 25.0; // Recasts the scramble every 25 seconds if they stay close
      }
    } else {
      _updateGruntLogic(dt);
    }
  }

  bool _isInVisionCone(Vector2 targetPos) {
    final vectorToTarget = targetPos - position;
    final angleToTarget = atan2(vectorToTarget.y, vectorToTarget.x);
    
    double diffAngle = (angleToTarget - facingAngle) % (2 * pi);
    if (diffAngle > pi) diffAngle -= 2 * pi;
    else if (diffAngle < -pi) diffAngle += 2 * pi;
    
    const double fov = pi / 1.5; 
    return diffAngle.abs() <= (fov / 2);
  }

  @override
  Future<void> onLoad() async {
    priority = ((position.y + 16) * 10).toInt(); 

    if (!isHunter) {
      if (_random.nextInt(10) == 0) {
        bool hasStalker = game.bots.any((b) => b != this && b.personality == BotPersonality.stalker);
        bool hasPhantom = game.bots.any((b) => b != this && b.personality == BotPersonality.phantom);
        bool hasTrapdoor = game.bots.any((b) => b != this && b.personality == BotPersonality.trapdoor);

        List<BotPersonality> specialtyPool = [];
        if (!hasStalker) specialtyPool.add(BotPersonality.stalker);
        if (!hasPhantom) specialtyPool.add(BotPersonality.phantom);
        if (!hasTrapdoor) specialtyPool.add(BotPersonality.trapdoor);

        if (specialtyPool.isNotEmpty) {
          personality = specialtyPool[_random.nextInt(specialtyPool.length)];
        } else {
          personality = BotPersonality.grunt;
        }
      } else {
        personality = BotPersonality.grunt;
      }
    }

    try {
      final supabase = Supabase.instance.client;
      final charsRes = await supabase.from('characters').select('*');
      
      if (charsRes != null && charsRes.isNotEmpty) {
        final List<Map<String, dynamic>> chars = List<Map<String, dynamic>>.from(charsRes);
        final randomChar = chars[_random.nextInt(chars.length)];
        
        assignedCharacterId = randomChar['id'] ?? 'default';
        species = randomChar['species'] as String? ?? 'humanoid';
        final baseSpeed = (randomChar['base_speed'] as num?)?.toDouble() ?? 200.0;
        
        // --- SCALING BOT DIFFICULTY ---
        // Increase speed parameters based on the host's current score
        double levelMultiplier = 1.0;
        if (game.player.score > 2000) levelMultiplier = 1.15; 
        if (game.player.score > 5000) levelMultiplier = 1.30; 
        
        wanderSpeed = baseSpeed * 0.40 * levelMultiplier;  
        huntSpeed = baseSpeed * 0.65 * levelMultiplier;    
        
        visualScale = (randomChar['visual_scale'] as num?)?.toDouble() ?? 1.0;

        if (isHunter) {
          visualScale *= 1.4; 
          huntSpeed = baseSpeed * 0.95 * levelMultiplier; 
          if (_fallbackSprite != null) _fallbackSprite!.paint.color = Colors.redAccent;
        }

        scale = Vector2.all(visualScale); 
      }
    } catch (e) {}

    await GraveStakesGame.ensureCharacterLoaded(assignedCharacterId);

    try {
      final rig = GraveStakesGame.characterRigCache[assignedCharacterId] ?? game.loadedRigData;
      if (rig == null) throw Exception('Bot rig data is entirely missing!');

      voxelComponent = VoxelCharacterComponent(
        images: GraveStakesGame.characterImagesCache[assignedCharacterId] ?? game.loadedAssetImages,
        rigData: rig,
        hitboxSize: size,
      ) ..anchor = Anchor.bottomCenter 
        ..position = Vector2(size.x / 2, size.y); 
      add(voxelComponent!);
    } catch (e) {
      _fallbackSprite = RectangleComponent(size: size, paint: Paint()..color = Colors.deepOrangeAccent);
      add(_fallbackSprite!);
    }
    
    if (game.matchMode == '2v2' && teamId != 0) {
      final teamColor = teamId == 1 ? const Color(0xFF0072B2) : const Color(0xFFE69F00);
      
      add(CircleComponent(
        radius: 20.0,
        paint: Paint()
          ..color = teamColor.withAlpha(180)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0,
        anchor: Anchor.center,
        position: size / 2,
      ));

      if (_fallbackSprite != null) {
        _fallbackSprite!.paint.color = teamColor;
      }
    }
        
    _chooseNewDirection();
  }

  void _chooseNewDirection() {
    directionTimer = (_random.nextDouble() * 2) + 1; 
    double randomAngle = _random.nextDouble() * 2 * pi;
    movementDelta = Vector2(sin(randomAngle), -cos(randomAngle)); 
    facingAngle = randomAngle;
  }

  void applyStun(double duration, {bool isVermin = false, String? attackerId, Vector2? attackerPos}) {
    if (localImmunityToMe > 0) return;
    
    isStunned = true;
    stunTimer = duration;
    
    if (attackerPos != null) {
      Vector2 awayDir = (position - attackerPos).normalized();
      
      // --- FIX: SAFE RECOIL ---
      // Step backward incrementally so we stop immediately if we hit a wall!
      double distanceToMove = 50.0;
      while (distanceToMove > 0) {
        double step = min(5.0, distanceToMove);
        final testPos = position + (awayDir * step);
        if (!game.gameMap.checkCollision(testPos, size)) {
          position = testPos;
          distanceToMove -= step;
        } else {
          break; // Stop flying backward!
        }
      }
      
      facingAngle = awayDir.screenAngle(); 
    }

    if (isVermin) {
      recoveryTimer = 2.0;
    }

    if (attackerId != null && game.mySessionId == attackerId) {
      game.player.score += 150;
      game.camera.viewport.add(FloatingText(
        text: '+150 SOULS', 
        worldPosition: Vector2(position.x - 25, position.y - 60)
      ));
    }
  }

  void applyCharm(double duration, PositionComponent charmer) {
    isStunned = false; 
    charmTimer = duration;
    charmerTarget = charmer;
    currentState = BotState.charmed;
  }

  PositionComponent? _findClosestVisiblePlayer() {
    PositionComponent? closest;
    double minDistance = 350.0; 

    // Target Local Player
    if (!game.player.isStunned) {
      if (game.matchMode == '2v2' && game.getEntityTeam(this) == game.getEntityTeam(game.player)) {
        // Skip
      } else {
        bool isStealthing = game.player.isInvisible || (game.player.isDisguised && !game.player.isMoving);
        if (!isStealthing) {
          double dist = position.distanceTo(game.player.position);
          if (dist < minDistance && _isInVisionCone(game.player.position) && game.gameMap.hasLineOfSight(position, game.player.position)) {
            minDistance = dist;
            closest = game.player;
          }
        }
      }
    }

    // Target Remote Players
    for (var entry in game.networkPlayers.entries) {
      if (game.matchMode == '2v2' && game.getEntityTeam(this) == game.getEntityTeam(entry.key)) continue; // SKIP
      var remote = entry.value;
      bool isStealthing = remote.isInvisible || (remote.isDisguised && !remote.isMoving);
      if (!isStealthing) {
        double dist = position.distanceTo(remote.position);
        if (dist < minDistance && _isInVisionCone(remote.position) && game.gameMap.hasLineOfSight(position, remote.position)) {
          minDistance = dist;
          closest = remote;
        }
      }
    }

    // --- BOT VS BOT TARGETING ---
    for (var bot in game.bots) {
      if (bot == this || bot.isStunned) continue; 
      if (game.matchMode == '2v2' && game.getEntityTeam(this) == game.getEntityTeam(bot)) continue; 
      
      bool isStealthing = bot.isInvisible;
      if (!isStealthing) {
        double dist = position.distanceTo(bot.position);
        if (dist < minDistance && _isInVisionCone(bot.position) && game.gameMap.hasLineOfSight(position, bot.position)) {
          minDistance = dist;
          closest = bot;
        }
      }
    }
    return closest;
  }

  PositionComponent? _getAbsoluteClosestPlayer() {
    PositionComponent? closest;
    double minDistance = 99999.0; 

    // Target Local Player
    if (!game.player.isStunned) {
      if (game.matchMode == '2v2' && game.getEntityTeam(this) == game.getEntityTeam(game.player)) {
        // Skip
      } else {
        bool isStealthing = game.player.isInvisible || (game.player.isDisguised && !game.player.isMoving);
        if (!isStealthing) {
          double dist = position.distanceTo(game.player.position);
          if (dist < minDistance) { minDistance = dist; closest = game.player; }
        }
      }
    }
    
    // Target Remote Players
    for (var entry in game.networkPlayers.entries) {
      if (game.matchMode == '2v2' && game.getEntityTeam(this) == game.getEntityTeam(entry.key)) continue; // SKIP
      var remote = entry.value;
      bool isStealthing = remote.isInvisible || (remote.isDisguised && !remote.isMoving);
      if (!isStealthing) {
        double dist = position.distanceTo(remote.position);
        if (dist < minDistance) { minDistance = dist; closest = remote; }
      }
    }

    // --- BOT VS BOT TARGETING ---
    for (var bot in game.bots) {
      if (bot == this || bot.isStunned) continue; 
      if (game.matchMode == '2v2' && game.getEntityTeam(this) == game.getEntityTeam(bot)) continue; 
      
      bool isStealthing = bot.isInvisible;
      if (!isStealthing) {
        double dist = position.distanceTo(bot.position);
        if (dist < minDistance) {
          minDistance = dist;
          closest = bot;
        }
      }
    }
    return closest;
  }

  bool _isBeingWatchedBy(PositionComponent target) {
    double targetFacing = 0.0;
    
    if (target is Player) targetFacing = target.facingAngle;
    else if (target is RemotePlayer) targetFacing = target.facingAngle;
    else if (target is BotPlayer) targetFacing = target.facingAngle;
    else return false; 

    final toBot = (position - target.position).normalized();
    final targetForward = Vector2(sin(targetFacing), -cos(targetFacing));
    
    return targetForward.dot(toBot) > 0.3 && game.gameMap.hasLineOfSight(position, target.position); 
  }

  void _updateStalkerLogic(double dt) {
    PositionComponent? prey = _getAbsoluteClosestPlayer();
    
    if (prey != null && position.distanceTo(prey.position) < 900.0) {
      if (attackCooldown > 0) {
        currentState = BotState.flee;
        if (evasionTimer <= 0) {
          movementDelta = (position - prey.position).normalized();
          facingAngle = movementDelta.screenAngle();
        }
      } else if (_isBeingWatchedBy(prey)) {
        currentState = BotState.wander;
        movementDelta = Vector2.zero();
        if (attackCooldown < 0.5) attackCooldown = 0.5; 
      } else {
        currentState = BotState.hunt;
        if (evasionTimer <= 0) {
          movementDelta = (prey.position - position).normalized();
          facingAngle = movementDelta.screenAngle();
        }
      }
      currentTarget = prey;
    } else {
      _updateGruntLogic(dt);
    }
  }

  void _updateTrapdoorLogic(double dt) {
    _updateGruntLogic(dt); 
    if (attackCooldown > 0 || isStunned || currentState == BotState.flee || currentState == BotState.charmed) {
      isInvisible = false; 
    } else {
      PositionComponent? closest = _getAbsoluteClosestPlayer();
      if (closest != null && _isBeingWatchedBy(closest)) {
        isInvisible = false; 
      } else {
        isInvisible = true;  
      }
    }
  }

  void _updateGruntLogic(double dt) {
    PositionComponent? visibleTarget;
    if (attackCooldown <= 0) visibleTarget = _findClosestVisiblePlayer();

    if (visibleTarget != null) {
      currentTarget = visibleTarget;
      lastKnownPosition = currentTarget!.position.clone();
      currentState = BotState.hunt;
    } else if (currentState == BotState.hunt && lastKnownPosition != null) {
      currentState = BotState.investigate;
      currentTarget = null;
    }

    if (currentState == BotState.hunt) {
      if (currentTarget != null) {
        if (evasionTimer <= 0) {
          movementDelta = (currentTarget!.position - position).normalized();
          facingAngle = movementDelta.screenAngle();
        }
      } else {
        currentState = BotState.wander;
      }
    } else if (currentState == BotState.investigate && lastKnownPosition != null) {
      if (evasionTimer <= 0) {
        movementDelta = (lastKnownPosition! - position).normalized();
        facingAngle = movementDelta.screenAngle();
      }
      
      if (position.distanceTo(lastKnownPosition!) < 20.0) {
        currentState = BotState.wander;
        lastKnownPosition = null;
        _chooseNewDirection();
      }
    } else {
      currentState = BotState.wander;
      directionTimer -= dt;
      if (directionTimer <= 0) _chooseNewDirection();
      if (evasionTimer <= 0) facingAngle = movementDelta.screenAngle();
    }
  }

  @override
  void update(double dt) {    
    priority = ((position.y + 16) * 10).toInt();

    if (!game.gameStarted) return;
    super.update(dt);    

    if (voxelComponent != null) {
      voxelComponent!.targetAngle = facingAngle - (pi / 2); 
      voxelComponent!.isMoving = !isStunned && (currentState == BotState.hunt || currentState == BotState.charmed || currentState == BotState.flee || directionTimer > 0);
      voxelComponent!.isStunned = isStunned;
      voxelComponent!.stunTimer = stunTimer;
      voxelComponent!.isHighlighted = (highlightTimer > 0);
      voxelComponent!.isVisible = !isInvisible; 
      voxelComponent!.isInvisible = false;

      try {
        voxelComponent!.activeMaskImage = game.images.fromCache('${currentMaskId}_mask.png');
      } catch (e) {}
    }

    if (_fallbackSprite != null && !isStunned && highlightTimer <= 0) {
      _fallbackSprite!.paint.color = _fallbackSprite!.paint.color.withOpacity(isInvisible ? 0.0 : 1.0);
    }

    if (localImmunityToMe > 0) localImmunityToMe -= dt;
    if (evasionTimer > 0) evasionTimer -= dt;
    
    if (highlightTimer > 0) {
      highlightTimer -= dt;
      if (highlightTimer <= 0 && !isStunned && _fallbackSprite != null) {
        _fallbackSprite!.paint.color = (game.matchMode == '2v2' && teamId != 0) 
            ? (teamId == 1 ? Colors.blueAccent : Colors.orangeAccent) 
            : (isHunter ? Colors.redAccent : Colors.deepOrangeAccent); 
      }
    }

    if (isStunned) {
      stunTimer -= dt;
      if (_fallbackSprite != null) {
         int alpha = (150 + sin(stunTimer * 30) * 105).toInt().clamp(0, 255);
         _fallbackSprite!.paint.color = Colors.cyanAccent.withAlpha(alpha);
         _fallbackSprite!.position = Vector2(sin(stunTimer * 50) * 4, 0);
      }
      if (stunTimer <= 0) {
        isStunned = false;
        if (_fallbackSprite != null) {
          _fallbackSprite!.paint.color = (game.matchMode == '2v2' && teamId != 0) 
            ? (teamId == 1 ? Colors.blueAccent : Colors.orangeAccent) 
            : (isHunter ? Colors.redAccent : Colors.deepOrangeAccent); 
          _fallbackSprite!.position = Vector2.zero(); 
        }
      }
    }

    if (currentState == BotState.charmed) {
      charmTimer -= dt;
      if (charmTimer <= 0) {
        currentState = BotState.wander;
        charmerTarget = null;
      }
    }

    if (!game.isHost) return;

    if (!isStunned) {
      double currentSpeed = wanderSpeed;
      bool hitWall = false;

      BotPlayer? activeHunter;
      for (var b in game.bots) {
        if (b.isHunter && b != this) activeHunter = b;
      }

      if (currentState == BotState.charmed && charmerTarget != null) {
        currentSpeed = wanderSpeed; 
        movementDelta = (charmerTarget!.position - position).normalized();
        facingAngle = movementDelta.screenAngle();
        currentTarget = null; 

      } else if (isHunter) {
        if (!isStunned) {
          coreCycleTimer += dt;
          if (coreCycleTimer >= 2.6 && coreCycleTimer < 3.0) {
            isCoreExposed = true;
            if (_fallbackSprite != null) _fallbackSprite!.paint.color = Colors.white;
            if (voxelComponent != null) voxelComponent!.isHighlighted = true;
          } else {
            isCoreExposed = false;
            if (_fallbackSprite != null) _fallbackSprite!.paint.color = Colors.redAccent;
            if (voxelComponent != null) voxelComponent!.isHighlighted = false;
          }
          if (coreCycleTimer >= 3.0) coreCycleTimer = 0.0; 
        }

        currentState = BotState.hunt;
        currentSpeed = huntSpeed;

        if (acousticAggroTimer > 0 && acousticAggroTarget != null) {
          acousticAggroTimer -= dt;
          _pathRecalcTimer -= dt;
          if (_pathRecalcTimer <= 0) {
            _hunterPath = game.gameMap.findPath(position, acousticAggroTarget!);
            _pathRecalcTimer = 0.5;
          }
        } else {
          currentTarget = _getAbsoluteClosestPlayer();
          if (currentTarget != null) {
            _pathRecalcTimer -= dt;
            if (_pathRecalcTimer <= 0) {
              _hunterPath = game.gameMap.findPath(position, currentTarget!.position);
              _pathRecalcTimer = 0.5; 
            }
          } else {
            _hunterPath.clear();
            directionTimer -= dt;
            if (directionTimer <= 0) _chooseNewDirection();
          }
        }
        
        if (_hunterPath.isNotEmpty) {
          if (position.distanceTo(_hunterPath.first) < 15.0) _hunterPath.removeAt(0);
          if (_hunterPath.isNotEmpty) {
            movementDelta = (_hunterPath.first - position).normalized();
          } else if (currentTarget != null) {
            movementDelta = (currentTarget!.position - position).normalized();
          }
        } else if (currentTarget != null) {
          movementDelta = (currentTarget!.position - position).normalized();
        }
        facingAngle = movementDelta.screenAngle();

      } else if (activeHunter != null && position.distanceTo(activeHunter.position) < 800.0) {
        currentState = BotState.flee;
        currentSpeed = huntSpeed * 1.2; 
        
        if (evasionTimer <= 0) {
          movementDelta = (position - activeHunter.position).normalized();
          facingAngle = movementDelta.screenAngle();
        }

      } else {
        if (personality == BotPersonality.stalker) {
          _updateStalkerLogic(dt);
          if (currentState == BotState.flee) {
            currentSpeed = huntSpeed * 1.6; 
          } else if (currentState == BotState.wander && movementDelta.isZero()) {
            currentSpeed = 0.0; 
          } else {
            currentSpeed = huntSpeed * 1.3; 
          }
        } else if (personality == BotPersonality.phantom) {
          _updatePhantomLogic(dt);
          currentSpeed = huntSpeed * 0.90;
        } else if (personality == BotPersonality.trapdoor) {
          _updateTrapdoorLogic(dt);
          currentSpeed = (currentState == BotState.hunt) ? huntSpeed : (currentState == BotState.investigate ? huntSpeed * 0.85 : wanderSpeed);
          if (isInvisible && currentState == BotState.hunt) currentSpeed *= 1.2;
        } else {
          _updateGruntLogic(dt); 
          currentSpeed = (currentState == BotState.hunt) ? huntSpeed : (currentState == BotState.investigate ? huntSpeed * 0.85 : wanderSpeed);
        }
      }

      if (recoveryTimer > 0) {
        recoveryTimer -= dt;
        currentSpeed *= 0.5; 
      }

      final potentialPosition = position + (movementDelta * currentSpeed * dt);
      final oldPosition = position.clone();

      // --- THE FAILSAFE: GHOST EXTRICATION ---
      // If the bot is CURRENTLY inside a wall, let them ghost-walk toward their 
      // target until they pop out into free space.
      bool currentlyStuck = game.gameMap.checkCollision(position, size);

      if (currentlyStuck) {
        position.x = potentialPosition.x;
        position.y = potentialPosition.y;
      } else {
        // Standard Collision bounds
        final testX = Vector2(potentialPosition.x, position.y);
        if (!game.gameMap.checkCollision(testX, size)) { position.x = potentialPosition.x; } else { hitWall = true; }

        final testY = Vector2(position.x, potentialPosition.y);
        if (!game.gameMap.checkCollision(testY, size)) { position.y = potentialPosition.y; } else { hitWall = true; }
      }
      // ---------------------------------------

      if (hitWall && evasionTimer <= 0) {
        double turnAngle = (pi / 4) + (_random.nextDouble() * (pi / 4)); 
        if (_random.nextBool()) facingAngle += turnAngle; else facingAngle -= turnAngle;
        movementDelta = Vector2(sin(facingAngle), -cos(facingAngle));
        evasionTimer = 0.5; 
        if (currentState == BotState.wander) directionTimer = 0.5;
      }

      if (attackCooldown > 0) attackCooldown -= dt;

      if (currentTarget != null && currentState == BotState.hunt) {
        final distance = position.distanceTo(currentTarget!.position);
        
        // --- THE SCARE EXECUTION BLOCK ---
        if (distance < 110 && attackCooldown <= 0) {
          if (game.gameMap.hasLineOfSight(position, currentTarget!.position)) {
            
            // 1. MASK ROULETTE
            if (_random.nextInt(10) == 0) {
              List<String> specials = ['flying', 'vermin', 'siren'];
              currentMaskId = specials[_random.nextInt(specials.length)];
            } else {
              currentMaskId = 'standard';
            }

            // 2. ACCURACY WHIFF
            bool targetIsMoving = true; 
            if (currentTarget is Player) targetIsMoving = (currentTarget as Player).isMoving;
            else if (currentTarget is RemotePlayer) targetIsMoving = (currentTarget as RemotePlayer).isMoving;
            else if (currentTarget is BotPlayer) targetIsMoving = (currentTarget as BotPlayer).movementDelta.length > 0;
            
            bool whiffedAttack = targetIsMoving && (_random.nextDouble() < 0.25);

            if (whiffedAttack) {
              game.camera.viewport.add(FloatingText(
                text: 'MISSED!', 
                worldPosition: Vector2(position.x - 20, position.y - 60),
              ));
              AudioManager.instance.playEntityFootstep(assignedCharacterId, position, isLocal: false);
              attackCooldown = 4.0; 
              
            } else {
              // --- THE BOT HIT! FIRE VISUALS & SOUNDS ---
              AudioManager.instance.playSpatialScare(currentMaskId, position);
              if (voxelComponent != null) voxelComponent!.triggerScareAnimation();
              
              if (currentMaskId == 'flying') {
                game.world.add(FlyingScareBlast(position: position.clone(), angle: facingAngle, ownerId: 'bot_${game.bots.indexOf(this)}'));
              } else if (currentMaskId == 'vermin') {
                for (int i = 0; i < 15; i++) {
                  game.scareManager.spawnCritter(Critter(position: position.clone(), behavior: SwarmBehavior.scatter, seed: DateTime.now().millisecondsSinceEpoch, index: i, initialAngle: facingAngle, ownerId: 'bot_${game.bots.indexOf(this)}'));
                }
              } else if (currentMaskId == 'siren') {
                add(SirenBlast()..position = size / 2);
              } else {
                game.world.add(ScareBlast(position: position.clone(), angle: facingAngle - (pi / 2))..priority = priority + 5);
              }

              // Tell remote clients the bot scared!
              game.myChannel.sendBroadcastMessage(event: 'bot_scare', payload: {
                'bot_index': game.bots.indexOf(this),
                'mask_id': currentMaskId,
                'x': position.x, 'y': position.y, 'a': facingAngle
              });

              String attackWord = isHunter ? 'CRUSHED!' : 'SCARED!';
              if (!isHunter && personality == BotPersonality.stalker) attackWord = 'STALKED!';
              if (!isHunter && personality == BotPersonality.trapdoor) attackWord = 'AMBUSHED!';
              game.camera.viewport.add(FloatingText(text: attackWord, worldPosition: Vector2(position.x - 30, position.y - 60)));

              // Apply Stuns and Add to simulatedScore!
              if (currentTarget == game.player) {
                game.jumpScareEffect.trigger(); 
                game.player.applyStun(2.0, attackerPos: position);   
                triggerPrivateHighlight();
                game.player.triggerPrivateHighlight();
                simulatedScore += 100; // <--- FIX: Bot gets points!
              } else if (currentTarget is RemotePlayer) {
                String? targetId;
                game.networkPlayers.forEach((key, val) { if (val == currentTarget) targetId = key; });
                if (targetId != null) game.myChannel.sendBroadcastMessage(event: 'stun', payload: {'id': targetId, 'duration': 2.0});
                simulatedScore += 100; // <--- FIX: Bot gets points!
              } else if (currentTarget is BotPlayer) {
                (currentTarget as BotPlayer).applyStun(2.0, attackerPos: position);
                simulatedScore += 100; // <--- FIX: Bot gets points!
              }
              
              double cooldownMult = game.player.score > 2000 ? 0.75 : 1.0; 
              attackCooldown = 8.0 * cooldownMult; 
            }

            movementDelta = (position - currentTarget!.position).normalized();
            facingAngle = movementDelta.screenAngle();
            directionTimer = 3.0; 
            evasionTimer = 0; 
          }
        }
        // --- END SCARE EXECUTION BLOCK ---
      }

      // --- NEW: LET STAND-IN BOTS LOOT CHESTS ---
      if (isCompetitiveStandIn && game.isHost) {
        for (var box in game.world.children.whereType<SpookyBox>()) {
          if (position.distanceTo(box.position) < 40.0) {
            game.claimSpookyBoxForBot(box.id, this);
            break; 
          }
        }
      }

      if (currentState == BotState.hunt || currentState == BotState.wander || currentState == BotState.charmed || currentState == BotState.flee) {
        double actualVelocity = position.distanceTo(oldPosition) / dt;
        if (actualVelocity > 5.0) {
          double dynamicInterval = 0.45 * (wanderSpeed / actualVelocity);
          dynamicInterval += (_random.nextDouble() * 0.1) - 0.05;
          _footstepTimer += dt;
          if (_footstepTimer >= dynamicInterval) {
            _footstepTimer = 0.0; 
            AudioManager.instance.playEntityFootstep(assignedCharacterId, position, isLocal: false);
          }
        } else { _footstepTimer = 0.0; }
      } else { _footstepTimer = 0.0; }
    }
  }
}