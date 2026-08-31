import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class FlashlightHud extends PositionComponent with HasGameReference<GraveStakesGame>, TapCallbacks {
  FlashlightHud() {
    // Shrink to a sleek, modern bar instead of a bulky battery
    size = Vector2(80, 10);
    priority = 200;
  }

  @override
  void onGameResize(Vector2 gameSize) {
    super.onGameResize(gameSize);
    // Align directly under the Attack Button's X axis (which is gameSize.x - 110)
    // Push it down to gameSize.y - 25 so it sits cleanly below the button
    position = Vector2(gameSize.x - 110 - (size.x / 2), gameSize.y - 25);
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (game.gameStarted && !game.player.isStunned) {
      game.player.rechargeFlashlight();
    }
  }

  @override
  void render(Canvas canvas) {
    if (!game.gameStarted) return;
    
    final battery = game.player.flashlightBattery;
    final isRecharging = game.player.isRecharging;
    final isDead = game.player.isFlashlightDead;

    final fillRatio = (battery / 100.0).clamp(0.0, 1.0);
    
    // Determine Color based on state
    Color barColor = Colors.greenAccent;
    if (isRecharging) {
      barColor = Colors.cyanAccent; // USB Powerbank color
    } else if (isDead) {
      // Flash red if completely dead and not recharging
      barColor = (DateTime.now().millisecondsSinceEpoch % 500 < 250) ? Colors.redAccent : Colors.transparent;
    } else if (battery < 20.0) {
      barColor = Colors.orangeAccent;
    }

    final bgPaint = Paint()..color = Colors.black54;
    final borderPaint = Paint()..color = Colors.white54..style = PaintingStyle.stroke..strokeWidth = 1.0;
    final fillPaint = Paint()..color = barColor;

    // Draw Sleek Bar Body
    final bodyRect = Rect.fromLTWH(0, 0, size.x, size.y);
    canvas.drawRRect(RRect.fromRectAndRadius(bodyRect, const Radius.circular(4)), bgPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(bodyRect, const Radius.circular(4)), borderPaint);

    // Draw Fill (With 2px padding so the border shows)
    if (fillRatio > 0 && !isDead || isRecharging) {
      final fillRect = Rect.fromLTWH(2, 2, (size.x - 4) * fillRatio, size.y - 4);
      canvas.drawRRect(RRect.fromRectAndRadius(fillRect, const Radius.circular(2)), fillPaint);
    }
    
    // Draw "TAP TO PLUG IN" hovering right above the bar if dead
    if (isDead && !isRecharging) {
      const textStyle = TextStyle(
        color: Colors.white, 
        fontSize: 10, 
        fontWeight: FontWeight.bold, 
        shadows: [Shadow(blurRadius: 2, color: Colors.black)]
      );
      final textSpan = TextSpan(text: 'TAP TO PLUG IN', style: textStyle);
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();
      textPainter.paint(canvas, Offset((size.x - textPainter.width) / 2, -14));
    }
  }
}