import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'dart:math';
import 'game.dart';

class TrailingEmbers extends PositionComponent with HasGameReference<GraveStakesGame> {
  List<int> feedbackResults = [];
  
  // Renders right in front of the player's face on the HUD
  final Vector2 restingPosition = Vector2(150, 300); 

  TrailingEmbers() : super(priority: 200000); // HUD level priority

  void updateFeedback(List<int> newFeedback) {
    feedbackResults = newFeedback;
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    // 1. Calculate how fast the player is moving
    final player = game.player;
    double speed = player.isMoving ? player.maxSpeed : 0.0;

    Vector2 targetPosition = restingPosition.clone();
    
    // 2. If moving, push the embers down and off-screen (the delay effect)
    if (speed > 0) {
      targetPosition.add(Vector2(60, 120)); 
    }

    // 3. Add a sickly, organic bobbing motion
    final time = game.currentTime();
    targetPosition.y += sin(time * 2) * 15; 
    targetPosition.x += cos(time * 1.5) * 8;

    // 4. Smoothly glide toward the target
    position.lerp(targetPosition, dt * 2.5); 
  }

  @override
  void render(Canvas canvas) {
    if (!game.isFpsMode) return;

    for (int i = 0; i < feedbackResults.length; i++) {
      int status = feedbackResults[i];
      Color coreColor;

      if (status == 2) { // Right Door, Right Position
        coreColor = Colors.white;
      } else if (status == 1) { // Right Door, Wrong Position
        coreColor = Colors.redAccent;
      } else { // Wrong Door
        coreColor = Colors.grey[900]!;
      }

      final paint = Paint()
        ..color = coreColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0); // The "Smudge"

      // Offset each ember so they form a diagonal constellation
      final offset = Offset(i * 35.0, i * 20.0);
      canvas.drawCircle(offset, 12.0, paint);
      
      // Draw a solid core so they pop against the dark hallway
      canvas.drawCircle(offset, 3.0, Paint()..color = Colors.white.withOpacity(0.4));
    }
  }
}