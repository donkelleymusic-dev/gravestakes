import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'dart:math';
import 'game.dart';

// ADDED: with HasGameReference<GraveStakesGame> so it can check game.isFpsMode
class ScareBlast extends PositionComponent with HasGameReference<GraveStakesGame> {
  double lifeTimer = 0.25;
  final double maxLife = 0.25;

  ScareBlast({required Vector2 position, required double angle}) 
      : super(position: position, angle: angle, anchor: Anchor.center);

  @override
  void render(Canvas canvas) {
    int alpha = ((lifeTimer / maxLife) * 150).toInt().clamp(0, 255);
    
    final paint = Paint()
      ..color = Colors.white.withAlpha(alpha)
      ..style = PaintingStyle.fill;
    
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: 250),
      -1.2, 
      2.4,  
      true, 
      paint,
    );
  }

  @override
  void update(double dt) {
    // NEW: 3D FPS Priority Override
    if (game.isFpsMode) {
      priority = 999999;
    } else {
      priority = ((position.y + size.y) * 10).toInt();
    }

    super.update(dt);
    lifeTimer -= dt;
    if (lifeTimer <= 0) {
      removeFromParent(); 
    }
  }
}

class BansheeBeam extends PositionComponent with HasGameReference<GraveStakesGame> {
  final double angle;
  double _lifeTimer = 0.6; 

  BansheeBeam({required Vector2 position, required this.angle})
      : super(position: position, size: Vector2.all(32), anchor: Anchor.center);

  @override
  void update(double dt) {
    // NEW: 3D FPS Priority Override
    if (game.isFpsMode) {
      priority = 999999;
    } else {
      priority = ((position.y + 16) * 10).toInt();
    }

    super.update(dt);
    _lifeTimer -= dt;
    if (_lifeTimer <= 0) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    double progress = (_lifeTimer / 0.6).clamp(0.0, 1.0);
    
    final corePaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(progress)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0 * progress
      ..strokeCap = StrokeCap.round;

    final outerPaint = Paint()
      ..color = Colors.blue.withOpacity(progress * 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24.0 * progress
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0)
      ..strokeCap = StrokeCap.round;

    final start = Offset(size.x / 2, size.y / 2);
    final end = start + Offset(sin(angle) * 1500, -cos(angle) * 1500);

    canvas.drawLine(start, end, outerPaint);
    canvas.drawLine(start, end, corePaint);
  }
}

class FpsBansheeBeam extends PositionComponent with HasGameReference<GraveStakesGame> {
  double _lifeTimer = 0.6;
  FpsBansheeBeam() : super(priority: 200000);

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size; // Lock to screen size
  }

  @override
  void update(double dt) {
    super.update(dt);
    _lifeTimer -= dt;
    if (_lifeTimer <= 0) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    double progress = (_lifeTimer / 0.6).clamp(0.0, 1.0);
    
    final corePaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(progress)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 30.0 * progress
      ..strokeCap = StrokeCap.round;

    final outerPaint = Paint()
      ..color = Colors.blue.withOpacity(progress * 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 80.0 * progress
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20.0)
      ..strokeCap = StrokeCap.round;

    // Shoots a massive laser vertically up the center of the FPS camera
    final start = Offset(size.x / 2, size.y); 
    final end = Offset(size.x / 2, size.y / 2 - 100); 

    canvas.drawLine(start, end, outerPaint);
    canvas.drawLine(start, end, corePaint);
  }
}

class FpsScareBlast extends PositionComponent with HasGameReference<GraveStakesGame> {
  double _lifeTimer = 0.25;
  FpsScareBlast() : super(priority: 200000);

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _lifeTimer -= dt;
    if (_lifeTimer <= 0) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    double progress = 1.0 - (_lifeTimer / 0.25).clamp(0.0, 1.0); 
    int alpha = ((1.0 - progress) * 150).toInt().clamp(0, 255);
    
    final paint = Paint()
      ..color = Colors.white.withAlpha(alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 40.0 * (1.0 - progress);
    
    // Expands a shockwave outward from the center of the screen
    canvas.drawCircle(Offset(size.x / 2, size.y / 2), progress * (size.x * 0.8), paint);
  }
}