import 'dart:math';
import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart' hide Image;

class GameMap extends Component with HasGameReference<FlameGame> {
  final String roomId;
  final String mapName;
  
  final List<Rect> obstacles = [];
  final List<Rect> safeZones = [];
  final List<Vector2> potentialBoxSpawns = [];
  final List<Vector2> playerSpawns = []; 

  final int gridWidth = 30;
  final int gridHeight = 30;
  final double tileSize = 64.0; 

  late List<List<int>> mapGrid;

  GameMap({required this.roomId, required this.mapName});

  @override
  Future<void> onLoad() async {
    priority = 0;
    
    // 1. Generate the Procedural 30x30 Dungeon!
    _generateDrunkenWalkGrid();

    // 2. Build the physical map from the grid
    _buildMapFromGrid();
    
    // 3. Fallback borders to keep players inside the universe
    _buildMapBorders();
  }

  void _generateDrunkenWalkGrid() {
    // Fill the map with walls (1)
    mapGrid = List.generate(gridHeight, (_) => List.filled(gridWidth, 1));
    
    int x = gridWidth ~/ 2;
    int y = gridHeight ~/ 2;
    mapGrid[y][x] = 0; // 0 = Floor
    
    int targetEmptySpaces = (gridWidth * gridHeight * 0.45).toInt(); 
    int currentEmpty = 1;
    
    // FIX: Deterministic seed based on the room ID so all players share the exact same map layout!
    final rand = Random(roomId.hashCode);
    
    // The "Drunkard" carves out the dungeon
    while (currentEmpty < targetEmptySpaces) {
      int dir = rand.nextInt(4);
      // Move, but keep a 2-block padding around the absolute edges
      if (dir == 0 && x > 2) x--;
      else if (dir == 1 && x < gridWidth - 3) x++;
      else if (dir == 2 && y > 2) y--;
      else if (dir == 3 && y < gridHeight - 3) y++;
      
      if (mapGrid[y][x] == 1) {
        mapGrid[y][x] = 0;
        currentEmpty++;
      }
    }
  }

  // Remove the MapRow class entirely and update _buildMapFromGrid in game_map.dart:

  void _buildMapFromGrid() {
    List<Vector2> allOpenTiles = [];

    // Master floor
    game.world.add(RectangleComponent(
      size: Vector2(gridWidth * tileSize, gridHeight * tileSize),
      position: Vector2.zero(),
      paint: Paint()..color = const Color(0xFF1A1A1A),
      priority: -10,
    ));

    for (int y = 0; y < gridHeight; y++) {
      for (int x = 0; x < gridWidth; x++) {
        final worldX = x * tileSize;
        final worldY = y * tileSize;

        if (mapGrid[y][x] == 0) {
          allOpenTiles.add(Vector2(worldX + (tileSize / 2), worldY + (tileSize / 2)));
        } else if (mapGrid[y][x] == 1) {
          // Spawn each wall tile individually with its own true 2.5D depth!
          game.world.add(WallComponent(
            position: Vector2(worldX, worldY),
            tileSize: tileSize,
          ));
          obstacles.add(Rect.fromLTWH(worldX, worldY, tileSize, tileSize));
        }
      }
    }

    allOpenTiles.shuffle();
    for (int i = 0; i < allOpenTiles.length; i++) {
      if (i < 8) playerSpawns.add(allOpenTiles[i]);
      else if (i < 20) potentialBoxSpawns.add(allOpenTiles[i]);
      else break;
    }
  }

  // ==========================================================
  // YOUR EXISTING MATH (Untouched so gameplay doesn't break!)
  // ==========================================================

  Vector2 getSafeSpawnLocation(Vector2 intendedPos, Vector2 entitySize) {
    if (!checkCollision(intendedPos, entitySize)) return intendedPos;

    double searchRadius = 16.0; 
    const double maxSearchRadius = 320.0; 
    const int directionsToCheck = 8; 

    while (searchRadius <= maxSearchRadius) {
      for (int i = 0; i < directionsToCheck; i++) {
        double angle = (i * 2 * pi) / directionsToCheck;
        Vector2 testPos = intendedPos + Vector2(cos(angle) * searchRadius, sin(angle) * searchRadius);
        if (!checkCollision(testPos, entitySize)) return testPos;
      }
      searchRadius += 16.0; 
    }
    return intendedPos; 
  }

  List<Vector2> findPath(Vector2 startWorld, Vector2 endWorld) {
    int startX = (startWorld.x / tileSize).floor().clamp(0, gridWidth - 1);
    int startY = (startWorld.y / tileSize).floor().clamp(0, gridHeight - 1);
    int endX = (endWorld.x / tileSize).floor().clamp(0, gridWidth - 1);
    int endY = (endWorld.y / tileSize).floor().clamp(0, gridHeight - 1);

    // If already in the exact same tile, just walk directly to the coordinate
    if (startX == endX && startY == endY) return [endWorld];

    List<Point<int>> queue = [Point(startX, startY)];
    Map<Point<int>, Point<int>?> cameFrom = {Point(startX, startY): null};
    bool found = false;

    while (queue.isNotEmpty) {
      var current = queue.removeAt(0);
      if (current.x == endX && current.y == endY) {
        found = true;
        break;
      }

      // Check standard 4-way movement (Up, Down, Left, Right)
      List<Point<int>> neighbors = [
        Point(current.x + 1, current.y), Point(current.x - 1, current.y),
        Point(current.x, current.y + 1), Point(current.x, current.y - 1),
      ];

      for (var next in neighbors) {
        if (next.x >= 0 && next.x < gridWidth && next.y >= 0 && next.y < gridHeight) {
          // If it's a floor (0) and we haven't visited it yet
          if (mapGrid[next.y][next.x] == 0 && !cameFrom.containsKey(next)) {
            queue.add(next);
            cameFrom[next] = current;
          }
        }
      }
    }

    if (!found) return []; // No valid path found

    // Reconstruct the path backwards from the destination
    List<Vector2> path = [];
    Point<int>? current = Point(endX, endY);
    while (current != null && current != Point(startX, startY)) {
      // Convert grid coordinates back to exact center-pixel world coordinates
      path.add(Vector2((current.x * tileSize) + (tileSize / 2), (current.y * tileSize) + (tileSize / 2)));
      current = cameFrom[current];
    }
    return path.reversed.toList();
  }

