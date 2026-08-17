import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class GameTimer extends TextComponent with HasGameReference<GraveStakesGame> {
  double timeLeft = 60.0; // 60 second rounds
  bool isRunning = false;

  GameTimer() : super(position: Vector2(20, 50), priority: 100);

  @override
  void update(double dt) {
    if (isRunning) {
      timeLeft -= dt;
      if (timeLeft <= 0) {
        timeLeft = 0;
        isRunning = false;
        game.endGame(); // Call this on the game class
      }
    }
    text = isRunning ? 'TIME: ${timeLeft.toInt()}s' : 'PRESS START';
  }

  void start() {
    timeLeft = 60.0;
    isRunning = true;
  }
}