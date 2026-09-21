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
      
      // SINE WAVE: Smooth math completely eliminates the DC voltage pop
      _synthWave = await SoLoud.instance.loadWaveform(WaveForm.sin, true, 0.25, 1.0);
      isInitialized = true;
    } catch (e) {
      debugPrint('SynthManager ERROR during init: $e');
    }
  }

  // --- MENU INTERACTIONS ---
  Future<void> playMagicTap() async {
    if (!isInitialized || _synthWave == null) return;
    
    try {
      // THE ATTACK ENVELOPE: Start at 0.0 and fade up over 10ms
      final handle = SoLoud.instance.play(_synthWave!, volume: 0.0, looping: true);
      SoLoud.instance.setRelativePlaySpeed(handle, 4.0);
      SoLoud.instance.fadeVolume(handle, 0.15, const Duration(milliseconds: 10));
      
      // THE RELEASE ENVELOPE: Sustain briefly, then fade out over 150ms
      Future.delayed(const Duration(milliseconds: 40), () {
        SoLoud.instance.fadeVolume(handle, 0.0, const Duration(milliseconds: 150));
      });
      
      // Free the voice ONLY after the volume is safely at 0.0
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
      final handle = SoLoud.instance.play(_synthWave!, volume: 0.0, looping: true); 
      SoLoud.instance.setRelativePlaySpeed(handle, pitch);
      
      SoLoud.instance.fadeVolume(handle, 0.15, Duration(milliseconds: durationMs));
      activeHandles.add(handle);
    }
    return activeHandles;
  }

  void stopChestCrescendo(List<dynamic> handles) { 
    for (var handle in handles) {
      // Smooth out the abrupt release if the user lets go early
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
      // Attack envelope
      final handle = SoLoud.instance.play(_synthWave!, volume: 0.0, looping: true);
      SoLoud.instance.setRelativePlaySpeed(handle, pitch);
      SoLoud.instance.fadeVolume(handle, 0.15, const Duration(milliseconds: 20));
      
      // Release envelope
      Future.delayed(const Duration(milliseconds: 50), () {
        SoLoud.instance.fadeVolume(handle, 0.0, const Duration(milliseconds: 800));
      });
      
      Future.delayed(const Duration(milliseconds: 860), () {
        SoLoud.instance.stop(handle);
      });
    }
  }
}