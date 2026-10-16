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
  
  double _lifeTimer = 2.5; 
  double _footstepTimer = 0.0;
  
  // MUST NOT HAVE AN UNDERSCORE so fps_viewport_overlay can see it!
  VoxelCharacterComponent? voxel; 
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

    final rig = GraveStakesGame.characterRigCache[charId] ?? game.loadedRigData;
    final images = GraveStakesGame.characterImagesCache[charId] ?? game.loadedAssetImages;

    if (rig != null) {
      voxel = VoxelCharacterComponent(
        images: images,
        rigData: rig,
        hitboxSize: size,
      )
        ..anchor = Anchor.bottomCenter
        ..position = size / 2 // Lock strictly to local center
        ..isMoving = true
        ..isVisible = true // Failsafe to ensure it draws
        ..targetAngle = angle - (pi / 2);
      
      add(voxel!); 
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

    // GHOST MODE: Sprint dead straight, ignoring all map collision!
    Vector2 velocity = Vector2(sin(angle), -cos(angle)) * 280.0; 
    position += velocity * dt;
    
    if (voxel != null) {
      voxel!.targetAngle = angle - (pi / 2); 
    }

    _footstepTimer += dt;
    if (_footstepTimer >= 0.25) {
      _footstepTimer = 0.0;
      if (AudioManager.instance.isInitialized) {
        AudioManager.instance.playEntityFootstep(charId, position, isLocal: false);
      }
    }
  }
}

class PoltergeistTrap extends SpriteComponent with HasGameReference<GraveStakesGame> {
  final String ownerId;
  final double angle;
  bool _isArmed = false;
  double _armTimer = 1.5; 

  PoltergeistTrap({required Vector2 position, required this.angle, required this.ownerId})
      : super(position: position, size: Vector2.all(32), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    // Load a sprite so the 3D raycaster has an image to project!
    try {
      sprite = await game.loadSprite('poltergeist_mask.png');
    } catch (e) {
      sprite = await game.loadSprite('standard_mask.png');
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_isArmed) {
      _armTimer -= dt;
      if (_armTimer <= 0) _isArmed = true;
      return;
    }

    if (ownerId == game.mySessionId) {
      bool triggered = false;
      for (var bot in game.bots) {
        if (!bot.isStunned && position.distanceTo(bot.position) < 60.0) triggered = true;
      }
      for (var entry in game.networkPlayers.entries) {
        if (game.matchMode == '2v2' && game.getEntityTeam(ownerId) == game.getEntityTeam(entry.key)) continue;
        if (position.distanceTo(entry.value.position) < 60.0) triggered = true;
      }

      if (triggered) {
        AudioManager.instance.playSpatialScare('standard', position);
        game.world.add(ScareBlast(position: position.clone(), angle: angle - (pi / 2))..priority = 1000);
        game.camera.viewport.add(FloatingText(text: 'POLTERGEIST TRIGGERED!', worldPosition: Vector2(position.x - 60, position.y - 60)));
        game.myChannel.sendBroadcastMessage(event: 'trap_detonate', payload: {'owner_id': ownerId, 'x': position.x, 'y': position.y, 'a': angle});
        game.triggerLocalScare(position, angle, false, maskId: 'poltergeist', range: 300.0);
        removeFromParent();
      }
    }
  }

  @override
  void render(Canvas canvas) {
    if (!_isArmed) return;
    super.render(canvas); // Let the raycaster draw the sprite!
    
    // Only draw the pulsing vector rings if we are in 2D mode
    if (!game.isFpsMode) {
      bool isMyTrap = (ownerId == game.mySessionId);
      bool isMyTeam = (game.matchMode == '2v2' && game.getEntityTeam(ownerId) == game.getEntityTeam(game.mySessionId));

      if (isMyTrap || isMyTeam) {
        final paint = Paint()..color = Colors.purpleAccent.withOpacity(0.6)..style = PaintingStyle.stroke..strokeWidth = 2.0;
        canvas.drawCircle(Offset(size.x / 2, size.y / 2), 16, paint);
        double pulse = (sin(DateTime.now().millisecondsSinceEpoch / 150.0) + 1) / 2;
        canvas.drawCircle(Offset(size.x / 2, size.y / 2), 4 + (6 * pulse), paint);
      }
    }
  }
}