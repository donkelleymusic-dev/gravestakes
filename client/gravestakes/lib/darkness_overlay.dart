import 'dart:math' as math;
import 'dart:ui' as ui; 
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart';
import 'player.dart';

class DarknessOverlay extends Component with HasGameReference<GraveStakesGame> {
  final Player player;

  DarknessOverlay(this.player) : super(priority: 10);

  @override
  void render(Canvas canvas) {
    final viewSize = game.camera.viewport.size;
    if (viewSize.x == 0) return; 

    final rect = Rect.fromLTWH(-500, -500, viewSize.x + 1000, viewSize.y + 1000);

    canvas.saveLayer(rect, Paint());

    final center = (viewSize / 2).toOffset();
    
    // CHANGED: Base range is now much shorter (350.0). 
    // If you grab the extended range buff, it blooms out to the full 600.0!
    final double coneLength = player.hasExtendedRange ? 600.0 : 350.0; 
    const sweepAngle = math.pi / 2; // 90 degrees

    final canvasAngle = player.angle - (math.pi / 2);
    final startAngle = canvasAngle - (sweepAngle / 2);
    final endAngle = canvasAngle + (sweepAngle / 2);

    final leftEdge = Offset(
      center.dx + math.cos(startAngle) * coneLength,
      center.dy + math.sin(startAngle) * coneLength,
    );
    final rightEdge = Offset(
      center.dx + math.cos(endAngle) * coneLength,
      center.dy + math.sin(endAngle) * coneLength,
    );

    final conePath = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(leftEdge.dx, leftEdge.dy)
      ..lineTo(rightEdge.dx, rightEdge.dy)
      ..close();

    // --- Gloomy Midnight Flashlight Paint ---
    final flashlightPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        coneLength,
        [
          Colors.white.withOpacity(0.45), 
          Colors.white.withOpacity(0.15), 
          Colors.white.withOpacity(0.0),  
        ],
        [
          0.0, 
          0.4, 
          1.0, 
        ],
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 35.0);

    // --- Dimmer Player Glow ---
    final playerGlowPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        60.0,
        [
          Colors.white.withOpacity(0.35), 
          Colors.white.withOpacity(0.0),
        ],
      );

    canvas.drawPath(conePath, flashlightPaint);
    canvas.drawCircle(center, 60.0, playerGlowPaint); 

    final darkPaint = Paint()
      ..color = Colors.black.withOpacity(0.96)
      ..blendMode = BlendMode.srcOut;

    canvas.drawRect(rect, darkPaint);
    canvas.restore();
  }
}