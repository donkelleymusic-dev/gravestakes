import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class ScareBlast extends PositionComponent {
  double lifeTimer = 0.25;
  final double maxLife = 0.25;

  ScareBlast({required Vector2 position, required double angle}) 
      : super(position: position, angle: angle, anchor: Anchor.center);

  @override
  void render(Canvas canvas) {
    // Fades out over 0.25 seconds
    int alpha = ((lifeTimer / maxLife) * 150).toInt().clamp(0, 255);
    
    final paint = Paint()
      ..color = Colors.white.withAlpha(alpha)
      ..style = PaintingStyle.fill;
    
    // Draw a cone (radius 250 pixels) pointing forward
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: 250),
      -1.2, // Start angle (slightly to the left)
      2.4,  // Sweep angle (covers the front cone)
      true, // Connect back to center
      paint,
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    lifeTimer -= dt;
    if (lifeTimer <= 0) {
      removeFromParent(); // Delete itself when the flash is over
    }
  }
}