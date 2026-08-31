import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class ModeToggleButton extends PositionComponent with HasGameReference<GraveStakesGame>, TapCallbacks {
  final double buttonRadius = 25.0;

  ModeToggleButton() {
    size = Vector2.all(buttonRadius * 2);
    anchor = Anchor.center;
    priority = 200000; 
  }

  @override
  void onGameResize(Vector2 gameSize) {
    super.onGameResize(gameSize);
    // Sits just to the right of the mini MAP button under the left joystick
    position = Vector2(140, gameSize.y - 22); 
  }

  @override
  void onTapDown(TapDownEvent event) {
    game.isFpsMode = !game.isFpsMode;
  }

  @override
  void render(Canvas canvas) {
    final center = Offset(buttonRadius, buttonRadius);
    final bgPaint = Paint()..color = Colors.black87;
    final borderPaint = Paint()
      ..color = game.isFpsMode ? Colors.redAccent : Colors.cyanAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(center, buttonRadius, bgPaint);
    canvas.drawCircle(center, buttonRadius, borderPaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: game.isFpsMode ? '3D' : '2D',
        style: TextStyle(
          color: game.isFpsMode ? Colors.redAccent : Colors.cyanAccent,
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