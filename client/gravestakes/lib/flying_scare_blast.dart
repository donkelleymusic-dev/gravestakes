import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'game.dart';

class FlyingScareBlast extends PositionComponent with HasGameReference<GraveStakesGame> {
  final double speed = 180.0; // Slower, tactical speed
  late Vector2 direction;
  double lifeTimer = 2.0; 
  
  SoundHandle? _audioHandle;
  static const double _audioScale = 50.0;

  FlyingScareBlast({required Vector2 position, required double angle})
      : super(position: position, size: Vector2(64, 64), anchor: Anchor.center, angle: angle) {
    direction = Vector2(sin(angle), -cos(angle));
  }

  @override
  Future<void> onLoad() async {
    add(CircleComponent(
      radius: 16,
      paint: Paint()..color = Colors.purpleAccent.withOpacity(0.8),
      anchor: Anchor.center,
      position: size / 2,
    ));

    if (game.isAudioReady && game.batScreechSource != null) {
      final posX = position.x / _audioScale;
      final posY = position.y / _audioScale;
      _audioHandle = SoLoud.instance.play3d(game.batScreechSource!, posX, posY, 0.0, volume: 1.0);
      SoLoud.instance.set3dSourceMinMaxDistance(_audioHandle!, 2.0, 30.0);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    position += direction * speed * dt;
    
    if (_audioHandle != null && game.isAudioReady) {
      final posX = position.x / _audioScale;
      final posY = position.y / _audioScale;
      SoLoud.instance.set3dSourcePosition(_audioHandle!, posX, posY, 0.0);
    }

    lifeTimer -= dt;
    if (lifeTimer <= 0) {
      _stopAudio();
      removeFromParent();
      return;
    }

    // ==========================================
    // HOST AUTHORITY: STOP ON FIRST ENEMY HIT
    // ==========================================
    if (game.isHost) {
      // 1. Check Bots
      for (var bot in game.bots) {
        if (bot.localImmunityToMe > 0) continue;
        if (position.distanceTo(bot.position) < 30.0) {
          bot.applyStun(3.0);
          bot.localImmunityToMe = 5.0;
          bot.triggerPrivateHighlight();
          _stopAudio();
          removeFromParent();
          return; // Stops and destroys instantly!
        }
      }

      // 2. Check Remote Players
      for (var entry in game.networkPlayers.entries) {
        var remote = entry.value;
        if (remote.localImmunityToMe > 0) continue;
        if (position.distanceTo(remote.position) < 30.0) {
          remote.applyStun(3.0);
          remote.localImmunityToMe = 5.0;
          remote.triggerPrivateHighlight();
          
          game.myChannel.sendBroadcastMessage(
            event: 'stun',
            payload: {'id': entry.key, 'duration': 3.0, 'attacker_id': game.mySessionId},
          );
          
          _stopAudio();
          removeFromParent();
          return;
        }
      }
    }
  }

  @override
  void onRemove() {
    _stopAudio();
    super.onRemove();
  }

  void _stopAudio() {
    if (_audioHandle != null && game.isAudioReady) {
      SoLoud.instance.stop(_audioHandle!);
      _audioHandle = null;
    }
  }
}