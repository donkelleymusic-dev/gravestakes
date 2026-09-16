import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart';

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