import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart'; 

class FloatingText extends PositionComponent with HasGameReference<GraveStakesGame> {
  final String text;
  late TextComponent textComponent;
  
  double lifeTime = 1.5; 
  double timeElapsed = 0;
  Vector2 worldPosition; 

  FloatingText({required this.text, required this.worldPosition}) : super() {
    priority = 150; // Defeats the darkness overlay!
  }

  @override
  Future<void> onLoad() async {
    textComponent = TextComponent(
      text: text,
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.yellowAccent,
          fontSize: 24,
          fontWeight: FontWeight.bold,
          fontFamily: 'Courier',
          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
    );
    add(textComponent);
  }

  @override
  void update(double dt) {
    super.update(dt);
    timeElapsed += dt;
    
    // Float upwards in world space
    worldPosition.y -= 50 * dt; 
    
    // MANUAL CONVERSION: Safely calculate screen coordinates from world coordinates!
    final cameraWorldPos = game.camera.viewfinder.position;
    final screenCenter = game.camera.viewport.size / 2;
    
    position = (worldPosition - cameraWorldPos) + screenCenter;
    
    if (timeElapsed >= lifeTime) {
      removeFromParent();
    }
  }
}