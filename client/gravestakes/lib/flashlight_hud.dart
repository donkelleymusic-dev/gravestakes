import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class FlashlightHud extends PositionComponent with HasGameReference<GraveStakesGame>, TapCallbacks {
  FlashlightHud() {
    // Taller, chunky battery proportions for clean tapping
    size = Vector2(80, 22);
    priority = 200;
  }

  @override
  void onGameResize(Vector2 gameSize) {
    super.onGameResize(gameSize);
    // Align directly under the Attack Button (Y adjusted slightly to account for the extra height)
    position = Vector2(gameSize.x - 110 - (size.x / 2), gameSize.y - 32);
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
    
    // NEW: Check if battery is critically low (under 15%)
    final isCriticallyLow = battery > 0 && battery < 15.0 && !isRecharging;
    // NEW: Global blink state syncing the bar, border, and text
    final blinkState = DateTime.now().millisecondsSinceEpoch % 500 < 250;

    final fillRatio = (battery / 100.0).clamp(0.0, 1.0);
    
    // Determine Color based on charge state
    Color barColor = Colors.greenAccent;
    if (isRecharging) {
      barColor = Colors.cyanAccent; // Powerbank charging state
    } else if (isDead) {
      // Flashing warning red if completely drained
      barColor = blinkState ? Colors.redAccent : Colors.red.shade900;
    } else if (isCriticallyLow) {
      // Frantic flashing when about to die
      barColor = blinkState ? Colors.redAccent : Colors.orangeAccent;
    } else if (battery < 25.0) {
      barColor = Colors.orangeAccent;
    }

    final bgPaint = Paint()..color = Colors.black87;
    
    // Thicken and turn the border red during critical flashes
    final borderPaint = Paint()
      ..color = (isDead || (isCriticallyLow && blinkState)) ? Colors.redAccent : Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = (isDead || (isCriticallyLow && blinkState)) ? 2.5 : 1.5;
      
    final fillPaint = Paint()..color = barColor;

    // Battery Shell Proportions (Main Body + Terminal Cap on right)
    double capWidth = 5.0;
    double bodyWidth = size.x - capWidth;
    
    // 1. Draw Positive Terminal Cap (Right Side)
    final capRect = Rect.fromLTWH(
      bodyWidth - 1, 
      size.y * 0.25, 
      capWidth, 
      size.y * 0.5
    );
    canvas.drawRRect(RRect.fromRectAndRadius(capRect, const Radius.circular(2)), Paint()..color = Colors.white70);

    // 2. Draw Battery Outer Case
    final bodyRect = Rect.fromLTWH(0, 0, bodyWidth, size.y);
    canvas.drawRRect(RRect.fromRectAndRadius(bodyRect, const Radius.circular(4)), bgPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(bodyRect, const Radius.circular(4)), borderPaint);

    // 3. Draw Depleting/Filling Energy Core
    if ((fillRatio > 0 && !isDead) || isRecharging) {
      double maxFillWidth = bodyWidth - 4;
      final fillRect = Rect.fromLTWH(2, 2, maxFillWidth * fillRatio, size.y - 4);
      canvas.drawRRect(RRect.fromRectAndRadius(fillRect, const Radius.circular(2)), fillPaint);
    }

    // 4. Draw Inner Cell Segment Lines
    final dividerPaint = Paint()
      ..color = Colors.black45
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    
    for (int i = 1; i < 4; i++) {
      double divX = (bodyWidth / 4) * i;
      canvas.drawLine(Offset(divX, 2), Offset(divX, size.y - 2), dividerPaint);
    }

    // 5. Warning / Charging Label
    String? hudText;
    if (isRecharging) {
      hudText = 'CHARGING...';
    } else if (isDead) {
      hudText = 'TAP TO PLUG IN';
    } else if (isCriticallyLow) {
      // Flashes the text on and off when low
      hudText = blinkState ? 'LOW BATTERY!' : null; 
    }

    if (hudText != null) {
      final textStyle = TextStyle(
        color: (isDead || isCriticallyLow) ? Colors.redAccent : Colors.cyanAccent, 
        fontSize: 9, 
        fontWeight: FontWeight.bold, 
        fontFamily: 'Courier',
        shadows: const [Shadow(blurRadius: 3, color: Colors.black)]
      );
      final textPainter = TextPainter(
        text: TextSpan(text: hudText, style: textStyle), 
        textDirection: TextDirection.ltr
      )..layout();
      
      textPainter.paint(
        canvas, 
        Offset((bodyWidth - textPainter.width) / 2, -13)
      );
    }
  }
}