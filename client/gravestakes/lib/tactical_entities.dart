import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'game.dart';
import 'audio_manager.dart';
import 'scare_blast.dart';
import 'floating_text.dart';
import 'voxel_character_component.dart';

class WendigoDecoy extends PositionComponent with HasGameReference<GraveStakesGame> {
  final String ownerId;
  final String charId;
  double angle;
  
  double _lifeTimer = 2.5; // Sprints for exactly 2.5 seconds
  double _footstepTimer = 0.0;
  
  VoxelCharacterComponent? _voxel;
  final Random _random = Random();

  WendigoDecoy({
    required Vector2 position, 
    required this.angle, 
    required this.ownerId,
    required this.charId,
  }) : super(position: position, size: Vector2.all(32), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    priority = ((position.y + 16) * 10).toInt();

    // Pull the exact 3D rig the attacker is wearing
    final rig = GraveStakesGame.characterRigCache[charId] ?? game.loadedRigData;
    final images = GraveStakesGame.characterImagesCache[charId] ?? game.loadedAssetImages;

    if (rig != null) {
      _voxel = VoxelCharacterComponent(
        images: images,
        rigData: rig,
        hitboxSize: size,
      )
        ..anchor = Anchor.bottomCenter
        ..position = Vector2(size.x / 2, size.y)
        ..isMoving = true
        ..targetAngle = angle - (pi / 2);
      
      add(_voxel!);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _lifeTimer -= dt;

    if (_lifeTimer <= 0) {
      game.world.add(ScareBlast(position: position.clone(), angle: angle - (pi / 2)));
      AudioManager.instance.playSpatialScare('standard', position);
      removeFromParent();
      return;
    }

    // 1. Move Forward Fast
    Vector2 velocity = Vector2(sin(angle), -cos(angle)) * 280.0; 
    final potentialPosition = position + (velocity * dt);

    // 2. Wall Deflection Logic
    if (!game.gameMap.checkCollision(potentialPosition, size)) {
      position = potentialPosition;
    } else {
      // Panic turn: Pick left or right 90 degrees to slide down the hallway
      double turn = _random.nextBool() ? (pi / 2) : -(pi / 2);
      angle += turn;
      if (_voxel != null) _voxel!.targetAngle = angle - (pi / 2);
    }

    // 3. Audio Trickery
    _footstepTimer += dt;
    if (_footstepTimer >= 0.25) {
      _footstepTimer = 0.0;
      if (AudioManager.instance.isInitialized) {
        AudioManager.instance.playEntityFootstep(charId, position, isLocal: false);
      }
    }
    
    // Update rendering priority as it moves
    priority = ((position.y + 16) * 10).toInt();
  }

  @override
  void render(Canvas canvas) {
    // Wrap the entire child voxel tree in a ghostly, scanlined cyan filter
    canvas.saveLayer(
      Rect.fromLTWH(-100, -100, 200, 200),
      Paint()
        ..colorFilter = const ColorFilter.mode(Colors.cyanAccent, BlendMode.modulate)
        ..color = Colors.white.withOpacity(0.65), 
    );
    super.render(canvas);
    canvas.restore();
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