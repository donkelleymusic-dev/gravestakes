import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class FloatingText extends PositionComponent {
  final String text;
  late TextComponent textComponent;
  
  double lifeTime = 1.5; // How long it stays on screen
  double timeElapsed = 0;

  FloatingText({required this.text, required Vector2 position}) : super(position: position) {
    priority = 150; // High priority so it renders ABOVE the darkness overlay!
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
    
    // Float upwards at 50 pixels per second
    position.y -= 50 * dt; 
    
    // Self-destruct when time is up
    if (timeElapsed >= lifeTime) {
      removeFromParent();
    }
  }
}