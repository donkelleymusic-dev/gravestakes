import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'game.dart';

class FlyingScareBlast extends CircleComponent with HasGameReference<GraveStakesGame> {
  final double speed = 180.0; 
  late Vector2 direction;
  double lifeTimer = 2.0; 
  double spawnTimer = 0.15; 
  
  // --- NEW: Define the ownerId property ---
  final String ownerId;
  
  bool isDead = false; 
  
  SoundHandle? _audioHandle;
  static const double _audioScale = 50.0;

  // --- NEW: Require ownerId in the constructor ---
  FlyingScareBlast({required Vector2 position, required double angle, required this.ownerId})
      : super(
          position: position,
          radius: 20.0, 
          paint: Paint()..color = Colors.purpleAccent,
          anchor: Anchor.center,
          angle: angle,
        ) {
    direction = Vector2(sin(angle), -cos(angle));
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();
    debugPrint('FLYING BAT LOADED at world position: $position with direction: $direction');
    
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
      isDead = true; // <--- Changed from removeFromParent()
      return;
    }

    if (spawnTimer > 0) {
      spawnTimer -= dt;
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
          //bot.applyStun(3.0);
          bot.applyStun(3.0, isVermin: true, attackerId: ownerId);
          bot.localImmunityToMe = 5.0;
          bot.triggerPrivateHighlight();
          _stopAudio();
          isDead = true; // <--- Changed from removeFromParent()
          return; 
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
          isDead = true; // <--- Changed from removeFromParent()
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