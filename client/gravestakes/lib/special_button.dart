import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class SpecialButton extends PositionComponent with HasGameReference<GraveStakesGame>, TapCallbacks {
  SpecialButton() : super(priority: 150);

  late final TextComponent label;

  // Checks if the player holds an unspent charge or is actively using it
  bool get isActivatable => game.player.hasInvisibilityCharge || game.player.isInvisible;

  @override
  Future<void> onLoad() async {
    size = Vector2(110, 44);
    position = Vector2(game.camera.viewport.size.x - 165, game.camera.viewport.size.y - 240);

    label = TextComponent(
      text: '',
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      anchor: Anchor.center,
      position: size / 2,
    );
    add(label);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // Keeps persistent position above the 4-way attack button
    position = Vector2(size.x - 165, size.y - 240);
  }

  @override
  void renderTree(Canvas canvas) {
    // Completely skips rendering both the container and child label when no action is available
    if (!isActivatable) return;
    super.renderTree(canvas);
  }

  @override
  void render(Canvas canvas) {
    final player = game.player;
    final isActive = player.isInvisible;

    final paint = Paint()
      ..color = isActive
          ? Colors.cyanAccent.withValues(alpha: 0.8)
          : Colors.deepPurpleAccent.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final rrect = RRect.fromRectAndRadius(size.toRect(), const Radius.circular(8));
    canvas.drawRRect(rrect, paint);
    canvas.drawRRect(rrect, borderPaint);

    super.render(canvas);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final player = game.player;

    if (player.isInvisible) {
      label.text = 'INVIS (${player.invisibilityTimer.toStringAsFixed(1)}s)';
    } else if (player.hasInvisibilityCharge) {
      label.text = 'INVISIBILITY';
    } else {
      label.text = '';
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    // Ignores accidental taps when hidden
    if (!isActivatable) return;
    game.player.activateInvisibility();
  }
}