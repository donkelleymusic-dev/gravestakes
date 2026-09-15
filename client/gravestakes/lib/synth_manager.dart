import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

class SynthManager {
  static final SynthManager instance = SynthManager._internal();
  SynthManager._internal();

  bool isInitialized = false;
  AudioSource? _sineWave;

  Future<void> init() async {
    if (isInitialized) {
      debugPrint('SynthManager: Already initialized.');
      return;
    }
    
    debugPrint('SynthManager: Starting initialization...');
    try {
      if (!SoLoud.instance.isInitialized) {
        debugPrint('SynthManager ERROR: SoLoud engine is not initialized yet!');
        return;
      }
      
      // Initialize a pure sine wave oscillator
      _sineWave = await SoLoud.instance.loadWaveform(WaveForm.sin, true, 0.25, 1.0);
      isInitialized = true;
      debugPrint('SynthManager: Initialization SUCCESS. Waveform loaded.');
    } catch (e) {
      debugPrint('SynthManager ERROR during init: $e');
    }
  }

  // --- MENU INTERACTIONS ---
  void playMagicTap() {
    debugPrint('SynthManager: playMagicTap() triggered.');
    
    if (!isInitialized) {
      debugPrint('SynthManager WARNING: Cannot play, manager is not initialized.');
      return;
    }
    if (_sineWave == null) {
      debugPrint('SynthManager WARNING: Cannot play, _sineWave is null.');
      return;
    }
    
    try {
      final handle = SoLoud.instance.play(_sineWave!, volume: 0.6);
      debugPrint('SynthManager: Sound playing. Handle ID: $handle');
      
      SoLoud.instance.setRelativePlaySpeed(handle, 4.0);
      SoLoud.instance.fadeVolume(handle, 0.0, const Duration(milliseconds: 150));
      
      Future.delayed(const Duration(milliseconds: 150), () {
        SoLoud.instance.stop(handle);
        debugPrint('SynthManager: Voice freed for Handle ID: $handle');
      });
    } catch (e) {
      debugPrint('SynthManager ERROR during playback: $e');
    }
  }

  // --- CHEST OPENING SEQUENCE ---
  
  List<dynamic> startChestCrescendo(int durationMs) {
    debugPrint('SynthManager: startChestCrescendo() triggered.');
    if (!isInitialized || _sineWave == null) return [];

    double root = 1.0 + (Random().nextDouble() * 0.5); 
    List<double> diminishedTriad = [
      root,
      root * pow(2, 3 / 12), 
      root * pow(2, 6 / 12)  
    ];

    List<dynamic> activeHandles = []; 

    for (double pitch in diminishedTriad) {
      final handle = SoLoud.instance.play(_sineWave!, volume: 0.0); 
      SoLoud.instance.setRelativePlaySpeed(handle, pitch);
      SoLoud.instance.fadeVolume(handle, 0.7, Duration(milliseconds: durationMs));
      activeHandles.add(handle);
    }
    debugPrint('SynthManager: Chest crescendo started with handles: $activeHandles');
    return activeHandles;
  }

  void stopChestCrescendo(List<dynamic> handles) { 
    debugPrint('SynthManager: stopChestCrescendo() stopping handles: $handles');
    for (var handle in handles) {
      SoLoud.instance.stop(handle);
    }
  }

  void resolveChestOpen(List<dynamic> handles) { 
    debugPrint('SynthManager: resolveChestOpen() triggered.');
    stopChestCrescendo(handles); 
    
    if (!isInitialized || _sineWave == null) return;
    
    double root = 2.0; 
    List<double> majorTriad = [
      root,
      root * pow(2, 4 / 12), 
      root * pow(2, 7 / 12)  
    ];

    for (double pitch in majorTriad) {
      final handle = SoLoud.instance.play(_sineWave!, volume: 0.8);
      SoLoud.instance.setRelativePlaySpeed(handle, pitch);
      
      SoLoud.instance.fadeVolume(handle, 0.0, const Duration(milliseconds: 800));
      Future.delayed(const Duration(milliseconds: 800), () {
        SoLoud.instance.stop(handle);
      });
    }
  }
}