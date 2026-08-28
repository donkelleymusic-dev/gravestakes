import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'game.dart';

class GameTimer extends TextComponent with HasGameReference<GraveStakesGame> {
  double timeLeft = 180.0; 
  bool isRunning = false;
  double syncTick = 0;

  GameTimer() : super(
    anchor: Anchor.topCenter, 
    priority: 100,
  );

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    position = Vector2(size.x / 2, 40); 
    anchor = Anchor.topCenter;
  }

  @override
  void update(double dt) {
    super.update(dt); 
    
    if (isRunning) {
      timeLeft -= dt;
      
      if (game.isHost) {
        syncTick += dt;
        if (syncTick >= 2.0) { 
          syncTick = 0;
          game.myChannel.sendBroadcastMessage(
            event: 'sync_state',
            payload: {'gameStarted': true, 'timeLeft': timeLeft},
          );
        }
      }
      
      if (timeLeft <= 0) {
        timeLeft = 0;
        isRunning = false;
        
        // --- FINAL MATCH SOUND ---
        if (game.isAudioReady && game.scareSource != null) {
          SoLoud.instance.play(game.scareSource!, volume: 2.0); // Loud end bell!
        }
        
        if (game.isHost) {
          game.myChannel.sendBroadcastMessage(event: 'match_control', payload: {'action': 'end'});
          game.endGame(); 
        }
      }
    }

    // --- FORMAT MM:SS AND TURN RED AT 15 SECONDS ---
    if (isRunning) {
      int minutes = timeLeft ~/ 60;
      int seconds = (timeLeft % 60).toInt();
      text = '$minutes:${seconds.toString().padLeft(2, '0')}';

      textRenderer = TextPaint(
        style: TextStyle(
          color: timeLeft <= 15.0 ? Colors.redAccent : Colors.white,
          fontSize: 32,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: timeLeft <= 15.0 ? Colors.black : Colors.red, blurRadius: 4)],
        ),
      );
    } else {
      text = '';
    }
  }

  void start() {
    timeLeft = 180.0;
    isRunning = true;
  }
}