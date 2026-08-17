import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/palette.dart';
import 'package:flutter/painting.dart';
import 'player.dart';
import 'darkness_overlay.dart';

class GraveStakesGame extends FlameGame {
  late final JoystickComponent joystick;
  late final Player player;

  @override
  Future onLoad() async {
    // 1. Create a simple translucent joystick
    final knobPaint = BasicPalette.white.withAlpha(200).paint();
    final backgroundPaint = BasicPalette.white.withAlpha(100).paint();

    joystick = JoystickComponent(
      knob: CircleComponent(radius: 20, paint: knobPaint),
      background: CircleComponent(radius: 60, paint: backgroundPaint),
      margin: const EdgeInsets.only(left: 40, bottom: 40),
      priority: 20, // Add this line to keep the UI above the darkness
    );

    // 2. Spawn the player and pass it the joystick reference
    player = Player(joystick)
      ..position = size / 2; // Start in the center of the screen

    // 3. Add components to the game loop
    add(player);
    add(DarknessOverlay(player)); // Add the darkness!
    add(joystick);
  }
}