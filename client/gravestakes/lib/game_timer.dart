import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class GameTimer extends TextComponent with HasGameReference<GraveStakesGame> {
  double timeLeft = 180.0; // 180 second rounds (3 minutes)
  bool isRunning = false;

  GameTimer() : super(position: Vector2(20, 80), priority: 100);

  double syncTick = 0; // Add this variable at the top of your GameTimer class

  @override
  void update(double dt) {
    if (isRunning) {
      timeLeft -= dt;
      
      // THE HEARTBEAT: The Host continuously syncs everyone else
      if (game.isHost) {
        syncTick += dt;
        if (syncTick >= 2.0) { // Every 2 seconds
          syncTick = 0;
          game.myChannel.sendBroadcastMessage(
            event: 'sync_state',
            payload: {
              'gameStarted': true,
              'timeLeft': timeLeft,
            },
          );
        }
      }
      
      if (timeLeft <= 0) {
        timeLeft = 0;
        isRunning = false;
        
        // ONLY THE HOST CAN OFFICIALLY END THE MATCH
        if (game.isHost) {
          game.myChannel.sendBroadcastMessage(
            event: 'match_control',
            payload: {'action': 'end'},
          );
          game.endGame(); 
        }
      }
    }
    text = isRunning ? 'TIME: ${timeLeft.toInt()}s' : '';
  }

  void start() {
    timeLeft = 60.0;
    isRunning = true;
  }
}