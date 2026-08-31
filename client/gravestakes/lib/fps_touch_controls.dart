import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class FpsTouchControls extends PositionComponent with HasGameReference<GraveStakesGame> {
  FpsTouchControls() : super(priority: 200000); // Renders above world elements

  @override
  void onGameResize(Vector2 gameSize) {
    super.onGameResize(gameSize);
    // Moved Y from (gameSize.y - 170) to (gameSize.y - 212) -> Shifted up ~42px
    position = Vector2(20, gameSize.y - 212);
    size = Vector2(180, 40);
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();

    // 1. Instant 90° Left Snap
    add(FpsActionButton(
      label: '↰ 90°',
      position: Vector2(0, 0),
      onPressed: () => game.player.facingAngle -= (pi / 2),
    ));

    // 2. Glance Left (Peek Q)
    add(FpsActionButton(
      label: '◄ PEEK',
      position: Vector2(44, 0),
      onPressedDown: () => game.player.glanceOffset = -pi / 4,
      onPressedUp: () => game.player.glanceOffset = 0.0,
    ));

    // 3. Glance Right (Peek E)
    add(FpsActionButton(
      label: 'PEEK ►',
      position: Vector2(88, 0),
      onPressedDown: () => game.player.glanceOffset = pi / 4,
      onPressedUp: () => game.player.glanceOffset = 0.0,
    ));

    // 4. Instant 90° Right Snap
    add(FpsActionButton(
      label: '90° ↱',
      position: Vector2(132, 0),
      onPressed: () => game.player.facingAngle += (pi / 2),
    ));
  }

  @override
  void render(Canvas canvas) {
    // Only render these buttons when active in 3D FPS Mode!
    if (!game.isFpsMode) return;
    super.render(canvas);
  }
}

class FpsActionButton extends PositionComponent with TapCallbacks {
  final String label;
  final VoidCallback? onPressed;
  final VoidCallback? onPressedDown;
  final VoidCallback? onPressedUp;

  FpsActionButton({
    required this.label,
    required Vector2 position,
    this.onPressed,
    this.onPressedDown,
    this.onPressedUp,
  }) : super(position: position, size: Vector2(40, 32), anchor: Anchor.topLeft);

  @override
  void onTapDown(TapDownEvent event) {
    onPressed?.call();
    onPressedDown?.call();
  }

  @override
  void onTapUp(TapUpEvent event) {
    onPressedUp?.call();
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    onPressedUp?.call();
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    // Increased transparency from black87 to 50% opacity
    final bgPaint = Paint()..color = Colors.black.withOpacity(0.50);
    final borderPaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.70)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), bgPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), borderPaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: Colors.cyanAccent.withOpacity(0.90), fontSize: 8, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset((size.x - textPainter.width) / 2, (size.y - textPainter.height) / 2),
    );
  }
}