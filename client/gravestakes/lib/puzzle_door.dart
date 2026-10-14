import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'dart:math';
import 'game.dart';
import 'audio_manager.dart';

class PuzzleDoor extends PositionComponent with HasGameReference<GraveStakesGame> {
  final int doorId;
  double _clueTimer = 0.0;
  
  // --- NEW: THE ORACLE TINT STATE ---
  Color? oracleTint;

  void applyOracleTint(Color color) {
    oracleTint = color;
  }
  // ----------------------------------
  
  bool get isDummy => !game.puzzleManager.correctSequence.contains(doorId);
  
  bool get isNextInSequence {
    int currentIndex = game.puzzleManager.currentInput.length;
    if (currentIndex >= game.puzzleManager.correctSequence.length) return false;
    return doorId == game.puzzleManager.correctSequence[currentIndex];
  }

  PuzzleDoor({
    required this.doorId,
    required super.position,
  }) : super(size: Vector2(64, 16), anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    
    if (!game.gameStarted || !game.player.isInPuzzleRoom) return;
    
    if (isNextInSequence) {
      _clueTimer += dt;
      if (_clueTimer >= 2.0) { 
        _clueTimer = 0.0;
        
        double distanceToPlayer = game.player.position.distanceTo(position);
        
        if (distanceToPlayer < 300.0) { 
          if (AudioManager.instance.isInitialized && AudioManager.instance.tickSource != null) {
            double spatialVolume = (1.0 - (distanceToPlayer / 300.0)) * 0.6;
            SoLoud.instance.play(AudioManager.instance.tickSource!, volume: spatialVolume);
          }
        }
      }
    }
  }

  void onInteract() {
    game.puzzleManager.handleDoorTap(doorId, position);
  }

  @override
  void render(Canvas canvas) {
    // Draw an identical, heavy wooden door whether it's a dummy or real
    final doorRect = Rect.fromLTWH(0, 0, size.x, size.y);
    canvas.drawRect(doorRect, Paint()..color = Colors.brown[800]!);
    canvas.drawRect(doorRect, Paint()..color = Colors.black87..style = PaintingStyle.stroke..strokeWidth = 2.0);

    // --- NEW: DRAW THE ORACLE GLOW IF ACTIVATED ---
    if (oracleTint != null) {
      final glowPaint = Paint()
        ..color = oracleTint!.withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0);
      
      final borderPaint = Paint()
        ..color = oracleTint!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      canvas.drawRect(doorRect, glowPaint);
      canvas.drawRect(doorRect, borderPaint);
    }
    // ----------------------------------------------
  }
}