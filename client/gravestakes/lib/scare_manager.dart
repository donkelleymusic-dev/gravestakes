import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart';
import 'critter.dart';
import 'flying_scare_blast.dart';

class ScareManager extends Component with HasGameReference<GraveStakesGame> {
  final List<Critter> critters = [];
  final List<FlyingScareBlast> bats = [];

  // Synchronously injects the effects into the active loop
  void spawnCritter(Critter c) {
    c.game = game; // Manually pass the game reference
    c.onLoad();    // Trigger audio hooks
    critters.add(c);
  }

  void spawnBat(FlyingScareBlast b) {
    b.game = game;
    b.onLoad();
    bats.add(b);
  }

  @override
  void update(double dt) {
    // Manually run their math (backwards so we can safely remove dead ones)
    for (int i = critters.length - 1; i >= 0; i--) {
      critters[i].update(dt);
      if (critters[i].isDead) critters.removeAt(i);
    }
    
    for (int i = bats.length - 1; i >= 0; i--) {
      bats[i].update(dt);
      if (bats[i].isDead) bats.removeAt(i);
    }
  }

  @override
  void render(Canvas canvas) {
    // renderTree guarantees Flame applies all proper X/Y world translations!
    for (var c in critters) { c.renderTree(canvas); }
    for (var b in bats) { b.renderTree(canvas); }
  }
}