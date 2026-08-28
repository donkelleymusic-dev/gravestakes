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
    
    // --- 1. SCALE BEAM BY BATTERY LIFE ---
    final double baseCone = player.hasExtendedRange ? 600.0 : 350.0; 
    // Ensure radius doesn't hit absolute zero to avoid rendering exceptions
    final double coneLength = math.max(0.1, baseCone * player.flashlightScale); 
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

    // --- 2. FADE BEAM OPACITY WHEN DYING ---
    final flashlightPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        coneLength,
        [
          Colors.white.withOpacity(0.45 * player.flashlightScale), 
          Colors.white.withOpacity(0.15 * player.flashlightScale), 
          Colors.white.withOpacity(0.0),  
        ],
        [
          0.0, 
          0.4, 
          1.0, 
        ],
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 35.0);

    // --- 3. SHRINK AMBIENT GLOW AROUND FEET ---
    // Drops from 60px down to a terrifying 15px when dead
    final double glowRadius = math.max(15.0, 60.0 * player.flashlightScale);
    final playerGlowPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        glowRadius,
        [
          Colors.white.withOpacity(0.35), 
          Colors.white.withOpacity(0.0),
        ],
      );

    // Only draw the cone if we actually have battery
    if (player.flashlightScale > 0) {
      canvas.drawPath(conePath, flashlightPaint);
    }
    
    // Always draw the tiny foot glow so you don't lose your character entirely
    canvas.drawCircle(center, glowRadius, playerGlowPaint); 

    final darkPaint = Paint()
      ..color = Colors.black.withOpacity(0.96)
      ..blendMode = BlendMode.srcOut;

    canvas.drawRect(rect, darkPaint);
    canvas.restore();
  }
}