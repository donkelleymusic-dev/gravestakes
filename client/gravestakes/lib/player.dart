import 'package:flame/components.dart';
import 'package:flame/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flame_audio/flame_audio.dart';
import 'dart:math';
import 'game.dart';
import 'floating_text.dart';

class Player extends PositionComponent with KeyboardHandler, HasGameReference<GraveStakesGame> {
  final JoystickComponent leftJoystick;
  final JoystickComponent rightJoystick; // NEW: Dedicated aiming stick
  final RealtimeChannel channel; 
  final bool isGunner; // NEW: Role flag

  final double maxSpeed = 200.0;
  int score = 0;
  
  double networkTick = 0; 
  final double networkRate = 0.05;

  Vector2 keyboardDelta = Vector2.zero();

  bool isStunned = false;
  double stunTimer = 0;
  double attackCooldown = 0;
  
  String equippedColorString = 'red'; 

  Player(this.leftJoystick, this.rightJoystick, this.channel, {this.isGunner = false}) 
    : super(size: Vector2.all(32.0), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    await _fetchEquippedCosmetics();
  }

  Future<void> _fetchEquippedCosmetics() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      add(RectangleComponent(size: size, paint: BasicPalette.red.paint()));
      return;
    }

    try {
      final res = await Supabase.instance.client
          .from('user_loadouts')
          .select('item_value')
          .eq('user_id', user.id)
          .eq('slot_type', 'flashlight_color')
          .maybeSingle();

      Color chosenColor = BasicPalette.red.color; 

      if (res != null) {
        final val = res['item_value'] as String;
        equippedColorString = val; 
        switch (val) {
          case 'green': chosenColor = Colors.greenAccent; break;
          case 'purple': chosenColor = Colors.purpleAccent; break;
          case 'red': chosenColor = Colors.redAccent; break;
          case 'blue': chosenColor = Colors.cyanAccent; break;
          default: chosenColor = BasicPalette.red.color;
        }
      }

      add(RectangleComponent(size: size, paint: Paint()..color = chosenColor));
    } catch (e) {
      debugPrint('Error loading cosmetics: $e');
      add(RectangleComponent(size: size, paint: BasicPalette.red.paint()));
    }
  }

  void triggerAttack() {
    if (attackCooldown > 0) return;
    attackCooldown = 3.0; 

    // Gunners shouldn't lunge forward, they just flash! Drivers/Solo can lunge.
    if (!isGunner) {
      final forward = Vector2(cos(angle), sin(angle));
      const double lungeDistance = 45.0; 
      position += forward * lungeDistance;
    }

    FlameAudio.play('ElevenLabs_Scary_stinger.mp3');
    
    channel.sendBroadcastMessage(
      event: 'scare',
      payload: {
        'id': game.mySessionId, 
        'x': position.x, 
        'y': position.y,
        'a': angle,
      },
    );

    int victimsHit = game.triggerLocalScare(position, angle);

    if (victimsHit > 0) {
      int baseScore = victimsHit * 100;
      int comboBonus = (victimsHit - 1) * 50 * (victimsHit - 1); 
      int totalEarned = baseScore + comboBonus;
      score += totalEarned;
      
      String popupText = victimsHit > 1 ? '+$totalEarned COMBO x$victimsHit!' : '+$totalEarned';
      game.world.add(FloatingText(text: popupText, position: Vector2(position.x - 20, position.y - 50)));
    }
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

    if (keysPressed.contains(LogicalKeyboardKey.space)) {
      triggerAttack();
    }

    return true; 
  }

  @override
  void update(double dt) {
    if (!game.gameStarted) return; 
    super.update(dt);

    if (attackCooldown > 0) attackCooldown -= dt;
    if (isStunned) {
      stunTimer -= dt;
      if (stunTimer <= 0) isStunned = false;
      return; 
    }

    // 1. AIMING LOGIC (Both Driver and Gunner use Right Stick to aim)
    if (!rightJoystick.delta.isZero()) {
      angle = rightJoystick.delta.screenAngle();
    }

    // 2. MOVEMENT LOGIC (Only Drivers/Solo players move!)
    if (!isGunner) {
      Vector2 movementDelta = Vector2.zero();

      if (!keyboardDelta.isZero()) {
        movementDelta = keyboardDelta;
      } else if (!leftJoystick.delta.isZero()) {
        movementDelta = leftJoystick.relativeDelta;
      }

      if (!movementDelta.isZero()) {
        // If we aren't using the aiming stick, auto-face the direction we are walking
        if (rightJoystick.delta.isZero()) {
          angle = movementDelta.screenAngle();
        }

        final potentialPosition = position + (movementDelta * maxSpeed * dt);

        if (!game.gameMap.checkCollision(Vector2(potentialPosition.x, position.y), size)) {
          position.x = potentialPosition.x;
        }
        if (!game.gameMap.checkCollision(Vector2(position.x, potentialPosition.y), size)) {
          position.y = potentialPosition.y;
        }
      }
    }

    // 3. NETWORK SYNC
    networkTick += dt;
    if (networkTick >= networkRate) {
      networkTick = 0;
      channel.sendBroadcastMessage(
        event: 'move',
        payload: {
          'id': game.mySessionId,
          'x': position.x, 
          'y': position.y, 
          'a': angle,
          'c': equippedColorString, 
        },
      );
    }
  }
}