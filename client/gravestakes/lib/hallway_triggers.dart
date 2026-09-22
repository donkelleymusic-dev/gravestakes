import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
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
    
    if (!player.isInPuzzleRoom && position.distanceTo(player.position) < 32.0) {
      player.isInPuzzleRoom = true;
      game.isFpsMode = true;
      player.position = Vector2((46 * 64.0) + 32.0, (6 * 64.0) + 32.0);
      player.facingAngle = pi; 
      removeFromParent(); 
    }
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    canvas.drawRect(rect, Paint()..color = Colors.black);
    canvas.drawRect(rect, Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 10.0));
  }
}

// --- THE EUCLIDEAN LOOP (DOOR RAILS) ---
class InfiniteLoopTrigger extends PositionComponent with HasGameReference<GraveStakesGame> {
  final double tileOffsetCount; 
  
  InfiniteLoopTrigger({
    required super.position, 
    required this.tileOffsetCount,
  }) : super(size: Vector2(128, 64), anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    final player = game.player;
    
    // The loop ONLY triggers if the hallway is NOT solved yet!
    if (player.isInPuzzleRoom && !game.isHallwaySolved && position.distanceTo(player.position) < 40.0) {
      player.position.y -= (tileOffsetCount * 64.0);
    }
  }
}

// --- THE DOORWAY STATE ---
class MinigameEntrance extends PositionComponent with HasGameReference<GraveStakesGame> {
  double _msgCooldown = 0.0;

  MinigameEntrance({required Vector2 position}) 
    : super(position: position, size: Vector2(64, 32), anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    if (_msgCooldown > 0) _msgCooldown -= dt;

    final player = game.player;
    
    if (player.position.distanceTo(position) < 30.0 && !player.isInPuzzleRoom) {
      if (game.isPuzzleRoomOccupied) {
        player.position.y += 10.0; 
        if (_msgCooldown <= 0) {
          game.camera.viewport.add(FloatingText(
            text: 'SEALED FROM INSIDE...', 
            worldPosition: Vector2(player.position.x - 50, player.position.y - 60)
          ));
          _msgCooldown = 2.0;
        }
      } else {
        game.isPuzzleRoomOccupied = true;
        game.myChannel.sendBroadcastMessage(event: 'puzzle_lock', payload: {'locked': true});

        player.leftJoystick.delta.setZero();
        player.isInPuzzleRoom = true;
        game.isFpsMode = true;
        
        player.position = Vector2(46 * 64.0 + 32.0, 6 * 64.0 + 32.0);
        player.facingAngle = 0.0; 
        
        if (AudioManager.instance.isInitialized) {
          AudioManager.instance.stopMusic();
        }
      }
    }
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
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
    canvas.drawCircle(Offset(size.x / 2, size.y / 2), 4, Paint()..color = Colors.white);
  }
}

// --- THE ESCAPE PORTAL ---
class MinigameExit extends PositionComponent with HasGameReference<GraveStakesGame> {
  bool hasTriggered = false;
  double flickerTimer = 0.0;
  double currentOpacity = 1.0;
  final Random _random = Random();

  MinigameExit({required Vector2 position}) 
    : super(position: position, size: Vector2.all(64.0), anchor: Anchor.center) {
    priority = 90000; 
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (hasTriggered) return;
    if (!game.isHallwaySolved) return;

    // --- NEON FLICKER MATH ---
    flickerTimer -= dt;
    if (flickerTimer <= 0) {
      if (currentOpacity > 0.5) {
         currentOpacity = _random.nextDouble() * 0.3; 
         flickerTimer = 0.05 + (_random.nextDouble() * 0.1);
      } else {
         currentOpacity = 0.8 + (_random.nextDouble() * 0.2); 
         flickerTimer = 0.5 + (_random.nextDouble() * 2.0);
      }
    }

    // --- TELEPORT LOGIC ---
    final player = game.player;
    if (player.position.distanceTo(position) < 32.0) {
      hasTriggered = true;
      
      player.isInPuzzleRoom = false;
      game.isHallwaySolved = false; 
      game.isPuzzleRoomOccupied = false;
      game.myChannel.sendBroadcastMessage(event: 'puzzle_lock', payload: {'locked': false});
      
      final safeNodes = List<Vector2>.from(game.gameMap.playerSpawns)..shuffle();
      Vector2 exitNode = safeNodes.isNotEmpty ? safeNodes.first : Vector2(400, 400);
      player.position = game.gameMap.getSafeSpawnLocation(exitNode, player.size);
      
      if (AudioManager.instance.isInitialized) {
        AudioManager.instance.playRandomInGameTrack();
      }

      game.camera.viewport.add(FloatingText(
        text: 'ESCAPED!', 
        worldPosition: Vector2(player.position.x - 30, player.position.y - 50),
      ));
      
      if (AudioManager.instance.isInitialized && AudioManager.instance.powerupSource != null) {
        SoLoud.instance.play(AudioManager.instance.powerupSource!);
      }
      
      game.myChannel.sendBroadcastMessage(event: 'move', payload: {
        'id': game.mySessionId, 'x': player.position.x, 'y': player.position.y, 
        'a': player.facingAngle, 'm': false, 'sp': player.species
      });
    }
  }

  @override
  void render(Canvas canvas) {
    if (!game.isHallwaySolved) return;

    // 1. THE DARKNESS 
    final darknessPaint = Paint()..color = Colors.black.withOpacity(0.95);
    canvas.drawRect(Rect.fromLTWH(-500, -2500, 1000, 2600), darknessPaint);

    // 2. THE GLOWING FLOOR PAD
    final glowPaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.4 * currentOpacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16.0);
    canvas.drawCircle(Offset(size.x / 2, size.y / 2), 24.0, glowPaint);
    
    final corePaint = Paint()..color = Colors.white.withOpacity(0.8 * currentOpacity);
    canvas.drawCircle(Offset(size.x / 2, size.y / 2), 10.0, corePaint);

    // 3. THE FLICKERING RED "EXIT" SIGN
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'EXIT',
        style: TextStyle(
          color: Colors.redAccent.withOpacity(currentOpacity),
          fontSize: 32,
          fontWeight: FontWeight.bold,
          fontFamily: 'Courier',
          shadows: [
            Shadow(color: Colors.red.withOpacity(currentOpacity), blurRadius: 16),
            Shadow(color: Colors.black, blurRadius: 2, offset: const Offset(1, 1)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset((size.x / 2) - (textPainter.width / 2), -50));
  }
}