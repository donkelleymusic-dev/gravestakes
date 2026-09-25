import 'dart:math' as math;
import 'dart:ui' as ui; 
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart';
import 'player.dart';

class DarknessOverlay extends Component with HasGameReference<GraveStakesGame> {
  final Player player;

  DarknessOverlay(this.player) : super(priority: 10);

  void _drawFlashlight(Canvas canvas, Offset screenCenter, double angle, double fScale, {bool isLocal = false}) {
    if (fScale <= 0 && !isLocal) return;

    final double baseCone = (isLocal && player.hasExtendedRange) ? 600.0 : 350.0; 
    final double coneLength = math.max(0.1, baseCone * fScale); 
    const sweepAngle = math.pi / 2; 

    final canvasAngle = angle - (math.pi / 2);
    final startAngle = canvasAngle - (sweepAngle / 2);
    final endAngle = canvasAngle + (sweepAngle / 2);

    final leftEdge = Offset(
      screenCenter.dx + math.cos(startAngle) * coneLength,
      screenCenter.dy + math.sin(startAngle) * coneLength,
    );
    final rightEdge = Offset(
      screenCenter.dx + math.cos(endAngle) * coneLength,
      screenCenter.dy + math.sin(endAngle) * coneLength,
    );

    final conePath = Path()
      ..moveTo(screenCenter.dx, screenCenter.dy)
      ..lineTo(leftEdge.dx, leftEdge.dy)
      ..lineTo(rightEdge.dx, rightEdge.dy)
      ..close();

    final flashlightPaint = Paint()
      ..shader = ui.Gradient.radial(
        screenCenter,
        coneLength,
        [
          Colors.white.withOpacity(0.45 * fScale), 
          Colors.white.withOpacity(0.15 * fScale), 
          Colors.white.withOpacity(0.0),  
        ],
        [0.0, 0.4, 1.0],
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 35.0);

    final double glowRadius = math.max(15.0, 60.0 * fScale);
    final playerGlowPaint = Paint()
      ..shader = ui.Gradient.radial(
        screenCenter,
        glowRadius,
        [
          Colors.white.withOpacity(0.35), 
          Colors.white.withOpacity(0.0),
        ],
      );

    if (fScale > 0) {
      canvas.drawPath(conePath, flashlightPaint);
    }
    canvas.drawCircle(screenCenter, glowRadius, playerGlowPaint); 
  }

  @override
  void render(Canvas canvas) {
    final viewSize = game.camera.viewport.size;
    if (viewSize.x == 0) return; 

    final rect = Rect.fromLTWH(-500, -500, viewSize.x + 1000, viewSize.y + 1000);
    canvas.saveLayer(rect, Paint());

    final center = (viewSize / 2).toOffset();
    
    // CHANGED: Using facingAngle instead of angle
    _drawFlashlight(canvas, center, player.facingAngle, player.flashlightScale, isLocal: true);

    for (var remote in game.networkPlayers.values) {
      if (remote.isInvisible || remote.isDisguised) continue;

      final remoteScreenPos = Offset(
        center.dx + (remote.position.x - player.position.x),
        center.dy + (remote.position.y - player.position.y),
      );
      
      if (remoteScreenPos.dx > -600 && remoteScreenPos.dx < viewSize.x + 600 &&
          remoteScreenPos.dy > -600 && remoteScreenPos.dy < viewSize.y + 600) {
        
        // CHANGED: Using facingAngle instead of angle
        _drawFlashlight(canvas, remoteScreenPos, remote.facingAngle, remote.flashlightScale, isLocal: false);
      }
    }

    final darkPaint = Paint()
      ..color = Colors.black.withOpacity(0.96)
      ..blendMode = BlendMode.srcOut;

    canvas.drawRect(rect, darkPaint);
    canvas.restore();
  }
}