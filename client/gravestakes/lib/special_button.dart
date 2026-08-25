import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class SpecialButton extends PositionComponent with HasGameReference<GraveStakesGame>, TapCallbacks {
  SpecialButton() : super(priority: 150);

  late final TextComponent label;

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
    // Keeps it cleanly stacked above the 4-way attack button if the window resizes
    position = Vector2(size.x - 165, size.y - 240);
  }

  @override
  void render(Canvas canvas) {
    final player = game.player;
    final isReady = player.hasInvisibilityCharge;
    final isActive = player.isInvisible;

    final paint = Paint()
      ..color = isActive
          ? Colors.cyanAccent.withValues(alpha: 0.8)
          : isReady
              ? Colors.deepPurpleAccent.withValues(alpha: 0.85)
              : Colors.grey.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = (isReady || isActive) ? Colors.white : Colors.white24
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
    game.player.activateInvisibility();
  }
}