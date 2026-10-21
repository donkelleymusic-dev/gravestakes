// synth_manager.dart
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

class SynthManager {
  static final SynthManager instance = SynthManager._internal();
  SynthManager._internal();

  bool isInitialized = false;
  AudioSource? _synthWave;

  // Track active crescendo handles internally so they can NEVER be orphaned
  final List<SoundHandle> _activeCrescendoHandles = [];

  Future<void> init() async {
    if (isInitialized) return;
    try {
      if (!SoLoud.instance.isInitialized) return;
      
      // FIXED: Exact integer frequency (65.0 Hz) over a 2.0-second buffer.
      // Every harmonic (65Hz, 195Hz, 325Hz) and the 0.5Hz stereo phaser LFO complete 
      // an exact integer number of cycles at the loop boundary—eliminating wrap clicks!
      final synthBytes = _generateSynthWav(frequency: 65.0, duration: 2.0);
      
      _synthWave = await SoLoud.instance.loadMem('pure_synth.wav', synthBytes);
      
      isInitialized = true;
    } catch (e) {
      debugPrint('SynthManager ERROR during init: $e');
    }
  }

  // --- MENU INTERACTIONS ---
  void playMagicTap() {
    if (!isInitialized || _synthWave == null || !SoLoud.instance.isInitialized) return;
    try {
      final handle = SoLoud.instance.play(_synthWave!, volume: 0.01, paused: true, looping: true);
      SoLoud.instance.setRelativePlaySpeed(handle, 4.0);
      SoLoud.instance.setPause(handle, false);
      
      // Micro-attack ramp prevents initial phase-onset pop, followed by smooth decay
      SoLoud.instance.fadeVolume(handle, 0.15, const Duration(milliseconds: 12));
      Future.delayed(const Duration(milliseconds: 15), () {
        if (SoLoud.instance.isInitialized && SoLoud.instance.getIsValidVoiceHandle(handle)) {
          SoLoud.instance.fadeVolume(handle, 0.0, const Duration(milliseconds: 140));
          SoLoud.instance.scheduleStop(handle, const Duration(milliseconds: 150));
        }
      });
    } catch (e) {}
  }

  // --- CHEST OPENING SEQUENCE ---
  List<SoundHandle> startChestCrescendo(int durationMs) {
    if (!isInitialized || _synthWave == null || !SoLoud.instance.isInitialized) return [];
    
    // Always flush any existing crescendo handles first to prevent multitouch voice stacking!
    stopChestCrescendo(_activeCrescendoHandles);

    double root = 1.0 + (Random().nextDouble() * 0.5); 
    List<double> diminishedTriad = [root, root * pow(2, 3 / 12), root * pow(2, 6 / 12)];
    List<SoundHandle> newHandles = []; 

    for (double pitch in diminishedTriad) {
      final handle = SoLoud.instance.play(_synthWave!, volume: 0.02, paused: true, looping: true); 
      SoLoud.instance.setRelativePlaySpeed(handle, pitch);
      SoLoud.instance.setPause(handle, false);
      
      // Capped at 0.22 per voice (0.66 total triad sum) so overlapping with the burst chord never clips
      SoLoud.instance.fadeVolume(handle, 0.22, Duration(milliseconds: durationMs));
      newHandles.add(handle);
      _activeCrescendoHandles.add(handle);
    }
    return List<SoundHandle>.from(newHandles);
  }

  void stopChestCrescendo(List<dynamic> handles) {
    if (!SoLoud.instance.isInitialized) return;

    final toStop = <SoundHandle>{
      ...handles.whereType<SoundHandle>(),
      ..._activeCrescendoHandles,
    };
    _activeCrescendoHandles.clear();

    for (final handle in toStop) {
      try {
        if (SoLoud.instance.getIsValidVoiceHandle(handle)) {
          // 80ms smooth release on C++ audio thread prevents abrupt cutoff clicks
          SoLoud.instance.fadeVolume(handle, 0.0, const Duration(milliseconds: 80));
          SoLoud.instance.scheduleStop(handle, const Duration(milliseconds: 90));
        }
      } catch (_) {}
    }
  }

  void resolveChestOpen(List<dynamic> handles) { 
    stopChestCrescendo(handles); 
    if (!isInitialized || _synthWave == null || !SoLoud.instance.isInitialized) return;
    
    double root = 2.0; 
    List<double> majorTriad = [root, root * pow(2, 4 / 12), root * pow(2, 7 / 12)];

    for (double pitch in majorTriad) {
      // Start at 0.24 per voice (0.72 sum) so it leaves clean headroom while the crescendo tails out
      final handle = SoLoud.instance.play(_synthWave!, volume: 0.24, paused: true, looping: true);
      SoLoud.instance.setRelativePlaySpeed(handle, pitch);
      SoLoud.instance.setPause(handle, false); 
      
      SoLoud.instance.fadeVolume(handle, 0.0, const Duration(milliseconds: 800));
      SoLoud.instance.scheduleStop(handle, const Duration(milliseconds: 820));
    }
  }

