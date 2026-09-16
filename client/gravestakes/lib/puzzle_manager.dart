import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'game.dart';
import 'audio_manager.dart';
import 'trailing_embers.dart';
import 'spooky_box.dart';
import 'floating_text.dart';
import 'hallway_triggers.dart';

class PuzzleManager extends Component with HasGameReference<GraveStakesGame> {
  // Hardcoded for now: Doors 1, 3, and 4 in that exact order.
  final List<int> correctSequence = [1, 3, 4];
  
  List<int> currentInput = [];
  int strikes = 0;
  
  TrailingEmbers? _embers;

  void handleDoorTap(int doorId, Vector2 doorPosition) {
    // 1. DUMMY DOOR (IDs 2 and 5) -> Rattle and ignore
    if (doorId == 2 || doorId == 5) {
      if (AudioManager.instance.isInitialized && AudioManager.instance.impactSource != null) {
        SoLoud.instance.play(AudioManager.instance.impactSource!, volume: 0.6);
      }
      // Micro-recoil backwards
      game.player.position.y -= 15.0; 
      return;
    }

    // 2. REAL DOOR -> Log input and evaluate
    if (AudioManager.instance.isInitialized && AudioManager.instance.tickSource != null) {
      SoLoud.instance.play(AudioManager.instance.tickSource!, volume: 1.0);
    }
    
    currentInput.add(doorId);

    // Wait until they have confidently tapped 3 real doors before judging them
    if (currentInput.length == correctSequence.length) {
      _evaluateSequence(doorPosition);
    }
  }

  void _evaluateSequence(Vector2 lastDoorPosition) {
    List<int> feedback = [];
    bool isPerfect = true;

    // A. Mastermind Logic Calculation
    for (int i = 0; i < correctSequence.length; i++) {
      if (currentInput[i] == correctSequence[i]) {
        feedback.add(2); // White Ember
      } else if (correctSequence.contains(currentInput[i])) {
        feedback.add(1); // Red Ember
        isPerfect = false;
      } else {
        feedback.add(0); // Black Ember
        isPerfect = false;
      }
    }

    // Sort the feedback so the order of the embers doesn't reveal WHICH door was right
    feedback.sort((a, b) => b.compareTo(a));

    if (isPerfect) {
      _triggerVictory(lastDoorPosition);
    } else {
      _triggerStrike(feedback);
    }
  }

  void _triggerStrike(List<int> feedback) {
    strikes++;
    currentInput.clear();

    // Spawn or update the UI embers
    if (_embers == null) {
      _embers = TrailingEmbers();
      game.camera.viewport.add(_embers!);
    }
    _embers!.updateFeedback(feedback);

    if (strikes >= 3) {
      _ejectPlayer();
    } else {
      // Play a harsh error sound (reusing impact for now, but a synth drone is better)
      if (AudioManager.instance.isInitialized && AudioManager.instance.impactSource != null) {
        SoLoud.instance.play(AudioManager.instance.impactSource!, volume: 1.0);
      }
      // Apply a camera shake by forcing the player to stagger
      game.player.facingAngle += 0.2;
    }
  }

  void _triggerVictory(Vector2 lastDoorPosition) {
    // 1. Clean up UI and input
    _embers?.removeFromParent();
    _embers = null;
    currentInput.clear();

    // 2. Break the Euclidean Loop so they can actually reach the chest
    game.world.children.whereType<InfiniteLoopTrigger>().forEach((trigger) {
      trigger.removeFromParent();
    });

    // 3. Spawn the Abyssal Flesh Casket dead ahead
    // We will use SpookyBox for now, but give it a unique ID so we can reskin it later
    final chestPos = Vector2(lastDoorPosition.x + 32, lastDoorPosition.y + 300);
    game.world.add(SpookyBox(id: 'flesh_casket_${DateTime.now().millisecondsSinceEpoch}', position: chestPos));

    game.camera.viewport.add(FloatingText(
      text: 'THE LOOP IS BROKEN', 
      worldPosition: Vector2(game.player.position.x - 40, game.player.position.y - 60),
    ));
  }

  void _ejectPlayer() {
    final player = game.player;
    
    // 1. Clean up
    _embers?.removeFromParent();
    _embers = null;
    currentInput.clear();
    strikes = 0;

    // 2. Punish (The Phantom Debuff)
    player.applyDissonance(5.0);

    // 3. Snap out of FPS
    player.isInPuzzleRoom = false;
    game.isFpsMode = false;

    // 4. Crash land back at main spawn (fallback to 150,150)
    player.position = Vector2(150, 150);

    if (AudioManager.instance.isInitialized && AudioManager.instance.impactSource != null) {
      SoLoud.instance.play(AudioManager.instance.impactSource!, volume: 1.5);
    }
  }
}