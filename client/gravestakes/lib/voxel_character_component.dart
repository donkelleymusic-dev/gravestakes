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
  double stunTimer = 0.0;

  ui.Image? activeMaskImage;
  
  double _walkCycleTime = 0.0;

  VoxelCharacterComponent({
    required this.images,
    required this.rigData,
    required Vector2 hitboxSize,
  }) : super(size: hitboxSize, anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
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

    // DYNAMIC SCALING: Shrink the huge art down to fit the 32px hitbox exactly!
    double globalScale = size.x / (torsoW * 1.5); 
    canvas.scale(globalScale * scaleX, globalScale);
    //canvas.translate(0, -torsoH * 0.75); // Anchor feet relative to the hitbox center
    // FIX: Shift the entire rig UP so the visual feet align perfectly with the bottom of the 32px physical hitbox!
    canvas.translate(0, -torsoH * 0.5);

    // Animation Math
    double rad = normAngle;
    double frontWeight = sin(rad).abs(); 
    double sideWeight = cos(rad).abs();
    double rawSwing = sin(_walkCycleTime);
    double torsoBob = (cos(_walkCycleTime * 2) - 1.0) * -3.5; 
    double depthDir = showFront ? 1.0 : -1.0; 
    
    double legRot = rawSwing * 0.55 * sideWeight;
    double armRot = -rawSwing * 0.40 * sideWeight;
    double rLegY = rawSwing * 8.0 * frontWeight * depthDir;
    double rLegS = 1.0 + (rawSwing * 0.15 * frontWeight * depthDir); 
    double lLegY = -rawSwing * 8.0 * frontWeight * depthDir;
    double lLegS = 1.0 - (rawSwing * 0.15 * frontWeight * depthDir);
    double rArmY = -rawSwing * 5.0 * frontWeight * depthDir;
    double rArmS = 1.0 - (rawSwing * 0.10 * frontWeight * depthDir);
    double lArmY = rawSwing * 5.0 * frontWeight * depthDir;
    double lArmS = 1.0 + (rawSwing * 0.10 * frontWeight * depthDir);

    String side = showFront ? "front" : "back";
    
    double rootY = (torsoH / 2) + torsoBob; 
    double shoulderY = rootY - (torsoH / 2) + 15; 
    double hipY = rootY + (torsoH / 2) - 15;      
    double armOffset = (torsoW / 2) - 5;          
    double legOffset = (torsoW / 4);

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
          // Add a white flash overlay when hit/highlighted
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
      // Anchor the mask to the exact same neck joint as the head
      canvas.translate(x, y);
      
      // Scale the high-res mask to roughly match the width of the head
      double maskScale = hW / activeMaskImage!.width;
      canvas.scale(maskScale, maskScale);

      // Add a slight attacking wobble if the attack cooldown is active!
      // (We will pass 'attackCooldown' into the component shortly)
      
      canvas.drawImage(
        activeMaskImage!, 
        Offset(-activeMaskImage!.width / 2, -pY * (1/maskScale)), 
        Paint()
      );
      canvas.restore();
    }

    if (showFront) {
      drawExtrudedLimb('right_arm', armOffset, shoulderY + rArmY, -armRot, 4, rArmS);
      drawExtrudedLimb('right_leg', legOffset, hipY + rLegY, -legRot, 4, rLegS);
      drawExtrudedLimb('torso', 0, rootY, 0, 10, 1.0);
      drawExtrudedLimb('head', 0, shoulderY + 5, 0, 8, 1.0); 
      
      // Add the mask call right here, ONLY on the front view!
      drawMask(0, shoulderY + 5);
      
      drawExtrudedLimb('left_leg', -legOffset, hipY + lLegY, legRot, 4, lLegS);
      drawExtrudedLimb('left_arm', -armOffset, shoulderY + lArmY, armRot, 4, lArmS);
    } else {
      drawExtrudedLimb('left_leg', -legOffset, hipY + lLegY, legRot, 4, lLegS);
      drawExtrudedLimb('left_arm', -armOffset, shoulderY + lArmY, armRot, 4, lArmS);
      drawExtrudedLimb('right_leg', legOffset, hipY + rLegY, -legRot, 4, rLegS);
      drawExtrudedLimb('right_arm', armOffset, shoulderY + rArmY, -armRot, 4, rArmS);
      drawExtrudedLimb('torso', 0, rootY, 0, 10, 1.0);
      drawExtrudedLimb('head', 0, shoulderY + 5, 0, 8, 1.0);
    }
    canvas.restore();
  }
}