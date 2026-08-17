import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart';

// FIXED: Upgraded to HasGameReference
class JumpScareEffect extends Component with HasGameReference<GraveStakesGame> {
  bool isActive = false;
  double timer = 0;
  final double scareDuration = 2.0;

  JumpScareEffect() : super(priority: 100); 

  @override
  void render(Canvas canvas) {
    if (!isActive) return;

    final opacity = (timer / scareDuration).clamp(0.0, 1.0);
    final paint = Paint()
      ..color = Colors.redAccent.withOpacity(opacity)
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      // FIXED: Changed gameRef.size to game.size
      Rect.fromLTWH(0, 0, game.size.x, game.size.y),
      paint,
    );
  }

  @override
  void update(double dt) {
    if (!isActive) return;
    
    timer -= dt;
    if (timer <= 0) {
      isActive = false;
    }
  }

  void trigger() {
    isActive = true;
    timer = scareDuration;
  }
}