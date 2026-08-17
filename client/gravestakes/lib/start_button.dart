import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/palette.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class StartButton extends RectangleComponent with TapCallbacks, HasGameReference<GraveStakesGame> {
  StartButton() : super(
    size: Vector2(120, 50),
    paint: BasicPalette.green.paint(),
    priority: 200, // Put it above everything
  );

  @override
  Future<void> onLoad() async {
    // Position it safely near the top center or top right
    position = Vector2(game.camera.viewport.size.x - 140, 20);
    
    // Add text label
    add(TextComponent(
      text: 'START GAME', 
      position: Vector2(15, 15),
      textRenderer: TextPaint(style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    ));
  }

  // Fallback in case viewport size was 0 on onLoad
  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    position = Vector2(size.x - 140, 20);
  }

  @override
  void onTapUp(TapUpEvent event) {
    game.startGame(); // Kick off the actual game loop
    removeFromParent(); // Make the button disappear when clicked
  }
}