import 'package:flame/components.dart';
import 'package:flame/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flame/collisions.dart';
import 'dart:math';
import 'game.dart';
import 'floating_text.dart';
import 'scare_blast.dart';
import 'power_up.dart';
import 'chest_reward.dart';

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
  final double networkRate = 0.12;

  Vector2 keyboardDelta = Vector2.zero();

  bool isStunned = false;
  double stunTimer = 0;
  double attackCooldown = 0;
  
  String equippedColorString = 'red'; 
  
  // Sprite and base color storage for the visual stun effect
  late RectangleComponent _sprite;
  Color _baseColor = Colors.redAccent; 

  // NEW: The hovering text timer!
  late TextComponent _buffTimerText;

  double highlightTimer = 0;

  double disguiseTimer = 0.0;
  double _tickAccumulator = 0.0;

  bool get isMoving => !keyboardDelta.isZero() || (!isGunner && !leftJoystick.delta.isZero());

  // ==========================================
  // LOCAL FOOTSTEP VARIABLES
  // ==========================================
  double _footstepTimer = 0.0;
  final Random _random = Random();

  bool hasInvisibilityCharge = false;
  bool isInvisible = false;
  double invisibilityTimer = 0.0;
  bool isDisguised = false;
  bool hasExtendedRange = false;
  int coinsEarned = 0;
  SpriteComponent? _bushSprite;

  void applyChestReward(ChestReward reward) {
    switch (reward.type) {
      case ChestRewardType.points:
        score += reward.value;
        break;
      case ChestRewardType.currency:
        coinsEarned += reward.value;
        break;
      case ChestRewardType.invisibility:
        hasInvisibilityCharge = true;
        break;
      case ChestRewardType.disguise:
        isDisguised = true;
        disguiseTimer = 40.0; 
        _tickAccumulator = 0.0; 
        break;
      case ChestRewardType.rangeIncrease:
        hasExtendedRange = true;
        break;
      case ChestRewardType.teleport:
        game.camera.viewport.add(FloatingText(text: 'WHOOSH!', worldPosition: Vector2(position.x - 20, position.y - 40)));

        // 1. Gather every known safe floor node on the active map
        final List<Vector2> allSafeNodes = [
          ...game.gameMap.playerSpawns,
          ...game.gameMap.potentialBoxSpawns,
        ];
        
        // 2. Pick a safe node far away from where we currently are
        if (allSafeNodes.isNotEmpty) {
          allSafeNodes.shuffle();
          Vector2 bestNode = allSafeNodes.first;
          
          for (var node in allSafeNodes) {
            if (node.distanceTo(position) > 300.0) {
              bestNode = node;
              break;
            }
          }
          
          // 3. Snap to it safely
          position = game.gameMap.getSafeSpawnLocation(bestNode, size);
        }

        game.camera.viewport.add(FloatingText(text: 'POOF!', worldPosition: Vector2(position.x - 20, position.y - 40)));
        
        networkTick = networkRate; 
        break;
    }
  }

  void activateInvisibility() {
    if (!hasInvisibilityCharge || isInvisible) return;
    hasInvisibilityCharge = false;
    isInvisible = true;
    invisibilityTimer = 15.0; 
  }

  void _playLocalFootstep() {
    if (!game.isAudioReady || game.footstepSource == null) return;
    final randomPitch = 0.85 + (_random.nextDouble() * 0.30);
    
    final handle = SoLoud.instance.play(
      game.footstepSource!,
      volume: 0.5, 
    );
    
    SoLoud.instance.setRelativePlaySpeed(handle, randomPitch);
  }

  void triggerPrivateHighlight() {
    highlightTimer = 1.0; 
    _sprite.paint.color = Colors.white; 
  }

  Player(this.leftJoystick, this.rightJoystick, this.channel, {this.isGunner = false}) 
    : super(size: Vector2.all(32.0), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    await _fetchEquippedCosmetics();

    add(RectangleHitbox(
      size: Vector2(32, 32), 
      anchor: Anchor.center,
    ));

    // NEW: Build the Hovering Timer Text Component!
    _buffTimerText = TextComponent(
      position: Vector2(size.x / 2, -15), // Placed just above the player's head
      anchor: Anchor.center,
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.yellowAccent,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
          fontFamily: 'Courier',
          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
    );
    add(_buffTimerText);

    try {
      final sheet = game.images.fromCache('Base_BaseChip_pipo.png');
      _bushSprite = SpriteComponent(
        sprite: Sprite(sheet, srcPosition: Vector2(0, 160), srcSize: Vector2(32, 32)),
        size: Vector2.all(32),
        anchor: Anchor.center,
      );
    } catch (e) {
      debugPrint('Bush sprite not found in cache: $e');
    }
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

    _sprite = RectangleComponent(size: size, paint: Paint()..color = _baseColor);
    add(_sprite);
  }

  void triggerAttack() {
    if (attackCooldown > 0) return;
    attackCooldown = 9.0; 

    if (!isGunner) {
      final forward = Vector2(sin(angle), -cos(angle));
      double distanceToMove = 45.0; 
      
      while (distanceToMove > 0) {
        double step = min(5.0, distanceToMove);
        final testPos = position + (forward * step);
        
        if (!game.gameMap.checkCollision(testPos, size)) {
          position = testPos;
          distanceToMove -= step;
        } else {
          break; 
        }
      }
    }

    if (game.isAudioReady && game.scareSource != null) {
      SoLoud.instance.play(game.scareSource!);
    }
    
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

    int victimsHit = game.triggerLocalScare(position, angle, isPoweredUp, hasExtendedRange: hasExtendedRange);

    if (victimsHit > 0) {
      int baseScore = victimsHit * 100;
      int comboBonus = (victimsHit - 1) * 50 * (victimsHit - 1); 
      int totalEarned = baseScore + comboBonus;
      score += totalEarned;
      
      String popupText = victimsHit > 1 ? '+$totalEarned COMBO x$victimsHit!' : '+$totalEarned';
      game.camera.viewport.add(FloatingText(text: popupText, worldPosition: Vector2(position.x - 20, position.y - 50)));
    }
  }

  void applyStun(double duration) {
    isStunned = true;
    stunTimer = duration;
    _sprite.paint.color = Colors.cyanAccent; 
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
    
    // ==========================================
    // UNIFIED BUFF TIMERS, UI & TICKING
    // ==========================================
    bool isBuffActive = false;
    double lowestTimer = 999.0;
    List<String> activeBuffs = [];

    // 1. Process Disguise
    if (isDisguised) {
      disguiseTimer -= dt;
      isBuffActive = true;
      if (disguiseTimer < lowestTimer) lowestTimer = disguiseTimer;
      activeBuffs.add('BUSH: ${disguiseTimer.ceil()}s');
      
      if (disguiseTimer <= 0) {
        isDisguised = false;
        disguiseTimer = 0.0;
      }
    }

    // 2. Process Invisibility
    if (isInvisible) {
      invisibilityTimer -= dt;
      isBuffActive = true;
      if (invisibilityTimer < lowestTimer) lowestTimer = invisibilityTimer;
      activeBuffs.add('INVIS: ${invisibilityTimer.ceil()}s');
      
      if (invisibilityTimer <= 0) {
        isInvisible = false;
        invisibilityTimer = 0.0;
      }
    }

    // 3. Process Power-Ups
    if (powerUpTimer > 0) {
      powerUpTimer -= dt; // Moved this up here so they all decrement together!
      isBuffActive = true;
      if (powerUpTimer < lowestTimer) lowestTimer = powerUpTimer;
      
      // Only add to the UI if it didn't just expire this exact frame
      if (powerUpTimer > 0) {
        activeBuffs.add('POWER: ${powerUpTimer.ceil()}s');
      }
    }

    // UPDATE THE UI TEXT!
    _buffTimerText.text = activeBuffs.join('\n'); 

    // AUDIO TICKING LOGIC (Remains exactly the same)
    if (isBuffActive) {
      _tickAccumulator += dt;
      if (_tickAccumulator >= 1.0) {
        _tickAccumulator -= 1.0;
        
        if (game.isAudioReady && game.tickSource != null) {
          // Much quieter normally (5% volume), Loud (100% volume) for the last 8 seconds!
          final tickVolume = lowestTimer <= 8.0 ? 1.0 : 0.05;
          SoLoud.instance.play(game.tickSource!, volume: tickVolume);
        }
      }
    } else {
      _tickAccumulator = 0.0;
    }

    // --- HIGHLIGHTS AND OPACITY HANDLING ---
    if (highlightTimer > 0) {
      highlightTimer -= dt;
      _sprite.paint.color = Colors.white; 
      // (Removed the powerUpTimer decrement from here)
    } else if (powerUpTimer > 0) {
      _sprite.paint.color = Colors.yellowAccent;
    } else if (!isStunned) {
      if (isDisguised) {
        _sprite.paint.color = Colors.transparent; 
      } else if (isInvisible) {
        _sprite.paint.color = _baseColor.withAlpha(80); 
      } else {
        _sprite.paint.color = _baseColor; 
      }
    }

    // Toggle the Bush Sprite overlay
    if (isDisguised) {
      if (_bushSprite != null && _bushSprite!.parent == null) {
        add(_bushSprite!);
      }
    } else {
      if (_bushSprite != null && _bushSprite!.parent != null) {
        _bushSprite!.removeFromParent();
      }
    }

    // Check for collisions with PowerUps safely
    final worldComponents = game.world.children.toList();
    List<PowerUp> powerUpsToRemove = [];
    
    for (var comp in worldComponents) {
      if (comp is PowerUp) {
        if (position.distanceTo(comp.position) < 30) {
          powerUpTimer = 10.0; 
          try {
            if (game.isAudioReady && game.powerupSource != null) {
              SoLoud.instance.play(game.powerupSource!);
            }
          } catch (e) {
            debugPrint('Failed to play powerup sound: $e');
          }
          
          powerUpsToRemove.add(comp);
          
          channel.sendBroadcastMessage(
            event: 'consume_powerup',
            payload: {
              'id': comp.id
            },
          );
          
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
                's': score,
                'd': isDisguised, 
                'm': isMoving,    
                'i': isInvisible,
              },
            );
          }
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
        _sprite.paint.color = _baseColor; 
        _sprite.position = Vector2.zero();
      }
      return; 
    }

    // 1. AIMING LOGIC 
    if (!rightJoystick.delta.isZero()) {
      angle = rightJoystick.delta.screenAngle();
    }

    // 2. MOVEMENT LOGIC 
    if (!isGunner) {
      Vector2 movementDelta = Vector2.zero();

      if (!keyboardDelta.isZero()) {
        movementDelta = keyboardDelta;
      } else if (!leftJoystick.delta.isZero()) {
        movementDelta = leftJoystick.relativeDelta;
      }

      if (!movementDelta.isZero()) {
        if (rightJoystick.delta.isZero()) {
          angle = movementDelta.screenAngle();
        }

        double currentSpeed = isPoweredUp ? 280.0 : maxSpeed;
        final potentialPosition = position + (movementDelta * currentSpeed * dt);

        final oldPosition = position.clone();

        if (!game.gameMap.checkCollision(Vector2(potentialPosition.x, position.y), size)) {
          position.x = potentialPosition.x;
        }
        if (!game.gameMap.checkCollision(Vector2(position.x, potentialPosition.y), size)) {
          position.y = potentialPosition.y;
        }

        double actualVelocity = position.distanceTo(oldPosition) / dt; 

        if (actualVelocity > 5.0) {
           double dynamicInterval = 0.40 * (200.0 / actualVelocity);
           dynamicInterval += (_random.nextDouble() * 0.1) - 0.05; 
           
           _footstepTimer += dt;
           if (_footstepTimer >= dynamicInterval) {
             _footstepTimer = 0.0;
             _playLocalFootstep();
           }
        } else {
          _footstepTimer = 0.0; 
        }
      } else {
        _footstepTimer = 0.0; 
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
          's': score,
          'd': isDisguised, 
          'm': isMoving,
          'i': isInvisible,
        },
      );
    }
  }
}