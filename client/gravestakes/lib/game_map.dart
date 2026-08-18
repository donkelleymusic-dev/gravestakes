import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame_tiled/flame_tiled.dart';
import 'package:flutter/material.dart' hide Image;

class GameMap extends Component {
  final String roomId;
  late TiledComponent tiledMap;
  final List<Rect> obstacles = [];

  GameMap({required this.roomId});

  @override
  Future<void> onLoad() async {
    // 1. Load the Tiled map from assets/tiles/map_01.tmx
    // Adjust Vector2.all(32.0) if your tileset uses 16x16 instead!
    //tiledMap = await TiledComponent.load('samplemap_don.tmx', Vector2.all(32.0));
    //add(tiledMap);
_buildFallbackBoundaries(); // Force the old invisible walls for a second
    // 2. Center the map offset (Optional: Centers a 64x64 map around 0,0)
    tiledMap.position = Vector2(-1024, -1024);

    // 3. Scan the map for the invisible collision layer named "Hitboxes"
    final obstacleGroup = tiledMap.tileMap.getLayer<ObjectGroup>('Hitboxes');
    
    if (obstacleGroup != null) {
      for (final obj in obstacleGroup.objects) {
        // We offset the hitbox positions by the map's starting position
        double adjustedX = obj.x + tiledMap.position.x;
        double adjustedY = obj.y + tiledMap.position.y;
        
        obstacles.add(Rect.fromLTWH(adjustedX, adjustedY, obj.width, obj.height));
      }
    } else {
      debugPrint('WARNING: No layer named "Hitboxes" found in Tiled map!');
      _buildFallbackBoundaries();
    }
  }

  void _buildFallbackBoundaries() {
    obstacles.add(const Rect.fromLTWH(-1500, -1500, 3000, 50)); 
    obstacles.add(const Rect.fromLTWH(-1500, 1450, 3000, 50));  
    obstacles.add(const Rect.fromLTWH(-1500, -1500, 50, 3000)); 
    obstacles.add(const Rect.fromLTWH(1450, -1500, 50, 3000));  
  }

  // --- COLLISION MATH (Unchanged, so your AI and Flashlight still work perfectly) ---
  bool checkCollision(Vector2 pos, Vector2 size) {
    final playerRect = Rect.fromCenter(center: Offset(pos.x, pos.y), width: size.x, height: size.y);
    for (final obs in obstacles) {
      if (playerRect.overlaps(obs)) return true;
    }
    return false;
  }

  // --- LINE OF SIGHT MATH (Unchanged) ---
  bool hasLineOfSight(Vector2 p1, Vector2 p2) {
    for (final obs in obstacles) {
      if (_lineIntersectsRect(p1, p2, obs)) return false;
    }
    return true;
  }

  bool _lineIntersectsRect(Vector2 p1, Vector2 p2, Rect r) {
    double minX = min(p1.x, p2.x);
    double maxX = max(p1.x, p2.x);
    double minY = min(p1.y, p2.y);
    double maxY = max(p1.y, p2.y);
    
    if (maxX < r.left || minX > r.right || maxY < r.top || minY > r.bottom) return false;

    final rectLines = [
      [Vector2(r.left, r.top), Vector2(r.right, r.top)],
      [Vector2(r.right, r.top), Vector2(r.right, r.bottom)],
      [Vector2(r.right, r.bottom), Vector2(r.left, r.bottom)],
      [Vector2(r.left, r.bottom), Vector2(r.left, r.top)],
    ];

    for (var line in rectLines) {
      if (_doIntersect(p1, p2, line[0], line[1])) return true;
    }
    if (r.contains(Offset(p1.x, p1.y)) || r.contains(Offset(p2.x, p2.y))) return true;
    return false;
  }

  bool _doIntersect(Vector2 p1, Vector2 q1, Vector2 p2, Vector2 q2) {
    double orientation(Vector2 p, Vector2 q, Vector2 r) {
      double val = (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y);
      if (val == 0) return 0; 
      return (val > 0) ? 1 : 2; 
    }

    bool onSegment(Vector2 p, Vector2 q, Vector2 r) {
      if (q.x <= max(p.x, r.x) && q.x >= min(p.x, r.x) &&
          q.y <= max(p.y, r.y) && q.y >= min(p.y, r.y)) return true;
      return false;
    }

    double o1 = orientation(p1, q1, p2);
    double o2 = orientation(p1, q1, q2);
    double o3 = orientation(p2, q2, p1);
    double o4 = orientation(p2, q2, q1);

    if (o1 != o2 && o3 != o4) return true;
    if (o1 == 0 && onSegment(p1, p2, q1)) return true;
    if (o2 == 0 && onSegment(p1, q2, q1)) return true;
    if (o3 == 0 && onSegment(p2, p1, q2)) return true;
    if (o4 == 0 && onSegment(p2, q1, q2)) return true;

    return false;
  }
}