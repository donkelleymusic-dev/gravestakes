import 'dart:math';
import 'dart:typed_data';
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
      
      // Dropped one octave (131 Hz) using the new harmonic generator
      final synthBytes = _generateSynthWav(frequency: 131.0, duration: 1.0);
      
      _synthWave = await SoLoud.instance.loadMem('pure_synth.wav', synthBytes);
      
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

  // --- DART-SIDE ALGORITHMIC SYNTHESIZER ---
  Uint8List _generateSineWaveWav({required double frequency, required double duration}) {
    const int sampleRate = 44100;
    final int samples = (sampleRate * duration).toInt();
    const int bytesPerSample = 2; // 16-bit audio
    final int dataSize = samples * bytesPerSample;
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
    buffer.setUint32(offset, 16, Endian.little); offset += 4; // Subchunk1Size (16 for PCM)
    buffer.setUint16(offset, 1, Endian.little); offset += 2;  // AudioFormat (1 = PCM)
    buffer.setUint16(offset, 1, Endian.little); offset += 2;  // NumChannels (1 = Mono)
    buffer.setUint32(offset, sampleRate, Endian.little); offset += 4; 
    buffer.setUint32(offset, sampleRate * bytesPerSample, Endian.little); offset += 4; // ByteRate
    buffer.setUint16(offset, bytesPerSample, Endian.little); offset += 2; // BlockAlign
    buffer.setUint16(offset, 16, Endian.little); offset += 2; // BitsPerSample

    // data sub-chunk
    buffer.setUint8(offset++, 0x64); // 'd'
    buffer.setUint8(offset++, 0x61); // 'a'
    buffer.setUint8(offset++, 0x74); // 't'
    buffer.setUint8(offset++, 0x61); // 'a'
    buffer.setUint32(offset, dataSize, Endian.little); offset += 4;

    // Generate PCM Sine Wave Data
    // We cap amplitude at 50% (32767 * 0.5) to prevent any hard digital clipping during chord summation
    const double amplitude = 16383.0; 
    
    for (int i = 0; i < samples; i++) {
      final double t = i / sampleRate;
      final double sampleValue = sin(2 * pi * frequency * t) * amplitude;
      buffer.setInt16(offset, sampleValue.toInt(), Endian.little);
      offset += 2;
    }

    return buffer.buffer.asUint8List();
  }

  // --- DART-SIDE STEREO ALGORITHMIC SYNTHESIZER ---
  Uint8List _generateSynthWav({required double frequency, required double duration}) {
    const int sampleRate = 44100;
    final int samples = (sampleRate * duration).toInt();
    
    // UPGRADE: 2 Channels (Stereo)
    const int channels = 2; 
    const int bytesPerSample = 2; 
    const int frameSize = channels * bytesPerSample; // 4 bytes per frame (L+R)
    
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
    
    // Set Channels to 2, and update ByteRate / BlockAlign for Stereo
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

    const double baseAmplitude = 16383.0; 
    
    for (int i = 0; i < samples; i++) {
      final double t = i / sampleRate;
      
      // 1.0 Hz LFO ensures it starts and ends at exactly 0 offset for a seamless loop
      final double lfo = sin(2 * pi * 1.0 * t); 
      
      // Max phase shift of roughly 120 degrees for a deep, swirling phaser effect
      final double phaseShift = lfo * (2 * pi / 3); 
      
      // --- LEFT CHANNEL: Pure, stationary harmonics ---
      final double fL = sin(2 * pi * frequency * t);
      final double h3L = (1 / 3) * sin(2 * pi * (frequency * 3) * t);
      final double h5L = (1 / 5) * sin(2 * pi * (frequency * 5) * t);
      final double leftWave = (fL + h3L + h5L) * 0.7;

      // --- RIGHT CHANNEL: Phase-shifted harmonics for wide stereo movement ---
      final double fR = sin(2 * pi * frequency * t + phaseShift);
      final double h3R = (1 / 3) * sin(2 * pi * (frequency * 3) * t + (phaseShift * 3));
      final double h5R = (1 / 5) * sin(2 * pi * (frequency * 5) * t + (phaseShift * 5));
      final double rightWave = (fR + h3R + h5R) * 0.7;

      // Write Left (2 bytes)
      buffer.setInt16(offset, (leftWave * baseAmplitude).toInt(), Endian.little);
      offset += 2;
      
      // Write Right (2 bytes)
      buffer.setInt16(offset, (rightWave * baseAmplitude).toInt(), Endian.little);
      offset += 2;
    }

    return buffer.buffer.asUint8List();
  }
}