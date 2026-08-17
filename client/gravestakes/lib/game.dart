import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/palette.dart';
import 'package:flutter/painting.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'player.dart';
import 'remote_player.dart';
import 'bot_player.dart'; 
import 'game_map.dart'; // Import the map
import 'darkness_overlay.dart';
import 'jump_scare_effect.dart';
import 'score_hud.dart';
import 'game_timer.dart';
import 'start_button.dart';
import 'attack_button.dart';

class GraveStakesGame extends FlameGame with HasKeyboardHandlerComponents {
  late final JoystickComponent joystick;
  late final Player player;
  late final RemotePlayer remotePlayer;
  late final JumpScareEffect jumpScareEffect;
  late final GameMap gameMap; // Map reference

  late final GameTimer gameTimer;
  late final ScoreHud scoreHud;
  bool gameStarted = false;
  
  final List<BotPlayer> bots = [];
  final myChannel = Supabase.instance.client.channel('room_1');

  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.topLeft;
    
    // 1. BUILD THE JOYSTICK FIRST
    final knobPaint = BasicPalette.white.withAlpha(200).paint();
    final backgroundPaint = BasicPalette.white.withAlpha(100).paint();

    joystick = JoystickComponent(
      knob: CircleComponent(radius: 20, paint: knobPaint),
      background: CircleComponent(radius: 60, paint: backgroundPaint),
      margin: const EdgeInsets.only(left: 40, bottom: 40),
    );

    // 2. Initialize map and world items
    gameMap = GameMap();
    world.add(gameMap);

    // NOW the joystick exists when the player asks for it!
    player = Player(joystick, myChannel)..position = Vector2.zero();
    remotePlayer = RemotePlayer()..position = Vector2(-100, -100);
    jumpScareEffect = JumpScareEffect();

    world.add(player);
    world.add(remotePlayer);
    
    final random = Random();
    for (int i = 0; i < 3; i++) {
      final bot = BotPlayer()
        ..position = Vector2(
          (random.nextDouble() * 400 - 200), 
          (random.nextDouble() * 400 - 200),
        );
      bots.add(bot);
      world.add(bot); 
    }

    camera.follow(player);

    // ==========================================
    // 3. VIEWPORT & UI LAYER 
    // ==========================================
    camera.viewport.add(DarknessOverlay(player)); 
    camera.viewport.add(jumpScareEffect);
    camera.viewport.add(joystick);
    camera.viewport.add(ScoreHud());
    camera.viewport.add(gameTimer = GameTimer());
    camera.viewport.add(StartButton());
    camera.viewport.add(AttackButton()); 

    _setupSupabaseListener();
  }

  void endGame() {
    // Reset logic
    player.score = 0;
    player.position = Vector2.zero();
  }
  // Call this whenever a scare happens (locally or via network)
  void triggerLocalScare(Vector2 attackerPos) {
    // Check if it hits any bots
    for (var bot in bots) {
      if (bot.position.distanceTo(attackerPos) < 250) {
        bot.applyStun(4.0); // Stun the bot for 4 seconds!
      }
    }
  }
  
  void startGame() {
    gameStarted = true;
    gameTimer.start();
  }

  void _setupSupabaseListener() {
    myChannel
      .onBroadcast(
        event: 'move',
        callback: (payload) {
          final x = payload['x'] as double;
          final y = payload['y'] as double;
          final angle = payload['a'] as double;
          remotePlayer.updatePosition(x, y, angle);
        },
      )
      .onBroadcast(
        event: 'scare',
        callback: (payload) {
          final attackerPos = Vector2(payload['x'] as double, payload['y'] as double);
          triggerLocalScare(attackerPos);
          if (player.position.distanceTo(attackerPos) < 150) {
            jumpScareEffect.trigger();
            player.applyStun(2.0);
          }

          for (var bot in bots) {
            if (bot.position.distanceTo(attackerPos) < 150) {
              bot.applyStun(3.0); 
            }
          }
        },
      )
      .subscribe();
  }
}