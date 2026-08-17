import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flutter/material.dart' show Colors;
import 'dart:math' as math;
import 'game.dart';
import 'player.dart';

class DarknessOverlay extends Component with HasGameRef {
  final Player player;
  late final Paint darkPaint;
  late final Paint clearPaint;

  // Set priority high (10) so it draws on top of the player and map
  DarknessOverlay(this.player) : super(priority: 10) {
    // 95% opacity black for that pitch-dark crypt feeling
    darkPaint = Paint()..color = Colors.black.withOpacity(0.95);
    
    // BlendMode.clear acts as an eraser to punch holes in the dark layer
    clearPaint = Paint()..blendMode = BlendMode.clear;
  }

  @override
  void render(Canvas canvas) {
    // 1. Define the screen boundary
    final gameSize = gameRef.size;
    final rect = Rect.fromLTWH(0, 0, gameSize.x, gameSize.y);

    // 2. Save layer is required for BlendMode.clear to work correctly
    canvas.saveLayer(rect, Paint());

    // 3. Draw the darkness over the entire screen
    canvas.drawRect(rect, darkPaint);

    // 4. Calculate the flashlight cone
    final center = player.position.toOffset();
    const coneLength = 350.0;
    const sweepAngle = math.pi / 2; // 90-degree flashlight beam

    // Flame's 0 angle points UP. Canvas 0 angle points RIGHT.
    // We subtract pi/2 to align the rendering math with Flame's physics.
    final canvasAngle = player.angle - (math.pi / 2);
    final startAngle = canvasAngle - (sweepAngle / 2);

    final path = Path();
    path.moveTo(center.dx, center.dy);
    
    // Draw the curved arc of the flashlight beam
    path.arcTo(
      Rect.fromCircle(center: center, radius: coneLength),
      startAngle,
      sweepAngle,
      false, // Do not force a new path (keeps it connected to center)
    );
    path.close();

    // 5. Punch out the flashlight cone
    canvas.drawPath(path, clearPaint);

    // 6. Punch out a small ambient circle right around the player 
    // so they aren't completely blind to attacks from behind
    canvas.drawCircle(center, 50, clearPaint);

    // 7. Restore the canvas to composite the shadows back to the screen
    canvas.restore();
  }
}