import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class AttackButton extends PositionComponent with HasGameReference<GraveStakesGame>, TapCallbacks {
  final double buttonRadius = 55.0;
  late final TextPaint _textPaint;
  
  AttackButton() {
    size = Vector2(buttonRadius * 2, buttonRadius * 2);
    anchor = Anchor.center;
    priority = 200;
    
    // --- NEW: Font stylings for the button letters ---
    _textPaint = TextPaint(
      style: const TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.bold,
        shadows: [Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1))],
      ),
    );
  }

  @override
  void onGameResize(Vector2 gameSize) {
    super.onGameResize(gameSize);
    position = Vector2(gameSize.x - 110, gameSize.y - 130);
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (!game.gameStarted || game.player.isStunned) return;

    final localPos = event.localPosition;
    final dx = localPos.x - buttonRadius;
    final dy = localPos.y - buttonRadius;

    int targetSlot = 0;
    if (dx >= 0 && dy < 0) {
      targetSlot = 0; // Top-Right
    } else if (dx >= 0 && dy >= 0) {
      targetSlot = 1; // Bottom-Right
    } else if (dx < 0 && dy >= 0) {
      targetSlot = 2; // Bottom-Left
    } else {
      targetSlot = 3; // Top-Left
    }

    // Attempt to fire! (The Player class now safely catches empty slots)
    game.player.triggerAttack(forceMaskIndex: targetSlot);
  }

  @override
  void render(Canvas canvas) {
    if (!game.gameStarted) return;
    
    final player = game.player;
    final center = Offset(buttonRadius, buttonRadius);

    final bgPaint = Paint()..color = Colors.black54;
    canvas.drawCircle(center, buttonRadius, bgPaint);

    final List<List<double>> quadrantAngles = [
      [-pi / 2, pi / 2], // Top-Right
      [0, pi / 2],       // Bottom-Right
      [pi / 2, pi / 2],  // Bottom-Left
      [pi, pi / 2],      // Top-Left
    ];

    for (int i = 0; i < 4; i++) {
      final startAngle = quadrantAngles[i][0];
      final sweepAngle = quadrantAngles[i][1];
      
      final mask = player.equippedMasks[i];

      if (mask != null) {
        final fillRatio = (player.energy / mask.energyCost).clamp(0.0, 1.0);
        final activeColor = fillRatio >= 1.0 ? Colors.redAccent : Colors.red.withOpacity(0.3);
        final paint = Paint()..color = activeColor..style = PaintingStyle.fill;

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: buttonRadius * fillRatio),
          startAngle,
          sweepAngle,
          true,
          paint,
        );

        // --- NEW: Draw the Letter perfectly centered in the slice! ---
        final textAngle = startAngle + (sweepAngle / 2);
        final textRadius = buttonRadius * 0.65; // Push the letter out toward the edge
        final textCenter = Offset(
          center.dx + cos(textAngle) * textRadius,
          center.dy + sin(textAngle) * textRadius,
        );
        
        // Grab the first letter (S for Siren, B for Bat, etc.)
        String letter = mask.name.substring(0, 1).toUpperCase();
        _textPaint.render(canvas, letter, Vector2(textCenter.dx, textCenter.dy), anchor: Anchor.center);

      } else {
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

    final linePaint = Paint()..color = Colors.white30..strokeWidth = 2.0;
    canvas.drawLine(Offset(buttonRadius, 0), Offset(buttonRadius, buttonRadius * 2), linePaint);
    canvas.drawLine(Offset(0, buttonRadius), Offset(buttonRadius * 2, buttonRadius), linePaint);
  }
}