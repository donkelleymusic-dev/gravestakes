import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'game.dart';
import 'floating_text.dart';
import 'audio_manager.dart';

class FlyingScareBlast extends PositionComponent with HasGameReference<GraveStakesGame> {
  final double speed = 240.0; 
  late Vector2 direction;
  double lifeTimer = 4.0;     
  double spawnTimer = 0.15; 
  
  final String ownerId;
  bool isDead = false; 
  
  SoundHandle? _audioHandle;
  static const double _audioScale = 50.0;

  FlyingScareBlast({required Vector2 position, required double angle, required this.ownerId})
      : super(
          position: position,
          size: Vector2.all(40.0), 
          anchor: Anchor.center,
          angle: angle,
          priority: 200000, 
        ) {
    direction = Vector2(sin(angle), -cos(angle));
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();
    if (parent != null) parent!.priority = 200000; 

    if (AudioManager.instance.isInitialized && AudioManager.instance.maskScareSounds['flying'] != null) {
      final posX = position.x / _audioScale;
      final posY = position.y / _audioScale;
      _audioHandle = SoLoud.instance.play3d(AudioManager.instance.maskScareSounds['flying']!, posX, posY, 0.0, volume: 1.0);
      SoLoud.instance.set3dSourceMinMaxDistance(_audioHandle!, 2.0, 30.0);
    }
  }

  @override
  void update(double dt) {
    priority = 999999; 
    super.update(dt);
    
    position += direction * speed * dt;
    
    if (_audioHandle != null && AudioManager.instance.isInitialized) {
      final posX = position.x / _audioScale;
      final posY = position.y / _audioScale;
      SoLoud.instance.set3dSourcePosition(_audioHandle!, posX, posY, 0.0);
    }

    lifeTimer -= dt;
    if (lifeTimer <= 0) {
      _stopAudio();
      isDead = true; 
      removeFromParent();
      return;
    }

    if (spawnTimer > 0) {
      spawnTimer -= dt;
      return; 
    }

    if (game.isHost) {
      for (var bot in game.bots) {
        if (game.matchMode == '2v2' && game.getEntityTeam(ownerId) == game.getEntityTeam(bot)) continue; 
        if (bot.localImmunityToMe > 0) continue;
        
        if (position.distanceTo(bot.position) < 30.0) {
          bot.applyStun(3.0, isVermin: true, attackerId: ownerId);
          bot.localImmunityToMe = 5.0;
          bot.triggerPrivateHighlight();
          _stopAudio();
          isDead = true; 
          removeFromParent();
          return; 
        }
      }

      for (var entry in game.networkPlayers.entries) {
        if (game.matchMode == '2v2' && game.getEntityTeam(ownerId) == game.getEntityTeam(entry.key)) continue; 
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
          isDead = true; 
          removeFromParent();
          return;
        }
      }

      if (ownerId != game.mySessionId && !game.player.isStunned) {
        if (position.distanceTo(game.player.position) < 30.0) {
          if (game.player.activeCounters.contains('flying')) {
            game.camera.viewport.add(FloatingText(
              text: 'BLAST ABSORBED!', 
              worldPosition: Vector2(game.player.position.x - 20, game.player.position.y - 40),
            ));
            _stopAudio();
            isDead = true;
            removeFromParent();
            return;
          }

          game.player.applyStun(3.0);
          _stopAudio();
          isDead = true;
          removeFromParent();
          return;
        }
      }
    }
  }

  // --- NEW: PROCEDURAL FLAPPING BAT RENDERER ---
  @override
  void render(Canvas canvas) {
    super.render(canvas);
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);

    // Creates a rapid sine wave between -1.0 and 1.0 based on how long it's been alive
    double flap = sin(lifeTimer * 30); 
    final path = Path();

    // Core Body
    path.addOval(const Rect.fromLTWH(-5, -8, 10, 16));

    // Left Wing (Dynamic Bezier Curves)
    path.moveTo(-4, -4);
    path.quadraticBezierTo(-20, flap * -20 - 10, -35, flap * 10 - 5); 
    path.quadraticBezierTo(-20, flap * 10 + 5, -2, 6); 

    // Right Wing (Dynamic Bezier Curves)
    path.moveTo(4, -4);
    path.quadraticBezierTo(20, flap * -20 - 10, 35, flap * 10 - 5);
    path.quadraticBezierTo(20, flap * 10 + 5, 2, 6);

    canvas.drawPath(path, Paint()..color = Colors.purpleAccent.withOpacity(0.9));
    canvas.drawPath(
      path, 
      Paint()
        ..color = Colors.cyanAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
    );

    canvas.restore();
  }

  @override
  void onRemove() {
    _stopAudio();
    super.onRemove();
  }

  void _stopAudio() {
    if (_audioHandle != null && AudioManager.instance.isInitialized) {
      SoLoud.instance.stop(_audioHandle!);
      _audioHandle = null;
    }
  }
}