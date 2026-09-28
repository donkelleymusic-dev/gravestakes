import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'game.dart';
import 'audio_manager.dart';
import 'scare_blast.dart';
import 'floating_text.dart';

class WendigoDecoy extends PositionComponent with HasGameReference<GraveStakesGame> {
  final String ownerId;
  final double angle;
  double _lifeTimer = 3.5; // Runs for 3.5 seconds
  double _footstepTimer = 0.0;
  late Vector2 velocity;

  WendigoDecoy({required Vector2 position, required this.angle, required this.ownerId})
      : super(position: position, size: Vector2.all(32), anchor: Anchor.center) {
    velocity = Vector2(sin(angle), -cos(angle)) * 260.0; // Sprints slightly faster than a player
  }

  @override
  void update(double dt) {
    super.update(dt);
    _lifeTimer -= dt;

    // The decoy physically moves through the world
    final potentialPosition = position + (velocity * dt);
    if (!game.gameMap.checkCollision(potentialPosition, size)) {
      position = potentialPosition;
    } else {
      // If it hits a wall early, it vanishes instantly without the fake blast
      removeFromParent();
      return;
    }

    // Drops heavy fake footsteps to trick the audio system
    _footstepTimer += dt;
    if (_footstepTimer >= 0.3) {
      _footstepTimer = 0.0;
      if (AudioManager.instance.isInitialized) {
        AudioManager.instance.playEntityFootstep('default', position, isLocal: false);
      }
    }

    // Detonates the fake blast at the end of its run
    if (_lifeTimer <= 0) {
      game.world.add(ScareBlast(position: position.clone(), angle: angle - (pi / 2)));
      AudioManager.instance.playSpatialScare('standard', position);
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    // Draws a shadowy, featureless blur
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.x / 2, size.y / 2), width: 24, height: 16),
      Paint()..color = Colors.black.withOpacity(0.5)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0)
    );
  }
}

class PoltergeistTrap extends PositionComponent with HasGameReference<GraveStakesGame> {
  final String ownerId;
  final double angle;
  bool _isArmed = false;
  double _armTimer = 1.5; // 1.5 seconds before it arms

  PoltergeistTrap({required Vector2 position, required this.angle, required this.ownerId})
      : super(position: position, size: Vector2.all(32), anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    if (!_isArmed) {
      _armTimer -= dt;
      if (_armTimer <= 0) _isArmed = true;
      return;
    }

    // ONLY the trap's owner evaluates collisions to prevent the network from duplicating the stun event
    if (ownerId == game.mySessionId) {
      bool triggered = false;

      // Check Bots
      for (var bot in game.bots) {
        if (!bot.isStunned && position.distanceTo(bot.position) < 60.0) triggered = true;
      }
      
      // Check Enemy Players
      for (var entry in game.networkPlayers.entries) {
        if (game.matchMode == '2v2' && game.getEntityTeam(ownerId) == game.getEntityTeam(entry.key)) continue;
        if (position.distanceTo(entry.value.position) < 60.0) triggered = true;
      }

      if (triggered) {
        // 1. Local Visuals & Audio
        AudioManager.instance.playSpatialScare('standard', position);
        game.world.add(ScareBlast(position: position.clone(), angle: angle - (pi / 2))..priority = 1000);
        
        game.camera.viewport.add(FloatingText(
          text: 'POLTERGEIST TRIGGERED!', 
          worldPosition: Vector2(position.x - 60, position.y - 60)
        ));
        
        // 2. Network Broadcast (So bystanders see the explosion)
        game.myChannel.sendBroadcastMessage(event: 'trap_detonate', payload: {
          'owner_id': ownerId,
          'x': position.x,
          'y': position.y,
          'a': angle
        });

        // 3. Evaluate the actual stun mechanics
        game.triggerLocalScare(position, angle, false, maskId: 'poltergeist', range: 300.0);
        removeFromParent();
      }
    }
  }

  @override
  void render(Canvas canvas) {
    if (!_isArmed) return;

    // Determine if the local viewing player owns this trap (or is on the same team)
    bool isMyTrap = (ownerId == game.mySessionId);
    bool isMyTeam = (game.matchMode == '2v2' && game.getEntityTeam(ownerId) == game.getEntityTeam(game.mySessionId));

    if (isMyTrap || isMyTeam) {
      // Draw a highly visible, pulsing tactical marker for the owner
      final paint = Paint()
        ..color = Colors.purpleAccent.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
        
      canvas.drawCircle(Offset(size.x / 2, size.y / 2), 16, paint);
      
      // Animate a pulsing inner core so the player knows it is hot and armed
      double pulse = (sin(DateTime.now().millisecondsSinceEpoch / 150.0) + 1) / 2;
      canvas.drawCircle(Offset(size.x / 2, size.y / 2), 4 + (6 * pulse), paint);
      
    } else {
      // Optional: Draw absolutely nothing for enemies, OR draw a nearly invisible distortion
      // leaving this empty means they trip it completely blind.
    }
  }
}