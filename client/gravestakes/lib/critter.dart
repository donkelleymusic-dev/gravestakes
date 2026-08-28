import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'game.dart';
import 'mask_data.dart';

class Critter extends CircleComponent with HasGameReference<GraveStakesGame> {
  bool isDead = false; // <--- NEW: Flag for the manager
  final SwarmBehavior behavior;
  final int seed;
  final int index;
  final double initialAngle;
  final String ownerId;
  
  late Random _localRandom;
  late Vector2 velocity;
  double lifeTimer = 3.0; 
  double spawnTimer = 0.15; // NEW: Grace period for visual scattering
  
  SoundHandle? _scurryHandle;
  static const double _audioScale = 50.0;

  Critter({
    required Vector2 position, 
    required this.behavior, 
    required this.seed, 
    required this.index,
    required this.initialAngle,
    required this.ownerId,
  }) : super(
         position: position,
         radius: 12.0, // The component IS the circle now!
         paint: Paint()..color = Colors.greenAccent,
         anchor: Anchor.center,
       ) {
    
    _localRandom = Random(seed + index);
    double spread = (_localRandom.nextDouble() * 2) - 1; 
    double startAngle = initialAngle + (spread * (pi / 4)); 
    
    double startSpeed = 200.0 + (_localRandom.nextDouble() * 150);
    velocity = Vector2(sin(startAngle), -cos(startAngle)) * startSpeed;
  }

  @override
  Future<void> onLoad() async {
    try {
      debugPrint('CRITTER [$index] LOADED at world position: $position');

      // 3D AUDIO HOOK wrapped to catch any crash
      if (index == 0 && game.isAudioReady && game.ratScurrySource != null) {
        final posX = position.x / _audioScale;
        final posY = position.y / _audioScale;

        _scurryHandle = SoLoud.instance.play3d(
          game.ratScurrySource!,
          posX,
          posY,
          0.0,
          volume: 0.6,
        );
        SoLoud.instance.set3dSourceMinMaxDistance(_scurryHandle!, 1.0, 15.0);
      }
      
      debugPrint('CRITTER [$index] SURVIVED ONLOAD!');
    } catch (e) {
      debugPrint('CRITTER [$index] CRASHED INSIDE ONLOAD: $e');
    }
  }

  @override
  void onMount() {
    super.onMount();
    debugPrint('CRITTER [$index] SUCCESSFULLY MOUNTED!');
  }

  @override
  void update(double dt) {
    debugPrint('CRITTER [$index] TICKING UPDATE. dt: $dt');
    super.update(dt);
    // Match the * 10 system used by players and walls
    priority = ((position.y + 16) * 10).toInt();
    
    lifeTimer -= dt;
    if (lifeTimer <= 0) {
      _stopAudio();
      //removeFromParent();
      isDead = true; // <--- CHANGE removeFromParent() to this
      return;
    }

    if (behavior == SwarmBehavior.scatter) {
      if (_localRandom.nextDouble() < 0.05) {
        double jitterAngle = (_localRandom.nextDouble() * pi) - (pi / 2);
        velocity.rotate(jitterAngle);
      }
    }

    // Always move the critter, even during spawn timer
    final potentialPosition = position + (velocity * dt);
    
    if (!game.gameMap.checkCollision(Vector2(potentialPosition.x, position.y), size)) {
      position.x = potentialPosition.x;
    } else {
      velocity.x *= -1; 
    }
    
    if (!game.gameMap.checkCollision(Vector2(position.x, potentialPosition.y), size)) {
      position.y = potentialPosition.y;
    } else {
      velocity.y *= -1; 
    }

    // Update the 3D position of the swarm's audio anchor if this is critter #0
    if (index == 0 && _scurryHandle != null && game.isAudioReady) {
      final posX = position.x / _audioScale;
      final posY = position.y / _audioScale;
      SoLoud.instance.set3dSourcePosition(_scurryHandle!, posX, posY, 0.0);
    }

    // NEW: Skip collision checks for the first 0.15 seconds
    if (spawnTimer > 0) {
      spawnTimer -= dt;
      return;
    }

    // Host Authority damage logic...
    if (game.isHost) {
      for (var bot in game.bots) {
        if (bot.localImmunityToMe > 0) continue;
        if (position.distanceTo(bot.position) < 20.0) {
          //bot.applyStun(1.5);
          bot.applyStun(1.5, isVermin: true, attackerId: ownerId);
          bot.localImmunityToMe = 3.0; 
          bot.triggerPrivateHighlight();
          _stopAudio();
          isDead = true; // <--- HERE
          removeFromParent();
          return;
        }
      }

      for (var entry in game.networkPlayers.entries) {
        if (entry.key == ownerId) continue;
        var remote = entry.value;
        if (remote.localImmunityToMe > 0) continue;
        if (position.distanceTo(remote.position) < 20.0) {
          remote.applyStun(1.5);
          remote.localImmunityToMe = 3.0;
          remote.triggerPrivateHighlight();
          game.myChannel.sendBroadcastMessage(
            event: 'stun',
            payload: {'id': entry.key, 'duration': 1.5, 'attacker_id': ownerId},
          );
          _stopAudio();
          removeFromParent();
          return;
        }
      }

      if (ownerId != game.mySessionId && !game.player.isStunned) {
        if (position.distanceTo(game.player.position) < 20.0) {
          game.jumpScareEffect.trigger();
          game.player.applyStun(1.5);
          game.player.triggerPrivateHighlight();
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
    if (_scurryHandle != null && game.isAudioReady) {
      SoLoud.instance.stop(_scurryHandle!);
      _scurryHandle = null;
    }
  }
}