import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'dart:math';

class SirenBlast extends PositionComponent {
  double lifeTimer = 0.5;
  final double maxLife = 0.5;

  SirenBlast({required Vector2 position, required double angle}) 
      : super(position: position, angle: angle, anchor: Anchor.center);

  @override
  void render(Canvas canvas) {
    int alpha = ((lifeTimer / maxLife) * 150).toInt().clamp(0, 255);
    
    // Draw a 180-degree ambient wash (Wide Cone)
    final washPaint = Paint()..color = Colors.pinkAccent.withAlpha(alpha ~/ 2)..style = PaintingStyle.fill;
    canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: 300), -pi / 2, pi, true, washPaint);

    // Draw the 25-degree Resonant Core (Tight Cone)
    final corePaint = Paint()..color = Colors.purpleAccent.withAlpha(alpha)..style = PaintingStyle.fill;
    canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: 300), -0.22, 0.44, true, corePaint);
  }

  @override
  void update(double dt) {
    super.update(dt);
    lifeTimer -= dt;
    if (lifeTimer <= 0) removeFromParent();
  }
}