import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

class SynthManager {
  static final SynthManager instance = SynthManager._internal();
  SynthManager._internal();

  bool isInitialized = false;
  AudioSource? _synthWave;

  Future<void> init() async {
    if (isInitialized) return;
    try {
      if (!SoLoud.instance.isInitialized) return;
      
      // A pure, clean sine wave. No superWave, no detune, no clipping.
      _synthWave = await SoLoud.instance.loadWaveform(WaveForm.sin, false, 0.25, 0.0);
      isInitialized = true;
    } catch (e) {
      debugPrint('SynthManager ERROR during init: $e');
    }
  }

  // --- MENU INTERACTIONS ---
  void playMagicTap() {
    if (!isInitialized || _synthWave == null) return;
    
    try {
      // 1. Spawn paused at 0 volume
      final handle = SoLoud.instance.play(_synthWave!, volume: 0.0, paused: true, looping: true);
      
      // 2. Safely apply pitch before it ever processes a single audio frame
      SoLoud.instance.setRelativePlaySpeed(handle, 4.0);
      
      // 3. Unpause (It is completely silent right now)
      SoLoud.instance.setPause(handle, false);
      
      // 4. Smooth attack envelope (completely eliminates the "click")
      SoLoud.instance.fadeVolume(handle, 0.1, const Duration(milliseconds: 20));
      
      // 5. Smooth decay envelope
      Future.delayed(const Duration(milliseconds: 20), () {
        SoLoud.instance.fadeVolume(handle, 0.0, const Duration(milliseconds: 150));
      });
      
      Future.delayed(const Duration(milliseconds: 180), () {
        SoLoud.instance.stop(handle);
      });
    } catch (e) {}
  }

  // --- CHEST OPENING SEQUENCE ---
  
  // NOTE: This is now strictly SYNCHRONOUS! No more 'async/await' race conditions.
  List<dynamic> startChestCrescendo(int durationMs) {
    if (!isInitialized || _synthWave == null) return [];

    double root = 1.0 + (Random().nextDouble() * 0.5); 
    List<double> diminishedTriad = [
      root,
      root * pow(2, 3 / 12), 
      root * pow(2, 6 / 12)  
    ];

    List<dynamic> activeHandles = []; 

    for (double pitch in diminishedTriad) {
      final handle = SoLoud.instance.play(_synthWave!, volume: 0.0, paused: true, looping: true); 
      SoLoud.instance.setRelativePlaySpeed(handle, pitch);
      SoLoud.instance.setPause(handle, false);
      
      // Smoothly fade in to maintain the suspense
      SoLoud.instance.fadeVolume(handle, 0.1, Duration(milliseconds: durationMs));
      activeHandles.add(handle);
    }
    return activeHandles;
  }

  void stopChestCrescendo(List<dynamic> handles) { 
    for (var handle in handles) {
      try {
        SoLoud.instance.fadeVolume(handle, 0.0, const Duration(milliseconds: 50));
        Future.delayed(const Duration(milliseconds: 60), () {
          SoLoud.instance.stop(handle);
        });
      } catch (_) {}
    }
  }

  // NOTE: Also strictly SYNCHRONOUS!
  void resolveChestOpen(List<dynamic> handles) { 
    stopChestCrescendo(handles); 
    
    if (!isInitialized || _synthWave == null) return;
    
    double root = 2.0; 
    List<double> majorTriad = [
      root,
      root * pow(2, 4 / 12), 
      root * pow(2, 7 / 12)  
    ];

    for (double pitch in majorTriad) {
      final handle = SoLoud.instance.play(_synthWave!, volume: 0.0, paused: true, looping: true);
      SoLoud.instance.setRelativePlaySpeed(handle, pitch);
      SoLoud.instance.setPause(handle, false);
      
      // Quick, smooth attack
      SoLoud.instance.fadeVolume(handle, 0.15, const Duration(milliseconds: 20));
      
      // Long, triumphant fade out
      Future.delayed(const Duration(milliseconds: 20), () {
        SoLoud.instance.fadeVolume(handle, 0.0, const Duration(milliseconds: 800));
      });
      
      Future.delayed(const Duration(milliseconds: 850), () {
        SoLoud.instance.stop(handle);
      });
    }
  }
}