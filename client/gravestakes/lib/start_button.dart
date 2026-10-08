import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/palette.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class StartButton extends RectangleComponent with TapCallbacks, HasGameReference<GraveStakesGame> {
  StartButton() : super(
    size: Vector2(240, 70),
    paint: Paint()..color = Colors.greenAccent.withOpacity(0.85),
    anchor: Anchor.center,
    priority: 200, 
  );

  @override
  Future<void> onLoad() async {
    // Lock it to the dead center of the screen
    position = Vector2(game.camera.viewport.size.x / 2, game.camera.viewport.size.y / 2);
    
    add(TextComponent(
      text: 'START GAME', 
      anchor: Anchor.center,
      position: size / 2, 
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.black, 
          fontSize: 26, 
          fontWeight: FontWeight.bold, 
          fontFamily: 'Orbitron', // Standardized font
          shadows: [Shadow(color: Colors.white54, blurRadius: 2)]
        )
      ),
    ));
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    position = Vector2(size.x / 2, size.y / 2);
  }

  @override
  void onTapDown(TapDownEvent event) {
    game.broadcastStartGame(); 
    removeFromParent(); 
  }
}