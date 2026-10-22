// fps_viewport_overlay.dart
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flutter/material.dart' hide Image;
import 'game.dart';
import 'bot_player.dart';
import 'remote_player.dart';
import 'spooky_box.dart';
import 'power_up.dart';
import 'flying_scare_blast.dart';
import 'critter.dart';
import 'scare_blast.dart';
import 'siren_blast.dart';
import 'player.dart';
import 'tactical_entities.dart';
import 'game_map.dart';

class FpsViewportOverlay extends PositionComponent with HasGameReference<GraveStakesGame> {
  FpsViewportOverlay() : super(priority: 10); 

  // Reusable buffer & paints to prevent GC churn every frame
  List<double> _zBuffer = [];
  final Paint _wallPaint = Paint();
  final Paint _brickLinePaint = Paint()..color = Colors.black45;
  final Paint _mortarLinePaint = Paint()..color = Colors.black38;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
    final int w = size.x.toInt();
    if (_zBuffer.length != w) {
      _zBuffer = List<double>.filled(w, 999999.0);
    }
  }

  @override
  void render(Canvas canvas) {
    if (!game.isFpsMode || !game.gameStarted) return;
    super.render(canvas);

    final player = game.player;
    final gameMap = game.gameMap;

    canvas.save(); 

    // --- FPS Mask Swap Camera Shudder ---
    if (player.maskSwapAnimationTimer > 0) {
      double shakeX = sin(player.maskSwapAnimationTimer * 60) * 8.0;
      double shakeY = cos(player.maskSwapAnimationTimer * 50) * 4.0;
      canvas.translate(shakeX, shakeY);
    }
    
    final double fov = pi / 2.4; 
    final double halfFov = fov / 2.0;
    
    final double totalViewAngle = player.facingAngle + player.glanceOffset;
    final Vector2 playerPos = player.position;

    final int screenWidth = size.x.toInt();
    if (screenWidth <= 0) {
      canvas.restore();
      return;
    }
    final double screenHeight = size.y;
    final double focalLength = (screenWidth / 2) / tan(halfFov);

    if (_zBuffer.length != screenWidth) {
      _zBuffer = List<double>.filled(screenWidth, 999999.0);
    } else {
      _zBuffer.fillRange(0, screenWidth, 999999.0);
    }

    // =============================================================
    // 1. FLASHLIGHT THROW DISTANCE TUNING
    // =============================================================
    double maxRayDistance = player.hasExtendedRange ? 420.0 : 280.0;
    maxRayDistance *= player.flashlightScale;

    // -------------------------------------------------------------
    // 1. CEILING AND FLOOR (PITCH BLACK IN THE DISTANCE)
    // -------------------------------------------------------------
    if (player.isInPuzzleRoom) {
      final ceilingRect = Rect.fromLTWH(0, 0, size.x, screenHeight / 2);
      canvas.drawRect(ceilingRect, Paint()..color = const Color(0xFF050000));
      
      double time = game.currentTime();
      if (sin(time * 15) * cos(time * 7) > 0.85) {
        canvas.drawRect(ceilingRect, Paint()..color = Colors.amber[100]!.withOpacity(0.15));
      }
      
      canvas.drawRect(Rect.fromLTWH(0, screenHeight / 2, size.x, screenHeight / 2), Paint()..color = const Color(0xFF090000));
    } else {
      // Pure black horizon at the center line so unhit rays fade into total darkness
      canvas.drawRect(Rect.fromLTWH(0, 0, size.x, screenHeight / 2), Paint()..color = Colors.black);
      canvas.drawRect(Rect.fromLTWH(0, screenHeight / 2, size.x, screenHeight / 2), Paint()..color = const Color(0xFF060609));
    }

    // -------------------------------------------------------------
    // 2. RAYCAST WALLS & STRICT FLASHLIGHT FALLOFF
    // -------------------------------------------------------------
    String currentSkin = player.equippedWallSkin;
    bool isVoidSkin = currentSkin == 'wall_void';

    const int stripWidth = 2; 
    final double tileSize = gameMap.tileSize;
    final int gridWidth = gameMap.gridWidth;
    final int gridHeight = gameMap.gridHeight;
    final mapGrid = gameMap.mapGrid;

    for (int x = 0; x < screenWidth; x += stripWidth) {
      double rayAngle = (totalViewAngle - halfFov) + (x / screenWidth) * fov;
      double dirX = sin(rayAngle);
      double dirY = -cos(rayAngle);

      double dist = 0.0;
      bool hitWall = false;
      double impactX = playerPos.x;
      double impactY = playerPos.y;
      int hitGridValue = 1;

      while (!hitWall && dist < maxRayDistance) {
        dist += 4.0;
        impactX = playerPos.x + dirX * dist;
        impactY = playerPos.y + dirY * dist;
        int gridX = (impactX / tileSize).floor();
        int gridY = (impactY / tileSize).floor();

        if (gridX < 0 || gridX >= gridWidth || gridY < 0 || gridY >= gridHeight) {
          hitWall = true;
        } else {
          int cell = mapGrid[gridY][gridX];
          if (cell > 0) {
            hitWall = true;
            hitGridValue = cell;
          }
        }
      }

      // FIXED: If the flashlight beam didn't hit a wall within range, draw NOTHING!
      // Leaving _zBuffer at 999999.0 and skipping drawRect lets distant hallways stay pitch black.
      if (!hitWall || maxRayDistance <= 1.0) {
        continue;
      }

      double correctedDist = dist * cos(rayAngle - totalViewAngle);
      if (correctedDist < 1.0) correctedDist = 1.0;

      for (int w = 0; w < stripWidth; w++) {
        if (x + w < screenWidth) _zBuffer[x + w] = correctedDist;
      }

      double wallHeight = min(screenHeight * 2.5, (tileSize * focalLength) / correctedDist);
      double wallTop = (screenHeight - wallHeight) / 2;

      // FIXED: Use raw radial 'dist' (not fisheye-shortened correctedDist) and clamp down to 0.0 
      // with a 1.5 power curve so walls fade completely into pitch black at maxRayDistance!
      double linearFade = (1.0 - (dist / maxRayDistance)).clamp(0.0, 1.0);
      double fadeFactor = pow(linearFade, 1.5).toDouble();
      int brightness = (255 * fadeFactor).round().clamp(0, 255);

      if (brightness <= 1 && !isVoidSkin) {
        continue; // Completely dark, skip drawing
      }
      
      double hitX = impactX % tileSize;
      double hitY = impactY % tileSize;
      bool isTileEdge = (hitX < 3.0 || hitX > tileSize - 3.0) || 
                        (hitY < 3.0 || hitY > tileSize - 3.0);

      Color wallColor;
      if (isVoidSkin) {
        wallColor = Colors.black;
      } else if (hitGridValue == 4) {
        wallColor = Color.fromARGB(255, brightness, (brightness * 0.85).toInt(), (brightness * 0.2).toInt());
      } else if (hitGridValue == 3) {
        wallColor = isTileEdge 
          ? Color.fromARGB(255, (brightness * 0.2).toInt(), (brightness * 0.1).toInt(), 0)
          : Color.fromARGB(255, (brightness * 0.4).toInt(), (brightness * 0.25).toInt(), (brightness * 0.1).toInt());
      } else if (hitGridValue == 2) {
        wallColor = isTileEdge 
          ? Color.fromARGB(255, (brightness * 0.3).toInt(), 0, 0)
          : Color.fromARGB(255, (brightness * 0.7).toInt(), (brightness * 0.1).toInt(), (brightness * 0.1).toInt());
      } else {
        wallColor = isTileEdge 
          ? Color.fromARGB(255, (brightness * 0.2).toInt(), (brightness * 0.1).toInt(), (brightness * 0.5).toInt())
          : Color.fromARGB(255, (brightness * 0.45).toInt(), (brightness * 0.2).toInt(), brightness);
      }

      if (!isVoidSkin) {
        bool isNearCorner = (hitX < 4.0 || hitX > tileSize - 4.0) &&
                            (hitY < 4.0 || hitY > tileSize - 4.0);
        if (isNearCorner) {
          wallColor = Color.fromARGB(
            wallColor.alpha,
            (wallColor.red * 0.6).toInt(),
            (wallColor.green * 0.6).toInt(),
            (wallColor.blue * 0.6).toInt(),
          );
        }

        if (correctedDist < 32.0) {
          double proxFactor = (correctedDist / 32.0).clamp(0.4, 1.0);
          wallColor = Color.fromARGB(
            wallColor.alpha,
            (wallColor.red * proxFactor).toInt(),
            (wallColor.green * proxFactor).toInt(),
            (wallColor.blue * proxFactor).toInt(),
          );
        }
      }

      _wallPaint.color = wallColor;
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), wallTop, stripWidth.toDouble(), wallHeight),
        _wallPaint,
      );

      if (isVoidSkin) {
        double glowHeight = 4.0;
        double glowY = wallTop + wallHeight - glowHeight;
        _wallPaint.color = Colors.purpleAccent.withOpacity(0.5 * fadeFactor);
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), glowY, stripWidth.toDouble(), glowHeight),
          _wallPaint,
        );
      } else if (fadeFactor > 0.08) {
        // FIXED: Scale brick & mortar opacity with fadeFactor so they disappear into darkness
        _brickLinePaint.color = Color.fromARGB((115 * fadeFactor).toInt(), 0, 0, 0);
        double brickHeight = wallHeight / 6.0;
        for (int b = 1; b < 6; b++) {
          double lineY = wallTop + (b * brickHeight);
          canvas.drawRect(
            Rect.fromLTWH(x.toDouble(), lineY, stripWidth.toDouble(), 1.5),
            _brickLinePaint,
          );
        }

        _mortarLinePaint.color = Color.fromARGB((96 * fadeFactor).toInt(), 0, 0, 0);
        double mortarY = wallTop + (wallHeight * 0.5);
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), mortarY, stripWidth.toDouble(), 2.0),
          _mortarLinePaint,
        );
      }
    }

    // -------------------------------------------------------------
    // 3. PROJECT BILLBOARDS (SINGLE-PASS WORLD SCAN)
    // -------------------------------------------------------------
    List<_RenderableEntity> entities = [];
    final double maxDistSq = maxRayDistance * maxRayDistance;

    for (var bot in game.bots) {
      if (!bot.isInvisible && bot.position.distanceToSquared(playerPos) <= maxDistSq) {
        entities.add(_RenderableEntity(pos: bot.position, component: bot));
      }
    }
    for (var remote in game.networkPlayers.values) {
      if (!remote.isInvisible && remote.position.distanceToSquared(playerPos) <= maxDistSq) {
        entities.add(_RenderableEntity(pos: remote.position, component: remote));
      }
      for (var siren in remote.children.whereType<SirenBlast>()) {
        entities.add(_RenderableEntity(pos: remote.position, component: siren));
      }
    }
    for (var critter in game.scareManager.critters) {
      if (!critter.isDead && critter.position.distanceToSquared(playerPos) <= maxDistSq) {
        entities.add(_RenderableEntity(pos: critter.position, component: critter));
      }
    }

    // FIXED: Single pass over world.children instead of 7 separate .whereType<T>() scans!
    for (final child in game.world.children) {
      if (child is WallComponent || child is Player || child is BotPlayer || child is RemotePlayer) {
        continue;
      }
      if (child is SpookyBox && child.isMounted && !child.isRemoving) {
        if (child.position.distanceToSquared(playerPos) <= maxDistSq) {
          entities.add(_RenderableEntity(pos: child.position, component: child));
        }
      } else if (child is PowerUp && child.isMounted && !child.isRemoving) {
        if (child.position.distanceToSquared(playerPos) <= maxDistSq) {
          entities.add(_RenderableEntity(pos: child.position, component: child));
        }
      } else if (child is FlyingScareBlast && !child.isDead) {
        entities.add(_RenderableEntity(pos: child.position, component: child));
      } else if (child is ScareBlast) {
        entities.add(_RenderableEntity(pos: child.position, component: child));
      } else if (child is SirenBlast) {
        entities.add(_RenderableEntity(pos: child.position, component: child));
      } else if (child is WendigoDecoy) {
        entities.add(_RenderableEntity(pos: child.position, component: child));
      } else if (child is PoltergeistTrap) {
        entities.add(_RenderableEntity(pos: child.position, component: child));
      } else if (child is CosmeticTrailParticle) {
        if (child.position.distanceToSquared(playerPos) <= maxDistSq) {
          entities.add(_RenderableEntity(pos: child.position, component: child));
        }
      }
    }

    // Check local player children directly
    for (var siren in player.children.whereType<SirenBlast>()) {
      entities.add(_RenderableEntity(pos: player.position, component: siren));
    }

    entities.sort((a, b) => b.pos.distanceToSquared(playerPos).compareTo(a.pos.distanceToSquared(playerPos)));

    final Vector2 forwardDir = Vector2(sin(totalViewAngle), -cos(totalViewAngle));
    final Vector2 rightDir = Vector2(cos(totalViewAngle), sin(totalViewAngle));

    for (var entity in entities) {
      Vector2 relPos = entity.pos - playerPos;

      double camY = relPos.dot(forwardDir);
      double camX = relPos.dot(rightDir);

      if (camY <= 5.0 || camY > maxRayDistance) continue;

      double entityAngle = atan2(camX, camY);
      double screenX = (screenWidth / 2) + tan(entityAngle) * focalLength;

      double scale = focalLength / camY;
      double projectedWidth = 48.0 * scale; 

      int centerCol = screenX.toInt().clamp(0, screenWidth - 1);
      int leftCol = (screenX - (projectedWidth / 2)).toInt().clamp(0, screenWidth - 1);
      int rightCol = (screenX + (projectedWidth / 2)).toInt().clamp(0, screenWidth - 1);

      if (camY > _zBuffer[centerCol] && camY > _zBuffer[leftCol] && camY > _zBuffer[rightCol]) {
        continue; 
      }

      double renderY = screenHeight / 2;
      double wallHeightAtDist = min(screenHeight * 2.5, (tileSize * focalLength) / camY);

      if (entity.component is FlyingScareBlast) {
        renderY -= (wallHeightAtDist * 0.75);
      } else if (entity.component is Critter) {
        renderY += (wallHeightAtDist * 0.38);
      } else if (entity.component is PoltergeistTrap || entity.component is CosmeticTrailParticle) {
        // Push traps and footstep trail embers down onto the 3D floor!
        renderY += (wallHeightAtDist * 0.45); 
      }

      canvas.save();
      canvas.translate(screenX, renderY);
      canvas.scale(scale * 0.5, scale * 0.5);

      // --- TEAM AURA VIGNETTE FOR BILLBOARD CHARACTERS (ONLY IN 2v2) ---
      if (game.matchMode == '2v2' && (entity.component is BotPlayer || entity.component is RemotePlayer)) {
        int entityTeam = game.getEntityTeam(entity.component);
        if (entityTeam != 0) {
          Color teamColor = entityTeam == 1 ? const Color(0xFF0072B2) : const Color(0xFFE69F00);
          canvas.drawCircle(
            Offset.zero, 
            36, 
            Paint()..color = teamColor.withOpacity(0.35),
          );
        }
      }

      if (entity.component is BotPlayer) {
        (entity.component as BotPlayer).voxelComponent?.render(canvas);
      } else if (entity.component is RemotePlayer) {
        (entity.component as RemotePlayer).voxelComponent?.render(canvas);
      } else if (entity.component is WendigoDecoy) {
        (entity.component as WendigoDecoy).voxel?.render(canvas);
      } else if (entity.component is PoltergeistTrap) {
        final trap = entity.component as PoltergeistTrap;
        if (trap.sprite != null) {
          trap.sprite!.render(canvas, size: Vector2(48, 48), position: Vector2(-24, -24));
        }
      } else if (entity.component is CosmeticTrailParticle) {
        final trail = entity.component as CosmeticTrailParticle;
        final double alpha = (trail.life / CosmeticTrailParticle.maxLife).clamp(0.0, 1.0);
        final bool isAsh = trail.spritePath.contains('ash');
        final Color glowColor = isAsh ? Colors.deepOrangeAccent : Colors.cyanAccent;

        // Draw glowing 3D floor ember / soul wisp
        canvas.drawOval(
          const Rect.fromLTWH(-14, -6, 28, 12),
          Paint()..color = glowColor.withOpacity(alpha * 0.45),
        );
        if (trail.sprite != null) {
          trail.sprite!.render(
            canvas,
            size: Vector2(24, 24),
            position: Vector2(-12, -12),
            overridePaint: Paint()..color = Colors.white.withOpacity(alpha),
          );
        } else {
          canvas.drawCircle(Offset.zero, 6, Paint()..color = Colors.amberAccent.withOpacity(alpha));
        }
      } else if (entity.component is SpookyBox) {
        final boxPaint = Paint()..color = const Color(0xFF8B4513); 
        final lidPaint = Paint()..color = const Color(0xFFA0522D); 
        final lockPaint = Paint()..color = Colors.amberAccent;      

        canvas.drawRect(const Rect.fromLTWH(-20, -10, 40, 28), boxPaint);
        canvas.drawRect(const Rect.fromLTWH(-22, -22, 44, 12), lidPaint);
        canvas.drawCircle(const Offset(0, 2), 5, lockPaint);
      } else if (entity.component is PowerUp) {
        canvas.drawCircle(Offset.zero, 16, Paint()..color = Colors.yellowAccent);
        canvas.drawCircle(Offset.zero, 8, Paint()..color = Colors.white);
      } else if (entity.component is FlyingScareBlast) {
        final bat = entity.component as FlyingScareBlast;
        double flap = sin(bat.lifeTimer * 30);
        
        final path = Path();
        path.addOval(const Rect.fromLTWH(-8, -12, 16, 24));
        
        path.moveTo(-6, -6);
        path.quadraticBezierTo(-25, flap * -25 - 15, -45, flap * 15 - 8);
        path.quadraticBezierTo(-25, flap * 15 + 8, -3, 9);
        
        path.moveTo(6, -6);
        path.quadraticBezierTo(25, flap * -25 - 15, 45, flap * 15 - 8);
        path.quadraticBezierTo(25, flap * 15 + 8, 3, 9);

        canvas.drawPath(path, Paint()..color = Colors.purpleAccent.withOpacity(0.9));
        canvas.drawPath(path, Paint()..color = Colors.cyanAccent..style = PaintingStyle.stroke..strokeWidth = 2.0);
      } else if (entity.component is Critter) {
        final critter = entity.component as Critter;
        double dotRight = critter.velocity.dot(rightDir);
        if (dotRight < 0) {
          canvas.scale(-1.0, 1.0); 
        }

        double wiggle = sin(critter.lifeTimer * 40) * 4.0;

        final bodyPaint = Paint()..color = const Color(0xFF5A5A66);
        final eyePaint = Paint()..color = Colors.redAccent;
        final appendagePaint = Paint()
          ..color = const Color(0xFF888899)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;

        canvas.drawOval(const Rect.fromLTWH(-10, -5, 20, 10), bodyPaint);
        canvas.drawCircle(const Offset(6, -2), 1.5, eyePaint);

        final tailPath = Path()
          ..moveTo(-10, 0)
          ..quadraticBezierTo(-18, wiggle, -25, -wiggle * 0.5);
        canvas.drawPath(tailPath, appendagePaint);

        canvas.drawLine(const Offset(-5, 4), Offset(-5 + wiggle, 9), appendagePaint);
        canvas.drawLine(const Offset(5, 4), Offset(5 - wiggle, 9), appendagePaint);
      } else if (entity.component is ScareBlast) {
        final blastPaint = Paint()..color = Colors.white.withOpacity(0.7);
        canvas.drawArc(const Rect.fromLTWH(-120, -120, 240, 240), -pi / 2, pi, true, blastPaint);
      } else if (entity.component is SirenBlast) {
        final siren = entity.component as SirenBlast;
        double fade = siren.lifeTimer > 2.0 ? 1.0 : (siren.lifeTimer / 2.0);
        int alpha = (fade * 180).toInt().clamp(0, 255);

        final washPaint = Paint()
          ..color = Colors.pinkAccent.withAlpha(alpha)
          ..style = PaintingStyle.fill;
        canvas.drawArc(const Rect.fromLTWH(-180, -180, 360, 360), -pi / 2, pi, true, washPaint);

        final ripplePaint = Paint()
          ..color = Colors.white.withAlpha(alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0;

        for (int i = 0; i < 3; i++) {
          double wavePhase = ((15.0 - siren.lifeTimer) * 2 + (i * 0.33)) % 1.0;
          double rippleRadius = wavePhase * 180.0;
          canvas.drawArc(
            Rect.fromCircle(center: Offset.zero, radius: rippleRadius), 
            -pi / 2, 
            pi, 
            false, 
            ripplePaint
          );
        }
      }
      canvas.restore();
    }

    // -------------------------------------------------------------
    // 4. ATTACK FLASH & FLASHLIGHT SPOTLIGHT
    // -------------------------------------------------------------
    if (player.starAnimTimer > 0) {
      canvas.save();
      canvas.translate(size.x / 2, size.y * 0.25); 
      double time = DateTime.now().millisecondsSinceEpoch / 200.0;
      for (int i = 0; i < 3; i++) {
        double angle = time + (i * (2 * pi / 3));
        double starX = cos(angle) * 45.0; 
        double starY = sin(angle) * 12.0;
        canvas.drawCircle(Offset(starX, starY), 6.0, Paint()..color = Colors.yellowAccent);
      }
      canvas.restore();
    }

    final localSiren = player.children.whereType<SirenBlast>().firstOrNull;
    if (localSiren != null) {
      double fade = localSiren.lifeTimer > 2.0 ? 1.0 : (localSiren.lifeTimer / 2.0);
      int alpha = (fade * 60).toInt().clamp(0, 255);
      
      canvas.drawRect(size.toRect(), Paint()..color = Colors.pinkAccent.withAlpha(alpha));

      final strokePaint = Paint()
        ..color = Colors.white.withAlpha((alpha * 2).clamp(0, 255))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0;

      for (int i = 0; i < 3; i++) {
        double wavePhase = ((15.0 - localSiren.lifeTimer) * 2 + (i * 0.33)) % 1.0;
        double rippleRadius = wavePhase * (size.x * 0.9);
        canvas.drawCircle(Offset(size.x / 2, size.y / 2), rippleRadius, strokePaint);
      }
    }

    if (player.attackCooldown > 0.4) {
      final attackPaint = Paint()..color = Colors.redAccent.withOpacity(0.20);
      canvas.drawRect(size.toRect(), attackPaint);
    }

    if (player.isPhasing) {
      final phasePaint = Paint()..color = Colors.cyanAccent.withOpacity(0.20);
      canvas.drawRect(size.toRect(), phasePaint);
    }

    if (player.maskSwapAnimationTimer > 0) {
      double blinkAlpha = (sin(player.maskSwapAnimationTimer * 100).abs() * 1.5).clamp(0.0, 1.0);
      final blinkPaint = Paint()..color = Colors.black.withOpacity(blinkAlpha);
      canvas.drawRect(size.toRect(), blinkPaint);
    }

    double spotRadius = (size.y * 0.45) * player.flashlightScale;
    if (spotRadius > 0) {
      final spotlightPaint = Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.x / 2, size.y / 2),
          spotRadius,
          [Colors.transparent, Colors.black.withOpacity(0.95)],
          [0.7, 1.0],
        );
      canvas.drawRect(size.toRect(), spotlightPaint);
    } else {
      canvas.drawRect(size.toRect(), Paint()..color = Colors.black);
    }

    // -------------------------------------------------------------
    // 5. LOCAL PLAYER 2V2 TEAM HUD VIGNETTE
    // -------------------------------------------------------------
    if (game.matchMode == '2v2') {
      int myTeam = game.getEntityTeam(player);
      Color myTeamColor = myTeam == 1 ? const Color(0xFF0072B2) : const Color(0xFFE69F00);

      final teamEdgePaint = Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.x / 2, size.y),
          size.x * 0.6,
          [myTeamColor.withOpacity(0.25), Colors.transparent],
          [0.0, 1.0],
        );

      canvas.drawRect(Rect.fromLTWH(0, size.y - 60, size.x, 60), teamEdgePaint);
    }

    canvas.restore();
  }
}

class _RenderableEntity {
  final Vector2 pos;
  final DynamicAwareComponent component;
  _RenderableEntity({required this.pos, required dynamic component}) : component = component as DynamicAwareComponent;
}
typedef DynamicAwareComponent = Component;