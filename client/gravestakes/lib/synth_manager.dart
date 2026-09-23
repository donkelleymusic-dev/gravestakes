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
      // Spawn paused at target volume (Prevents 0.0 culling)
      final handle = SoLoud.instance.play(_synthWave!, volume: 0.15, paused: true, looping: true);
      SoLoud.instance.setRelativePlaySpeed(handle, 4.0);
      
      // Unpause for an instant, pop-free attack
      SoLoud.instance.setPause(handle, false);
      
      // Smooth decay
      SoLoud.instance.fadeVolume(handle, 0.0, const Duration(milliseconds: 150));
      Future.delayed(const Duration(milliseconds: 160), () {
        SoLoud.instance.stop(handle);
      });
    } catch (e) {}
  }

  // --- CHEST OPENING SEQUENCE ---
  List<dynamic> startChestCrescendo(int durationMs) {
    if (!isInitialized || _synthWave == null) return [];
    double root = 1.0 + (Random().nextDouble() * 0.5); 
    List<double> diminishedTriad = [root, root * pow(2, 3 / 12), root * pow(2, 6 / 12)];
    List<dynamic> activeHandles = []; 

    for (double pitch in diminishedTriad) {
      // Spawn at an audible 0.1, fade up to MAXIMUM (1.0)
      final handle = SoLoud.instance.play(_synthWave!, volume: 0.1, paused: true, looping: true); 
      SoLoud.instance.setRelativePlaySpeed(handle, pitch);
      SoLoud.instance.setPause(handle, false);
      
      SoLoud.instance.fadeVolume(handle, 1.0, Duration(milliseconds: durationMs));
      activeHandles.add(handle);
    }
    return activeHandles;
  }

  void stopChestCrescendo(List<dynamic> handles) { 
    for (var handle in handles) {
      try {
        SoLoud.instance.fadeVolume(handle, 0.0, const Duration(milliseconds: 50));
        Future.delayed(const Duration(milliseconds: 60), () { SoLoud.instance.stop(handle); });
      } catch (_) {}
    }
  }

  void resolveChestOpen(List<dynamic> handles) { 
    stopChestCrescendo(handles); 
    if (!isInitialized || _synthWave == null) return;
    
    double root = 2.0; 
    List<double> majorTriad = [root, root * pow(2, 4 / 12), root * pow(2, 7 / 12)];

    for (double pitch in majorTriad) {
      // Strike the chord at MAXIMUM volume (1.0)
      final handle = SoLoud.instance.play(_synthWave!, volume: 1.0, paused: true, looping: true);
      SoLoud.instance.setRelativePlaySpeed(handle, pitch);
      SoLoud.instance.setPause(handle, false); 
      
      SoLoud.instance.fadeVolume(handle, 0.0, const Duration(milliseconds: 800));
      Future.delayed(const Duration(milliseconds: 850), () { SoLoud.instance.stop(handle); });
    }
  }
}