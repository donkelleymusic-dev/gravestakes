import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class RemotePlayer extends PositionComponent {
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
  
  int score = 0; // NEW: Track their score locally!

  RemotePlayer() : super(size: Vector2.all(32.0), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    _sprite = RectangleComponent(
      size: size, 
      paint: Paint()..color = _baseColor,
    );
    add(_sprite);
  }

  // NEW: Added {int? newScore} to the parameters
  void updatePosition(double newX, double newY, double newAngle, {String? colorStr, int? newScore}) {
    position.x = newX;
    position.y = newY;
    angle = newAngle;

    if (colorStr != null && colorStr != currentColorStr) {
      currentColorStr = colorStr;
      _updateBaseColor(colorStr);
    }
    
    // NEW: Update their score if the payload included it
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

    // Count down the immunity timer
    if (localImmunityToMe > 0) {
      localImmunityToMe -= dt;
    }

    // NEW: Highlight timer countdown
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