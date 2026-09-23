import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'game.dart';

// 1. Add the HasVisibility mixin
class FpsTouchControls extends PositionComponent with HasGameReference<GraveStakesGame>, HasVisibility {
  FpsTouchControls() : super(priority: 200000); 

  @override
  void onGameResize(Vector2 gameSize) {
    super.onGameResize(gameSize);
    position = Vector2(20, gameSize.y - 212);
    size = Vector2(180, 40);
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();

    add(FpsActionButton(
      label: '↰ 90°',
      position: Vector2(0, 0),
      onPressed: () => game.player.facingAngle -= (pi / 2),
    ));

    add(FpsActionButton(
      label: '◄ PEEK',
      position: Vector2(44, 0),
      onPressedDown: () => game.player.glanceOffset = -pi / 4,
      onPressedUp: () => game.player.glanceOffset = 0.0,
    ));

    add(FpsActionButton(
      label: 'PEEK ►',
      position: Vector2(88, 0),
      onPressedDown: () => game.player.glanceOffset = pi / 4,
      onPressedUp: () => game.player.glanceOffset = 0.0,
    ));

    add(FpsActionButton(
      label: '90° ↱',
      position: Vector2(132, 0),
      onPressed: () => game.player.facingAngle += (pi / 2),
    ));
  }

  // 2. Dynamically bind visibility to the camera mode every frame
  @override
  void update(double dt) {
    super.update(dt);
    isVisible = game.isFpsMode; 
  }
}

class FpsActionButton extends PositionComponent with TapCallbacks, DragCallbacks {
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

  // --- TAP EVENTS (Perfectly still holds and Web Clicks) ---
  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    onPressed?.call();
    onPressedDown?.call();
  }

  @override
  void onTapUp(TapUpEvent event) {
    super.onTapUp(event);
    onPressedUp?.call();
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    super.onTapCancel(event);
    onPressedUp?.call();
  }

  // --- DRAG EVENTS (Thumb rolling on touch screens) ---
  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    onPressed?.call();
    onPressedDown?.call();
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    onPressedUp?.call();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    onPressedUp?.call();
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
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