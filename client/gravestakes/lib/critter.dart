import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'game.dart';
import 'mask_data.dart';
import 'audio_manager.dart';

class Critter extends CircleComponent with HasGameReference<GraveStakesGame> {
  bool isDead = false; 
  final SwarmBehavior behavior;
  final int seed;
  final int index;
  final double initialAngle;
  final String ownerId;
  
  late Random _localRandom;
  late Vector2 velocity;
  double lifeTimer = 3.0; 
  double spawnTimer = 0.15; 

  // --- NEW: Animation state ---
  double _scuttleTimer = 0.0;
  
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
         radius: 2, // Keeps the physical hitbox tiny so they don't get stuck on walls
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
      if (index == 0 && AudioManager.instance.isInitialized && AudioManager.instance.maskScareSounds['vermin'] != null) {
        final posX = position.x / _audioScale;
        final posY = position.y / _audioScale;

        _scurryHandle = SoLoud.instance.play3d(
          AudioManager.instance.maskScareSounds['vermin']!,
          posX,
          posY,
          0.0,
          volume: 0.6,
        );
        SoLoud.instance.set3dSourceMinMaxDistance(_scurryHandle!, 1.0, 15.0);
      }
    } catch (e) {}
  }

  @override
  void update(double dt) {
    super.update(dt);
    priority = ((position.y + 16) * 10).toInt();
    
    // --- NEW: Advance animation and rotate body to face movement direction ---
    _scuttleTimer += dt * 40.0;
    angle = atan2(velocity.y, velocity.x); 
    
    lifeTimer -= dt;
    if (lifeTimer <= 0) {
      _stopAudio();
      isDead = true; 
      return;
    }

    if (behavior == SwarmBehavior.scatter) {
      if (_localRandom.nextDouble() < 0.05) {
        double jitterAngle = (_localRandom.nextDouble() * pi) - (pi / 2);
        velocity.rotate(jitterAngle);
      }
    }

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

    if (index == 0 && _scurryHandle != null && AudioManager.instance.isInitialized) {
      final posX = position.x / _audioScale;
      final posY = position.y / _audioScale;
      SoLoud.instance.set3dSourcePosition(_scurryHandle!, posX, posY, 0.0);
    }

    if (spawnTimer > 0) {
      spawnTimer -= dt;
      return;
    }

    if (game.isHost) {
      for (var bot in game.bots) {
        if (game.matchMode == '2v2' && game.getEntityTeam(ownerId) == game.getEntityTeam(bot)) continue;
        if (bot.localImmunityToMe > 0) continue;
        if (position.distanceTo(bot.position) < 20.0) {
          bot.applyStun(1.5, isVermin: true, attackerId: ownerId);
          bot.localImmunityToMe = 3.0; 
          bot.triggerPrivateHighlight();
          _stopAudio();
          isDead = true; 
          removeFromParent();
          return;
        }
      }

      for (var entry in game.networkPlayers.entries) {
        if (entry.key == ownerId) continue;
        if (game.matchMode == '2v2' && game.getEntityTeam(ownerId) == game.getEntityTeam(entry.key)) continue;
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
        if (game.matchMode == '2v2' && game.getEntityTeam(ownerId) == game.getEntityTeam(game.player)) return;
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

  // --- NEW: Procedural Render Method ---
  @override
  void render(Canvas canvas) {
    // Brightened the colors significantly so they don't blend into the pitch-black floor!
    final paintBody = Paint()..color = const Color(0xFF5A5A66); // Sickly pale grey
    final paintEye = Paint()..color = Colors.redAccent; 
    final paintMouth = Paint()..color = Colors.black..strokeWidth = 1.0;
    final paintAppendage = Paint()
      ..color = const Color(0xFF888899) // Lighter grey for legs/tail
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Body (Width 18, Height 10 pill shape)
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 18, height: 10), paintBody);

    // Animated Tail (Whips back and forth)
    double tailWiggle = sin(_scuttleTimer) * 5.0;
    final tailPath = Path()
      ..moveTo(-9, 0)
      ..quadraticBezierTo(-14, tailWiggle, -20, -tailWiggle * 0.5); 
    canvas.drawPath(tailPath, paintAppendage);

    // Eyes (Positioned near the front)
    canvas.drawCircle(const Offset(5, -2.5), 1.2, paintEye);
    canvas.drawCircle(const Offset(5, 2.5), 1.2, paintEye);

    // Mouth
    canvas.drawLine(const Offset(8, -1), const Offset(8, 1), paintMouth);

    // Scuttling Legs
    double legWiggle = cos(_scuttleTimer) * 4.0; // Increased leg sweep

    // Left/Top side legs
    canvas.drawLine(const Offset(-4, -4), Offset(-4 + legWiggle, -8), paintAppendage);
    canvas.drawLine(const Offset(4, -4), Offset(4 - legWiggle, -8), paintAppendage);

    // Right/Bottom side legs
    canvas.drawLine(const Offset(-4, 4), Offset(-4 - legWiggle, 8), paintAppendage);
    canvas.drawLine(const Offset(4, 4), Offset(4 + legWiggle, 8), paintAppendage);
  }

  @override
  void onRemove() {
    _stopAudio();
    super.onRemove();
  }

  void _stopAudio() {
    if (_scurryHandle != null && AudioManager.instance.isInitialized) {
      SoLoud.instance.stop(_scurryHandle!);
      _scurryHandle = null;
    }
  }
}
