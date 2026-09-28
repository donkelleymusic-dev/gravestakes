import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'game.dart';
import 'puzzle_door.dart';

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
    super.onTapDown(event);
    if (!game.gameStarted || game.player.isStunned) return;

    // --- NEW: DISARM THE DRIVER ---
    if (game.hasGunner && !game.player.isGunner) return;

    // --- NEW: Forgiving Magnetic Puzzle Interaction ---
    if (game.player.isInPuzzleRoom) {
      _triggerFlash(0); 
      
      PuzzleDoor? closestDoor;
      double closestDist = 250.0; 

      game.world.children.whereType<PuzzleDoor>().forEach((door) {
        double dist = game.player.position.distanceTo(door.position);
        if (dist < closestDist) {
          closestDist = dist;
          closestDoor = door;
        }
      });

      closestDoor?.onInteract();
      return; 
    }

    // --- EXISTING LOGIC: Standard Z-Grid reading order ---
    final localPos = event.localPosition;
    final dx = localPos.x - buttonRadius;
    final dy = localPos.y - buttonRadius;

    int targetSlot = 0;
    if (dx < 0 && dy < 0) targetSlot = 0;
    else if (dx >= 0 && dy < 0) targetSlot = 1;
    else if (dx < 0 && dy >= 0) targetSlot = 2;
    else targetSlot = 3;

    if (targetSlot < game.player.equippedMasks.length && game.player.equippedMasks[targetSlot] != null) {
      final mask = game.player.equippedMasks[targetSlot]!;
      // Only flash if we have energy AND the cooldown is clear
      if ((game.player.energy >= mask.energyCost || mask.id == 'standard') && game.player.attackCooldown <= 0) {
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
      final path = Path()
        ..moveTo(c.dx, c.dy + 8)
        ..lineTo(c.dx - 10, c.dy - 12)
        ..arcToPoint(Offset(c.dx + 10, c.dy - 12), radius: const Radius.circular(15), clockwise: true)
        ..close();
      canvas.drawPath(path, fillPaint);
    } 
    else if (maskId == 'siren') {
      canvas.drawArc(Rect.fromCircle(center: Offset(c.dx - 4, c.dy), radius: 6), pi / 2, pi, false, strokePaint);
      canvas.drawArc(Rect.fromCircle(center: Offset(c.dx - 4, c.dy), radius: 10), -pi/3, (2*pi)/3, false, strokePaint);
      canvas.drawArc(Rect.fromCircle(center: Offset(c.dx - 4, c.dy), radius: 15), -pi/3, (2*pi)/3, false, strokePaint);
    } 
    else if (maskId == 'vermin') {
      canvas.drawCircle(Offset(c.dx - 10, c.dy), 3, fillPaint);
      canvas.drawCircle(Offset(c.dx, c.dy), 3, fillPaint);
      canvas.drawCircle(Offset(c.dx + 10, c.dy), 3, fillPaint);
    } 
    else if (maskId == 'flying') {
      final path = Path()
        ..moveTo(c.dx - 14, c.dy - 4)
        ..quadraticBezierTo(c.dx - 7, c.dy - 10, c.dx, c.dy - 2) 
        ..quadraticBezierTo(c.dx + 7, c.dy - 10, c.dx + 14, c.dy - 4); 
      canvas.drawPath(path, strokePaint);
      canvas.drawLine(Offset(c.dx - 7, c.dy + 4), Offset(c.dx - 7, c.dy + 10), strokePaint);
      canvas.drawLine(Offset(c.dx + 7, c.dy + 4), Offset(c.dx + 7, c.dy + 10), strokePaint);
    } 
    else if (maskId == 'gorgon') {
      final path = Path()
        ..moveTo(c.dx - 10, c.dy)
        ..quadraticBezierTo(c.dx, c.dy - 9, c.dx + 10, c.dy)
        ..quadraticBezierTo(c.dx, c.dy + 9, c.dx - 10, c.dy);
      canvas.drawPath(path, strokePaint);
      canvas.drawLine(Offset(c.dx, c.dy - 4), Offset(c.dx, c.dy + 4), strokePaint..strokeWidth = 2.5);
    }
    else if (maskId == 'poltergeist') {
      final path = Path()
        ..moveTo(c.dx, c.dy - 9)
        ..lineTo(c.dx + 9, c.dy)
        ..lineTo(c.dx, c.dy + 9)
        ..lineTo(c.dx - 9, c.dy)
        ..close();
      canvas.drawPath(path, strokePaint);
      canvas.drawCircle(c, 2.0, fillPaint);
    }
    else if (maskId == 'banshee') {
      canvas.drawOval(Rect.fromCenter(center: Offset(c.dx - 6, c.dy), width: 4, height: 11), fillPaint);
      canvas.drawArc(Rect.fromCircle(center: Offset(c.dx - 3, c.dy), radius: 7), -pi/3, (2*pi)/3, false, strokePaint);
      canvas.drawArc(Rect.fromCircle(center: Offset(c.dx - 3, c.dy), radius: 11), -pi/3, (2*pi)/3, false, strokePaint);
    }
    else if (maskId == 'wendigo') {
      final path = Path()
        ..moveTo(c.dx, c.dy + 7)
        ..lineTo(c.dx - 7, c.dy - 6)
        ..moveTo(c.dx, c.dy + 7)
        ..lineTo(c.dx + 7, c.dy - 6)
        ..moveTo(c.dx - 3.5, c.dy + 0.5)
        ..lineTo(c.dx - 8.5, c.dy + 1.5)
        ..moveTo(c.dx + 3.5, c.dy + 0.5)
        ..lineTo(c.dx + 8.5, c.dy + 1.5);
      canvas.drawPath(path, strokePaint);
    }
    else if (maskId == 'parasite') {
      canvas.drawCircle(c, 8, strokePaint);
      for (int i = 0; i < 8; i++) {
        double angle = i * (pi / 4);
        canvas.drawLine(
          Offset(c.dx + cos(angle) * 8, c.dy + sin(angle) * 8),
          Offset(c.dx + cos(angle) * 4, c.dy + sin(angle) * 4),
          strokePaint..strokeWidth = 1.5
        );
      }
    }
    else {
      canvas.drawCircle(c, 4, fillPaint);
    }
  }

  @override
  void render(Canvas canvas) {
    if (!game.gameStarted) return;
    if (game.hasGunner && !game.player.isGunner) return;
    
    final player = game.player; 
    final center = Offset(buttonRadius, buttonRadius);

    // --- PUZZLE ROOM OVERRIDE ---
    if (player.isInPuzzleRoom) {
      bool isNearDoor = false;
      for (var door in game.world.children.whereType<PuzzleDoor>()) {
        if (player.position.distanceTo(door.position) < 250.0) {
          isNearDoor = true;
          break;
        }
      }

      final bgPaint = Paint()..color = isNearDoor ? Colors.black87 : Colors.black54;
      final borderPaint = Paint()
        ..color = _flashedSlot == 0 
            ? Colors.white 
            : (isNearDoor ? Colors.amberAccent : Colors.red[900]!)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isNearDoor ? 4.0 : 3.0;

      canvas.drawCircle(center, buttonRadius, bgPaint);
      canvas.drawCircle(center, buttonRadius, borderPaint);
      
      final keyholePaint = Paint()
        ..color = isNearDoor ? Colors.white : Colors.grey
        ..style = PaintingStyle.fill;
        
      canvas.drawCircle(Offset(center.dx, center.dy - 5), 8, keyholePaint);
      canvas.drawPath(Path()
        ..moveTo(center.dx - 6, center.dy)
        ..lineTo(center.dx + 6, center.dy)
        ..lineTo(center.dx + 10, center.dy + 15)
        ..lineTo(center.dx - 10, center.dy + 15)
        ..close(), keyholePaint);
      return;
    }

    // --- STANDARD ATTACK WHEEL ---
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
        // 1. DRAW ENERGY LAYER (GREEN)
        final fillRatio = (player.energy / mask.energyCost).clamp(0.0, 1.0);
        Color energyColor = fillRatio >= 1.0 ? Colors.greenAccent : Colors.greenAccent.withOpacity(0.3);
        if (_flashedSlot == i) energyColor = Colors.white;

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: buttonRadius * fillRatio),
          startAngle,
          sweepAngle,
          true,
          Paint()..color = energyColor..style = PaintingStyle.fill,
        );

        // 2. DRAW COOLDOWN LAYER (RED)
        if (player.attackCooldown > 0) {
          // Calculate the cooldown ratio specific to this mask's maximum cooldown length
          double maxCd = mask.cooldown > 0 ? mask.cooldown : 1.0; 
          double cdRatio = (player.attackCooldown / maxCd).clamp(0.0, 1.0);
          
          if (cdRatio > 0) {
            final cdPaint = Paint()..color = Colors.redAccent.withOpacity(0.85)..style = PaintingStyle.fill;
            // The red wedge shrinks towards the center as the cooldown ticks down
            canvas.drawArc(
              Rect.fromCircle(center: center, radius: buttonRadius * cdRatio),
              startAngle,
              sweepAngle,
              true,
              cdPaint,
            );
          }
        }

        // 3. DRAW THE VECTOR ICON
        final iconAngle = startAngle + (sweepAngle / 2);
        final iconRadius = buttonRadius * 0.65; 
        final iconCenter = Offset(
          center.dx + cos(iconAngle) * iconRadius,
          center.dy + sin(iconAngle) * iconRadius,
        );
        
        _drawMaskIcon(canvas, iconCenter, mask.id);

      } else {
        // Draw empty slot
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