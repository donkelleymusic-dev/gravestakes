import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class CharacterAssetManager {
  /// Fetches the ZIP bytes from local cache if available, otherwise downloads and caches it.
  static Future<List<int>> getZipBytes(String zipPath) async {
    if (zipPath.startsWith('http')) {
      // DefaultCacheManager handles ETags, disk caching, and network fetching automatically.
      final file = await DefaultCacheManager().getSingleFile(zipPath);
      return await file.readAsBytes();
    } else {
      // Fallback for local assets (e.g., 'assets/character_assets.zip')
      final ByteData data = await rootBundle.load(zipPath);
      return data.buffer.asUint8List();
    }
  }
}