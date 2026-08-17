import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class AttackButton extends CircleComponent with TapCallbacks, HasGameReference<GraveStakesGame> {
  AttackButton() : super(
    radius: 40,
    paint: Paint()..color = Colors.red.withOpacity(0.7),
    priority: 200,
  );

  @override
  Future<void> onLoad() async {
    // Position it in the bottom-right corner of the viewport
    position = Vector2(game.camera.viewport.size.x - 100, game.camera.viewport.size.y - 120);
    
    // Add a clear text label inside the button
    add(TextComponent(
      text: 'SCARE',
      position: Vector2(10, 32),
      textRenderer: TextPaint(
        style: TextStyle(
          color: Colors.white, 
          fontSize: 14, 
          fontWeight: FontWeight.bold,
        ),
      ),
    ));
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // Keep it locked to the bottom-right if the screen orientation changes
    position = Vector2(size.x - 100, size.y - 120);
  }

  @override
  void onTapUp(TapUpEvent event) {
    // Trigger the exact same attack method on your player!
    game.player.triggerAttack();
  }
}