import 'package:flame/components.dart';
import 'package:flame/palette.dart';
import 'package:flutter/services.dart'; // Required for LogicalKeyboardKey
import 'package:supabase_flutter/supabase_flutter.dart';

// Mix in KeyboardHandler to intercept keystrokes
class Player extends PositionComponent with KeyboardHandler {
  final JoystickComponent joystick;
  final RealtimeChannel channel; 
  final double maxSpeed = 200.0;
  
  double networkTick = 0; 
  final double networkRate = 0.05; 

  // Tracks our current keyboard input vector
  Vector2 keyboardDelta = Vector2.zero();

  Player(this.joystick, this.channel) : super(size: Vector2.all(32.0), anchor: Anchor.center);

  @override
  Future onLoad() async {
    add(
      RectangleComponent(
        size: size,
        paint: BasicPalette.red.paint(),
      ),
    );
  }

  @override
  bool onKeyEvent(KeyEvent event, Set keysPressed) {
    keyboardDelta = Vector2.zero();

    // Map WASD and Arrow Keys to movement
    if (keysPressed.contains(LogicalKeyboardKey.keyW) || keysPressed.contains(LogicalKeyboardKey.arrowUp)) {
      keyboardDelta.y -= 1;
    }
    if (keysPressed.contains(LogicalKeyboardKey.keyS) || keysPressed.contains(LogicalKeyboardKey.arrowDown)) {
      keyboardDelta.y += 1;
    }
    if (keysPressed.contains(LogicalKeyboardKey.keyA) || keysPressed.contains(LogicalKeyboardKey.arrowLeft)) {
      keyboardDelta.x -= 1;
    }
    if (keysPressed.contains(LogicalKeyboardKey.keyD) || keysPressed.contains(LogicalKeyboardKey.arrowRight)) {
      keyboardDelta.x += 1;
    }

    // Normalize the vector so diagonal movement isn't 1.4x faster than moving straight
    if (!keyboardDelta.isZero()) {
      keyboardDelta.normalize();
    }

    // Return true to allow other components to receive the key event if needed
    return true; 
  }

  @override
  void update(double dt) {
    super.update(dt);

    Vector2 movementDelta = Vector2.zero();

    // 1. Check keyboard first (Desktop)
    if (!keyboardDelta.isZero()) {
      movementDelta = keyboardDelta;
    } 
    // 2. Fall back to joystick (Mobile)
    else if (!joystick.delta.isZero()) {
      movementDelta = joystick.relativeDelta;
    }

    // 3. Apply the movement if either input is active
    if (!movementDelta.isZero()) {
      position.add(movementDelta * maxSpeed * dt);
      
      // Update rotation to face the movement direction
      angle = movementDelta.screenAngle();

      // Handle Networking
      networkTick += dt;
      if (networkTick >= networkRate) {
        networkTick = 0;
        channel.sendBroadcastMessage(
          event: 'move',
          payload: {
            'x': position.x,
            'y': position.y,
            'a': angle,
          },
        );
      }
    }
  }
}