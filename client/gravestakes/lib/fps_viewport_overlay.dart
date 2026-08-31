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

class FpsViewportOverlay extends PositionComponent with HasGameReference<GraveStakesGame> {
  FpsViewportOverlay() : super(priority: 10); 

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }

  @override
  void render(Canvas canvas) {
    if (!game.isFpsMode || !game.gameStarted) return;
    super.render(canvas);

    final player = game.player;
    final gameMap = game.gameMap;
    
    // --- WIDER FOV (75 Degrees) ---
    final double fov = pi / 2.4; 
    final double halfFov = fov / 2.0;
    
    final double totalViewAngle = player.facingAngle + player.glanceOffset;
    final Vector2 playerPos = player.position;

    final int screenWidth = size.x.toInt();
    final double screenHeight = size.y;
    final double focalLength = (screenWidth / 2) / tan(halfFov);

    final List<double> zBuffer = List.filled(screenWidth, 999999.0);

    // =============================================================
    // 1. FLASHLIGHT THROW DISTANCE TUNING
    // =============================================================
    double maxRayDistance = player.hasExtendedRange ? 420.0 : 280.0;
    maxRayDistance *= player.flashlightScale;

    // -------------------------------------------------------------
    // CEILING AND FLOOR
    // -------------------------------------------------------------
    canvas.drawRect(Rect.fromLTWH(0, 0, size.x, screenHeight / 2), Paint()..color = const Color(0xFF0A0A10));
    canvas.drawRect(Rect.fromLTWH(0, screenHeight / 2, size.x, screenHeight / 2), Paint()..color = const Color(0xFF14141E));

    // -------------------------------------------------------------
    // 2. RAYCAST WALLS & LIMITED VISIBILITY
    // -------------------------------------------------------------
    int stripWidth = 2; 
    for (int x = 0; x < screenWidth; x += stripWidth) {
      double rayAngle = (totalViewAngle - halfFov) + (x / screenWidth) * fov;
      double cosRay = cos(rayAngle);
      double sinRay = sin(rayAngle);

      double dist = 0.0;
      bool hitWall = false;
      Vector2 impactPos = Vector2.zero();

      while (!hitWall && dist < maxRayDistance) {
        dist += 4.0;
        Vector2 checkPos = playerPos + Vector2(sinRay * dist, -cosRay * dist);
        int gridX = (checkPos.x / gameMap.tileSize).floor();
        int gridY = (checkPos.y / gameMap.tileSize).floor();

        if (gridX < 0 || gridX >= gameMap.gridWidth || gridY < 0 || gridY >= gameMap.gridHeight) {
          hitWall = true;
          impactPos = checkPos;
        } else if (gameMap.mapGrid[gridY][gridX] == 1) {
          hitWall = true;
          impactPos = checkPos;
        }
      }

      double correctedDist = dist * cos(rayAngle - totalViewAngle);
      if (correctedDist < 1.0) correctedDist = 1.0;

      for (int w = 0; w < stripWidth; w++) {
        if (x + w < screenWidth) zBuffer[x + w] = correctedDist;
      }

      double wallHeight = min(screenHeight * 2.5, (gameMap.tileSize * focalLength) / correctedDist);
      double wallTop = (screenHeight - wallHeight) / 2;

      // --- INCREASED AMBIENT FLOOR VISIBILITY ---
      double fadeFactor = (1.0 - (correctedDist / maxRayDistance)).clamp(0.15, 1.0);
      int brightness = (255 * fadeFactor).clamp(10, 255).toInt();
      
      double hitX = impactPos.x % gameMap.tileSize;
      double hitY = impactPos.y % gameMap.tileSize;
      bool isTileEdge = (hitX < 3.0 || hitX > gameMap.tileSize - 3.0) || 
                        (hitY < 3.0 || hitY > gameMap.tileSize - 3.0);

      Color wallColor = isTileEdge 
        ? Color.fromARGB(255, (brightness * 0.2).toInt(), (brightness * 0.1).toInt(), (brightness * 0.5).toInt())
        : Color.fromARGB(255, (brightness * 0.45).toInt(), (brightness * 0.2).toInt(), brightness);

      // --- CORNER SHADOWS ---
      bool isNearCorner = (hitX < 4.0 || hitX > gameMap.tileSize - 4.0) &&
                          (hitY < 4.0 || hitY > gameMap.tileSize - 4.0);
      if (isNearCorner) {
        wallColor = Color.fromARGB(
          wallColor.alpha,
          (wallColor.red * 0.6).toInt(),
          (wallColor.green * 0.6).toInt(),
          (wallColor.blue * 0.6).toInt(),
        );
      }

      // --- NEAR-PLANE FOG (PROXIMITY DARKENING) ---
      if (correctedDist < 32.0) {
        double proxFactor = (correctedDist / 32.0).clamp(0.4, 1.0);
        wallColor = Color.fromARGB(
          wallColor.alpha,
          (wallColor.red * proxFactor).toInt(),
          (wallColor.green * proxFactor).toInt(),
          (wallColor.blue * proxFactor).toInt(),
        );
      }

      // Draw Wall Strip
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), wallTop, stripWidth.toDouble(), wallHeight),
        Paint()..color = wallColor,
      );

      // --- HORIZONTAL BRICK COURSES ---
      double brickHeight = wallHeight / 6.0;
      for (int b = 1; b < 6; b++) {
        double lineY = wallTop + (b * brickHeight);
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), lineY, stripWidth.toDouble(), 1.5),
          Paint()..color = Colors.black45,
        );
      }

      // Original Mortar Center Line
      double mortarY = wallTop + (wallHeight * 0.5);
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), mortarY, stripWidth.toDouble(), 2.0),
        Paint()..color = Colors.black38,
      );
    }

    // -------------------------------------------------------------
    // 3. PROJECT BILLBOARDS WITH CUSTOM HEIGHT OFFSETS
    // -------------------------------------------------------------
    List<_RenderableEntity> entities = [];

    for (var bot in game.bots) {
      entities.add(_RenderableEntity(pos: bot.position, component: bot));
    }
    for (var remote in game.networkPlayers.values) {
      if (!remote.isInvisible) {
        entities.add(_RenderableEntity(pos: remote.position, component: remote));
      }
    }
    for (var box in game.world.children.whereType<SpookyBox>()) {
      if (box.isMounted && !box.isRemoving) {
        entities.add(_RenderableEntity(pos: box.position, component: box));
      }
    }
    for (var powerup in game.world.children.whereType<PowerUp>()) {
      if (powerup.isMounted && !powerup.isRemoving) {
        entities.add(_RenderableEntity(pos: powerup.position, component: powerup));
      }
    }
    for (var bat in game.scareManager.bats) {
      if (!bat.isDead) entities.add(_RenderableEntity(pos: bat.position, component: bat));
    }
    for (var critter in game.scareManager.critters) {
      if (!critter.isDead) entities.add(_RenderableEntity(pos: critter.position, component: critter));
    }
    for (var blast in game.world.children.whereType<ScareBlast>()) {
      entities.add(_RenderableEntity(pos: blast.position, component: blast));
    }
    for (var siren in game.world.children.whereType<SirenBlast>()) {
      entities.add(_RenderableEntity(pos: siren.position, component: siren));
    }
    for (var playerComp in game.children.whereType<Player>()) {
      for (var siren in playerComp.children.whereType<SirenBlast>()) {
        entities.add(_RenderableEntity(pos: playerComp.position, component: siren));
      }
    }
    for (var remoteComp in game.networkPlayers.values) {
      for (var siren in remoteComp.children.whereType<SirenBlast>()) {
        entities.add(_RenderableEntity(pos: remoteComp.position, component: siren));
      }
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

      if (camY > zBuffer[centerCol] && camY > zBuffer[leftCol] && camY > zBuffer[rightCol]) {
        continue; 
      }

      double renderY = screenHeight / 2;
      double wallHeightAtDist = min(screenHeight * 2.5, (gameMap.tileSize * focalLength) / camY);

      if (entity.component is FlyingScareBlast) {
        renderY -= (wallHeightAtDist * 0.42);
      } else if (entity.component is Critter) {
        renderY += (wallHeightAtDist * 0.38);
      }

      canvas.save();
      canvas.translate(screenX, renderY);
      canvas.scale(scale * 0.5, scale * 0.5);

      // --- TEAM AURA VIGNETTE FOR BILLBOARD CHARACTERS ---
      if (entity.component is BotPlayer || entity.component is RemotePlayer) {
        int entityTeam = game.getEntityTeam(entity.component);
        Color teamColor = entityTeam == 1 ? const Color(0xFF0072B2) : const Color(0xFFE69F00);

        canvas.drawCircle(
          Offset.zero, 
          36, 
          Paint()
            ..color = teamColor.withOpacity(0.45)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12)
        );
      }

      if (entity.component is BotPlayer) {
        (entity.component as BotPlayer).voxelComponent?.render(canvas);
      } else if (entity.component is RemotePlayer) {
        (entity.component as RemotePlayer).voxelComponent?.render(canvas);
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
        canvas.drawCircle(Offset.zero, 24, Paint()..color = Colors.purpleAccent.withOpacity(0.9));
        canvas.drawCircle(Offset.zero, 12, Paint()..color = Colors.white);
      } else if (entity.component is Critter) {
        canvas.drawCircle(Offset.zero, 5, Paint()..color = Colors.greenAccent);
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
    if (player.attackCooldown > 0.4) {
      final attackPaint = Paint()..color = Colors.redAccent.withOpacity(0.20);
      canvas.drawRect(size.toRect(), attackPaint);
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
  }
}

class _RenderableEntity {
  final Vector2 pos;
  final DynamicAwareComponent component;
  _RenderableEntity({required this.pos, required dynamic component}) : component = component as DynamicAwareComponent;
}
typedef DynamicAwareComponent = Component;