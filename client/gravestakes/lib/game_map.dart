import 'dart:math';
import 'dart:ui';
import 'package:http/http.dart' as http; 
import 'package:flame/components.dart';
import 'package:flame/flame.dart'; 
import 'package:flame_tiled/flame_tiled.dart';
import 'package:tiled/tiled.dart'; 
import 'package:supabase_flutter/supabase_flutter.dart'; 
import 'package:flutter/material.dart' hide Image;
import 'package:flame/game.dart';

class GameMap extends Component with HasGameReference<FlameGame> {
  final String roomId;
  final String mapName;
  
  late TiledComponent tiledMap;
  final List<Rect> obstacles = [];
  final List<Rect> safeZones = [];
  final List<Vector2> potentialBoxSpawns = [];
  final List<Vector2> playerSpawns = []; // Dynamic Player Spawns!

  // ==========================================
  // STATIC MEMORY CACHE
  // ==========================================
  static String? cachedMapId;
  static String? cachedUpdatedAt;
  static String? cachedTmxString;
  static double? cachedTileSize;

  GameMap({required this.roomId, required this.mapName});

  @override
  Future<void> onLoad() async {
    priority = 0;
    
    debugPrint('Checking for map updates for: $mapName...');
    
    final versionCheck = await Supabase.instance.client
        .from('maps')
        .select('id, updated_at')
        .eq('name', mapName)
        .single();

    final activeMapId = versionCheck['id'] as String;
    final activeUpdatedAt = versionCheck['updated_at'] as String;

    if (cachedMapId == activeMapId && cachedUpdatedAt == activeUpdatedAt && cachedTmxString != null) {
      debugPrint('Map is up to date! Loading from fast memory cache...');
    } else {
      debugPrint('New map version detected! Downloading full payload...');
      
      final fullMapData = await Supabase.instance.client
          .from('maps')
          .select('tmx_data, map_assets, tile_size')
          .eq('id', activeMapId)
          .single();

      //Flame.images.clearCache();

      final mapAssets = fullMapData['map_assets'] as List<dynamic>;
      
      for (var asset in mapAssets) {
        final cacheKey = (asset['name'] ?? asset['filename']) as String; 
        final imageUrl = asset['url'] as String;      
        
        debugPrint('Downloading $cacheKey...');
        final imageResponse = await http.get(Uri.parse(imageUrl));
        final decodedImage = await decodeImageFromList(imageResponse.bodyBytes);
        
        Flame.images.add(cacheKey, decodedImage);
      }

      cachedMapId = activeMapId;
      cachedUpdatedAt = activeUpdatedAt;
      cachedTmxString = fullMapData['tmx_data'] as String;
      cachedTileSize = (fullMapData['tile_size'] as num).toDouble();
    }

    final parsedMap = await TiledMap.fromString(
      cachedTmxString!, 
      (key) async => throw Exception('External TSX files not supported. Ensure tilesets are embedded in the TMX!'),
    );
    
    final renderableMap = await RenderableTiledMap.fromTiledMap(
      parsedMap, 
      Vector2.all(cachedTileSize!), 
      atlasMaxX: 8192, 
      atlasMaxY: 8192, 
    );
    
    // INITIALIZE IT FIRST BEFORE THE LOOPS!
    tiledMap = TiledComponent(renderableMap);
    add(tiledMap);
    
    final map = tiledMap.tileMap.map;

    // ==========================================
    // PARSE ASSET-LEVEL HITBOXES & SAFE ZONES
    // ==========================================
    for (final layer in map.layers.whereType<TileLayer>()) {
      for (int y = 0; y < map.height; y++) {
        for (int x = 0; x < map.width; x++) {
          
          final tileData = layer.tileData?[y][x];
          final gid = tileData?.tile ?? 0;
          if (gid == 0) continue; 
          
          final tileset = map.tilesetByTileGId(gid);
          final localId = gid - tileset.firstGid!;
          
          final tile = tileset.tiles.cast<Tile?>().firstWhere(
            (t) => t?.localId == localId, 
            orElse: () => null,
          );
          
          if (tile != null && tile.objectGroup is ObjectGroup) {
            final objectGroup = tile.objectGroup as ObjectGroup; 
            for (final obj in objectGroup.objects) {
              double adjustedX = (x * map.tileWidth) + obj.x + tiledMap.position.x;
              double adjustedY = (y * map.tileHeight) + obj.y + tiledMap.position.y;
              final rect = Rect.fromLTWH(adjustedX, adjustedY, obj.width, obj.height);
              
              if (obj.class_ == 'SafeZone' || obj.type == 'SafeZone') {
                safeZones.add(rect);
              } else {
                obstacles.add(rect); 
              }
            }
          }
        }
      }
    }

    final safeGroup = tiledMap.tileMap.getLayer<ObjectGroup>('SafeZones');
    if (safeGroup != null) {
      for (final obj in safeGroup.objects) {
        double adjustedX = obj.x + tiledMap.position.x;
        double adjustedY = obj.y + tiledMap.position.y;
        safeZones.add(Rect.fromLTWH(adjustedX, adjustedY, obj.width, obj.height));
      }
    }

    final obstacleGroup = tiledMap.tileMap.getLayer<ObjectGroup>('Hitboxes');
    if (obstacleGroup != null) {
      for (final obj in obstacleGroup.objects) {
        double adjustedX = obj.x + tiledMap.position.x;
        double adjustedY = obj.y + tiledMap.position.y;
        obstacles.add(Rect.fromLTWH(adjustedX, adjustedY, obj.width, obj.height));
      }
    } 

    final boxSpawnGroup = tiledMap.tileMap.getLayer<ObjectGroup>('BoxSpawns');
    if (boxSpawnGroup != null) {
      for (final obj in boxSpawnGroup.objects) {
        double adjustedX = obj.x + tiledMap.position.x;
        double adjustedY = obj.y + tiledMap.position.y;
        potentialBoxSpawns.add(Vector2(adjustedX, adjustedY));
      }
    }

    final playerSpawnGroup = tiledMap.tileMap.getLayer<ObjectGroup>('PlayerSpawns');
    if (playerSpawnGroup != null) {
      for (final obj in playerSpawnGroup.objects) {
        double adjustedX = obj.x + tiledMap.position.x;
        double adjustedY = obj.y + tiledMap.position.y;
        playerSpawns.add(Vector2(adjustedX, adjustedY));
      }
    }
    
    _buildMapBorders();
  }

