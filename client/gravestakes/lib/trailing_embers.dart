import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'dart:math';
import 'game.dart';

class TrailingEmbers extends PositionComponent with HasGameReference<GraveStakesGame> {
  List<int> feedbackResults = [];
  final Vector2 restingPosition = Vector2(150, 300); 
  double _popScale = 0.0; // NEW: Animation scale

  TrailingEmbers() : super(priority: 200000);

  // NEW: Clear old embers
  void clearFeedback() {
    feedbackResults.clear();
    _popScale = 0.0;
  }

  void updateFeedback(List<int> newFeedback) {
    feedbackResults = newFeedback;
    _popScale = 0.0; // Reset scale to trigger pop-in animation
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    // Animate the scale so they "pop" onto the screen
    if (_popScale < 1.0) {
      _popScale += dt * 4.0;
      if (_popScale > 1.0) _popScale = 1.0;
    }

    final player = game.player;
    double speed = player.isMoving ? player.maxSpeed : 0.0;
    Vector2 targetPosition = restingPosition.clone();
    
    if (speed > 0) targetPosition.add(Vector2(60, 120)); 

    final time = game.currentTime();
    targetPosition.y += sin(time * 2) * 15; 
    targetPosition.x += cos(time * 1.5) * 8;

    position.lerp(targetPosition, dt * 2.5); 
  }

  @override
  void render(Canvas canvas) {
    if (!game.isFpsMode || feedbackResults.isEmpty) return;

    canvas.save();
    
    // 1. Move to the origin point of the embers
    canvas.translate(150.0, 300.0);
    // 2. Apply the scale
    canvas.scale(_popScale, _popScale);
    // 3. Move back so the drawing coordinates remain correct
    canvas.translate(-150.0, -300.0);

    for (int i = 0; i < feedbackResults.length; i++) {
      int status = feedbackResults[i];
      Color coreColor = status == 2 ? Colors.white : (status == 1 ? Colors.redAccent : Colors.grey[900]!);

      final paint = Paint()
        ..color = coreColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);

      final offset = Offset(i * 35.0, i * 20.0);
      canvas.drawCircle(offset, 12.0, paint);
      canvas.drawCircle(offset, 3.0, Paint()..color = Colors.white.withOpacity(0.4));
    }
    
    canvas.restore();
  }
}