import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart'; 

import 'game.dart'; 
import 'voxel_character_component.dart';

class RemotePlayer extends PositionComponent with HasGameReference<GraveStakesGame> {
  String currentColorStr = 'red';

  String currentMaskId = 'standard';
  double visualAttackCooldown = 0.0;

  double facingAngle = 0.0;
  
  // Track dynamic character ID and scale
  String equippedCharacterId = 'default';
  double visualScale = 1.0;
  
  VoxelCharacterComponent? voxelComponent;
  RectangleComponent? _fallbackSprite;
  Color _baseColor = Colors.redAccent;

  double highlightTimer = 0;

  double flashlightScale = 1.0;

  void triggerPrivateHighlight() {
    highlightTimer = 1.0; 
    if (_fallbackSprite != null) _fallbackSprite!.paint.color = Colors.white;
  }

  bool isStunned = false;
  double stunTimer = 0;
  double localImmunityToMe = 0;
  int score = 0; 
  Vector2 _targetPosition = Vector2.zero();

  double _distanceAccumulator = 0.0;
  static const double _audioScale = 50.0;
  final Random _random = Random();

  bool isDisguised = false;
  bool isMoving = false;
  bool isInvisible = false;
  SpriteComponent? _bushSprite;

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

  RemotePlayer() : super(size: Vector2.all(32.0), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    _buildVoxelComponent(); 

    try {
      final sheet = game.images.fromCache('Base_BaseChip_pipo.png');
      _bushSprite = SpriteComponent(
        sprite: Sprite(sheet, srcPosition: Vector2(0, 160), srcSize: Vector2(32, 32)),
        size: Vector2.all(32),
        anchor: Anchor.center,
      );
    } catch (e) {}
  }

  // Extracted so we can rebuild it dynamically with the safety throw included!
  void _buildVoxelComponent() {
    if (voxelComponent != null) voxelComponent!.removeFromParent();
    
    try {
      final rig = game.characterRigCache[equippedCharacterId] ?? game.loadedRigData;
      if (rig == null) throw Exception('Remote rig data is entirely missing!');

      voxelComponent = VoxelCharacterComponent(
        images: game.characterImagesCache[equippedCharacterId] ?? game.loadedAssetImages,
        rigData: rig,
        hitboxSize: size,
      )..position = size / 2;
      add(voxelComponent!);
    } catch (e) {
      debugPrint('RemotePlayer failed to load Voxel Character: $e');
      _fallbackSprite = RectangleComponent(size: size, paint: Paint()..color = _baseColor);
      add(_fallbackSprite!);
    }
  }

  void updatePosition(double newX, double newY, double newAngle, {
    String? colorStr, 
    int? newScore, 
    bool isDisguised = false, 
    bool isMoving = false, 
    bool isInvisible = false,
    double? fScale,
    String? characterId,
    double? scaleValue,
    String? maskId,
  }) {
    final newPos = Vector2(newX, newY);
    
    if (_targetPosition.isZero() || position.distanceTo(newPos) > 200.0) { position = newPos.clone(); }
    _distanceAccumulator += _targetPosition.distanceTo(newPos);
    
    _targetPosition = newPos;
    //angle = newAngle;
    facingAngle = newAngle;

    if (colorStr != null && colorStr != currentColorStr) {
      currentColorStr = colorStr;
      switch (colorStr) {
        case 'green': _baseColor = Colors.greenAccent; break;
        case 'purple': _baseColor = Colors.purpleAccent; break;
        case 'blue': _baseColor = Colors.cyanAccent; break;
        case 'red': default: _baseColor = Colors.redAccent; break;
      }
    }
    
    if (newScore != null) score = newScore;
    this.isDisguised = isDisguised;
    this.isMoving = isMoving;
    this.isInvisible = isInvisible;
    if (fScale != null) this.flashlightScale = fScale;

    // Hot-swap the art rig if the network tells us they changed characters
    if (characterId != null && characterId != equippedCharacterId) {
      equippedCharacterId = characterId;
      _buildVoxelComponent();
    }
    
    if (scaleValue != null && scaleValue != visualScale) {
      visualScale = scaleValue;
      scale = Vector2.all(visualScale);
    }

    if (maskId != null) currentMaskId = maskId;
  }

  void applyStun(double duration) {
    isStunned = true; stunTimer = duration;
  }

  @override
  void update(double dt) {
    super.update(dt);

    // --- NEW: Add this so remote players sort properly with walls! ---
    priority = ((position.y + 16) * 10).toInt();

    if (voxelComponent != null) {
      voxelComponent!.targetAngle = facingAngle - (pi / 2); 
      
      // --- FIX: Delete this line so they stop spinning like a clock! ---
      // voxelComponent!.angle = -angle; 
      
      voxelComponent!.isMoving = isMoving;
      voxelComponent!.isStunned = isStunned;
      voxelComponent!.stunTimer = stunTimer;
      voxelComponent!.isHighlighted = (highlightTimer > 0);
      voxelComponent!.isVisible = !(isDisguised || isInvisible);
    }

    voxelComponent!.attackCooldown = visualAttackCooldown;
      try {
        voxelComponent!.activeMaskImage = game.images.fromCache('${currentMaskId}_mask.png');
      } catch (e) {}

    if (!_targetPosition.isZero()) position.lerp(_targetPosition, 15 * dt);
    if (localImmunityToMe > 0) localImmunityToMe -= dt;

    if (!isStunned && _distanceAccumulator >= 85.0) {
      _distanceAccumulator = 0.0; 
      _playSpatialFootstep();
    }

    if (highlightTimer > 0) {
      highlightTimer -= dt;
      if (highlightTimer <= 0 && !isStunned && _fallbackSprite != null) {
        _fallbackSprite!.paint.color = _baseColor;
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
          _fallbackSprite!.paint.color = _baseColor;
          _fallbackSprite!.position = Vector2.zero();
        }
      }
    }

    if (isDisguised) {
      if (_bushSprite != null && _bushSprite!.parent == null) add(_bushSprite!);
    } else if (isInvisible) {
      if (_bushSprite != null && _bushSprite!.parent != null) _bushSprite!.removeFromParent();
    } else {
      if (_bushSprite != null && _bushSprite!.parent != null) _bushSprite!.removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas); 
    if (localImmunityToMe > 0) {
      final alpha = (150 + sin(localImmunityToMe * 10) * 105).toInt().clamp(0, 255);
      final paint = Paint()..color = Colors.amber.withAlpha(alpha)..style = PaintingStyle.stroke..strokeWidth = 3;
      canvas.drawCircle(Offset(size.x / 2, size.y / 2), 24, paint);
    }
  }

  void applyTeamColor(int teamId) {
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
}