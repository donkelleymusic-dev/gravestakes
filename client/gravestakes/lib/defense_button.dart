import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class DefenseButton extends PositionComponent with TapCallbacks, HasGameReference<GraveStakesGame> {
  late CircleComponent background;
  late TextComponent label;

  DefenseButton() : super(size: Vector2(70, 70));

  @override
  Future<void> onLoad() async {
    position = Vector2(game.camera.viewport.size.x - 120, game.camera.viewport.size.y - 120);
    
    background = CircleComponent(
      radius: 35,
      paint: Paint()..color = Colors.blueAccent.withOpacity(0.5),
    );
    
    label = TextComponent(
      text: 'DODGE',
      textRenderer: TextPaint(style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
      anchor: Anchor.center,
      position: size / 2,
    );

    add(background);
    add(label);
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (!game.player.isStunned && !game.player.isPhasing) {
      background.paint.color = Colors.cyanAccent.withOpacity(0.8);
      game.player.triggerPhaseDash();
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    background.paint.color = Colors.blueAccent.withOpacity(0.5);
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    background.paint.color = Colors.blueAccent.withOpacity(0.5);
  }
}