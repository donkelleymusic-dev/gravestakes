import 'package:flame/components.dart';
import 'package:flame/events.dart'; // Required for keyboard mixins
import 'package:flame/game.dart';
import 'package:flame/palette.dart';
import 'package:flutter/painting.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'player.dart';
import 'remote_player.dart';
import 'darkness_overlay.dart';

// Add the 'with HasKeyboardHandlerComponents' mixin here:
class GraveStakesGame extends FlameGame with HasKeyboardHandlerComponents {
  late final JoystickComponent joystick;
  late final Player player;
  late final RemotePlayer remotePlayer;
  
  final myChannel = Supabase.instance.client.channel('room_1');

  @override
  Future onLoad() async {
    final knobPaint = BasicPalette.white.withAlpha(200).paint();
    final backgroundPaint = BasicPalette.white.withAlpha(100).paint();

    joystick = JoystickComponent(
      knob: CircleComponent(radius: 20, paint: knobPaint),
      background: CircleComponent(radius: 60, paint: backgroundPaint),
      margin: const EdgeInsets.only(left: 40, bottom: 40),
      priority: 20,
    );

    player = Player(joystick, myChannel)..position = size / 2;
    remotePlayer = RemotePlayer()..position = Vector2(-100, -100);

    add(player);
    add(remotePlayer);
    add(DarknessOverlay(player)); 
    add(joystick);

    _setupSupabaseListener();
  }

  void _setupSupabaseListener() {
    myChannel.onBroadcast(
      event: 'move',
      callback: (payload) {
        final x = payload['x'] as double;
        final y = payload['y'] as double;
        final angle = payload['a'] as double;
        remotePlayer.updatePosition(x, y, angle);
      },
    ).subscribe();
  }
}