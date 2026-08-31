import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class MapOverlay extends PositionComponent with HasGameReference<GraveStakesGame> {
  bool isOpen = false;

  MapOverlay() : super(priority: 100000); // Sit on top of HUD

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }

  void toggle() {
    isOpen = !isOpen;
  }

  @override
  void render(Canvas canvas) {
    if (!isOpen) return;

    final gameMap = game.gameMap;
    if (gameMap.maxExploredX < 0) return; // Nothing revealed yet

    // Dark semi-transparent background
    final bgPaint = Paint()..color = Colors.black.withOpacity(0.85);
    canvas.drawRect(size.toRect(), bgPaint);

    // Calculate bounding box for explored area
    int exploredW = max(1, gameMap.maxExploredX - gameMap.minExploredX + 1);
    int exploredH = max(1, gameMap.maxExploredY - gameMap.minExploredY + 1);

    // Leave a 40px margin around screen edges
    double availableWidth = size.x - 80;
    double availableHeight = size.y - 80;

    double cellScale = min(availableWidth / exploredW, availableHeight / exploredH).clamp(4.0, 24.0);

    // Center map on screen
    double mapDrawWidth = exploredW * cellScale;
    double mapDrawHeight = exploredH * cellScale;
    double startX = (size.x - mapDrawWidth) / 2;
    double startY = (size.y - mapDrawHeight) / 2;

    final wallPaint = Paint()..color = Colors.grey[400]!;
    final floorPaint = Paint()..color = Colors.grey[900]!;
    final borderPaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Draw explored tiles
    for (int y = gameMap.minExploredY; y <= gameMap.maxExploredY; y++) {
      for (int x = gameMap.minExploredX; x <= gameMap.maxExploredX; x++) {
        if (!gameMap.visitedGrid[y][x]) continue;

        double drawX = startX + ((x - gameMap.minExploredX) * cellScale);
        double drawY = startY + ((y - gameMap.minExploredY) * cellScale);
        Rect tileRect = Rect.fromLTWH(drawX, drawY, cellScale, cellScale);

        bool isWall = gameMap.mapGrid[y][x] == 1;
        canvas.drawRect(tileRect, isWall ? wallPaint : floorPaint);
      }
    }

    // Draw Player's relative position on map
    int playerGridX = (game.player.position.x / gameMap.tileSize).floor();
    int playerGridY = (game.player.position.y / gameMap.tileSize).floor();

    if (playerGridX >= gameMap.minExploredX && playerGridX <= gameMap.maxExploredX &&
        playerGridY >= gameMap.minExploredY && playerGridY <= gameMap.maxExploredY) {
      double playerDrawX = startX + ((playerGridX - gameMap.minExploredX) * cellScale) + (cellScale / 2);
      double playerDrawY = startY + ((playerGridY - gameMap.minExploredY) * cellScale) + (cellScale / 2);

      final playerMarker = Paint()..color = Colors.redAccent;
      canvas.drawCircle(Offset(playerDrawX, playerDrawY), max(3.0, cellScale / 3), playerMarker);
    }

    // Draw frame around map
    canvas.drawRect(Rect.fromLTWH(startX - 2, startY - 2, mapDrawWidth + 4, mapDrawHeight + 4), borderPaint);
  }
}