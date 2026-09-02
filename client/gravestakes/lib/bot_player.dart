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

enum BotState { wander, hunt, investigate, charmed, flee }

class BotPlayer extends PositionComponent with HasGameReference<GraveStakesGame> {
  bool isHunter; 
  double wanderSpeed = 80.0;
  double huntSpeed = 130.0; 
  double visualScale = 1.0;
  String assignedCharacterId = 'default';
  
  // --- NEW: Internal Team Awareness ---
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
  
  late final String fakeUsername;
  int simulatedScore = 0; 

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

  /* void _playSpatialFootstep() {
    if (!game.isAudioReady || game.footstepSource == null) return;
    final distance = (position - game.player.position).length;
    if (distance > 1000.0) return;

    final posX = position.x / _audioScale;
    final randomPitch = 0.85 + (_random.nextDouble() * 0.30);
    final posY = position.y / _audioScale;

    final handle = SoLoud.instance.play3d(game.footstepSource!, posX, posY, 0.0, volume: 0.85);
    SoLoud.instance.setRelativePlaySpeed(handle, randomPitch);
    SoLoud.instance.set3dSourceMinMaxDistance(handle, 2.0, 20.0);
    SoLoud.instance.set3dSourceAttenuation(handle, 1, 1.2);
  } */

  BotPlayer({this.isHunter = false}) : super(size: Vector2.all(32.0), anchor: Anchor.center) {
    fakeUsername = _fakeNames[_random.nextInt(_fakeNames.length)];
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
    try {
      final supabase = Supabase.instance.client;
      final charsRes = await supabase.from('characters').select('*');
      
      if (charsRes != null && charsRes.isNotEmpty) {
        final List<Map<String, dynamic>> chars = List<Map<String, dynamic>>.from(charsRes);
        final randomChar = chars[_random.nextInt(chars.length)];
        
        assignedCharacterId = randomChar['id'] ?? 'default';
        final baseSpeed = (randomChar['base_speed'] as num?)?.toDouble() ?? 200.0;
        
        wanderSpeed = baseSpeed * 0.40;  
        huntSpeed = baseSpeed * 0.65;    
        
        visualScale = (randomChar['visual_scale'] as num?)?.toDouble() ?? 1.0;

        if (isHunter) {
          visualScale *= 1.4; 
          huntSpeed = baseSpeed * 0.95; 
          if (_fallbackSprite != null) _fallbackSprite!.paint.color = Colors.redAccent;
        }

        scale = Vector2.all(visualScale); 
      }
    } catch (e) {}

    try {
      final rig = game.characterRigCache[assignedCharacterId] ?? game.loadedRigData;
      if (rig == null) throw Exception('Bot rig data is entirely missing!');

      voxelComponent = VoxelCharacterComponent(
        images: game.characterImagesCache[assignedCharacterId] ?? game.loadedAssetImages,
        rigData: rig,
        hitboxSize: size,
      ) ..anchor = Anchor.bottomCenter 
        ..position = Vector2(size.x / 2, size.y); 
      add(voxelComponent!);
    } catch (e) {
      _fallbackSprite = RectangleComponent(size: size, paint: Paint()..color = Colors.deepOrangeAccent);
      add(_fallbackSprite!);
    }
    
    // --- NEW: Paint Bot according to its dynamically assigned team! ---
    // --- NEW: Paint Bot according to its dynamically assigned team! ---
    if (game.matchMode == '2v2' && teamId != 0) {
      // Team 1 = Accessible Blue, Team 2 = Accessible Orange
      final teamColor = teamId == 1 ? const Color(0xFF0072B2) : const Color(0xFFE69F00);
      
      // Draw the permanent ring under their feet
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

  void applyStun(double duration, {bool isVermin = false, String? attackerId}) {
    if (localImmunityToMe > 0) return;
    
    isStunned = true;
    stunTimer = duration;
    
    if (isVermin) {
      recoveryTimer = 2.0;
    }

    if (attackerId != null && game.mySessionId == attackerId) {
      game.player.score += 150;
      game.camera.viewport.add(FloatingText(
        text: '+150 SCARE!', 
        worldPosition: Vector2(position.x - 20, position.y - 50)
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

    if (!game.player.isStunned) {
      // --- NEW: Bot skips targeting its own teammates! ---
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
    return closest;
  }

  PositionComponent? _getAbsoluteClosestPlayer() {
    PositionComponent? closest;
    double minDistance = 99999.0; 

    if (!game.player.isStunned) {
      if (game.matchMode == '2v2' && game.getEntityTeam(this) == game.getEntityTeam(game.player)) {
        // Skip
      } else {
        // --- Add stealth check to Hunter radar ---
        bool isStealthing = game.player.isInvisible || (game.player.isDisguised && !game.player.isMoving);
        if (!isStealthing) {
          double dist = position.distanceTo(game.player.position);
          if (dist < minDistance) { minDistance = dist; closest = game.player; }
        }
      }
    }
    for (var entry in game.networkPlayers.entries) {
      if (game.matchMode == '2v2' && game.getEntityTeam(this) == game.getEntityTeam(entry.key)) continue; // SKIP
      var remote = entry.value;
      // Add stealth check to Hunter radar ---
      bool isStealthing = remote.isInvisible || (remote.isDisguised && !remote.isMoving);
      if (!isStealthing) {
        double dist = position.distanceTo(remote.position);
        if (dist < minDistance) { minDistance = dist; closest = remote; }
      }
    }
    return closest;
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

    if (game.gameTimer.timeLeft <= 60.0 && game.gameTimer.timeLeft > 0 && !isHunter) {
      isHunter = true;
      huntSpeed *= 1.35; 
      if (_fallbackSprite != null) _fallbackSprite!.paint.color = Colors.redAccent;
      if (voxelComponent != null) triggerPrivateHighlight(); 
    }

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
            // --- If radar loses lock (everyone invisible), clear path and wander ---
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
          currentSpeed = huntSpeed;
          if (evasionTimer <= 0) {
            movementDelta = (currentTarget!.position - position).normalized();
            facingAngle = movementDelta.screenAngle();
          }
        } else if (currentState == BotState.investigate && lastKnownPosition != null) {
          currentSpeed = huntSpeed * 0.85; 
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

      if (recoveryTimer > 0) {
        recoveryTimer -= dt;
        currentSpeed *= 0.5; 
      }

      final potentialPosition = position + (movementDelta * currentSpeed * dt);
      final oldPosition = position.clone();

      final testX = Vector2(potentialPosition.x, position.y);
      if (!game.gameMap.checkCollision(testX, size)) { position.x = potentialPosition.x; } else { hitWall = true; }

      final testY = Vector2(position.x, potentialPosition.y);
      if (!game.gameMap.checkCollision(testY, size)) { position.y = potentialPosition.y; } else { hitWall = true; }

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
        if (distance < 110 && attackCooldown <= 0) {
          if (game.gameMap.hasLineOfSight(position, currentTarget!.position)) {
            game.world.add(ScareBlast(position: position, angle: facingAngle - (pi / 2)));
            
            // --- Play spatial scare sound for bot attack ---
            AudioManager.instance.playSpatialScare('standard', position);

            if (currentTarget == game.player) {
              game.jumpScareEffect.trigger(); 
              game.player.applyStun(2.0);   
              triggerPrivateHighlight();
              game.player.triggerPrivateHighlight();
            } else {
              String? targetId;
              game.networkPlayers.forEach((key, val) { if (val == currentTarget) targetId = key; });
              if (targetId != null) {
                game.myChannel.sendBroadcastMessage(event: 'stun', payload: {'id': targetId, 'duration': 2.0});
              }
            }
            attackCooldown = 8.0; 
            movementDelta = (position - currentTarget!.position).normalized();
            facingAngle = movementDelta.screenAngle();
            directionTimer = 3.0; 
            evasionTimer = 0; 
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
            //_playSpatialFootstep();
            AudioManager.instance.playEntityFootstep(assignedCharacterId, position, isLocal: false);
          }
        } else { _footstepTimer = 0.0; }
      } else { _footstepTimer = 0.0; }
    }
  }
}