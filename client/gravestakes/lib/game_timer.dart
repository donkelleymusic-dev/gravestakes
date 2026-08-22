import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class GameTimer extends TextComponent with HasGameReference<GraveStakesGame> {
  double timeLeft = 180.0; // 180 second rounds (3 minutes)
  bool isRunning = false;
  double syncTick = 0;

  // 1. Swap hardcoded position for the topCenter anchor
  GameTimer() : super(
    anchor: Anchor.topCenter, 
    priority: 100,
  );

  // 2. Add the dynamic resize method to keep it dead-center!
  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // Dynamically track the exact center of the screen width
    position = Vector2(size.x / 2, 40); 
    anchor = Anchor.topCenter;
  }

  @override
  void update(double dt) {
    super.update(dt); // Good practice to include super.update
    
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
    timeLeft = 180.0;
    isRunning = true;
  }
}