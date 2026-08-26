import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'game.dart';
import 'scare_blast.dart';
import 'voxel_character_component.dart';

// --- CHANGED: Added the charmed state for the Siren mask ---
enum BotState { wander, hunt, charmed }

class BotPlayer extends PositionComponent with HasGameReference<GraveStakesGame> {
  // These will now be dynamically overwritten based on the database!
  double wanderSpeed = 80.0;
  double huntSpeed = 130.0; 
  double visualScale = 1.0;
  String assignedCharacterId = 'default';
  
  double _footstepTimer = 0.0;
  final double _audioScale = 50.0;   

  BotState currentState = BotState.wander;
  PositionComponent? currentTarget;
  PositionComponent? charmerTarget; // The player who lured the bot

  bool isStunned = false;
  double stunTimer = 0;
  double charmTimer = 0; // Duration of the Siren effect
  double attackCooldown = 0;
  double localImmunityToMe = 0;
  double directionTimer = 0;
  double evasionTimer = 0; 
  Vector2 movementDelta = Vector2.zero();
  
  VoxelCharacterComponent? voxelComponent;
  RectangleComponent? _fallbackSprite;
  
  final Random _random = Random();
  double highlightTimer = 0;

  void triggerPrivateHighlight() {
    highlightTimer = 1.0; 
    if (_fallbackSprite != null) _fallbackSprite!.paint.color = Colors.white; 
  }

  void _playSpatialFootstep() {
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
  }
  
  BotPlayer() : super(size: Vector2.all(32.0), anchor: Anchor.center);

  bool _isInVisionCone(Vector2 targetPos) {
    final vectorToTarget = targetPos - position;
    final angleToTarget = atan2(vectorToTarget.y, vectorToTarget.x);
    
    double diffAngle = (angleToTarget - angle) % (2 * pi);
    if (diffAngle > pi) diffAngle -= 2 * pi;
    else if (diffAngle < -pi) diffAngle += 2 * pi;
    
    const double fov = pi / 1.5; 
    return diffAngle.abs() <= (fov / 2);
  }

  @override
  Future<void> onLoad() async {
    // --- NEW: Fetch a random character for this specific bot! ---
    try {
      final supabase = Supabase.instance.client;
      final charsRes = await supabase.from('characters').select('*');
      
      if (charsRes != null && charsRes.isNotEmpty) {
        final List<Map<String, dynamic>> chars = List<Map<String, dynamic>>.from(charsRes);
        final randomChar = chars[_random.nextInt(chars.length)];
        
        assignedCharacterId = randomChar['id'] ?? 'default';
        final baseSpeed = (randomChar['base_speed'] as num?)?.toDouble() ?? 200.0;
        
        // Bots are intentionally a bit slower than players. 
        // We apply a multiplier to the database base_speed so Goliath bots are slower than Default bots.
        wanderSpeed = baseSpeed * 0.40;  
        huntSpeed = baseSpeed * 0.65;    
        
        visualScale = (randomChar['visual_scale'] as num?)?.toDouble() ?? 1.0;
        scale = Vector2.all(visualScale); // Make Goliath bots physically larger!
      }
    } catch (e) {
      debugPrint('Bot failed to load dynamic stats: $e');
    }

    try {
      // Safely grab the rig, falling back to default
      final rig = game.characterRigCache[assignedCharacterId] ?? game.loadedRigData;
      
      // If BOTH are missing, throw the error to force the fallback box
      if (rig == null) throw Exception('Bot rig data is entirely missing!');

      voxelComponent = VoxelCharacterComponent(
        images: game.characterImagesCache[assignedCharacterId] ?? game.loadedAssetImages,
        rigData: rig,
        hitboxSize: size,
      )..position = size / 2;
      add(voxelComponent!);
    } catch (e) {
      debugPrint('Bot failed to load Voxel Character: $e');
      _fallbackSprite = RectangleComponent(size: size, paint: Paint()..color = Colors.deepOrangeAccent);
      add(_fallbackSprite!);
    }
    _chooseNewDirection();
  }

  void _chooseNewDirection() {
    directionTimer = (_random.nextDouble() * 2) + 1; 
    double randomAngle = _random.nextDouble() * 2 * pi;
    movementDelta = Vector2(sin(randomAngle), -cos(randomAngle)); 
  }

  void applyStun(double duration) {
    isStunned = true;
    stunTimer = duration;
    currentState = BotState.wander; 
    _chooseNewDirection(); 
  }

  // --- NEW: Apply the Siren Charm Effect ---
  void applyCharm(double duration, PositionComponent charmer) {
    isStunned = false; // Being charmed snaps you out of a stun
    charmTimer = duration;
    charmerTarget = charmer;
    currentState = BotState.charmed;
  }

