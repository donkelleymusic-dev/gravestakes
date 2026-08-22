import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart';
import 'mask_data.dart';

class Critter extends PositionComponent with HasGameReference<GraveStakesGame> {
  final SwarmBehavior behavior;
  final int seed;
  final int index;
  final double initialAngle;
  final String ownerId; // NEW: So your own swarm doesn't bite you!
  
  late Random _localRandom;
  late Vector2 velocity;
  double lifeTimer = 3.0; 

  Critter({
    required Vector2 position, 
    required this.behavior, 
    required this.seed, 
    required this.index,
    required this.initialAngle,
    required this.ownerId,
  }) : super(position: position, size: Vector2(10, 10), anchor: Anchor.center) {
    
    _localRandom = Random(seed + index);
    
    double spread = (_localRandom.nextDouble() * 2) - 1; 
    double startAngle = initialAngle + (spread * (pi / 4)); 
    
    double startSpeed = 200.0 + (_localRandom.nextDouble() * 150);
    velocity = Vector2(sin(startAngle), -cos(startAngle)) * startSpeed;
  }

  @override
  Future<void> onLoad() async {
    add(CircleComponent(
      radius: 5,
      paint: Paint()..color = Colors.lightGreenAccent,
      anchor: Anchor.center,
      position: size / 2,
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);
    lifeTimer -= dt;
    if (lifeTimer <= 0) {
      removeFromParent();
      return;
    }

    if (behavior == SwarmBehavior.scatter) {
      if (_localRandom.nextDouble() < 0.05) {
        double jitterAngle = (_localRandom.nextDouble() * pi) - (pi / 2);
        velocity.rotate(jitterAngle);
      }
    }

    final potentialPosition = position + (velocity * dt);
    
    if (!game.gameMap.checkCollision(Vector2(potentialPosition.x, position.y), size)) {
      position.x = potentialPosition.x;
    } else {
      velocity.x *= -1; 
    }
    
    if (!game.gameMap.checkCollision(Vector2(position.x, potentialPosition.y), size)) {
      position.y = potentialPosition.y;
    } else {
      velocity.y *= -1; 
    }

    // ==========================================
    // NEW: HOST AUTHORITY DAMAGE
    // ==========================================
    if (game.isHost) {
      // 1. Check Bots
      for (var bot in game.bots) {
        if (bot.localImmunityToMe > 0) continue;
        if (position.distanceTo(bot.position) < 20.0) {
          bot.applyStun(1.5);
          bot.localImmunityToMe = 3.0; 
          bot.triggerPrivateHighlight();
          removeFromParent();
          return;
        }
      }

      // 2. Check Remote Players
      for (var entry in game.networkPlayers.entries) {
        if (entry.key == ownerId) continue; // Don't bite the owner!
        var remote = entry.value;
        
        if (remote.localImmunityToMe > 0) continue;
        if (position.distanceTo(remote.position) < 20.0) {
          remote.applyStun(1.5);
          remote.localImmunityToMe = 3.0;
          remote.triggerPrivateHighlight();
          
          game.myChannel.sendBroadcastMessage(
            event: 'stun',
            payload: {'id': entry.key, 'duration': 1.5, 'attacker_id': ownerId},
          );
          
          removeFromParent();
          return;
        }
      }

      // 3. Check the Host (If the Host didn't fire the swarm)
      if (ownerId != game.mySessionId && !game.player.isStunned) {
        if (position.distanceTo(game.player.position) < 20.0) {
          game.jumpScareEffect.trigger();
          game.player.applyStun(1.5);
          game.player.triggerPrivateHighlight();
          removeFromParent();
          return;
        }
      }
    }
  }
}