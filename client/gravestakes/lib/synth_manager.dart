import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

class SynthManager {
  static final SynthManager instance = SynthManager._internal();
  SynthManager._internal();

  bool isInitialized = false;
  AudioSource? _sineWave;

  Future<void> init() async {
    if (isInitialized) return;
    try {
      // Initialize a pure sine wave oscillator
      _sineWave = await SoLoud.instance.loadWaveform(WaveForm.sin, true, 0.25, 1.0);
      isInitialized = true;
    } catch (e) {
      debugPrint('SynthManager init error: $e');
    }
  }

  // --- MENU INTERACTIONS ---
  void playMagicTap() {
    if (!isInitialized || _sineWave == null) return;
    
    final handle = SoLoud.instance.play(_sineWave!, volume: 0.6);
    // Pitch up by 4 octaves for a bright UI ping
    SoLoud.instance.setRelativePlaySpeed(handle, 4.0);
    
    // Quick 150ms decay envelope
    SoLoud.instance.fadeVolume(handle, 0.0, const Duration(milliseconds: 150));
    
    // Free the voice once the fade completes
    Future.delayed(const Duration(milliseconds: 150), () {
      SoLoud.instance.stop(handle);
    });
  }

  // --- CHEST OPENING SEQUENCE ---
  
  /// Returns the active voice handles so we can automate or kill them dynamically
  List<dynamic> startChestCrescendo(int durationMs) {
    if (!isInitialized || _sineWave == null) return [];

    double root = 1.0 + (Random().nextDouble() * 0.5); 
    List<double> diminishedTriad = [
      root,
      root * pow(2, 3 / 12), 
      root * pow(2, 6 / 12)  
    ];

    List<dynamic> activeHandles = []; // <-- Changed to dynamic

    for (double pitch in diminishedTriad) {
      final handle = SoLoud.instance.play(_sineWave!, volume: 0.0); 
      SoLoud.instance.setRelativePlaySpeed(handle, pitch);
      SoLoud.instance.fadeVolume(handle, 0.7, Duration(milliseconds: durationMs));
      activeHandles.add(handle);
    }
    return activeHandles;
  }

  /// Instantly kills the crescendo voices if the player lets go early
  void stopChestCrescendo(List<dynamic> handles) { // <-- Changed to dynamic
    for (var handle in handles) {
      SoLoud.instance.stop(handle);
    }
  }

  /// Resolves the tension with a bright major chord when the chest bursts
  void resolveChestOpen(List<dynamic> handles) { // <-- Changed to dynamic
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