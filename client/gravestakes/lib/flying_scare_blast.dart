import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class FlyingScareBlast extends PositionComponent with HasGameReference<GraveStakesGame> {
  final double speed = 350.0; 
  late Vector2 direction;
  double lifeTimer = 1.5; 

  FlyingScareBlast({required Vector2 position, required double angle})
      : super(position: position, size: Vector2(64, 64), anchor: Anchor.center, angle: angle) {
    direction = Vector2(sin(angle), -cos(angle));
  }

  @override
  Future<void> onLoad() async {
    add(CircleComponent(
      radius: 16,
      paint: Paint()..color = Colors.purpleAccent.withOpacity(0.8),
      anchor: Anchor.center,
      position: size / 2,
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    // Ignored walls completely!
    position += direction * speed * dt;
    
    lifeTimer -= dt;
    if (lifeTimer <= 0) {
      removeFromParent();
      return;
    }
  }
}