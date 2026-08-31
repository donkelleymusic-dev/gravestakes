import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class MapButton extends PositionComponent with HasGameReference<GraveStakesGame>, TapCallbacks {
  final double buttonRadius = 25.0;

  MapButton() {
    size = Vector2.all(buttonRadius * 2);
    anchor = Anchor.center;
    priority = 200; // Stay above world elements
  }

  @override
  void onGameResize(Vector2 gameSize) {
    super.onGameResize(gameSize);
    // Position it in the top-right corner of the screen
    position = Vector2(gameSize.x - 40, 50);
  }

  @override
  void onTapDown(TapDownEvent event) {
    // Toggle the map overlay on tap
    game.mapOverlay.toggle();
  }

  @override
  void render(Canvas canvas) {
    final center = Offset(buttonRadius, buttonRadius);

    // Draw dark circle button
    final bgPaint = Paint()..color = Colors.black87;
    final borderPaint = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(center, buttonRadius, bgPaint);
    canvas.drawCircle(center, buttonRadius, borderPaint);

    // Draw simple "M" text inside
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'MAP',
        style: TextStyle(
          color: Colors.cyanAccent,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(buttonRadius - (textPainter.width / 2), buttonRadius - (textPainter.height / 2)),
    );
  }
}