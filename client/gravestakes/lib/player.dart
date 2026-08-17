import 'package:flame/components.dart';
import 'package:flame/palette.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flame_audio/flame_audio.dart';
import 'game.dart'; // Needed to access the map reference

class Player extends PositionComponent with KeyboardHandler, HasGameReference<GraveStakesGame> {
  final JoystickComponent joystick;
  final RealtimeChannel channel; 
  final double maxSpeed = 200.0;
  int score = 0;
  
  double networkTick = 0; 
  final double networkRate = 0.05;

  Vector2 keyboardDelta = Vector2.zero();

  bool isStunned = false;
  double stunTimer = 0;
  double attackCooldown = 0;

  Player(this.joystick, this.channel) : super(size: Vector2.all(32.0), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    add(RectangleComponent(size: size, paint: BasicPalette.red.paint()));
  }

  void triggerAttack() {
    if (attackCooldown > 0 || isStunned) return;
    
    attackCooldown = 3.0; 
    score += 100; 

    FlameAudio.play('ElevenLabs_Scary_stinger.mp3');

    // 1. Send network packet so other players see it
    channel.sendBroadcastMessage(
      event: 'scare',
      payload: {'x': position.x, 'y': position.y},
    );

    // 2. Trigger the local stun check for bots/players near you
    game.triggerLocalScare(position);

    // 3. Visual feedback (flash player yellow)
    children.whereType<RectangleComponent>().first.paint = BasicPalette.yellow.paint();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (isMounted) {
        children.whereType<RectangleComponent>().first.paint = BasicPalette.red.paint();
      }
    });
  }

  void applyStun(double duration) {
    isStunned = true;
    stunTimer = duration;
  }

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    keyboardDelta = Vector2.zero();

    if (keysPressed.contains(LogicalKeyboardKey.keyW) || keysPressed.contains(LogicalKeyboardKey.arrowUp)) keyboardDelta.y -= 1;
    if (keysPressed.contains(LogicalKeyboardKey.keyS) || keysPressed.contains(LogicalKeyboardKey.arrowDown)) keyboardDelta.y += 1;
    if (keysPressed.contains(LogicalKeyboardKey.keyA) || keysPressed.contains(LogicalKeyboardKey.arrowLeft)) keyboardDelta.x -= 1;
    if (keysPressed.contains(LogicalKeyboardKey.keyD) || keysPressed.contains(LogicalKeyboardKey.arrowRight)) keyboardDelta.x += 1;

    if (!keyboardDelta.isZero()) keyboardDelta.normalize();

    // The Attack Trigger (Spacebar)
    if (keysPressed.contains(LogicalKeyboardKey.space)) {
      triggerAttack();
    }

    return true; 
  }

  @override
  void update(double dt) {
    if (!game.gameStarted) return; // Do nothing if game hasn't started!
    super.update(dt);

    if (attackCooldown > 0) attackCooldown -= dt;
    if (isStunned) {
      stunTimer -= dt;
      if (stunTimer <= 0) isStunned = false;
      return; 
    }

    Vector2 movementDelta = Vector2.zero();

    if (!keyboardDelta.isZero()) {
      movementDelta = keyboardDelta;
    } else if (!joystick.delta.isZero()) {
      movementDelta = joystick.relativeDelta;
    }

    if (!movementDelta.isZero()) {
      angle = movementDelta.screenAngle();

      // Calculate future position for collision testing
      final potentialPosition = position + (movementDelta * maxSpeed * dt);

      // Check if moving horizontally causes a collision
      final testX = Vector2(potentialPosition.x, position.y);
      if (!game.gameMap.checkCollision(testX, size)) {
        position.x = potentialPosition.x;
      }

      // Check if moving vertically causes a collision
      final testY = Vector2(position.x, potentialPosition.y);
      if (!game.gameMap.checkCollision(testY, size)) {
        position.y = potentialPosition.y;
      }

      // Network throttling
      networkTick += dt;
      if (networkTick >= networkRate) {
        networkTick = 0;
        channel.sendBroadcastMessage(
          event: 'move',
          payload: {'x': position.x, 'y': position.y, 'a': angle},
        );
      }
    }
  }
}