  @override
  bool checkCollision(Vector2 pos, Vector2 size) {
    // Check the four corners of the entity, with a tiny 4px buffer so they slide around corners easily
    double left = pos.x - (size.x / 2) + 4;
    double right = pos.x + (size.x / 2) - 4;
    double top = pos.y - (size.y / 2) + 4;
    double bottom = pos.y + (size.y / 2) - 4;

    int startX = (left / tileSize).floor();
    int endX = (right / tileSize).floor();
    int startY = (top / tileSize).floor();
    int endY = (bottom / tileSize).floor();

    // Prevent walking off the absolute edge of the array
    if (startX < 0 || endX >= gridWidth || startY < 0 || endY >= gridHeight) return true;

    for (int y = startY; y <= endY; y++) {
      for (int x = startX; x <= endX; x++) {
        if (mapGrid[y][x] == 1) return true; // It's a wall!
      }
    }
    return false;
  }

  @override
  bool hasLineOfSight(Vector2 p1, Vector2 p2) {
    double dist = p1.distanceTo(p2);
    if (dist < 20) return true; // Point blank always hits
    Vector2 dir = (p2 - p1).normalized();
    
    // Start the laser 20 pixels away from the player, and stop 20 pixels before the bot!
    for (double i = 20.0; i < (dist - 20.0); i += 8.0) {
      Vector2 checkPos = p1 + (dir * i);
      int gridX = (checkPos.x / tileSize).floor();
      int gridY = (checkPos.y / tileSize).floor();
      
      if (gridX < 0 || gridX >= gridWidth || gridY < 0 || gridY >= gridHeight) return false;
      if (mapGrid[gridY][gridX] == 1) return false; // Laser hit a wall
    }
    return true;
  }

  void _buildMapBorders() {
    double mapWidth = gridWidth * tileSize;
    double mapHeight = gridHeight * tileSize;
    const double t = 50.0;
    obstacles.add(Rect.fromLTWH(-t, -t, mapWidth + (t * 2), t));
    obstacles.add(Rect.fromLTWH(-t, mapHeight, mapWidth + (t * 2), t));
    obstacles.add(Rect.fromLTWH(-t, 0, t, mapHeight));
    obstacles.add(Rect.fromLTWH(mapWidth, 0, t, mapHeight));
  }

  bool _lineIntersectsRect(Vector2 p1, Vector2 p2, Rect r) {
    double minX = min(p1.x, p2.x); double maxX = max(p1.x, p2.x);
    double minY = min(p1.y, p2.y); double maxY = max(p1.y, p2.y);
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
      if (q.x <= max(p.x, r.x) && q.x >= min(p.x, r.x) && q.y <= max(p.y, r.y) && q.y >= min(p.y, r.y)) return true;
      return false;
    }
    double o1 = orientation(p1, q1, p2); double o2 = orientation(p1, q1, q2);
    double o3 = orientation(p2, q2, p1); double o4 = orientation(p2, q2, q1);
    if (o1 != o2 && o3 != o4) return true;
    if (o1 == 0 && onSegment(p1, p2, q1)) return true;
    if (o2 == 0 && onSegment(p1, q2, q1)) return true;
    if (o3 == 0 && onSegment(p2, p1, q2)) return true;
    if (o4 == 0 && onSegment(p2, q1, q2)) return true;
    return false;
  }
}

class MapRow extends PositionComponent {
  final int gridY;
  final List<int> rowData;
  final double tileSize;
  
  static final Paint _fillPaint = Paint()..color = Colors.deepPurpleAccent;
  static final Paint _strokePaint = Paint()..color = Colors.purpleAccent
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  MapRow({required this.gridY, required this.rowData, required this.tileSize}) 
    // The entire row sorts dynamically based on its bottom edge!
    : super(position: Vector2(0, gridY * tileSize), priority: (gridY * tileSize + tileSize).toInt());

  @override
  void render(Canvas canvas) {
    for (int x = 0; x < rowData.length; x++) {
      if (rowData[x] == 1) {
        // Draw the wall relative to the row's position
        final rect = Rect.fromLTWH(x * tileSize, 0, tileSize, tileSize);
        canvas.drawRect(rect, _fillPaint);
        canvas.drawRect(rect, _strokePaint);
      }
    }
  }
}

class WallComponent extends PositionComponent {
  final double tileSize;
  static final Paint _fillPaint = Paint()..color = Colors.deepPurpleAccent;
  static final Paint _strokePaint = Paint()..color = Colors.purpleAccent
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  WallComponent({required Vector2 position, required this.tileSize})
      : super(
          position: position, 
          size: Vector2.all(tileSize),
          // True 2.5D sorting based on the absolute bottom edge of this tile, multiplied for precision
          priority: ((position.y + tileSize) * 10).toInt(),
        );

  // NO update() method = Zero CPU overhead per frame!

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, tileSize, tileSize);
    canvas.drawRect(rect, _fillPaint);
    canvas.drawRect(rect, _strokePaint);
  }
}