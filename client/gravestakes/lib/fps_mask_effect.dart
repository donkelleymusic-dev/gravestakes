import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class FpsMaskEffect extends PositionComponent with HasGameReference {
  final String maskId;
  double _timer = 0.4;
  final double _duration = 0.4;
  Sprite? maskSprite;

  FpsMaskEffect({required this.maskId}) : super(anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    super.onLoad();
    position = game.camera.viewport.size / 2;
    size = Vector2(250, 250);

    try {
      maskSprite = await Sprite.load('${maskId}_mask.png');
    } catch (e) {
      // Fallback if asset fails
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _timer -= dt;
    if (_timer <= 0) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (maskSprite == null) return;

    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);

    // Progress from 0.0 (start) to 1.0 (end)
    double progress = 1.0 - (_timer / _duration);

    // Dramatic scale: Starts small, explodes past the camera lens, then fades
    double scale = 0.5 + (progress * 2.5);
    
    // --- THE BANSHEE ASCENSION ---
    if (maskId == 'banshee') {
      // 1. Calculate a perfect parabolic arc that peaks at exactly 50% of the animation
      // sin(progress * pi) creates a smooth curve from 0.0 -> 1.0 -> 0.0
      double arc = sin(progress * pi);
      
      // 2. Shoot the mask 800 pixels into the "sky" (negative Y)
      double skywardTranslation = -800.0 * arc;
      canvas.translate(0, skywardTranslation);
      
      // 3. Keep the mask slightly smaller so it feels high up and distant
      scale = 0.5 + (progress * 1.2); 
    }

    canvas.scale(scale, scale);

    // Slight rotation punch
    canvas.rotate(sin(progress * pi * 2) * 0.1);

    // Opacity fade out towards the end of the animation
    double opacity = (1.0 - progress).clamp(0.0, 1.0);
    
    final paint = Paint()..color = Colors.white.withOpacity(opacity);

    // Draw the mask graphic centered on screen
    maskSprite!.render(
      canvas,
      position: Vector2(-maskSprite!.originalSize.x / 2, -maskSprite!.originalSize.y / 2),
      size: maskSprite!.originalSize,
      overridePaint: paint,
    );

    canvas.restore();
  }
}