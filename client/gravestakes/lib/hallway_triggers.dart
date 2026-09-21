import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart';
import 'floating_text.dart';
import 'audio_manager.dart';

// --- THE ENTRANCE ---
class Trapdoor extends PositionComponent with HasGameReference<GraveStakesGame> {
  Trapdoor({required super.position}) : super(size: Vector2(64, 64), anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    final player = game.player;
    
    // If player steps on the trapdoor...
    if (!player.isInPuzzleRoom && position.distanceTo(player.position) < 32.0) {
      // 1. Set the puzzle state
      player.isInPuzzleRoom = true;
      
      // 2. Force 3D FPS Mode
      game.isFpsMode = true;
      
      // 3. Teleport to the start of the off-grid hallway (Centered in the 64px tile)
      //player.position = Vector2(10000.0 + 64.0, 10000.0 + 64.0);
      player.position = Vector2((46 * 64.0) + 32.0, (6 * 64.0) + 32.0);
      
      // 4. Force them to look straight down the hallway (South)
      player.facingAngle = pi; 
      
      // 5. Consume the trapdoor so nobody else can fall in
      removeFromParent(); 
    }
  }

  @override
  void render(Canvas canvas) {
    // Blatantly obvious test graphics: A black hole with a glowing red rim
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    canvas.drawRect(rect, Paint()..color = Colors.black);
    canvas.drawRect(rect, Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 10.0));
  }
}

// --- THE EUCLIDEAN LOOP ---
class InfiniteLoopTrigger extends PositionComponent with HasGameReference<GraveStakesGame> {
  final double tileOffsetCount; // How many tiles to shift them back
  
  InfiniteLoopTrigger({
    required super.position, 
    required this.tileOffsetCount,
  }) : super(size: Vector2(128, 64), anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    final player = game.player;
    
    if (player.isInPuzzleRoom && position.distanceTo(player.position) < 40.0) {
      // Seamlessly subtract the exact distance of N tiles from their Y coordinate.
      // Because the procedural walls repeat every 64 pixels, the math is visually invisible!
      player.position.y -= (tileOffsetCount * 64.0);
    }
  }
}

class MinigameEntrance extends PositionComponent with HasGameReference<GraveStakesGame> {
  double _msgCooldown = 0.0;

  MinigameEntrance({required Vector2 position}) 
    : super(position: position, size: Vector2(64, 32), anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    if (_msgCooldown > 0) _msgCooldown -= dt;

    final player = game.player;
    
    // Check if the local player stepped into the doorway
    if (player.position.distanceTo(position) < 30.0 && !player.isInPuzzleRoom) {
      
      if (game.isPuzzleRoomOccupied) {
        // BOUNCE THEM BACK IF OCCUPIED
        player.position.y += 10.0; 
        if (_msgCooldown <= 0) {
          game.camera.viewport.add(FloatingText(
            text: 'SEALED FROM INSIDE...', 
            worldPosition: Vector2(player.position.x - 50, player.position.y - 60)
          ));
          _msgCooldown = 2.0;
        }
      } else {
        // --- SUCK THEM INTO THE PUZZLE ---
        game.isPuzzleRoomOccupied = true;
        game.myChannel.sendBroadcastMessage(event: 'puzzle_lock', payload: {'locked': true});

        player.leftJoystick.delta.setZero();
        player.isInPuzzleRoom = true;
        game.isFpsMode = true;
        
        // Teleport to the start of the secret hallway (Tile X:46, Y:6)
        player.position = Vector2(46 * 64.0 + 32.0, 6 * 64.0 + 32.0);
        player.facingAngle = 0.0; // Face South, looking down the hall
        
        if (AudioManager.instance.isInitialized) {
          AudioManager.instance.stopMusic();
        }
      }
    }
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    
    // Glows Cyan when empty, deep Red when occupied
    final Color glowColor = game.isPuzzleRoomOccupied ? Colors.red[900]! : Colors.cyanAccent;
    
    final paint = Paint()
      ..color = glowColor.withOpacity(0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
      
    final borderPaint = Paint()
      ..color = glowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawRect(rect, paint);
    canvas.drawRect(rect, borderPaint);
    
    // Draw a little keyhole or rune in the center
    canvas.drawCircle(Offset(size.x / 2, size.y / 2), 4, Paint()..color = Colors.white);
  }
}