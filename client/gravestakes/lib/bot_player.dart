import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart';
import 'scare_blast.dart';

enum BotState { wander, hunt }

class BotPlayer extends PositionComponent with HasGameReference<GraveStakesGame> {
  double wanderSpeed = 80.0;
  double huntSpeed = 130.0; 
  
  BotState currentState = BotState.wander;
  PositionComponent? currentTarget;

  bool isStunned = false;
  double stunTimer = 0;
  double attackCooldown = 0;

  double localImmunityToMe = 0;
  
  double directionTimer = 0;
  double evasionTimer = 0; // NEW: Helps the bot commit to sliding around obstacles
  Vector2 movementDelta = Vector2.zero();
  
  double networkTick = 0;
  final double networkRate = 0.05;

  late RectangleComponent _sprite;
  final Random _random = Random();

  double highlightTimer = 0;

  void triggerPrivateHighlight() {
    highlightTimer = 1.0; 
    _sprite.paint.color = Colors.white; 
  }

  BotPlayer() : super(size: Vector2.all(32.0), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    _sprite = RectangleComponent(
      size: size,
      paint: Paint()..color = Colors.deepOrangeAccent, 
    );
    add(_sprite);
    
    _chooseNewDirection();
  }

  void _chooseNewDirection() {
    directionTimer = (_random.nextDouble() * 2) + 1; // 1 to 3 seconds
    double randomAngle = _random.nextDouble() * 2 * pi;
    movementDelta = Vector2(cos(randomAngle), sin(randomAngle));
  }

  void applyStun(double duration) {
    isStunned = true;
    stunTimer = duration;
    _sprite.paint.color = Colors.cyanAccent;
    currentState = BotState.wander; // Lose aggro when stunned
    
    // Force them to pick a new direction when they wake up
    _chooseNewDirection(); 
  }

  // AI LOGIC: Find the closest human player
  PositionComponent? _findClosestVisiblePlayer() {
    PositionComponent? closest;
    double minDistance = 350.0; 

    if (!game.player.isStunned) {
      double dist = position.distanceTo(game.player.position);
      if (dist < minDistance && game.gameMap.hasLineOfSight(position, game.player.position)) {
        minDistance = dist;
        closest = game.player;
      }
    }

    for (var remote in game.networkPlayers.values) {
      double dist = position.distanceTo(remote.position);
      if (dist < minDistance && game.gameMap.hasLineOfSight(position, remote.position)) {
        minDistance = dist;
        closest = remote;
      }
    }

    return closest;
  }

