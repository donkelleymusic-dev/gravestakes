// character_asset_manager.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

class CharacterAssetManager {
  // Prevents multiple bots from downloading the exact same ZIP concurrently at match start
  static final Map<String, Future<List<int>>> _inFlightDownloads = {};
  static final Map<String, Uint8List> _webMemoryCache = {};

  /// Fetches the ZIP bytes from local cache if available, otherwise downloads and caches it.
  static Future<List<int>> getZipBytes(String zipPath) {
    if (_inFlightDownloads.containsKey(zipPath)) {
      return _inFlightDownloads[zipPath]!;
    }
    final future = _fetchBytesInternal(zipPath);
    _inFlightDownloads[zipPath] = future;
    future.whenComplete(() => _inFlightDownloads.remove(zipPath));
    return future;
  }

  static Future<List<int>> _fetchBytesInternal(String zipPath) async {
    if (zipPath.startsWith('http')) {
      // Web safe fallback (DefaultCacheManager relies on dart:io / sqflite)
      if (kIsWeb) {
        if (_webMemoryCache.containsKey(zipPath)) {
          return _webMemoryCache[zipPath]!;
        }
        final response = await http.get(Uri.parse(zipPath));
        if (response.statusCode == 200) {
          _webMemoryCache[zipPath] = response.bodyBytes;
          return response.bodyBytes;
        }
        throw Exception('Failed to download asset on web: HTTP ${response.statusCode}');
      }

      // Mobile/Desktop disk caching
      final file = await DefaultCacheManager().getSingleFile(zipPath);
      return await file.readAsBytes();
    } else {
      // Fallback for local assets (e.g., 'assets/character_assets.zip')
      final ByteData data = await rootBundle.load(zipPath);
      return data.buffer.asUint8List();
    }
  }
}