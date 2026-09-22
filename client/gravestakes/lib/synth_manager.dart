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
      
      // Enabling SuperWave (true) with a slight detune (0.5) gives the sine wave 
      // a richer, melodic "bing" tone instead of a flat, popping test click.
      _synthWave = await SoLoud.instance.loadWaveform(WaveForm.sin, true, 0.25, 0.5);
      isInitialized = true;
    } catch (e) {
      debugPrint('SynthManager ERROR during init: $e');
    }
  }

  // --- MENU INTERACTIONS ---
  Future<void> playMagicTap() async {
    if (!isInitialized || _synthWave == null) return;
    
    try {
      // 1. Spawn actively running but strictly at volume 0.0 (Fixes the C++ NaN division bug)
      final handle = SoLoud.instance.play(_synthWave!, volume: 0.0, paused: false, looping: true);
      
      // 2. Set pitch safely now that the phase accumulators exist
      SoLoud.instance.setRelativePlaySpeed(handle, 4.0);
      
      // 3. Instant attack via direct assignment (prevents zero-crossing pop)
      SoLoud.instance.setVolume(handle, 0.15);
      
      // 4. Smooth decay to absolute zero
      SoLoud.instance.fadeVolume(handle, 0.0, const Duration(milliseconds: 150));
      
      Future.delayed(const Duration(milliseconds: 160), () {
        SoLoud.instance.stop(handle);
      });
    } catch (e) {}
  }

  // --- CHEST OPENING SEQUENCE ---
  
  Future<List<dynamic>> startChestCrescendo(int durationMs) async {
    if (!isInitialized || _synthWave == null) return [];

    double root = 1.0 + (Random().nextDouble() * 0.5); 
    List<double> diminishedTriad = [
      root,
      root * pow(2, 3 / 12), 
      root * pow(2, 6 / 12)  
    ];

    List<dynamic> activeHandles = []; 

    for (double pitch in diminishedTriad) {
      // Spawn actively running but safely muted
      final handle = SoLoud.instance.play(_synthWave!, volume: 0.0, paused: false, looping: true); 
      SoLoud.instance.setRelativePlaySpeed(handle, pitch);
      
      // Fade IN over the exact duration to maintain the suspense crescendo
      SoLoud.instance.fadeVolume(handle, 0.15, Duration(milliseconds: durationMs));
      activeHandles.add(handle);
    }
    return activeHandles;
  }

  void stopChestCrescendo(List<dynamic> handles) { 
    for (var handle in handles) {
      // Sweep to absolute zero to prevent pops
      SoLoud.instance.fadeVolume(handle, 0.0, const Duration(milliseconds: 50));
      Future.delayed(const Duration(milliseconds: 60), () {
        SoLoud.instance.stop(handle);
      });
    }
  }

  Future<void> resolveChestOpen(List<dynamic> handles) async { 
    stopChestCrescendo(handles); 
    
    if (!isInitialized || _synthWave == null) return;
    
    double root = 2.0; 
    List<double> majorTriad = [
      root,
      root * pow(2, 4 / 12), 
      root * pow(2, 7 / 12)  
    ];

    for (double pitch in majorTriad) {
      final handle = SoLoud.instance.play(_synthWave!, volume: 0.0, paused: false, looping: true);
      SoLoud.instance.setRelativePlaySpeed(handle, pitch);
      
      // Pop the major triad loud instantly for the reward impact
      SoLoud.instance.setVolume(handle, 0.15);
      
      // Long fade out
      SoLoud.instance.fadeVolume(handle, 0.0, const Duration(milliseconds: 800));
      
      Future.delayed(const Duration(milliseconds: 850), () {
        SoLoud.instance.stop(handle);
      });
    }
  }
}