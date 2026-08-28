import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class FlashlightHud extends PositionComponent with HasGameReference<GraveStakesGame>, TapCallbacks {
  FlashlightHud() {
    size = Vector2(120, 40);
    priority = 200;
  }

  @override
  void onGameResize(Vector2 gameSize) {
    super.onGameResize(gameSize);
    // Position it center-bottom, slightly offset to not block the player
    position = Vector2((gameSize.x / 2) - (size.x / 2), gameSize.y - 80);
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
    final borderPaint = Paint()..color = Colors.white54..style = PaintingStyle.stroke..strokeWidth = 2.0;
    final fillPaint = Paint()..color = barColor;

    // Draw Battery Body
    final bodyRect = Rect.fromLTWH(0, 0, size.x - 10, size.y);
    canvas.drawRRect(RRect.fromRectAndRadius(bodyRect, const Radius.circular(6)), bgPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(bodyRect, const Radius.circular(6)), borderPaint);

    // Draw Battery Tip
    final tipRect = Rect.fromLTWH(size.x - 10, size.y / 4, 10, size.y / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(tipRect, const Radius.circular(3)), bgPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(tipRect, const Radius.circular(3)), borderPaint);

    // Draw Fill (With 4px padding)
    if (fillRatio > 0 && !isDead || isRecharging) {
      final fillRect = Rect.fromLTWH(4, 4, (size.x - 18) * fillRatio, size.y - 8);
      canvas.drawRRect(RRect.fromRectAndRadius(fillRect, const Radius.circular(3)), fillPaint);
    }
    
    // Draw "TAP TO CHARGE" if dead
    if (isDead && !isRecharging) {
      const textStyle = TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold);
      final textSpan = TextSpan(text: 'TAP TO PLUG IN', style: textStyle);
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();
      textPainter.paint(canvas, Offset((size.x - 10 - textPainter.width) / 2, (size.y - textPainter.height) / 2));
    }
  }
}