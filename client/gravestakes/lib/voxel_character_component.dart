// voxel_character_component.dart
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class VoxelCharacterComponent extends PositionComponent {
  final Map<String, ui.Image> images;
  final Map<String, dynamic>? rigData;
  
  double targetAngle = 0.0;
  bool isMoving = false;
  bool isHighlighted = false;
  bool isStunned = false;
  bool isVisible = true;
  bool isInvisible = false;
  bool showStars = false;
  double stunTimer = 0.0;

  String currentMaskId = 'standard';

  double attackCooldown = 0.0;
  double swapAnimTimer = 0.0;
  double scareAnimTimer = 0.0;

  ui.Image? activeMaskImage;
  double _walkCycleTime = 0.0;

  // FIXED: Pre-allocated static Paint objects to eliminate 300+ ColorFilter allocations per frame
  static final Paint _basePaint = Paint();
  static final Paint _extrudeShadowPaint = Paint()
    ..colorFilter = const ColorFilter.mode(Colors.black45, BlendMode.srcATop);
  static final Paint _highlightPaint = Paint()
    ..colorFilter = const ColorFilter.mode(Colors.white, BlendMode.srcATop);
  static final Paint _starPaint = Paint()..color = Colors.yellowAccent;
  static final Paint _cloakFillPaint = Paint()..color = Colors.black.withOpacity(0.80);
  static final Paint _cloakStrokePaint = Paint()
    ..color = Colors.cyanAccent
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0
    ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 3.0);

  int _cachedTotalLegs = 2;

  void triggerSwapAnimation() {
    swapAnimTimer = 0.15;
  }

  void triggerScareAnimation(String maskId) {
    currentMaskId = maskId;
    scareAnimTimer = 0.75;
  }

  VoxelCharacterComponent({
    required this.images,
    required this.rigData,
    required Vector2 hitboxSize,
  }) : super(size: hitboxSize, anchor: Anchor.center) {
    if (rigData != null && rigData!['parts'] is Map) {
      final parts = rigData!['parts'] as Map;
      _cachedTotalLegs = parts.keys
          .where((k) => k.toString().startsWith('leg') || k.toString().contains('_leg'))
          .length;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (swapAnimTimer > 0) swapAnimTimer -= dt;
    if (scareAnimTimer > 0) scareAnimTimer -= dt;
    if (isMoving && !isStunned) {
      _walkCycleTime += dt * 8.0; 
    } else {
      _walkCycleTime = 0.0;
    }
  }

  @override
  void render(Canvas canvas) {
    if (!isVisible || rigData == null || images.isEmpty) return;
    super.render(canvas);

    canvas.save();

    final parts = rigData!['parts'];
    final torsoW = parts['torso']['width'];
    final torsoH = parts['torso']['height'];

    if (isStunned) {
      canvas.translate(sin(stunTimer * 50) * 4, 0);
    }

    canvas.translate(size.x / 2, size.y / 2);

    if (showStars) {
      canvas.save();
      canvas.translate(0, -size.y * 0.8); 
      double time = DateTime.now().millisecondsSinceEpoch / 200.0;
      for (int i = 0; i < 3; i++) {
        double angle = time + (i * (2 * pi / 3));
        double starX = cos(angle) * 14.0;
        double starY = sin(angle) * 4.0;
        canvas.drawCircle(Offset(starX, starY), 3.0, _starPaint);
      }
      canvas.restore();
    }

    double normAngle = targetAngle % (2 * pi);
    if (normAngle < 0) normAngle += 2 * pi;
    double degrees = normAngle * 180 / pi;
    
    double scaleX = 1.0;
    bool showFront = true;
    
    if (degrees > 315 || degrees <= 45) { scaleX = 0.5; showFront = true; }         
    else if (degrees > 45 && degrees <= 135) { scaleX = 1.0; showFront = true; }    
    else if (degrees > 135 && degrees <= 225) { scaleX = -0.5; showFront = true; }  
    else { scaleX = 1.0; showFront = false; }                                       

    if (degrees > 22.5 && degrees <= 67.5) scaleX = 0.75;
    if (degrees > 112.5 && degrees <= 157.5) scaleX = -0.75;
    if (degrees > 202.5 && degrees <= 247.5) { scaleX = -0.75; showFront = false; }
    if (degrees > 292.5 && degrees <= 337.5) { scaleX = 0.75; showFront = false; }

    double globalScale = size.x / (torsoW * 1.5); 
    canvas.scale(globalScale * scaleX, globalScale);
    canvas.translate(0, -torsoH * 0.5);

    double rad = normAngle;
    double frontWeight = sin(rad).abs(); 
    double sideWeight = cos(rad).abs();
    double torsoBob = (cos(_walkCycleTime * 2) - 1.0) * -3.5; 
    double depthDir = showFront ? 1.0 : -1.0; 
    String side = showFront ? "front" : "back";

    double rootY = (torsoH / 2) + torsoBob; 
    double shoulderY = rootY - (torsoH / 2) + 15; 
    double hipY = rootY + (torsoH / 2) - 15;      

    void drawExtrudedLimb(String name, double x, double y, double rot, int thickness, double scaleMod) {
      if (!parts.containsKey(name)) return;
      final partData = parts[name];
      final img = images['${name}_$side.png'];
      if (img == null) return;
      
      double w = partData['width'].toDouble();
      double h = partData['height'].toDouble();
      double pX = partData['pivot_x'].toDouble();
      double pY = partData['pivot_y'].toDouble();

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rot);
      canvas.scale(scaleMod, scaleMod); 
      
      double extrudeDir = (degrees > 90 && degrees < 270) ? 1.0 : -1.0;
      int currentThickness = (scaleX.abs() < 1.0) ? thickness : 0;

      final srcRect = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
      final dstRect = Rect.fromLTWH(-pX, -pY, w, h);

      for (int i = currentThickness; i >= 0; i--) {
        canvas.save();
        canvas.translate(i * extrudeDir * 2.5, 0);
        
        final Paint layerPaint = (i > 0)
            ? _extrudeShadowPaint
            : (isHighlighted ? _highlightPaint : _basePaint);
        
        canvas.drawImageRect(img, srcRect, dstRect, layerPaint);
        canvas.restore();
      }
      canvas.restore();
    }

    void drawMask(double x, double y) {
      if (activeMaskImage == null || !parts.containsKey('head')) return;
      
      final headData = parts['head'];
      double hW = headData['width'].toDouble();
      double pY = headData['pivot_y'].toDouble();

      canvas.save();
      canvas.translate(x, y);
      
      double maskScale = hW / activeMaskImage!.width;

      if (swapAnimTimer > 0) {
        canvas.rotate(sin(swapAnimTimer * 60) * 0.3); 
        maskScale *= 1.2; 
      }

      if (scareAnimTimer > 0) {
        double progress = 1.0 - (scareAnimTimer / 0.75); 
        
        if (currentMaskId == 'banshee') {
           double arc = sin(progress * pi);
           double skywardDistance = -150.0 * arc;
           canvas.translate(0, skywardDistance);
           canvas.rotate(sin(progress * pi * 20) * 0.25);
        } else {
           double lungeDistance = sin(progress * pi) * 30.0;
           canvas.translate(0, -lungeDistance);
           maskScale += sin(progress * pi) * 1.2;
           canvas.rotate(sin(progress * pi * 10) * 0.35); 
        }
      }

      canvas.scale(maskScale, maskScale);

      canvas.drawImage(
        activeMaskImage!, 
        Offset(-activeMaskImage!.width / 2, -pY * (1 / maskScale)), 
        _basePaint,
      );
      canvas.restore();
    }

    parts.forEach((partName, partData) {
      if (partName == 'torso' || partName == 'head') return; 

      bool isArm = partName.startsWith('arm') || partName.contains('_arm');
      bool isLeg = partName.startsWith('leg') || partName.contains('_leg');
      
      int index = 0;
      if (partName.contains('_')) {
        index = int.tryParse(partName.split('_').last) ?? 0;
      }
      
      if (partName == 'left_arm') index = 0;
      if (partName == 'right_arm') index = 1;
      if (partName == 'left_leg') index = 0;
      if (partName == 'right_leg') index = 1;

      double sideOffset = (index % 2 == 0) ? 0.0 : pi;
      int row = index ~/ 2;
      double rippleDelay = row * (pi / 2.5);
      
      double phaseOffset = sideOffset - rippleDelay;
      double rawSwing = sin(_walkCycleTime + phaseOffset);
      
      double posX = 0.0;
      double posY = rootY;
      double rot = 0.0;
      double scaleMod = 1.0;
      int thickness = 4;

      if (isLeg) {
        double yOffset = 0.0;
        if (_cachedTotalLegs == 1) {
          posX = 0.0;
          yOffset = -30.0; 
        } else {
          double legSpacing = (torsoW / 2) / max(1, _cachedTotalLegs - 1);
          posX = -(torsoW / 4) + (index * legSpacing);
        }
        
        if (partName == 'left_leg') posX = -(torsoW / 4);
        if (partName == 'right_leg') posX = (torsoW / 4);

        posY = hipY + yOffset + (rawSwing * 8.0 * frontWeight * depthDir);
        rot = rawSwing * 0.55 * sideWeight;
        scaleMod = 1.0 + (rawSwing * 0.15 * frontWeight * depthDir * (index.isEven ? 1 : -1));
      } else if (isArm) {
        bool isLeftArm = index % 2 == 0;
        posX = isLeftArm ? -(torsoW / 2) + 10 : (torsoW / 2) - 10;

        if (partName == 'left_arm') posX = -(torsoW / 2) + 5;
        if (partName == 'right_arm') posX = (torsoW / 2) - 5;

        double verticalStackOffset = row * 35.0;
        posY = shoulderY + verticalStackOffset + (-rawSwing * 5.0 * frontWeight * depthDir);
        rot = -rawSwing * 0.40 * sideWeight;
        scaleMod = 1.0 - (rawSwing * 0.10 * frontWeight * depthDir);
      }

      drawExtrudedLimb(partName, posX, posY, rot, thickness, scaleMod);
    });

    drawExtrudedLimb('torso', 0, rootY, 0, 10, 1.0);
    drawExtrudedLimb('head', 0, shoulderY + 5, 0, 8, 1.0);
    if (showFront) {
      drawMask(0, shoulderY + 5);
    }

    canvas.restore();
    
    if (isInvisible) {
      final path = Path()
        ..moveTo(2, size.y + 6)
        ..quadraticBezierTo(6, -2, size.x / 2 - 7, -10)
        ..quadraticBezierTo(size.x / 2, -16, size.x / 2 + 7, -10)
        ..quadraticBezierTo(size.x - 6, -2, size.x - 2, size.y + 6)
        ..quadraticBezierTo(size.x / 2, size.y + 10, 2, size.y + 6)
        ..close();

      canvas.drawPath(path, _cloakFillPaint);
      canvas.drawPath(path, _cloakStrokePaint);
    }
  }
}