import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class AttackButton extends PositionComponent with HasGameReference<GraveStakesGame>, TapCallbacks {
  final double buttonRadius = 55.0;
  
  AttackButton() {
    size = Vector2(buttonRadius * 2, buttonRadius * 2);
    anchor = Anchor.center;
    priority = 200;
  }

  @override
  void onGameResize(Vector2 gameSize) {
    super.onGameResize(gameSize);
    position = Vector2(gameSize.x - 110, gameSize.y - 130);
  }

  @override
  void onTapDown(TapDownEvent event) {
    debugPrint('Am I the Host right now? ${game.isHost}');
    if (!game.gameStarted || game.player.isStunned) return;

    final localPos = event.localPosition;
    final dx = localPos.x - buttonRadius;
    final dy = localPos.y - buttonRadius;

    // Determine which quadrant was tapped
    int targetSlot = 0;
    if (dx >= 0 && dy < 0) {
      targetSlot = 0; // Top-Right (Slot 1)
    } else if (dx >= 0 && dy >= 0) {
      targetSlot = 1; // Bottom-Right (Slot 2)
    } else if (dx < 0 && dy >= 0) {
      targetSlot = 2; // Bottom-Left (Slot 3)
    } else {
      targetSlot = 3; // Top-Left (Slot 4)
    }

    // Only fire if the player actually has a mask equipped in this slot
    if (targetSlot < game.player.equippedMasks.length) {
      game.player.triggerAttack(forceMaskIndex: targetSlot);
    }
  }

  @override
  void render(Canvas canvas) {
    if (!game.gameStarted) return;
    
    final player = game.player;
    final center = Offset(buttonRadius, buttonRadius);

    // 1. Draw Base Background Circle
    final bgPaint = Paint()..color = Colors.black54;
    canvas.drawCircle(center, buttonRadius, bgPaint);

    // Define quadrant angles (Start angle, sweep angle) in canvas coordinates
    // Slot 0: Top-Right (-pi/2 to 0)
    // Slot 1: Bottom-Right (0 to pi/2)
    // Slot 2: Bottom-Left (pi/2 to pi)
    // Slot 3: Top-Left (pi to 3pi/2)
    final List<List<double>> quadrantAngles = [
      [-pi / 2, pi / 2], // Top-Right
      [0, pi / 2],       // Bottom-Right
      [pi / 2, pi / 2],  // Bottom-Left
      [pi, pi / 2],      // Top-Left
    ];

    for (int i = 0; i < 4; i++) {
      final startAngle = quadrantAngles[i][0];
      final sweepAngle = quadrantAngles[i][1];

      if (i < player.equippedMasks.length) {
        final mask = player.equippedMasks[i];
        final fillRatio = (player.energy / mask.energyCost).clamp(0.0, 1.0);

        // Active Quadrant Fill
        final activeColor = fillRatio >= 1.0 ? Colors.redAccent : Colors.red.withOpacity(0.3);
        final paint = Paint()..color = activeColor..style = PaintingStyle.fill;

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: buttonRadius * fillRatio),
          startAngle,
          sweepAngle,
          true,
          paint,
        );
      } else {
        // Inactive / Empty Slot Placeholder
        final emptyPaint = Paint()..color = Colors.white10..style = PaintingStyle.fill;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: buttonRadius * 0.8),
          startAngle,
          sweepAngle,
          true,
          emptyPaint,
        );
      }
    }

    // 2. Draw Crosshairs / Grid Dividers
    final linePaint = Paint()..color = Colors.white30..strokeWidth = 2.0;
    canvas.drawLine(Offset(buttonRadius, 0), Offset(buttonRadius, buttonRadius * 2), linePaint);
    canvas.drawLine(Offset(0, buttonRadius), Offset(buttonRadius * 2, buttonRadius), linePaint);
  }
}