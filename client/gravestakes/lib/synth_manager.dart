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
      
      // superWave is set to 'false', and detune to '0.0'. 
      // This prevents the oscillator from multiplying into clipping thresholds.
      _synthWave = await SoLoud.instance.loadWaveform(WaveForm.sin, false, 0.25, 0.0);
      isInitialized = true;
    } catch (e) {
      debugPrint('SynthManager ERROR during init: $e');
    }
  }

  // --- MENU INTERACTIONS ---
  Future<void> playMagicTap() async {
    if (!isInitialized || _synthWave == null) return;
    
    try {
      // Start volume at a mathematically safe 0.01, and spawn it PAUSED.
      final handle = SoLoud.instance.play(_synthWave!, volume: 0.01, paused: true, looping: true);
      
      // Apply pitch shifting BEFORE the voice starts pushing samples
      SoLoud.instance.setRelativePlaySpeed(handle, 4.0);
      SoLoud.instance.setPause(handle, false);
      
      SoLoud.instance.fadeVolume(handle, 0.15, const Duration(milliseconds: 10));
      
      Future.delayed(const Duration(milliseconds: 40), () {
        // Fade back to 0.01, not 0.0, to prevent divide-by-zero crashes
        SoLoud.instance.fadeVolume(handle, 0.01, const Duration(milliseconds: 150));
      });
      
      Future.delayed(const Duration(milliseconds: 200), () {
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
      // Spawn safely paused at 0.01
      final handle = SoLoud.instance.play(_synthWave!, volume: 0.01, paused: true, looping: true); 
      SoLoud.instance.setRelativePlaySpeed(handle, pitch);
      SoLoud.instance.setPause(handle, false);
      
      SoLoud.instance.fadeVolume(handle, 0.15, Duration(milliseconds: durationMs));
      activeHandles.add(handle);
    }
    return activeHandles;
  }

  void stopChestCrescendo(List<dynamic> handles) { 
    for (var handle in handles) {
      // Fade to a safe threshold before executing the hard stop
      SoLoud.instance.fadeVolume(handle, 0.01, const Duration(milliseconds: 50));
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
      final handle = SoLoud.instance.play(_synthWave!, volume: 0.01, paused: true, looping: true);
      SoLoud.instance.setRelativePlaySpeed(handle, pitch);
      SoLoud.instance.setPause(handle, false);
      
      SoLoud.instance.fadeVolume(handle, 0.15, const Duration(milliseconds: 20));
      
      Future.delayed(const Duration(milliseconds: 50), () {
        SoLoud.instance.fadeVolume(handle, 0.01, const Duration(milliseconds: 800));
      });
      
      Future.delayed(const Duration(milliseconds: 860), () {
        SoLoud.instance.stop(handle);
      });
    }
  }
}