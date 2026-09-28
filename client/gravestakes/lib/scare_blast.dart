import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'dart:math';
import 'game.dart';

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

class BansheeBeam extends PositionComponent with HasGameReference<GraveStakesGame> {
  final double angle;
  double _lifeTimer = 0.6; // Lasts just over half a second

  BansheeBeam({required Vector2 position, required this.angle})
      : super(position: position, size: Vector2.all(32), anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    _lifeTimer -= dt;
    if (_lifeTimer <= 0) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    // Fade out as it dies
    double progress = (_lifeTimer / 0.6).clamp(0.0, 1.0);
    
    // Draw a massive, piercing sonic line
    final corePaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(progress)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0 * progress
      ..strokeCap = StrokeCap.round;

    final outerPaint = Paint()
      ..color = Colors.blue.withOpacity(progress * 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24.0 * progress
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0)
      ..strokeCap = StrokeCap.round;

    final start = Offset(size.x / 2, size.y / 2);
    // 1500 pixels directly forward
    final end = start + Offset(sin(angle) * 1500, -cos(angle) * 1500);

    canvas.drawLine(start, end, outerPaint);
    canvas.drawLine(start, end, corePaint);
  }
}