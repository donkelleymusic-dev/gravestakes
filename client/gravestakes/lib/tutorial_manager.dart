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

class TutorialManager extends Component with HasGameReference<GraveStakesGame> {
  TutorialStep currentStep = TutorialStep.movement;
  
  double stepTimer = 0;
  bool hasMoved = false;
  bool hasAimed = false;
  bool hasAttacked = false;
  bool hasPickedUpPowerUp = false;

  // UI tracking variables
  Vector2? initialPosition;

  @override
  void onMount() {
    super.onMount();
    initialPosition = game.player.position.clone();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (currentStep == TutorialStep.completed) return;

    final player = game.player;

    switch (currentStep) {
      case TutorialStep.movement:
        // Advance if the player moves more than 50 pixels from start
        if (initialPosition != null && player.position.distanceTo(initialPosition!) > 50) {
          hasMoved = true;
          _advanceStep();
        }
        break;

      case TutorialStep.aiming:
        // Advance if the player rotates or uses the right joystick
        if (!game.rightJoystick.delta.isZero() || player.angle != 0) {
          hasAimed = true;
          _advanceStep();
        }
        break;

      case TutorialStep.attacking:
        // Advance if the player attacks (we can check attack cooldown triggering)
        if (player.attackCooldown > 0) {
          hasAttacked = true;
          _advanceStep();
        }
        break;

      case TutorialStep.powerUp:
        // Advance if the player collects a power-up
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
    // 1. Mark tutorial as completed in Supabase
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

    // 2. Clean up tutorial manager and let the game start normally
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
        instruction = 'TUTORIAL COMPLETE! Welcome to Grave Stakes.';
        break;
    }

    // Render an instructional HUD box at the top center of the screen
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
    
    // Position near the top of the viewport camera
    final offset = Offset(
      (game.camera.viewport.size.x / 2) - (textPainter.width / 2),
      40.0,
    );
    
    // Background banner
    final bgRect = Rect.fromCenter(
      center: offset + Offset(textPainter.width / 2, textPainter.height / 2),
      width: textPainter.width + 40,
      height: textPainter.height + 20,
    );
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(8)),
      Paint()..color = Colors.black.withAlpha(200),
    );

    textPainter.paint(canvas, offset);
  }
}