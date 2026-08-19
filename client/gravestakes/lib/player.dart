import 'package:flame/components.dart';
import 'package:flame/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flame_audio/flame_audio.dart';
import 'dart:math';
import 'game.dart';
import 'floating_text.dart';
import 'scare_blast.dart';
import 'power_up.dart';

class Player extends PositionComponent with KeyboardHandler, HasGameReference<GraveStakesGame> {
  final JoystickComponent leftJoystick;
  final JoystickComponent rightJoystick; 
  final RealtimeChannel channel; 
  final bool isGunner; 

  final double maxSpeed = 200.0;
  int score = 0;

  //Power-Up State
  double powerUpTimer = 0;
  bool get isPoweredUp => powerUpTimer > 0;
  
  double networkTick = 0; 
  final double networkRate = 0.05;

  Vector2 keyboardDelta = Vector2.zero();

  bool isStunned = false;
  double stunTimer = 0;
  double attackCooldown = 0;
  
  String equippedColorString = 'red'; 
  
  // NEW: Sprite and base color storage for the visual stun effect
  late RectangleComponent _sprite;
  Color _baseColor = Colors.redAccent; 

  double highlightTimer = 0;

  void triggerPrivateHighlight() {
    highlightTimer = 1.0; 
    _sprite.paint.color = Colors.white; 
  }

  Player(this.leftJoystick, this.rightJoystick, this.channel, {this.isGunner = false}) 
    : super(size: Vector2.all(32.0), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    await _fetchEquippedCosmetics();
  }

  Future<void> _fetchEquippedCosmetics() async {
    final user = Supabase.instance.client.auth.currentUser;
    
    if (user != null) {
      try {
        final res = await Supabase.instance.client
            .from('user_loadouts')
            .select('item_value')
            .eq('user_id', user.id)
            .eq('slot_type', 'flashlight_color')
            .maybeSingle();

        if (res != null) {
          final val = res['item_value'] as String;
          equippedColorString = val; 
          switch (val) {
            case 'green': _baseColor = Colors.greenAccent; break;
            case 'purple': _baseColor = Colors.purpleAccent; break;
            case 'red': _baseColor = Colors.redAccent; break;
            case 'blue': _baseColor = Colors.cyanAccent; break;
          }
        }
      } catch (e) {
        debugPrint('Error loading cosmetics: $e');
      }
    }

    // NEW: We add it to a managed sprite instead of just blindly adding it to the component tree
    _sprite = RectangleComponent(size: size, paint: Paint()..color = _baseColor);
    add(_sprite);
  }

  void triggerAttack() {
    if (attackCooldown > 0) return;
    attackCooldown = 3.0; 

    // Gunners shouldn't lunge forward, they just flash! Drivers/Solo can lunge.
    if (!isGunner) {
      final forward = Vector2(sin(angle), -cos(angle));
      double distanceToMove = 45.0; 
      
      // Step forward incrementally to slide up to walls without clipping
      while (distanceToMove > 0) {
        double step = min(5.0, distanceToMove);
        final testPos = position + (forward * step);
        
        if (!game.gameMap.checkCollision(testPos, size)) {
          position = testPos;
          distanceToMove -= step;
        } else {
          break; // Hit a wall, stop lunging immediately
        }
      }
    }

    FlameAudio.play('ElevenLabs_Scary_stinger.mp3');
    
    // NEW: Spawn the visual cone blast to the world!
    game.world.add(ScareBlast(position: position, angle: angle - (pi / 2)));
    
    channel.sendBroadcastMessage(
      event: 'scare',
      payload: {
        'id': game.mySessionId, 
        'x': position.x, 
        'y': position.y,
        'a': angle,
      },
    );

    // Pass our powered-up status to the scare calculator!
    int victimsHit = game.triggerLocalScare(position, angle, isPoweredUp);

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
    _sprite.paint.color = Colors.cyanAccent; // NEW: Instantly turn shocked color
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
    
    // --- POWER-UP LOGIC & HIGHLIGHTS ---
    if (highlightTimer > 0) {
      highlightTimer -= dt;
      _sprite.paint.color = Colors.white; // Force white while highlighting
      if (isPoweredUp) powerUpTimer -= dt; // Keep ticking powerup
    } else if (isPoweredUp) {
      powerUpTimer -= dt;
      _sprite.paint.color = Colors.yellowAccent;
    } else if (!isStunned) {
      _sprite.paint.color = _baseColor; 
    }

    // Check for collisions with PowerUps safely
    final worldComponents = game.world.children.toList();
    List<PowerUp> powerUpsToRemove = [];
    
    for (var comp in worldComponents) {
      if (comp is PowerUp) {
        if (position.distanceTo(comp.position) < 30) {
          powerUpTimer = 10.0; 
          try {
            FlameAudio.play('ElevenLabs_Scary_stinger.mp3');
          } catch (_) {}
          
          powerUpsToRemove.add(comp);
          
          channel.sendBroadcastMessage(
            event: 'consume_powerup',
            payload: {'id': comp.id},
          );
        }
      }
    }

    for (var spark in powerUpsToRemove) {
      spark.removeFromParent();
    }

    // SHAKE EFFECT FOR HUMANS
    if (isStunned) {
      stunTimer -= dt;
      
      int alpha = (150 + sin(stunTimer * 30) * 105).toInt().clamp(0, 255);
      _sprite.paint.color = Colors.cyanAccent.withAlpha(alpha);
      _sprite.position = Vector2(sin(stunTimer * 50) * 4, 0);

      if (stunTimer <= 0) {
        isStunned = false;
        _sprite.paint.color = _baseColor; // Return to equipped color
        _sprite.position = Vector2.zero();
      }
      return; // Skip movement processing while stunned
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

        // Base speed is 200. Surged speed is 280.
        double currentSpeed = isPoweredUp ? 280.0 : maxSpeed;
        final potentialPosition = position + (movementDelta * currentSpeed * dt);

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