  PositionComponent? _findClosestVisiblePlayer() {
    PositionComponent? closest;
    double minDistance = 350.0; 

    if (!game.player.isStunned) {
      bool isStealthing = game.player.isInvisible || (game.player.isDisguised && !game.player.isMoving);
      if (!isStealthing) {
        double dist = position.distanceTo(game.player.position);
        if (dist < minDistance && _isInVisionCone(game.player.position) && game.gameMap.hasLineOfSight(position, game.player.position)) {
          minDistance = dist;
          closest = game.player;
        }
      }
    }

    for (var remote in game.networkPlayers.values) {
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

  @override
  void update(double dt) {
    if (!game.gameStarted) return;
    super.update(dt);

    if (voxelComponent != null) {
      voxelComponent!.targetAngle = angle - (pi / 2); 
      voxelComponent!.angle = -angle; 
      
      // Moving if hunting, charmed, or actively wandering
      voxelComponent!.isMoving = !isStunned && (currentState == BotState.hunt || currentState == BotState.charmed || directionTimer > 0);
      voxelComponent!.isStunned = isStunned;
      voxelComponent!.stunTimer = stunTimer;
      voxelComponent!.isHighlighted = (highlightTimer > 0);
    }

    if (localImmunityToMe > 0) localImmunityToMe -= dt;
    if (evasionTimer > 0) evasionTimer -= dt;
    
    if (highlightTimer > 0) {
      highlightTimer -= dt;
      if (highlightTimer <= 0 && !isStunned && _fallbackSprite != null) {
        _fallbackSprite!.paint.color = Colors.deepOrangeAccent; 
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
          _fallbackSprite!.paint.color = Colors.deepOrangeAccent; 
          _fallbackSprite!.position = Vector2.zero(); 
        }
      }
    }

    // --- NEW: Charm Timer Countdown ---
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

      // 1. STATE LOGIC
      if (currentState == BotState.charmed && charmerTarget != null) {
        // Trance Walk! Move slowly toward the charmer but do not attack.
        currentSpeed = wanderSpeed; 
        movementDelta = (charmerTarget!.position - position).normalized();
        angle = movementDelta.screenAngle();
        currentTarget = null; // Can't hunt while charmed

      } else {
        // Normal Bot AI
        if (attackCooldown > 0) { currentTarget = null; } else { currentTarget = _findClosestVisiblePlayer(); }
        if (currentTarget != null) { currentState = BotState.hunt; } else { currentState = BotState.wander; }

        if (currentState == BotState.hunt) {
          currentSpeed = huntSpeed;
          if (evasionTimer <= 0) {
            movementDelta = (currentTarget!.position - position).normalized();
            angle = movementDelta.screenAngle();
          }
        } else {
          directionTimer -= dt;
          if (directionTimer <= 0) _chooseNewDirection();
          if (evasionTimer <= 0) angle = movementDelta.screenAngle();
        }
      }

      // 2. MOVEMENT LOGIC
      final potentialPosition = position + (movementDelta * currentSpeed * dt);
      final oldPosition = position.clone();

      final testX = Vector2(potentialPosition.x, position.y);
      if (!game.gameMap.checkCollision(testX, size)) { position.x = potentialPosition.x; } else { hitWall = true; }

      final testY = Vector2(position.x, potentialPosition.y);
      if (!game.gameMap.checkCollision(testY, size)) { position.y = potentialPosition.y; } else { hitWall = true; }

      if (hitWall && evasionTimer <= 0) {
        double turnAngle = (pi / 4) + (_random.nextDouble() * (pi / 4)); 
        if (_random.nextBool()) angle += turnAngle; else angle -= turnAngle;
        movementDelta = Vector2(sin(angle), -cos(angle));
        evasionTimer = 0.5; 
        if (currentState == BotState.wander) directionTimer = 0.5;
      }

      if (attackCooldown > 0) attackCooldown -= dt;

      // 3. ATTACK LOGIC (Only fires if hunting, explicitly ignores charmed state)
      if (currentTarget != null && currentState == BotState.hunt) {
        final distance = position.distanceTo(currentTarget!.position);
        if (distance < 110 && attackCooldown <= 0) {
          if (game.gameMap.hasLineOfSight(position, currentTarget!.position)) {
            game.world.add(ScareBlast(position: position, angle: angle - (pi / 2)));
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
            angle = movementDelta.screenAngle();
            directionTimer = 3.0; 
            evasionTimer = 0; 
          }
        }
      }

      // 4. FOOTSTEPS
      if (currentState == BotState.hunt || currentState == BotState.wander || currentState == BotState.charmed) {
        double actualVelocity = position.distanceTo(oldPosition) / dt;
        if (actualVelocity > 5.0) {
          double dynamicInterval = 0.45 * (wanderSpeed / actualVelocity);
          dynamicInterval += (_random.nextDouble() * 0.1) - 0.05;
          _footstepTimer += dt;
          if (_footstepTimer >= dynamicInterval) {
            _footstepTimer = 0.0; _playSpatialFootstep();
          }
        } else { _footstepTimer = 0.0; }
      } else { _footstepTimer = 0.0; }
    }
  }
}