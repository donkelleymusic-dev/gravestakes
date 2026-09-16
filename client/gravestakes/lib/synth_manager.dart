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
      
      // Changed to a SQUARE wave so it cuts through mobile speakers easily
      _synthWave = await SoLoud.instance.loadWaveform(WaveForm.square, true, 0.25, 1.0);
      isInitialized = true;
    } catch (e) {
      debugPrint('SynthManager ERROR during init: $e');
    }
  }

  // --- MENU INTERACTIONS ---
  void playMagicTap() {
    if (!isInitialized || _synthWave == null) return;
    
    try {
      // ADDED looping: true! Square waves are loud, so we drop the base volume to 0.15
      final handle = SoLoud.instance.play(_synthWave!, volume: 0.15, looping: true);
      
      SoLoud.instance.setRelativePlaySpeed(handle, 4.0);
      
      // Sustain for 30ms, then fade out over 200ms
      Future.delayed(const Duration(milliseconds: 30), () {
        SoLoud.instance.fadeVolume(handle, 0.0, const Duration(milliseconds: 200));
      });
      
      // Free the voice
      Future.delayed(const Duration(milliseconds: 230), () {
        SoLoud.instance.stop(handle);
      });
    } catch (e) {}
  }

  // --- CHEST OPENING SEQUENCE ---
  
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
      // ADDED looping: true!
      final handle = SoLoud.instance.play(_synthWave!, volume: 0.0, looping: true); 
      SoLoud.instance.setRelativePlaySpeed(handle, pitch);
      
      // Fade up to a low rumble volume over the hold duration
      SoLoud.instance.fadeVolume(handle, 0.1, Duration(milliseconds: durationMs));
      activeHandles.add(handle);
    }
    return activeHandles;
  }

  void stopChestCrescendo(List<dynamic> handles) { 
    for (var handle in handles) {
      SoLoud.instance.stop(handle);
    }
  }

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
      // ADDED looping: true! 
      final handle = SoLoud.instance.play(_synthWave!, volume: 0.15, looping: true);
      SoLoud.instance.setRelativePlaySpeed(handle, pitch);
      
      SoLoud.instance.fadeVolume(handle, 0.0, const Duration(milliseconds: 800));
      Future.delayed(const Duration(milliseconds: 800), () {
        SoLoud.instance.stop(handle);
      });
    }
  }
}