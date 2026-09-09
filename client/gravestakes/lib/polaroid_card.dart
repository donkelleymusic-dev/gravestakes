import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'game.dart';
import 'voxel_character_component.dart';

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
    // 1. Setup Attacker (Left side, leaning forward)
    final attackerRig = GraveStakesGame.characterRigCache[snapshot.attackerCharId];
    final attackerImages = GraveStakesGame.characterImagesCache[snapshot.attackerCharId];

    if (attackerRig != null && attackerImages != null) {
      final attacker = VoxelCharacterComponent(
        images: attackerImages,
        rigData: attackerRig,
        hitboxSize: Vector2(64, 64),
      );
      attacker.position = Vector2(size.x * 0.25, size.y * 0.7);
      attacker.targetAngle = pi / 2; // Face exact right
      
      // Dynamic Action Posing
      attacker.angle = 0.15; // Lean forward about 8 degrees
      attacker.scareAnimTimer = 0.25; // Freeze mask mid-lunge
      
      try {
        attacker.activeMaskImage = await images.load('${snapshot.attackerMaskId}_mask.png');
      } catch (e) {}

      add(attacker);
      
      // Add Speech Bubble
      add(ComicBubble(
        text: 'BOO!', 
        isSpeech: true, 
        position: attacker.position + Vector2(25, -60),
      ));
    }

    // 2. Setup Victim (Right side, fleeing frantically)
    final victimRig = GraveStakesGame.characterRigCache[snapshot.victimCharId];
    final victimImages = GraveStakesGame.characterImagesCache[snapshot.victimCharId];

    if (victimRig != null && victimImages != null) {
      final victim = VoxelCharacterComponent(
        images: victimImages,
        rigData: victimRig,
        hitboxSize: Vector2(64, 64),
      );
      victim.position = Vector2(size.x * 0.75, size.y * 0.7);
      
      // Dynamic Fleeing Posing
      victim.targetAngle = pi / 2; // Face exact right (running AWAY)
      victim.angle = 0.25; // Lean forward heavily into the sprint
      victim.isMoving = true;
      
      // Manually force a few frames of update so the legs split into a run cycle
      victim.update(0.3); 
      
      // Layering: Lines -> Victim -> Sound Bubble
      add(ActionLines(position: victim.position + Vector2(-20, 0)));
      add(victim);
      add(ComicBubble(
        text: '*huff huff*', 
        isSpeech: false, 
        position: victim.position + Vector2(30, 20),
      ));
    }
  }

  @override
  void update(double dt) {
    // OVERRIDE: Do absolutely nothing. Freezes the engine instantly.
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