import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'game.dart';

enum TutorialStep {
  movement,
  aiming,
  attacking,
  powerUp,
  completed,
}

// CHANGED: Attached to PositionComponent on the Viewport so it locks to the screen window!
class TutorialManager extends PositionComponent with HasGameReference<GraveStakesGame> {
  TutorialStep currentStep = TutorialStep.movement;
  
  double stepTimer = 0;
  bool hasMoved = false;
  bool hasAimed = false;
  bool hasAttacked = false;
  bool hasPickedUpPowerUp = false;

  Vector2? initialPosition;

  TutorialManager() : super(priority: 300); // Ensure it draws above game layers

  @override
  Future<void> onLoad() async {
    super.onLoad();
    initialPosition = game.player.position.clone();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (currentStep == TutorialStep.completed) return;

    final player = game.player;

    switch (currentStep) {
      case TutorialStep.movement:
        if (initialPosition != null && player.position.distanceTo(initialPosition!) > 50) {
          hasMoved = true;
          _advanceStep();
        }
        break;

      case TutorialStep.aiming:
        if (!game.rightJoystick.delta.isZero() || player.angle != 0) {
          hasAimed = true;
          _advanceStep();
        }
        break;

      case TutorialStep.attacking:
        if (player.attackCooldown > 0) {
          hasAttacked = true;
          _advanceStep();
        }
        break;

      case TutorialStep.powerUp:
        if (player.isPoweredUp) {
          hasPickedUpPowerUp = true;
          _advanceStep();
        }
        break;

      case TutorialStep.completed:
        break;
    }
  }

  void _advanceStep() {
    switch (currentStep) {
      case TutorialStep.movement:
        currentStep = TutorialStep.aiming;
        break;
      case TutorialStep.aiming:
        currentStep = TutorialStep.attacking;
        break;
      case TutorialStep.attacking:
        currentStep = TutorialStep.powerUp;
        break;
      case TutorialStep.powerUp:
        currentStep = TutorialStep.completed;
        _concludeTutorial();
        break;
      case TutorialStep.completed:
        break;
    }
  }

  Future<void> _concludeTutorial() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        await Supabase.instance.client
            .from('profiles')
            .update({'completed_tutorial': true})
            .eq('id', user.id);
      } catch (e) {
        debugPrint('Error updating tutorial status: $e');
      }
    }
    removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    if (currentStep == TutorialStep.completed) return;

    String instruction = '';
    switch (currentStep) {
      case TutorialStep.movement:
        instruction = 'STEP 1/4: Use Left Joystick or WASD to Move';
        break;
      case TutorialStep.aiming:
        instruction = 'STEP 2/4: Use Right Joystick to Aim your Flashlight';
        break;
      case TutorialStep.attacking:
        instruction = 'STEP 3/4: Press Spacebar or Attack Button to Shine Light';
        break;
      case TutorialStep.powerUp:
        instruction = 'STEP 4/4: Walk over the glowing Ectoplasm Spark!';
        break;
      case TutorialStep.completed:
        instruction = 'TUTORIAL COMPLETE! Welcome to LUMEN BREACH.';
        break;
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: instruction,
        style: const TextStyle(
          color: Colors.yellowAccent,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1))],
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    
    // --- position near bottom in middle of screen ---
    final screenWidth = game.camera.viewport.size.x;
    final screenHeight = game.camera.viewport.size.y;
    
    final offset = Offset(
      (screenWidth / 2) - (textPainter.width / 2),
      screenHeight - 120.0, // Fixed padding from the BOTTOM of the screen!
    );
    // -------------------------
    
    final bgRect = Rect.fromCenter(
      center: offset + Offset(textPainter.width / 2, textPainter.height / 2),
      width: textPainter.width + 40,
      height: textPainter.height + 20,
    );
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(8)),
      Paint()..color = Colors.black.withAlpha(220),
    );

    textPainter.paint(canvas, offset);
  }
}