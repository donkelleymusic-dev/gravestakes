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
    
    final double fov = pi / 3.0; 
    final double halfFov = fov / 2.0;
    
    // Include the peek/glance offset directly in the camera angle
    final double totalViewAngle = player.facingAngle + player.glanceOffset;
    final Vector2 playerPos = player.position;

    final int screenWidth = size.x.toInt();
    final double screenHeight = size.y;
    final double focalLength = (screenWidth / 2) / tan(halfFov);

    final List<double> zBuffer = List.filled(screenWidth, 999999.0);

    // -------------------------------------------------------------
    // 1. CEILING AND FLOOR
    // -------------------------------------------------------------
    canvas.drawRect(Rect.fromLTWH(0, 0, size.x, screenHeight / 2), Paint()..color = const Color(0xFF0A0A10));
    canvas.drawRect(Rect.fromLTWH(0, screenHeight / 2, size.x, screenHeight / 2), Paint()..color = const Color(0xFF14141E));

    // -------------------------------------------------------------
    // 2. RAYCAST WALLS & Z-BUFFER (INCLUDES GLANCE ANGLE)
    // -------------------------------------------------------------
    int stripWidth = 2; 
    for (int x = 0; x < screenWidth; x += stripWidth) {
      double rayAngle = (totalViewAngle - halfFov) + (x / screenWidth) * fov;
      double cosRay = cos(rayAngle);
      double sinRay = sin(rayAngle);

      double dist = 0.0;
      bool hitWall = false;
      Vector2 impactPos = Vector2.zero();

      while (!hitWall && dist < 1600.0) {
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

      int brightness = (255 - (correctedDist * 0.18)).clamp(15, 255).toInt();
      
      double hitX = impactPos.x % gameMap.tileSize;
      double hitY = impactPos.y % gameMap.tileSize;
      bool isTileEdge = (hitX < 3.0 || hitX > gameMap.tileSize - 3.0) || 
                        (hitY < 3.0 || hitY > gameMap.tileSize - 3.0);

      Color wallColor = isTileEdge 
        ? Color.fromARGB(255, (brightness * 0.2).toInt(), (brightness * 0.1).toInt(), (brightness * 0.5).toInt())
        : Color.fromARGB(255, (brightness * 0.45).toInt(), (brightness * 0.2).toInt(), brightness);

      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), wallTop, stripWidth.toDouble(), wallHeight),
        Paint()..color = wallColor,
      );

      double mortarY = wallTop + (wallHeight * 0.5);
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), mortarY, stripWidth.toDouble(), 2.0),
        Paint()..color = Colors.black38,
      );
    }

    // -------------------------------------------------------------
    // 3. PROJECT BILLBOARDS (FIXED DEPTH & ROTATION MATRIX)
    // -------------------------------------------------------------
    List<_RenderableEntity> entities = [];

    // Players and Bots
    for (var bot in game.bots) {
      entities.add(_RenderableEntity(pos: bot.position, component: bot));
    }
    for (var remote in game.networkPlayers.values) {
      if (!remote.isInvisible) {
        entities.add(_RenderableEntity(pos: remote.position, component: remote));
      }
    }
    // Items
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
    // Projectiles and Swarms
    for (var bat in game.scareManager.bats) {
      if (!bat.isDead) entities.add(_RenderableEntity(pos: bat.position, component: bat));
    }
    for (var critter in game.scareManager.critters) {
      if (!critter.isDead) entities.add(_RenderableEntity(pos: critter.position, component: critter));
    }
    // Flash Blast and Siren Arc Effects
    for (var blast in game.world.children.whereType<ScareBlast>()) {
      entities.add(_RenderableEntity(pos: blast.position, component: blast));
    }
    for (var siren in game.world.children.whereType<SirenBlast>()) {
      entities.add(_RenderableEntity(pos: siren.position, component: siren));
    }

    // Far-to-Near Sorting
    entities.sort((a, b) => b.pos.distanceToSquared(playerPos).compareTo(a.pos.distanceToSquared(playerPos)));

    final double cosView = cos(totalViewAngle);
    final double sinView = sin(totalViewAngle);

    for (var entity in entities) {
      Vector2 relPos = entity.pos - playerPos;

      // FIXED CAMERA SPACE TRANSFORM:
      // CamX = lateral offset (left/right)
      // CamY = forward depth distance in front of player
      double camX = relPos.x * cosView + relPos.y * sinView;
      double camY = -relPos.x * sinView + relPos.y * cosView;

      if (camY <= 5.0) continue; // Item is behind or right on top of camera

      double entityAngle = atan2(camX, camY);
      double screenX = (screenWidth / 2) + tan(entityAngle) * focalLength;

      double scale = focalLength / camY;
      double projectedWidth = 48.0 * scale; 

      int centerCol = screenX.toInt().clamp(0, screenWidth - 1);
      int leftCol = (screenX - (projectedWidth / 2)).toInt().clamp(0, screenWidth - 1);
      int rightCol = (screenX + (projectedWidth / 2)).toInt().clamp(0, screenWidth - 1);

      // Occlusion check against walls
      if (camY > zBuffer[centerCol] && camY > zBuffer[leftCol] && camY > zBuffer[rightCol]) {
        continue; 
      }

      canvas.save();
      canvas.translate(screenX, screenHeight / 2);
      canvas.scale(scale * 0.5, scale * 0.5);

      if (entity.component is BotPlayer) {
        (entity.component as BotPlayer).voxelComponent?.render(canvas);
      } else if (entity.component is RemotePlayer) {
        (entity.component as RemotePlayer).voxelComponent?.render(canvas);
      } else if (entity.component is SpookyBox) {
        // 3D Chest Container
        final boxPaint = Paint()..color = const Color(0xFF8B4513); // Saddle Brown
        final lidPaint = Paint()..color = const Color(0xFFA0522D); // Sienna Lid
        final lockPaint = Paint()..color = Colors.amberAccent;      // Gold Lock

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
        canvas.drawCircle(Offset.zero, 12, Paint()..color = Colors.greenAccent);
      } else if (entity.component is ScareBlast) {
        final blastPaint = Paint()..color = Colors.white.withOpacity(0.7);
        canvas.drawArc(const Rect.fromLTWH(-120, -120, 240, 240), -pi / 2, pi, true, blastPaint);
      } else if (entity.component is SirenBlast) {
        final sirenPaint = Paint()..color = Colors.pinkAccent.withOpacity(0.6);
        canvas.drawArc(const Rect.fromLTWH(-200, -200, 400, 400), -pi / 2, pi, true, sirenPaint);
      }
      canvas.restore();
    }

    // -------------------------------------------------------------
    // 4. ATTACK MUZZLE FLASH & FLASHLIGHT SPOTLIGHT
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
  }
}

class _RenderableEntity {
  final Vector2 pos;
  final DynamicAwareComponent component;
  _RenderableEntity({required this.pos, required dynamic component}) : component = component as DynamicAwareComponent;
}
typedef DynamicAwareComponent = Component;