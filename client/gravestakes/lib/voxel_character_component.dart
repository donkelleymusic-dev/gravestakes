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
  double stunTimer = 0.0;

  double attackCooldown = 0.0;
  double swapAnimTimer = 0.0;

  double scareAnimTimer = 0.0;

  ui.Image? activeMaskImage;
  double _walkCycleTime = 0.0;

  void triggerSwapAnimation() {
    swapAnimTimer = 0.15;
  }

  // Triggers the 0.5s lunge animation
  void triggerScareAnimation() {
    scareAnimTimer = 0.75;//0.5;
  }

  VoxelCharacterComponent({
    required this.images,
    required this.rigData,
    required Vector2 hitboxSize,
  }) : super(size: hitboxSize, anchor: Anchor.center);

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
    
    // Handle Stun Jiggle
    if (isStunned) {
      canvas.translate(sin(stunTimer * 50) * 4, 0);
    }

    // Move drawing pivot to center of Flame Component
    canvas.translate(size.x / 2, size.y / 2);

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

    final parts = rigData!['parts'];
    final torsoW = parts['torso']['width'];
    final torsoH = parts['torso']['height'];

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

    // Define helper functions AFTER variables are declared
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

      for (int i = currentThickness; i >= 0; i--) {
        canvas.save();
        canvas.translate(i * extrudeDir * 2.5, 0);
        
        Paint layerPaint = Paint();
        if (i > 0) {
          layerPaint.colorFilter = const ColorFilter.mode(Colors.black45, BlendMode.srcATop);
        } else if (isHighlighted) {
          layerPaint.colorFilter = const ColorFilter.mode(Colors.white, BlendMode.srcATop);
        }
        
        canvas.drawImageRect(
          img, 
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), 
          Rect.fromLTWH(-pX, -pY, w, h), 
          layerPaint
        );
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

      // --- SCARE LUNGE ANIMATION ---
      if (scareAnimTimer > 0) {
        // Progress goes from 1.0 down to 0.0
        double progress = scareAnimTimer / 0.5; 
        
        // 1. The Lunge: Move the mask "up/forward" off the face
        double lungeDistance = sin(progress * pi) * 30.0;
        canvas.translate(0, -lungeDistance);
        
        // 2. The Pop: Scale the mask to 2.2x its normal size at the peak
        maskScale += sin(progress * pi) * 1.2;
        
        // 3. The Violent Shake: Rapidly vibrate back and forth 3 times
        canvas.rotate(sin(progress * pi * 10) * 0.35); 
      }
      // ---------------------------------

      canvas.scale(maskScale, maskScale);

      canvas.drawImage(
        activeMaskImage!, 
        Offset(-activeMaskImage!.width / 2, -pY * (1/maskScale)), 
        Paint()
      );
      canvas.restore();
    }

    // --- DYNAMIC LIMB RENDERER ---
    parts.forEach((partName, partData) {
      if (partName == 'torso' || partName == 'head') return; 

      bool isArm = partName.startsWith('arm') || partName.contains('_arm');
      bool isLeg = partName.startsWith('leg') || partName.contains('_leg');
      
      int index = 0;
      try {
        if (partName.contains('_')) {
           index = int.tryParse(partName.split('_').last) ?? 0;
        }
      } catch (_) {}
      
      // Fallback index assignment for legacy bipedal characters
      if (partName == 'left_arm') index = 0;
      if (partName == 'right_arm') index = 1;
      if (partName == 'left_leg') index = 0;
      if (partName == 'right_leg') index = 1;

      // --- THE RIPPLE MATH ---
      // 1. Base alternating phase for left vs right (Even = 0, Odd = 180 degrees)
      double sideOffset = (index % 2 == 0) ? 0.0 : pi;
      
      // 2. Cascade offset based on the limb's row (Front-to-back delay)
      int row = index ~/ 2;
      double rippleDelay = row * (pi / 2.5); // Tweak 2.5 to change the wave's tightness
      
      // 3. Combine for the final staggered phase
      double phaseOffset = sideOffset - rippleDelay;
      double rawSwing = sin(_walkCycleTime + phaseOffset);
      
      double posX = 0.0;
      double posY = rootY;
      double rot = 0.0;
      double scaleMod = 1.0;
      int thickness = isArm ? 4 : 4;

      if (isLeg) {
        int totalLegs = parts.keys.where((k) => k.startsWith('leg') || k.contains('_leg')).length;
        double yOffset = 0.0;
        
        if (totalLegs == 1) {
          // Perfectly center the single leg directly under the body
          posX = 0.0;
          // Tuck the monoleg 30 pixels higher into the torso
          yOffset = -30.0; 
        } else {
          // Spread multiple legs evenly across the bottom of the torso
          double legSpacing = (torsoW / 2) / max(1, totalLegs - 1);
          posX = -(torsoW / 4) + (index * legSpacing);
        }
        
        // Hardcode fallback offsets for legacy bipedal rigs
        if (partName == 'left_leg') posX = -(torsoW / 4);
        if (partName == 'right_leg') posX = (torsoW / 4);

        // Apply the yOffset to the final vertical position calculation
        posY = hipY + yOffset + (rawSwing * 8.0 * frontWeight * depthDir);
        rot = rawSwing * 0.55 * sideWeight;
        scaleMod = 1.0 + (rawSwing * 0.15 * frontWeight * depthDir * (index.isEven ? 1 : -1));
      } else if (isArm) {
        bool isLeftArm = index % 2 == 0;

        // 1. Pin arms strictly to the outer edges of the torso
        posX = isLeftArm ? -(torsoW / 2) + 10 : (torsoW / 2) - 10;

        // Hardcode fallback offsets for legacy bipeds
        if (partName == 'left_arm') posX = -(torsoW / 2) + 5;
        if (partName == 'right_arm') posX = (torsoW / 2) - 5;

        // 2. Cascade extra limbs vertically down the sides of the body
        int row = index ~/ 2;
        double verticalStackOffset = row * 35.0; // Push each extra pair down by 35 pixels

        posY = shoulderY + verticalStackOffset + (-rawSwing * 5.0 * frontWeight * depthDir);
        rot = -rawSwing * 0.40 * sideWeight;
        scaleMod = 1.0 - (rawSwing * 0.10 * frontWeight * depthDir);
      }

      drawExtrudedLimb(partName, posX, posY, rot, thickness, scaleMod);
    });

    // Render Torso and Head statically in the center
    drawExtrudedLimb('torso', 0, rootY, 0, 10, 1.0);
    drawExtrudedLimb('head', 0, shoulderY + 5, 0, 8, 1.0);
    if (showFront) {
      drawMask(0, shoulderY + 5);
    }

    canvas.restore();
    
    // --- THE INVISIBILITY CLOAK ---
    if (isInvisible) {
      final path = Path();
      
      path.moveTo(2, size.y + 6);
      path.quadraticBezierTo(6, -2, size.x / 2 - 7, -10);
      path.quadraticBezierTo(size.x / 2, -16, size.x / 2 + 7, -10);
      path.quadraticBezierTo(size.x - 6, -2, size.x - 2, size.y + 6);
      path.quadraticBezierTo(size.x / 2, size.y + 10, 2, size.y + 6);
      path.close();

      canvas.drawPath(path, Paint()..color = Colors.black.withOpacity(0.80));
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.cyanAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 3.0),
      );
    }
  }
}