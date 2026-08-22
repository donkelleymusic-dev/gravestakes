import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'dart:math';
import 'game.dart';

class AttackButton extends PositionComponent with HasGameReference<GraveStakesGame>, TapCallbacks {
  final double buttonRadius = 50.0;
  
  AttackButton() {
    size = Vector2(buttonRadius * 2, buttonRadius * 2);
    anchor = Anchor.center;
    priority = 200;
  }

  @override
  void onGameResize(Vector2 gameSize) {
    super.onGameResize(gameSize);
    position = Vector2(gameSize.x - 100, gameSize.y - 120);
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (!game.gameStarted || game.player.isStunned) return;

    final tapPosition = event.localPosition;
    if (tapPosition.x < buttonRadius) {
      game.player.triggerAttack(forceMaskIndex: 0); // Left Side
    } else {
      game.player.triggerAttack(forceMaskIndex: 1); // Right Side
    }
  }

  @override
  void render(Canvas canvas) {
    if (!game.gameStarted) return;
    
    final player = game.player;
    if (player.equippedMasks.length < 2) return;

    final maskLeft = player.equippedMasks[0];
    final maskRight = player.equippedMasks[1];

    final center = Offset(buttonRadius, buttonRadius);

    // Background
    final bgPaint = Paint()..color = Colors.black54;
    canvas.drawCircle(center, buttonRadius, bgPaint);

    // Fill percentages
    final leftFill = (player.energy / maskLeft.energyCost).clamp(0.0, 1.0);
    final rightFill = (player.energy / maskRight.energyCost).clamp(0.0, 1.0);

    // Left Arc
    final leftColor = leftFill >= 1.0 ? Colors.redAccent : Colors.red.withOpacity(0.3);
    final leftPaint = Paint()..color = leftColor..style = PaintingStyle.fill;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: buttonRadius * leftFill),
      pi / 2, pi, true, leftPaint,
    );

    // Right Arc
    final rightColor = rightFill >= 1.0 ? Colors.purpleAccent : Colors.purple.withOpacity(0.3);
    final rightPaint = Paint()..color = rightColor..style = PaintingStyle.fill;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: buttonRadius * rightFill),
      -pi / 2, pi, true, rightPaint,
    );

    // Split Line
    final linePaint = Paint()..color = Colors.white24..strokeWidth = 2.0;
    canvas.drawLine(Offset(buttonRadius, 0), Offset(buttonRadius, buttonRadius * 2), linePaint);
  }
}