  @override
  void update(double dt) {
    if (!game.gameStarted) return;
    super.update(dt);

    // Count down the immunity timer
    if (localImmunityToMe > 0) {
      localImmunityToMe -= dt;
    }

    // Count down evasion timer
    if (evasionTimer > 0) {
      evasionTimer -= dt;
    }

    // NEW: Highlight timer countdown
    if (highlightTimer > 0) {
      highlightTimer -= dt;
      if (highlightTimer <= 0 && !isStunned) {
        _sprite.paint.color = Colors.deepOrangeAccent; 
      }
    }

    if (isStunned) {
      stunTimer -= dt;
      
      int alpha = (150 + sin(stunTimer * 30) * 105).toInt().clamp(0, 255);
      _sprite.paint.color = Colors.cyanAccent.withAlpha(alpha);
      _sprite.position = Vector2(sin(stunTimer * 50) * 4, 0);

      if (stunTimer <= 0) {
        isStunned = false;
        _sprite.paint.color = Colors.deepOrangeAccent; 
        _sprite.position = Vector2.zero(); 
      }
    }

    if (!game.isHost || isStunned) return;

    // --- SENSE ---
    // If the ghost is on cooldown, it is "Satisfied" and completely ignores humans
    if (attackCooldown > 0) {
      currentTarget = null;
    } else {
      currentTarget = _findClosestVisiblePlayer();
    }
    
    if (currentTarget != null) {
      currentState = BotState.hunt;
    } else {
      currentState = BotState.wander;
    }

    // --- MOVE ---
    double currentSpeed = wanderSpeed;
    bool hitWall = false;

    if (currentState == BotState.hunt) {
      currentSpeed = huntSpeed;
      // Only recalculate direct path to player if we aren't currently evading an obstacle
      if (evasionTimer <= 0) {
        movementDelta = (currentTarget!.position - position).normalized();
        angle = movementDelta.screenAngle();
      }
    } else {
      directionTimer -= dt;
      if (directionTimer <= 0) _chooseNewDirection();
      if (evasionTimer <= 0) {
        angle = movementDelta.screenAngle();
      }
    }

    final potentialPosition = position + (movementDelta * currentSpeed * dt);

    final testX = Vector2(potentialPosition.x, position.y);
    if (!game.gameMap.checkCollision(testX, size)) {
      position.x = potentialPosition.x;
    } else {
      hitWall = true;
    }

    final testY = Vector2(position.x, potentialPosition.y);
    if (!game.gameMap.checkCollision(testY, size)) {
      position.y = potentialPosition.y;
    } else {
      hitWall = true;
    }

    // NEW: The "Roomba Whiskers" Obstacle Avoidance
    // If we hit a wall and aren't already evading, pick a glancing angle and commit to it briefly
    if (hitWall && evasionTimer <= 0) {
      double turnAngle = (pi / 4) + (_random.nextDouble() * (pi / 4)); // 45 to 90 degrees
      
      // Randomly skirt left or right
      if (_random.nextBool()) {
        angle += turnAngle;
      } else {
        angle -= turnAngle;
      }
      
      movementDelta = Vector2(sin(angle), -cos(angle));
      evasionTimer = 0.5; // Commit to this slide for half a second
      
      if (currentState == BotState.wander) {
        directionTimer = 0.5;
      }
    }

    // --- ATTACK LOGIC ---
    if (attackCooldown > 0) attackCooldown -= dt;

    if (currentTarget != null) {
      final distance = position.distanceTo(currentTarget!.position);
      
      if (distance < 110 && attackCooldown <= 0) {//was 150 distance... but maybe we need to shorten that attack window for bots
        // NEW: Line-of-sight check so they don't attack through solid cliffs or houses
        if (game.gameMap.hasLineOfSight(position, currentTarget!.position)) {
          game.world.add(ScareBlast(position: position, angle: angle - (pi / 2)));
          
          if (currentTarget == game.player) {
            game.jumpScareEffect.trigger(); 
            game.player.applyStun(2.0);   
                       
            // NEW: Private highlight for the bot and the human victim
            triggerPrivateHighlight();
            game.player.triggerPrivateHighlight();
          } else {
            String? targetId;
            game.networkPlayers.forEach((key, val) {
              if (val == currentTarget) targetId = key;
            });
            if (targetId != null) {
              game.myChannel.sendBroadcastMessage(
                event: 'stun',
                payload: {'id': targetId, 'duration': 2.0},
              );
            }
          }
          
          attackCooldown = 8.0; 
          
          // The ghost is satisfied! Force it to immediately turn around and walk away from the victim.
          movementDelta = (position - currentTarget!.position).normalized();
          angle = movementDelta.screenAngle();
          directionTimer = 3.0; // Keep walking away for at least 3 seconds before picking a new path
          evasionTimer = 0; // Clear evasion so it doesn't accidentally slide back toward the player
        }
      }
    }

    // --- NETWORK BROADCAST ---
    networkTick += dt;
    if (networkTick >= networkRate) {
      networkTick = 0;
      
      final botIndex = game.bots.indexOf(this); 
      if (botIndex != -1) {
        game.myChannel.sendBroadcastMessage(
          event: 'bot_move',
          payload: {
            'index': botIndex,
            'x': position.x,
            'y': position.y,
            'a': angle,
          },
        );
      }
    }
  }
}