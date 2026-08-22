import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class AttackButton extends CircleComponent with TapCallbacks, HasGameReference<GraveStakesGame> {
  late final TextComponent label;

  AttackButton() : super(
    radius: 40,
    paint: Paint()..color = Colors.red.withValues(alpha: 0.85),
    priority: 200,
  );

  @override
  Future<void> onLoad() async {
    // Position it in the bottom-right corner of the viewport
    position = Vector2(game.camera.viewport.size.x - 100, game.camera.viewport.size.y - 120);
    
    // FIXED: Anchor the text in the absolute center of the circle so it looks professional!
    label = TextComponent(
      text: 'SCARE',
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.white, 
          fontSize: 14, 
          fontWeight: FontWeight.bold,
        ),
      ),
      anchor: Anchor.center,
      position: Vector2(radius, radius), // Center point of a CircleComponent of radius 40
    );
    add(label);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final player = game.player;
    final isOnCooldown = player.attackCooldown > 0;

    // FIXED: Ghost out the button and change color during cooldown
    paint.color = isOnCooldown 
        ? Colors.grey.withValues(alpha: 0.3) 
        : Colors.red.withValues(alpha: 0.85);

    // FIXED: Display countdown timer text when on cooldown, otherwise show 'SCARE'
    if (isOnCooldown) {
      label.text = '${player.attackCooldown.toStringAsFixed(1)}s';
    } else {
      label.text = 'SCARE';
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // Keep it locked to the bottom-right if the screen orientation changes
    position = Vector2(size.x - 100, size.y - 120);
  }

  @override
  void onTapDown(TapDownEvent event) {
    // Prevent tapping while on cooldown
    if (game.player.attackCooldown > 0) return;
    game.player.triggerAttack();
  }
}