import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'dart:math';
import 'game.dart';
import 'audio_manager.dart';

class PuzzleDoor extends PositionComponent with HasGameReference<GraveStakesGame> {
  final int doorId;
  double _clueTimer = 0.0;
  
  // Dummy logic: Doors 1, 3, and 4 are real. Door 2 and 5 are dummies.
  bool get isDummy => doorId == 2 || doorId == 5;
  
  // Hardcoded for testing: The player must tap Door 3, then 1, then 4.
  bool get isNextInSequence => true; // We will tie this to the PuzzleManager later

  PuzzleDoor({
    required this.doorId,
    required super.position,
  }) : super(size: Vector2(64, 16), anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    
    // 1. SILENCE THE LOBBY & MAIN MAP
    // Do not run any door logic if the match hasn't started or the player isn't in the hallway!
    if (!game.gameStarted || !game.player.isInPuzzleRoom) return;
    
    // Only emit clues if this door is the next one they need to find
    if (isNextInSequence) {
      _clueTimer += dt;
      if (_clueTimer >= 2.0) { // Emit a clue every 2 seconds
        _clueTimer = 0.0;
        
        // 2. SPATIAL AUDIO CALCULATION (Distance Attenuation)
        double distanceToPlayer = game.player.position.distanceTo(position);
        
        // Only play the sound if the player is within ~4.5 tiles of this specific door
        if (distanceToPlayer < 300.0) { 
          if (AudioManager.instance.isInitialized && AudioManager.instance.tickSource != null) {
            
            // The closer you get, the louder it ticks (Max volume clamped at 0.6)
            double spatialVolume = (1.0 - (distanceToPlayer / 300.0)) * 0.6;
            
            SoLoud.instance.play(AudioManager.instance.tickSource!, volume: spatialVolume);
          }
        }
      }
    }
  }

  /* void onInteract() {
    if (isDummy) {
      // PLAY THUD SOUND (Rattling dummy)
      if (AudioManager.instance.isInitialized && AudioManager.instance.impactSource != null) {
         SoLoud.instance.play(AudioManager.instance.impactSource!, volume: 0.8);
      }
      // Push player back slightly to simulate a locked door
      game.player.position.y += 10.0; 
    } else {
      // PLAY HEAVY CLUNK SOUND (Real tumbler locking in)
      if (AudioManager.instance.isInitialized && AudioManager.instance.tickSource != null) {
         SoLoud.instance.play(AudioManager.instance.tickSource!, volume: 1.0);
      }
      // TODO: Send input to PuzzleManager
    }
  } */

  void onInteract() {
    // Pass the interaction up to the PuzzleManager
    // It will handle the dummy thud vs the real clunk, and track the sequence!
    game.puzzleManager.handleDoorTap(doorId, position);
  }

  @override
  void render(Canvas canvas) {
    // Draw an identical, heavy wooden door whether it's a dummy or real
    final doorRect = Rect.fromLTWH(0, 0, size.x, size.y);
    canvas.drawRect(doorRect, Paint()..color = Colors.brown[800]!);
    canvas.drawRect(doorRect, Paint()..color = Colors.black87..style = PaintingStyle.stroke..strokeWidth = 2.0);
  }
}