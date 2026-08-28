import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class AttackButton extends PositionComponent with HasGameReference<GraveStakesGame>, TapCallbacks {
  final double buttonRadius = 55.0;
  int? _flashedSlot; 
  
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
    if (!game.gameStarted || game.player.isStunned) return;

    final localPos = event.localPosition;
    final dx = localPos.x - buttonRadius;
    final dy = localPos.y - buttonRadius;

    // Fixed Mapping: Standard Z-Grid reading order
    int targetSlot = 0;
    if (dx < 0 && dy < 0) {
      targetSlot = 0; // Top-Left
    } else if (dx >= 0 && dy < 0) {
      targetSlot = 1; // Top-Right
    } else if (dx < 0 && dy >= 0) {
      targetSlot = 2; // Bottom-Left
    } else {
      targetSlot = 3; // Bottom-Right
    }

    if (targetSlot < game.player.equippedMasks.length && game.player.equippedMasks[targetSlot] != null) {
      final mask = game.player.equippedMasks[targetSlot]!;
      // Only flash if the player actually has enough energy to fire it
      if (game.player.energy >= mask.energyCost || mask.id == 'standard') {
        _triggerFlash(targetSlot);
      }
    }

    game.player.triggerAttack(forceMaskIndex: targetSlot);
  }

  void _triggerFlash(int slot) {
    _flashedSlot = slot;
    Future.delayed(const Duration(milliseconds: 150), () {
      _flashedSlot = null;
    });
  }

  void _drawMaskIcon(Canvas canvas, Offset c, String maskId) {
    final fillPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    final strokePaint = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.0;

    if (maskId == 'standard') {
      // Flashlight beam: small bottom, wider top
      final path = Path()
        ..moveTo(c.dx, c.dy + 8)
        ..lineTo(c.dx - 10, c.dy - 12)
        ..arcToPoint(Offset(c.dx + 10, c.dy - 12), radius: const Radius.circular(15), clockwise: true)
        ..close();
      canvas.drawPath(path, fillPaint);
    } 
    else if (maskId == 'siren') {
      // Mouth profile with expanding sound waves
      canvas.drawArc(Rect.fromCircle(center: Offset(c.dx - 4, c.dy), radius: 6), pi / 2, pi, false, strokePaint); // Mouth
      canvas.drawArc(Rect.fromCircle(center: Offset(c.dx - 4, c.dy), radius: 10), -pi/3, (2*pi)/3, false, strokePaint); // Wave 1
      canvas.drawArc(Rect.fromCircle(center: Offset(c.dx - 4, c.dy), radius: 15), -pi/3, (2*pi)/3, false, strokePaint); // Wave 2
    } 
    else if (maskId == 'vermin') {
      // 3 tiny land-based critter circles
      canvas.drawCircle(Offset(c.dx - 10, c.dy), 3, fillPaint);
      canvas.drawCircle(Offset(c.dx, c.dy), 3, fillPaint);
      canvas.drawCircle(Offset(c.dx + 10, c.dy), 3, fillPaint);
    } 
    else if (maskId == 'flying') {
      // Bat vector shape with altitude lines
      final path = Path()
        ..moveTo(c.dx - 14, c.dy - 4)
        ..quadraticBezierTo(c.dx - 7, c.dy - 10, c.dx, c.dy - 2) // Left wing
        ..quadraticBezierTo(c.dx + 7, c.dy - 10, c.dx + 14, c.dy - 4); // Right wing
      canvas.drawPath(path, strokePaint);
      canvas.drawLine(Offset(c.dx - 7, c.dy + 4), Offset(c.dx - 7, c.dy + 10), strokePaint);
      canvas.drawLine(Offset(c.dx + 7, c.dy + 4), Offset(c.dx + 7, c.dy + 10), strokePaint);
    } 
    else {
      canvas.drawCircle(c, 4, fillPaint);
    }
  }

  @override
  void render(Canvas canvas) {
    if (!game.gameStarted) return;
    
    final player = game.player;
    final center = Offset(buttonRadius, buttonRadius);

    final bgPaint = Paint()..color = Colors.black54;
    canvas.drawCircle(center, buttonRadius, bgPaint);

    final List<List<double>> quadrantAngles = [
      [pi, pi / 2],      // 0: Top-Left
      [-pi / 2, pi / 2], // 1: Top-Right
      [pi / 2, pi / 2],  // 2: Bottom-Left
      [0, pi / 2],       // 3: Bottom-Right
    ];

    for (int i = 0; i < 4; i++) {
      final startAngle = quadrantAngles[i][0];
      final sweepAngle = quadrantAngles[i][1];
      
      final mask = player.equippedMasks[i];

      if (mask != null) {
        final fillRatio = (player.energy / mask.energyCost).clamp(0.0, 1.0);
        
        // Determine the base color
        Color activeColor = fillRatio >= 1.0 ? Colors.redAccent : Colors.red.withOpacity(0.3);
        
        // Override with a bright white flash if this slot was just tapped
        if (_flashedSlot == i) {
          activeColor = Colors.white;
        }

        final paint = Paint()..color = activeColor..style = PaintingStyle.fill;

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: buttonRadius * fillRatio),
          startAngle,
          sweepAngle,
          true,
          paint,
        );

        final iconAngle = startAngle + (sweepAngle / 2);
        final iconRadius = buttonRadius * 0.65; 
        final iconCenter = Offset(
          center.dx + cos(iconAngle) * iconRadius,
          center.dy + sin(iconAngle) * iconRadius,
        );
        
        _drawMaskIcon(canvas, iconCenter, mask.id);

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