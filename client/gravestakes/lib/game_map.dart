import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class GameMap extends Component {
  final List<Rect> walls = [
    // --- Outer Boundaries (Larger 1600x1600 complex) ---
    Rect.fromLTWH(-800, -800, 1600, 40), // Top wall
    Rect.fromLTWH(-800, 760, 1600, 40),  // Bottom wall
    Rect.fromLTWH(-800, -800, 40, 1600), // Left wall
    Rect.fromLTWH(760, -800, 40, 1600),  // Right wall

    // --- Interior Room Dividers & Corridors ---
    // Room 1 / Room 2 dividing wall (with a gap/doorway in the middle)
    Rect.fromLTWH(-800, -200, 550, 30), // Left side of wall
    Rect.fromLTWH(-50, -200, 600, 30),  // Right side of wall (leaving a 150px doorway)

    // Room 3 / Room 4 dividing wall (with a doorway on the left)
    Rect.fromLTWH(-300, 300, 1060, 30), 

    // Central Crypt Pillars / Obstacles
    Rect.fromLTWH(-400, -550, 120, 120),
    Rect.fromLTWH(300, -550, 120, 120),
    Rect.fromLTWH(-400, 450, 120, 120),
    Rect.fromLTWH(300, 450, 120, 120),
  ];

  final Paint wallPaint = Paint()..color = const Color(0xFF2a2a38);
  final Paint floorPaint = Paint()..color = const Color(0xFF0d0d12);

  @override
  void render(Canvas canvas) {
    final backgroundRect = Rect.fromLTWH(-800, -800, 1600, 1600);
    canvas.drawRect(backgroundRect, floorPaint);

    for (var wall in walls) {
      canvas.drawRect(wall, wallPaint);
    }
  }

  bool checkCollision(Vector2 futurePosition, Vector2 size) {
    final playerRect = Rect.fromCenter(
      center: futurePosition.toOffset(),
      width: size.x,
      height: size.y,
    );

    for (var wall in walls) {
      if (wall.overlaps(playerRect)) {
        return true;
      }
    }
    return false;
  }
}