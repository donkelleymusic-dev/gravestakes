import 'dart:math';
import 'dart:ui';
import 'package:http/http.dart' as http; // NEW
import 'package:flame/components.dart';
import 'package:flame/flame.dart'; // NEW
import 'package:flame_tiled/flame_tiled.dart';
import 'package:tiled/tiled.dart'; // NEW
import 'package:supabase_flutter/supabase_flutter.dart'; // NEW
import 'package:flutter/material.dart' hide Image;
import 'package:flame/game.dart';

class GameMap extends Component with HasGameReference<FlameGame> {
  final String roomId;
  late TiledComponent tiledMap;
  final List<Rect> obstacles = [];
  final List<Rect> safeZones = [];

  // ==========================================
  // STATIC MEMORY CACHE (Survives between matches!)
  // ==========================================
  static String? cachedMapId;
  static String? cachedUpdatedAt;
  static String? cachedTmxString;
  static double? cachedTileSize;

  GameMap({required this.roomId});

  @override
  Future<void> onLoad() async {
    priority = 0;
    
    debugPrint('Checking for map updates...');
    
    // 1. THE LIGHTWEIGHT PING: Only ask for the ID and Timestamp
    final versionCheck = await Supabase.instance.client
        .from('maps')
        .select('id, updated_at')
        .eq('is_active', true)
        .limit(1)
        .single();

    final activeMapId = versionCheck['id'] as String;
    final activeUpdatedAt = versionCheck['updated_at'] as String;

    // 2. THE CACHE CHECK (Zero Timezone Math Required!)
    if (cachedMapId == activeMapId && cachedUpdatedAt == activeUpdatedAt && cachedTmxString != null) {
      debugPrint('Map is up to date! Loading from fast memory cache...');
      // We do NOT need to download anything or touch Flame.images, they are already there!
    } else {
      debugPrint('New map version detected! Downloading full payload...');
      
      // 3. THE HEAVY DOWNLOAD
      final fullMapData = await Supabase.instance.client
          .from('maps')
          .select('tmx_data, map_assets, tile_size')
          .eq('id', activeMapId)
          .single();

      // Wipe Flame's image cache so we don't hold old versions of images
      Flame.images.clearCache();

      final mapAssets = fullMapData['map_assets'] as List<dynamic>;
      
      for (var asset in mapAssets) {
        final cacheKey = (asset['name'] ?? asset['filename']) as String; 
        final imageUrl = asset['url'] as String;      
        
        debugPrint('Downloading $cacheKey...');
        final imageResponse = await http.get(Uri.parse(imageUrl));
        final decodedImage = await decodeImageFromList(imageResponse.bodyBytes);
        
        Flame.images.add(cacheKey, decodedImage);
      }

      // Update our static cache with the new data
      cachedMapId = activeMapId;
      cachedUpdatedAt = activeUpdatedAt;
      cachedTmxString = fullMapData['tmx_data'] as String;
      cachedTileSize = (fullMapData['tile_size'] as num).toDouble();
    }

    // ==========================================
    // 4. PARSE AND BUILD THE TMX MAP (Using the Cache!)
    // ==========================================
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
    
    tiledMap = TiledComponent(renderableMap);
    add(tiledMap);
    
    final map = tiledMap.tileMap.map;

    // ==========================================
    // 5. PARSE ASSET-LEVEL HITBOXES & SAFE ZONES
    // (This remains exactly as you wrote it!)
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

    // Parse Map-Level Object Layers
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
    
    _buildMapBorders();
  }

  // Programmatically finds the nearest unblocked coordinate
  Vector2 getSafeSpawnLocation(Vector2 intendedPos, Vector2 entitySize) {
    // 1. If the original spot is perfectly safe, use it immediately!
    if (!checkCollision(intendedPos, entitySize)) {
      return intendedPos;
    }

    // 2. If it is blocked, begin searching outward in a circle
    double searchRadius = 16.0; // Jump outward in 16-pixel increments (half a tile)
    const double maxSearchRadius = 320.0; // Stop searching if we go 10 tiles away
    const int directionsToCheck = 8; // N, NE, E, SE, S, SW, W, NW

    while (searchRadius <= maxSearchRadius) {
      for (int i = 0; i < directionsToCheck; i++) {
        // Calculate the angle for this point on the circle
        double angle = (i * 2 * pi) / directionsToCheck;
        
        // Calculate the exact X/Y coordinate to test
        Vector2 testPos = intendedPos + Vector2(cos(angle) * searchRadius, sin(angle) * searchRadius);
        
        // If this new spot is clear, return it!
        if (!checkCollision(testPos, entitySize)) {
          debugPrint('QA FIX: Moved spawn point out by $searchRadius pixels.');
          return testPos;
        }
      }
      // If the entire circle is blocked, expand the radius and try again
      searchRadius += 16.0; 
    }

    // Fallback: If we searched everywhere and it's all blocked, return the original
    debugPrint('WARNING: Could not find any safe spawn within $maxSearchRadius pixels!');
    return intendedPos; 
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
    
    // 1. If the player is touching a Safe Zone (like a ladder), ignore ALL walls here!
    for (final safe in safeZones) {
      if (playerRect.overlaps(safe)) return false; 
    }

    // 2. Otherwise, run standard collision checks against cliffs/fences
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

  void _buildMapBorders() {
    final map = tiledMap.tileMap.map;
    
    // Calculate the total pixel width and height of the map
    double mapWidth = (map.width * map.tileWidth).toDouble();
    double mapHeight = (map.height * map.tileHeight).toDouble();
    
    const double thickness = 50.0;

    // Top Wall
    obstacles.add(Rect.fromLTWH(-thickness, -thickness, mapWidth + (thickness * 2), thickness));
    // Bottom Wall
    obstacles.add(Rect.fromLTWH(-thickness, mapHeight, mapWidth + (thickness * 2), thickness));
    // Left Wall
    obstacles.add(Rect.fromLTWH(-thickness, 0, thickness, mapHeight));
    // Right Wall
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