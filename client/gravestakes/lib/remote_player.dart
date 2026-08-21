import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart'; // NEW
import 'game.dart'; // NEW

class RemotePlayer extends PositionComponent with HasGameReference<GraveStakesGame> {
  String currentColorStr = 'red';
  late RectangleComponent _sprite;
  Color _baseColor = Colors.redAccent;

  double highlightTimer = 0;

  void triggerPrivateHighlight() {
    highlightTimer = 1.0; 
    _sprite.paint.color = Colors.white; 
  }

  bool isStunned = false;
  double stunTimer = 0;
  double localImmunityToMe = 0;
  
  int score = 0; // Track their score locally!

  Vector2 _targetPosition = Vector2.zero();

  // ==========================================
  // NEW: REMOTE FOOTSTEP VARIABLES
  // ==========================================
  double _distanceAccumulator = 0.0;
  static const double _audioScale = 50.0;
  final Random _random = Random();

  void _playSpatialFootstep() {
    if (!game.isAudioReady || game.footstepSource == null) return;

    final distance = (position - game.player.position).length;
    if (distance > 1000.0) return;

    // Map Flame X/Y to SoLoud X/Z
    final posX = position.x / _audioScale;
    final posZ = position.y / _audioScale; 

    final randomPitch = 0.85 + (_random.nextDouble() * 0.30);

    // Play on the X/Z plane (Y elevation is 0.0)
    final handle = SoLoud.instance.play3d(
      game.footstepSource!,
      posX,
      0.0,   // Elevation must be 0!
      posZ,  // Passing Flame's Y axis into the Z depth slot
      volume: 0.85,
    );

    SoLoud.instance.setRelativePlaySpeed(handle, randomPitch);
    SoLoud.instance.set3dSourceMinMaxDistance(handle, 2.0, 20.0);
    SoLoud.instance.set3dSourceAttenuation(handle, 1, 1.2);
  }

  RemotePlayer() : super(size: Vector2.all(32.0), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    _sprite = RectangleComponent(
      size: size, 
      paint: Paint()..color = _baseColor,
    );
    add(_sprite);
  }

  void updatePosition(double newX, double newY, double newAngle, {String? colorStr, int? newScore}) {
    final newPos = Vector2(newX, newY);
    
    // Snap instantly on first spawn or huge teleports
    if (_targetPosition.isZero() || position.distanceTo(newPos) > 200.0) {
      position = newPos.clone();
    }
    
    _distanceAccumulator += _targetPosition.distanceTo(newPos);
    
    _targetPosition = newPos;
    angle = newAngle;

    if (colorStr != null && colorStr != currentColorStr) {
      currentColorStr = colorStr;
      _updateBaseColor(colorStr);
    }
    
    if (newScore != null) {
      score = newScore;
    }
  }

  void _updateBaseColor(String colorStr) {
    switch (colorStr) {
      case 'green': _baseColor = Colors.greenAccent; break;
      case 'purple': _baseColor = Colors.purpleAccent; break;
      case 'blue': _baseColor = Colors.cyanAccent; break;
      case 'red':
      default: _baseColor = Colors.redAccent; break;
    }
    if (!isStunned) _sprite.paint.color = _baseColor;
  }

  void applyStun(double duration) {
    isStunned = true;
    stunTimer = duration;
    _sprite.paint.color = Colors.cyanAccent;
  }

  @override
  void update(double dt) {
    super.update(dt);

    // ==========================================
    // NEW: SMOOTH NETWORK GLIDING (LERP)
    // ==========================================
    if (!_targetPosition.isZero()) {
      position.lerp(_targetPosition, 15 * dt);
    }

    if (localImmunityToMe > 0) {
      localImmunityToMe -= dt;
    }

    if (!isStunned && _distanceAccumulator >= 85.0) {
      _distanceAccumulator = 0.0; 
      _playSpatialFootstep();
    }

    if (highlightTimer > 0) {
      highlightTimer -= dt;
      if (highlightTimer <= 0 && !isStunned) {
        _sprite.paint.color = _baseColor;
      }
    }

    if (isStunned) {
      stunTimer -= dt;
      
      int alpha = (150 + sin(stunTimer * 30) * 105).toInt().clamp(0, 255);
      _sprite.paint.color = Colors.cyanAccent.withAlpha(alpha);
      _sprite.position = Vector2(sin(stunTimer * 50) * 4, 0);

      if (stunTimer <= 0) {
        isStunned = false;
        _sprite.paint.color = _baseColor;
        _sprite.position = Vector2.zero();
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas); // Renders the sprite first

    // Draw a pulsating immunity shield ring if they are immune to us
    if (localImmunityToMe > 0) {
      final alpha = (150 + sin(localImmunityToMe * 10) * 105).toInt().clamp(0, 255);
      final paint = Paint()
        ..color = Colors.amber.withAlpha(alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      
      // Draw the circle slightly larger than the 32x32 sprite (radius 24)
      canvas.drawCircle(Offset(size.x / 2, size.y / 2), 24, paint);
    }
  }
}