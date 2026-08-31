import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flutter/material.dart' hide Image;
import 'game.dart';
import 'bot_player.dart';
import 'remote_player.dart';
import 'spooky_box.dart';
import 'power_up.dart';

class FpsViewportOverlay extends PositionComponent with HasGameReference<GraveStakesGame> {
  // Sit beneath HUD (priority 200) but above 2D map
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
    
    final double fov = pi / 3.0; // 60-degree FOV
    final double halfFov = fov / 2.0;
    final double playerAngle = player.facingAngle;
    final Vector2 playerPos = player.position;

    final int screenWidth = size.x.toInt();
    final double screenHeight = size.y;
    final double focalLength = (screenWidth / 2) / tan(halfFov);

    // Z-Buffer array to track wall depth for every screen column
    final List<double> zBuffer = List.filled(screenWidth, 999999.0);

    // -------------------------------------------------------------
    // 1. CEILING AND FLOOR
    // -------------------------------------------------------------
    canvas.drawRect(Rect.fromLTWH(0, 0, size.x, screenHeight / 2), Paint()..color = const Color(0xFF0A0A10));
    canvas.drawRect(Rect.fromLTWH(0, screenHeight / 2, size.x, screenHeight / 2), Paint()..color = const Color(0xFF14141E));

    // -------------------------------------------------------------
    // 2. RAYCAST WALLS & POPULATE Z-BUFFER (WITH PROCEDURAL TEXTURE)
    // -------------------------------------------------------------
    int stripWidth = 2; // Ray column width
    for (int x = 0; x < screenWidth; x += stripWidth) {
      double rayAngle = (playerAngle - halfFov) + (x / screenWidth) * fov;
      double cosRay = cos(rayAngle);
      double sinRay = sin(rayAngle);

      double dist = 0.0;
      bool hitWall = false;
      Vector2 impactPos = Vector2.zero();

      while (!hitWall && dist < 1600.0) {
        dist += 4.0; // Finer ray step for sharp texture alignment
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

      // Fisheye correction relative to player heading
      double correctedDist = dist * cos(rayAngle - playerAngle);
      if (correctedDist < 1.0) correctedDist = 1.0;

      // Store true distance in Z-Buffer across column width
      for (int w = 0; w < stripWidth; w++) {
        if (x + w < screenWidth) zBuffer[x + w] = correctedDist;
      }

      double wallHeight = min(screenHeight * 2.5, (gameMap.tileSize * focalLength) / correctedDist);
      double wallTop = (screenHeight - wallHeight) / 2;

      // Base shading based on distance
      int brightness = (255 - (correctedDist * 0.18)).clamp(15, 255).toInt();
      
      // Calculate tile edge for vertical seam (X or Y impact depending on wall face)
      double hitX = impactPos.x % gameMap.tileSize;
      double hitY = impactPos.y % gameMap.tileSize;
      bool isTileEdge = (hitX < 3.0 || hitX > gameMap.tileSize - 3.0) || 
                        (hitY < 3.0 || hitY > gameMap.tileSize - 3.0);

      // Darken vertical tile borders and horizontal mortar lines
      Color wallColor;
      if (isTileEdge) {
        // Vertical tile seam
        wallColor = Color.fromARGB(255, (brightness * 0.2).toInt(), (brightness * 0.1).toInt(), (brightness * 0.5).toInt());
      } else {
        // Standard purple wall face
        wallColor = Color.fromARGB(255, (brightness * 0.45).toInt(), (brightness * 0.2).toInt(), brightness);
      }

      final wallPaint = Paint()..color = wallColor;

      // Draw the main wall slice
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), wallTop, stripWidth.toDouble(), wallHeight),
        wallPaint,
      );

      // Draw a subtle horizontal mortar line across the middle of every wall block
      final mortarPaint = Paint()..color = Colors.black38;
      double mortarY = wallTop + (wallHeight * 0.5);
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), mortarY, stripWidth.toDouble(), 2.0),
        mortarPaint,
      );
    }

    // -------------------------------------------------------------
    // 3. PROJECT & RENDER BILLBOARDS WITH ACCURATE TANGENT MATH
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
      entities.add(_RenderableEntity(pos: box.position, component: box));
    }
    for (var powerup in game.world.children.whereType<PowerUp>()) {
      entities.add(_RenderableEntity(pos: powerup.position, component: powerup));
    }

    // Far-to-Near sorting
    entities.sort((a, b) => b.pos.distanceToSquared(playerPos).compareTo(a.pos.distanceToSquared(playerPos)));

    for (var entity in entities) {
      Vector2 relPos = entity.pos - playerPos;

      // Transform world coordinates into view-space coordinates
      double cosP = cos(-playerAngle);
      double sinP = sin(-playerAngle);
      double camX = relPos.x * cosP - relPos.y * sinP;
      double camY = relPos.x * sinP + relPos.y * cosP;

      if (camY <= 10.0) continue; // Behind camera

      // Angular calculation guarantees 1:1 rotational alignment with raycast walls
      double entityAngle = atan2(camX, camY);
      double screenX = (screenWidth / 2) + tan(entityAngle) * focalLength;

      double scale = focalLength / camY;
      double projectedWidth = 48.0 * scale; 

      int leftCol = (screenX - (projectedWidth / 2)).toInt().clamp(0, screenWidth - 1);
      int rightCol = (screenX + (projectedWidth / 2)).toInt().clamp(0, screenWidth - 1);

      // OCCLUSION CHECK: Only draw if the entity is CLOSER than the wall at its center & edges
      int centerCol = screenX.toInt().clamp(0, screenWidth - 1);
      if (camY > zBuffer[centerCol] && camY > zBuffer[leftCol] && camY > zBuffer[rightCol]) {
        continue; // Fully occluded behind a wall!
      }

      canvas.save();
      canvas.translate(screenX, screenHeight / 2);
      canvas.scale(scale * 0.5, scale * 0.5);

      if (entity.component is BotPlayer) {
        final bot = entity.component as BotPlayer;
        bot.voxelComponent?.render(canvas);
      } else if (entity.component is RemotePlayer) {
        final remote = entity.component as RemotePlayer;
        remote.voxelComponent?.render(canvas);
      } else if (entity.component is SpookyBox) {
        final boxPaint = Paint()..color = Colors.amberAccent;
        canvas.drawRect(const Rect.fromLTWH(-16, -16, 32, 32), boxPaint);
      } else if (entity.component is PowerUp) {
        final powerupPaint = Paint()..color = Colors.yellowAccent;
        canvas.drawCircle(Offset.zero, 12, powerupPaint);
      }
      canvas.restore();
    }

    // -------------------------------------------------------------
    // 4. SPOTLIGHT & FLASHLIGHT OVERLAY
    // -------------------------------------------------------------
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