import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'player.dart';

class PowerUpHud extends PositionComponent with HasGameReference {
  final Player player;

  PowerUpHud({required this.player}) : super(anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    // Follow right above the player's head
    position = player.position + Vector2(0, -35);
  }

  @override
  void render(Canvas canvas) {
    if (!player.isPoweredUp) return;

    // Calculate percentage remaining (10 seconds total)
    double progress = (player.powerUpTimer / 10.0).clamp(0.0, 1.0);

    const double barWidth = 40.0;
    const double barHeight = 6.0;

    // Draw background track
    final bgPaint = Paint()..color = Colors.black.withAlpha(150);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: barWidth, height: barHeight),
        const Radius.circular(3),
      ),
      bgPaint,
    );

    // Draw glowing yellow progress fill
    final fillPaint = Paint()
      ..color = Colors.yellowAccent
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    double currentWidth = barWidth * progress;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-barWidth / 2, -barHeight / 2, currentWidth, barHeight),
        const Radius.circular(3),
      ),
      fillPaint,
    );
  }
}