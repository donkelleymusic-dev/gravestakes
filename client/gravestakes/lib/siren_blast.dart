import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'dart:math';

import 'player.dart';
import 'remote_player.dart';

class SirenBlast extends PositionComponent {
  // --- MATCHES THE 15 SECOND CHARM DURATION ---
  double lifeTimer = 15.0; 
  final double maxLife = 15.0;

  SirenBlast() : super(
    size: Vector2.all(800.0),
    anchor: Anchor.center,
  );

  @override
  Future<void> onLoad() async {
    // Renders cleanly on top of the player's body
    priority = 10; 
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    // Automatically rotate the cone to match whichever player it is attached to
    if (parent is Player) {
      angle = (parent as Player).facingAngle - (pi / 2);
    } else if (parent is RemotePlayer) {
      angle = (parent as RemotePlayer).angle - (pi / 2);
    }

    lifeTimer -= dt;
    if (lifeTimer <= 0) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    
    // Stay at full opacity for 13 seconds, then fade out over the final 2 seconds
    double fade = lifeTimer > 2.0 ? 1.0 : (lifeTimer / 2.0);
    int alpha = (fade * 150).toInt().clamp(0, 255);
    
    final center = Offset(size.x / 2, size.y / 2);
    
    // 1. Solid Glowing Wash
    final washPaint = Paint()
      ..color = Colors.pinkAccent.withAlpha(alpha) 
      ..style = PaintingStyle.fill;
    canvas.drawArc(Rect.fromCircle(center: center, radius: 400.0), -pi / 2, pi, true, washPaint);

    // 2. Bright Core
    final corePaint = Paint()
      ..color = Colors.purpleAccent.withAlpha((alpha * 1.5).toInt().clamp(0, 255))
      ..style = PaintingStyle.fill;
    canvas.drawArc(Rect.fromCircle(center: center, radius: 250.0), -0.2, 0.4, true, corePaint);

    // 3. Sonic Ripples
    final strokePaint = Paint()
      ..color = Colors.white.withAlpha(alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0;

    for (int i = 0; i < 3; i++) {
      // The * 2 means it shoots out 2 ripples per second, continuously over the 15s
      double wavePhase = ((maxLife - lifeTimer) * 2 + (i * 0.33)) % 1.0;
      canvas.drawArc(Rect.fromCircle(center: center, radius: wavePhase * 400.0), -pi / 2, pi, false, strokePaint);
    }
  }
}