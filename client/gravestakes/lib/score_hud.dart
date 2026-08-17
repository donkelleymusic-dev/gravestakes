import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class ScoreHud extends TextComponent with HasGameReference<GraveStakesGame> {
  ScoreHud() : super(
    position: Vector2(20, 20),
    anchor: Anchor.topLeft,
    priority: 100, // Even higher priority so it's always on top
  );

  @override
  Future<void> onLoad() async {
    textRenderer = TextPaint(
      style: const TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.bold,
        shadows: [Shadow(color: Colors.red, blurRadius: 4)],
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Safely grab the score from the player
    text = 'SOULS COLLECTED: ${game.player.score}';
  }
}