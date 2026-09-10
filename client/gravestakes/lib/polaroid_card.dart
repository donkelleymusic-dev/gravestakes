import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'game.dart';
import 'voxel_character_component.dart';
import 'game_map.dart';

class PolaroidCard extends StatelessWidget {
  final ScareSnapshot snapshot;

  const PolaroidCard({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      height: 350,
      decoration: BoxDecoration(
        color: const Color(0xFFEBEBEB), 
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(4, 4))
        ],
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(12),
            height: 250,
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(color: Colors.black87, width: 2),
            ),
            child: ClipRect(
              child: GameWidget(game: PhotoStudioGame(snapshot: snapshot)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              '${snapshot.attackerName} got ${snapshot.victimName}!',
              style: const TextStyle(
                fontFamily: 'Courier', 
                fontSize: 16, 
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          Text(
            '@ ${snapshot.timestamp}s remaining',
            style: const TextStyle(fontFamily: 'Courier', fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class PhotoStudioGame extends FlameGame {
  final ScareSnapshot snapshot;

  PhotoStudioGame({required this.snapshot});

  @override
  Color backgroundColor() => const Color(0xFF1A1A24); 

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // --- NEW: PROCEDURAL LOCATION-BASED DIORAMA ---
    // Use the map coordinates to create a unique, repeatable seed for this exact spot.
    int seed = (snapshot.mapX.toInt() * 73856) ^ (snapshot.mapY.toInt() * 19349);
    final random = Random(seed);

    // Pick 1 of 3 rough architectural shapes based on location
    int architectureType = random.nextInt(3);

    for (int col = -1; col < 6; col++) {
      for (int row = -1; row < 4; row++) {
        bool placeWall = true;

        // Apply architectural artistic license
        if (architectureType == 0 && col > 2) placeWall = false; // Corner/Alley
        if (architectureType == 1 && (row == 0 || row == 3)) placeWall = false; // Narrow corridor
        if (architectureType == 2 && random.nextDouble() > 0.6) placeWall = false; // Broken/Ruined wall
        
        // Always ensure the very bottom has a "floor" block so characters don't float
        if (row == 3) placeWall = true; 

        if (placeWall) {
          final wall = WallComponent(
            position: Vector2(col * 64.0, (row * 64.0) - 32.0),
            tileSize: 64.0,
          );
          wall.priority = 0; // Way in the back
          add(wall);
        }
      }
    }
    
    // Add a semi-transparent black overlay to push the procedural walls into the shadows
    final shadowOverlay = RectangleComponent(
      size: Vector2(400, 400),
      paint: Paint()..color = Colors.black.withOpacity(0.4),
    );
    shadowOverlay.priority = 5; 
    add(shadowOverlay);
    // ----------------------------------------------

    final attackerRig = GraveStakesGame.characterRigCache[snapshot.attackerCharId] 
                     ?? GraveStakesGame.characterRigCache['default'];
    final attackerImages = GraveStakesGame.characterImagesCache[snapshot.attackerCharId] 
                        ?? GraveStakesGame.characterImagesCache['default'];

    final victimRig = GraveStakesGame.characterRigCache[snapshot.victimCharId] 
                   ?? GraveStakesGame.characterRigCache['default'];
    final victimImages = GraveStakesGame.characterImagesCache[snapshot.victimCharId] 
                      ?? GraveStakesGame.characterImagesCache['default'];

    if (attackerRig == null || victimRig == null) return;

    final attacker = VoxelCharacterComponent(images: attackerImages!, rigData: attackerRig, hitboxSize: Vector2(64, 64));
    final victim = VoxelCharacterComponent(images: victimImages!, rigData: victimRig, hitboxSize: Vector2(64, 64));

    // --- ENFORCE STRICT Z-INDEX LAYERING ---
    victim.priority = 10;   // Always in the background
    attacker.priority = 20; // Always in the foreground
    // ---------------------------------------

    try {
      attacker.activeMaskImage = await images.load('${snapshot.attackerMaskId}_mask.png');
    } catch (e) {}

    int sceneLayout = snapshot.timestamp % 4;

    switch (sceneLayout) {
      case 0: // THE CLASSIC CHASE (Standard distance)
        attacker.scale = Vector2.all(1.0);
        attacker.position = Vector2(size.x * 0.25, size.y * 0.7);
        attacker.targetAngle = pi / 2; 
        attacker.angle = 0.15; 
        attacker.scareAnimTimer = 0.25; 

        victim.scale = Vector2.all(1.0);
        victim.position = Vector2(size.x * 0.75, size.y * 0.7);
        victim.targetAngle = pi / 2; 
        victim.angle = 0.25; 
        victim.isMoving = true;
        victim.update(0.3); 

        add(ActionLines(position: victim.position + Vector2(-20, 0))..priority = 5);
        add(ComicBubble(text: '*huff huff*', isSpeech: false, position: victim.position + Vector2(30, 20))..priority = 30);
        add(ComicBubble(text: 'BOO!', isSpeech: true, position: attacker.position + Vector2(25, -60))..priority = 30);
        break;

      case 1: // THE HEAD-ON CLASH (Attacker very close, victim medium distance)
        attacker.scale = Vector2.all(1.6); // Pushed closer to lens
        attacker.position = Vector2(size.x * 0.25, size.y * 0.85); // Lowered so the head dominates
        attacker.targetAngle = pi / 2; 
        attacker.angle = 0.2; 
        attacker.scareAnimTimer = 0.35; 

        victim.scale = Vector2.all(1.1); // Slightly pushed back
        victim.position = Vector2(size.x * 0.75, size.y * 0.7);
        victim.targetAngle = -pi / 2; 
        victim.angle = -0.2; 
        victim.isStunned = true; 
        victim.stunTimer = 999.0;

        add(ActionLines(position: attacker.position + Vector2(-30, -30))..priority = 15);
        add(ComicBubble(text: 'GOTCHA!', isSpeech: true, position: attacker.position + Vector2(-10, -90))..priority = 30);
        add(ComicBubble(text: 'AAAH!', isSpeech: true, position: victim.position + Vector2(20, -70))..priority = 30);
        break;

      case 2: // THE DROP AMBUSH (Attacker massive, dropping past camera)
        victim.scale = Vector2.all(0.9); // Victim is smaller, lower in the frame
        victim.position = Vector2(size.x * 0.35, size.y * 0.8);
        victim.targetAngle = pi / 2; 
        victim.angle = 0.0; 

        attacker.scale = Vector2.all(1.4); // Attacker is huge
        attacker.position = Vector2(size.x * 0.75, size.y * 0.4); // Dropping from high up
        attacker.targetAngle = -pi / 2; 
        attacker.angle = -0.4; 
        attacker.scareAnimTimer = 0.15; 

        var diveLines = ActionLines(position: attacker.position + Vector2(40, -40))..priority = 15;
        diveLines.angle = -pi / 4; 
        add(diveLines);
        
        add(ComicBubble(text: '?', isSpeech: false, position: victim.position + Vector2(10, -50))..priority = 30);
        add(ComicBubble(text: 'HEHEHE', isSpeech: true, position: attacker.position + Vector2(40, 0))..priority = 30);
        break;

      case 3: // THE CLOSE CALL (Attacker lens-smashing huge, victim tiny)
        attacker.scale = Vector2.all(2.2); // Extremely close to the camera!
        attacker.position = Vector2(size.x * 0.1, size.y * 1.0); // Anchored off the bottom left edge
        attacker.targetAngle = pi / 2; 
        attacker.angle = 0.1;
        attacker.scareAnimTimer = 0.25;

        victim.scale = Vector2.all(0.65); // Tiny, running away in the background
        victim.position = Vector2(size.x * 0.8, size.y * 0.6); // Higher up to simulate distance
        victim.targetAngle = pi / 2; 
        victim.angle = 0.3; 
        victim.isMoving = true;
        victim.update(0.4); 

        add(ActionLines(position: victim.position + Vector2(-15, 0))..priority = 5);
        add(ComicBubble(text: '*scuff*', isSpeech: false, position: victim.position + Vector2(20, 20))..priority = 30);
        add(ComicBubble(text: 'BOO!', isSpeech: true, position: attacker.position + Vector2(-10, -110))..priority = 30); // Raised bubble to clear huge head
        break;
    }

    add(attacker);
    add(victim);
  }

  @override
  void update(double dt) {
    super.update(0.0);
  }
}

// ==========================================
// COMIC BOOK OVERLAY COMPONENTS
// ==========================================

class ActionLines extends PositionComponent {
  ActionLines({super.position});

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final paint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Draw cartoonish speed streaks stretching backward
    canvas.drawLine(const Offset(0, -10), const Offset(-50, -10), paint);
    canvas.drawLine(const Offset(10, 10), const Offset(-70, 10), paint);
    canvas.drawLine(const Offset(-5, 30), const Offset(-40, 30), paint);
  }
}

class ComicBubble extends PositionComponent {
  final String text;
  final bool isSpeech;

  ComicBubble({required this.text, required this.isSpeech, super.position});

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final bgPaint = Paint()..color = isSpeech ? Colors.white : Colors.amberAccent;
    final borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Determine sizing based on text length
    double w = (text.length * 9.0).clamp(40.0, 100.0);
    double h = isSpeech ? 35.0 : 20.0;
    
    // Draw the main bubble shape
    final rrect = RRect.fromLTRBR(-w/2, -h/2, w/2, h/2, Radius.circular(isSpeech ? 12 : 4));
    canvas.drawRRect(rrect, bgPaint);
    canvas.drawRRect(rrect, borderPaint);

    // Draw the directional tail for speech bubbles
    if (isSpeech) {
      final path = Path()
        ..moveTo(-w/4, h/2) // Start at bottom left of bubble
        ..lineTo(-w/2, h/2 + 15) // Point down towards character
        ..lineTo(0, h/2) // Connect back to bottom center
        ..close();
      canvas.drawPath(path, bgPaint);
      canvas.drawPath(path, borderPaint);
    }

    // Paint the text inside
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: Colors.black,
        fontSize: isSpeech ? 16 : 11,
        fontWeight: FontWeight.bold,
        fontStyle: isSpeech ? FontStyle.normal : FontStyle.italic,
        letterSpacing: 1.2,
      ),
    );
    
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    
    textPainter.layout();
    textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
  }
}