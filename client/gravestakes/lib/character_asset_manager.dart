// character_asset_manager.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

class CharacterAssetManager {
  static final Map<String, Future<List<int>>> _inFlightDownloads = {};
  static final Map<String, Uint8List> _webMemoryCache = {};

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
      if (kIsWeb) {
        if (_webMemoryCache.containsKey(zipPath)) {
          return _webMemoryCache[zipPath]!;
        }
        final response = await http.get(Uri.parse(zipPath)).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          _webMemoryCache[zipPath] = response.bodyBytes;
          return response.bodyBytes;
        }
        throw Exception('HTTP ${response.statusCode} fetching $zipPath');
      }

      // 1. Check local disk cache first (no network call)
      final cachedFile = await DefaultCacheManager().getFileFromCache(zipPath);
      if (cachedFile != null && await cachedFile.file.exists()) {
        return await cachedFile.file.readAsBytes();
      }

      // 2. Download via standard http.get with timeout instead of DefaultCacheManager's internal WebHelper queue
      // This prevents unhandled zoned HttpExceptions (like 504 Gateway Timeout) from crashing Sentry/Play Review!
      final response = await http.get(Uri.parse(zipPath)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        await DefaultCacheManager().putFile(zipPath, bytes, fileExtension: 'zip');
        return bytes;
      } else {
        throw Exception('Supabase Storage returned HTTP ${response.statusCode} for $zipPath');
      }
    } else {
      final ByteData data = await rootBundle.load(zipPath);
      return data.buffer.asUint8List();
    }
  }
}