  // --- DART-SIDE STEREO ALGORITHMIC SYNTHESIZER ---
  Uint8List _generateSynthWav({required double frequency, required double duration}) {
    const int sampleRate = 48000; 
    final int samples = (sampleRate * duration).round();
    
    // Force exact integer cycles across the buffer duration so sample[N] -> sample[0] is 100% seamless
    final double totalCycles = (frequency * duration).roundToDouble();
    final double exactFreq = totalCycles / duration;
    final double lfoFreq = 1.0 / duration; // Exactly 1 full LFO sweep per buffer loop

    const int channels = 2; 
    const int bytesPerSample = 2;
    const int frameSize = channels * bytesPerSample;
    
    final int dataSize = samples * frameSize;
    final int fileSize = 36 + dataSize;

    final buffer = ByteData(44 + dataSize);
    int offset = 0;

    // RIFF Header
    buffer.setUint8(offset++, 0x52); // 'R'
    buffer.setUint8(offset++, 0x49); // 'I'
    buffer.setUint8(offset++, 0x46); // 'F'
    buffer.setUint8(offset++, 0x46); // 'F'
    buffer.setUint32(offset, fileSize, Endian.little); offset += 4;
    buffer.setUint8(offset++, 0x57); // 'W'
    buffer.setUint8(offset++, 0x41); // 'A'
    buffer.setUint8(offset++, 0x56); // 'V'
    buffer.setUint8(offset++, 0x45); // 'E'

    // fmt sub-chunk
    buffer.setUint8(offset++, 0x66); // 'f'
    buffer.setUint8(offset++, 0x6D); // 'm'
    buffer.setUint8(offset++, 0x74); // 't'
    buffer.setUint8(offset++, 0x20); // ' '
    buffer.setUint32(offset, 16, Endian.little); offset += 4; 
    buffer.setUint16(offset, 1, Endian.little); offset += 2;  
    buffer.setUint16(offset, channels, Endian.little); offset += 2;  
    buffer.setUint32(offset, sampleRate, Endian.little); offset += 4; 
    buffer.setUint32(offset, sampleRate * frameSize, Endian.little); offset += 4; 
    buffer.setUint16(offset, frameSize, Endian.little); offset += 2; 
    buffer.setUint16(offset, 16, Endian.little); offset += 2; 

    // data sub-chunk
    buffer.setUint8(offset++, 0x64); // 'd'
    buffer.setUint8(offset++, 0x61); // 'a'
    buffer.setUint8(offset++, 0x74); // 't'
    buffer.setUint8(offset++, 0x61); // 'a'
    buffer.setUint32(offset, dataSize, Endian.little); offset += 4;

    // Conservative headroom (38% full scale) so 3-voice chords + phaser peaks never clip internal resamplers
    const double baseAmplitude = 12400.0; 
    
    for (int i = 0; i < samples; i++) {
      final double t = i / sampleRate;
      
      final double lfo = sin(2 * pi * lfoFreq * t); 
      final double phaseShift = lfo * (2 * pi / 3); 
      
      // --- LEFT CHANNEL: Pure, stationary harmonics ---
      final double fL = sin(2 * pi * exactFreq * t);
      final double h3L = (1 / 3) * sin(2 * pi * (exactFreq * 3) * t);
      final double h5L = (1 / 5) * sin(2 * pi * (exactFreq * 5) * t);
      final double leftWave = (fL + h3L + h5L) * 0.65;

      // --- RIGHT CHANNEL: Phase-shifted harmonics for wide stereo movement ---
      final double fR = sin(2 * pi * exactFreq * t + phaseShift);
      final double h3R = (1 / 3) * sin(2 * pi * (exactFreq * 3) * t + (phaseShift * 3));
      final double h5R = (1 / 5) * sin(2 * pi * (exactFreq * 5) * t + (phaseShift * 5));
      final double rightWave = (fR + h3R + h5R) * 0.65;

      buffer.setInt16(offset, (leftWave * baseAmplitude).round().clamp(-32767, 32767), Endian.little);
      offset += 2;
      
      buffer.setInt16(offset, (rightWave * baseAmplitude).round().clamp(-32767, 32767), Endian.little);
      offset += 2;
    }

    return buffer.buffer.asUint8List();
  }
}