  // Programmatically finds the nearest unblocked coordinate
  Vector2 getSafeSpawnLocation(Vector2 intendedPos, Vector2 entitySize) {
    if (!checkCollision(intendedPos, entitySize)) {
      return intendedPos;
    }

    double searchRadius = 16.0; 
    const double maxSearchRadius = 320.0; 
    const int directionsToCheck = 8; 

    while (searchRadius <= maxSearchRadius) {
      for (int i = 0; i < directionsToCheck; i++) {
        double angle = (i * 2 * pi) / directionsToCheck;
        Vector2 testPos = intendedPos + Vector2(cos(angle) * searchRadius, sin(angle) * searchRadius);
        
        if (!checkCollision(testPos, entitySize)) {
          debugPrint('QA FIX: Moved spawn point out by $searchRadius pixels.');
          return testPos;
        }
      }
      searchRadius += 16.0; 
    }

    debugPrint('WARNING: Could not find any safe spawn within $maxSearchRadius pixels!');
    return intendedPos; 
  }

  void _buildFallbackBoundaries() {
    obstacles.add(const Rect.fromLTWH(-1500, -1500, 3000, 50)); 
    obstacles.add(const Rect.fromLTWH(-1500, 1450, 3000, 50));  
    obstacles.add(const Rect.fromLTWH(-1500, -1500, 50, 3000)); 
    obstacles.add(const Rect.fromLTWH(1450, -1500, 50, 3000));  
  }

  bool checkCollision(Vector2 pos, Vector2 size) {
    final playerRect = Rect.fromCenter(center: Offset(pos.x, pos.y), width: size.x, height: size.y);
    
    for (final safe in safeZones) {
      if (playerRect.overlaps(safe)) return false; 
    }

    for (final obs in obstacles) {
      if (playerRect.overlaps(obs)) return true;
    }
    return false;
  }

  bool hasLineOfSight(Vector2 p1, Vector2 p2) {
    for (final obs in obstacles) {
      if (_lineIntersectsRect(p1, p2, obs)) return false;
    }
    return true;
  }

  void _buildMapBorders() {
    final map = tiledMap.tileMap.map;
    
    double mapWidth = (map.width * map.tileWidth).toDouble();
    double mapHeight = (map.height * map.tileHeight).toDouble();
    
    const double thickness = 50.0;

    obstacles.add(Rect.fromLTWH(-thickness, -thickness, mapWidth + (thickness * 2), thickness));
    obstacles.add(Rect.fromLTWH(-thickness, mapHeight, mapWidth + (thickness * 2), thickness));
    obstacles.add(Rect.fromLTWH(-thickness, 0, thickness, mapHeight));
    obstacles.add(Rect.fromLTWH(mapWidth, 0, thickness, mapHeight));
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