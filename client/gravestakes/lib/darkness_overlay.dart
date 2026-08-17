import 'dart:math' as math;
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
    
    // Increased length so the beam reaches the edges of the screen
    const coneLength = 600.0; 
    const sweepAngle = math.pi / 2; // 90 degrees

    final canvasAngle = player.angle - (math.pi / 2);
    final startAngle = canvasAngle - (sweepAngle / 2);
    final endAngle = canvasAngle + (sweepAngle / 2);

    // Calculate the two far corners of the flashlight beam
    final leftEdge = Offset(
      center.dx + math.cos(startAngle) * coneLength,
      center.dy + math.sin(startAngle) * coneLength,
    );
    final rightEdge = Offset(
      center.dx + math.cos(endAngle) * coneLength,
      center.dy + math.sin(endAngle) * coneLength,
    );

    // Build a straight-edged polygon (triangle). 
    // No curves = no crashed graphics rendering.
    final conePath = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(leftEdge.dx, leftEdge.dy)
      ..lineTo(rightEdge.dx, rightEdge.dy)
      ..close();

    // Draw the solid white shapes
    final whitePaint = Paint()..color = Colors.white;
    canvas.drawPath(conePath, whitePaint);
    canvas.drawCircle(center, 45.0, whitePaint); 

    // Flood the screen with darkness everywhere except the white shapes
    final darkPaint = Paint()
      ..color = Colors.black.withOpacity(0.96)
      ..blendMode = BlendMode.srcOut;

    canvas.drawRect(rect, darkPaint);
    canvas.restore();
  }
}