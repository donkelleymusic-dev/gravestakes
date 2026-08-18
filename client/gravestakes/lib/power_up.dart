import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class PowerUp extends PositionComponent {
  final String id;
  double pulseTimer = 0;

  PowerUp({required this.id, required Vector2 position}) 
      : super(position: position, size: Vector2.all(16.0), anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    pulseTimer += dt;
  }

  @override
  void render(Canvas canvas) {
    // Creates a glowing, pulsing orb
    final alpha = (150 + sin(pulseTimer * 5) * 105).toInt().clamp(0, 255);
    
    final paint = Paint()
      ..color = Colors.yellowAccent.withAlpha(alpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      
    // Draw the orb in the center of its 16x16 bounding box
    canvas.drawCircle(Offset(size.x / 2, size.y / 2), 8, paint);
  }
}