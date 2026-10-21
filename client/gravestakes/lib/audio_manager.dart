// audio_manager.dart
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flame/components.dart';

class AudioManager {
  static final AudioManager instance = AudioManager._internal();
  AudioManager._internal();

  bool isInitialized = false;

  // Background Music Handles
  SoundHandle? _currentMusicHandle;
  AudioSource? _currentMusicSource;

  bool isChaseMusicPlaying = false;

  // Music Sources
  AudioSource? menuMusic;
  AudioSource? chaseMusic;
  final List<AudioSource> inGameTracks = [];

  // Mask Scare SFX Map
  final Map<String, AudioSource> maskScareSounds = {};

  // Character Footstep & Mechanical Sound Profiles
  final Map<String, List<AudioSource>> characterFootsteps = {};
  final Map<String, AudioSource> characterIdleLoops = {}; 

  // Player Physiology SFX
  AudioSource? heavyBreathingSource;
  AudioSource? heartBeatSource;
  AudioSource? gaspBreathSource;
  SoundHandle? _localBreathingHandle;

  // Global SFX
  AudioSource? tickSource;
  AudioSource? powerupSource;
  AudioSource? impactSource;

  // --- Audio Taunt Catalog ---
  final Map<String, AudioSource> audioTaunts = {};

  double _userGlobalVolume = 1.0;
  bool _isMuted = false;

  void mute() {
    if (SoLoud.instance.isInitialized && !_isMuted) {
      _userGlobalVolume = SoLoud.instance.getGlobalVolume();
      SoLoud.instance.setGlobalVolume(0.0);
      _isMuted = true;
    }
  }

  void unmute() {
    if (SoLoud.instance.isInitialized && _isMuted) {
      SoLoud.instance.setGlobalVolume(_userGlobalVolume);
      _isMuted = false;
    }
  }

  Future<void> init() async {
    if (isInitialized) return;
    try {
      if (!SoLoud.instance.isInitialized) {
        try {
          // FIXED: Lowered bufferSize from 2048 to 1024 to prevent Android AAudio/synth ring-buffer ticks
          // and raised max active voice count to 128 so post-match synths never suffer voice-stealing pops.
          await SoLoud.instance.init(
            sampleRate: 48000, 
            bufferSize: 1024, 
          );
          SoLoud.instance.setMaxActiveVoiceCount(128);
        } catch (e) {
          SoLoud.instance.deinit();
          await Future.delayed(const Duration(milliseconds: 100));
          await SoLoud.instance.init(sampleRate: 48000, bufferSize: 1024);
          SoLoud.instance.setMaxActiveVoiceCount(128);
        }
      }

      // FIXED: Parallelize asset loading for faster startup
      final results = await Future.wait([
        SoLoud.instance.loadAsset('assets/audio/music/menu_theme.mp3'),       // 0
        SoLoud.instance.loadAsset('assets/audio/music/The_Chase.mp3'),        // 1
        SoLoud.instance.loadAsset('assets/audio/music/map_theme.mp3'),        // 2
        SoLoud.instance.loadAsset('assets/audio/Scare_Type_2.mp3'),           // 3
        SoLoud.instance.loadAsset('assets/audio/bat.mp3'),                    // 4
        SoLoud.instance.loadAsset('assets/audio/bugs.mp3'),                   // 5
        SoLoud.instance.loadAsset('assets/audio/Siren_Mask_Lure.mp3'),        // 6
        SoLoud.instance.loadAsset('assets/audio/Gorgon.mp3'),                 // 7
        SoLoud.instance.loadAsset('assets/audio/Poltergeist.mp3'),            // 8
        SoLoud.instance.loadAsset('assets/audio/Banshee.mp3'),                // 9
        SoLoud.instance.loadAsset('assets/audio/Wendigo.mp3'),                // 10
        SoLoud.instance.loadAsset('assets/audio/Parasite.mp3'),               // 11
        SoLoud.instance.loadAsset('assets/audio/Footsteps_Type_12.mp3'),      // 12
        SoLoud.instance.loadAsset('assets/audio/Breathing_Type_1.mp3'),       // 13
        SoLoud.instance.loadAsset('assets/audio/Heartbeat.mp3'),              // 14
        SoLoud.instance.loadAsset('assets/audio/gasp.mp3'),                   // 15
        SoLoud.instance.loadAsset('assets/audio/tick.mp3'),                   // 16
        SoLoud.instance.loadAsset('assets/audio/ElevenLabs_Scary_stinger.mp3'), // 17
        SoLoud.instance.loadAsset('assets/audio/train.mp3'),                  // 18
        SoLoud.instance.loadAsset('assets/audio/violin_scrape.mp3'),          // 19
      ]);

      menuMusic = results[0];
      chaseMusic = results[1];
      inGameTracks.add(results[2]);

      maskScareSounds['standard']    = results[3];
      maskScareSounds['flying']      = results[4];
      maskScareSounds['vermin']      = results[5];
      maskScareSounds['siren']       = results[6];
      maskScareSounds['gorgon']      = results[7];
      maskScareSounds['poltergeist'] = results[8];
      maskScareSounds['banshee']     = results[9];
      maskScareSounds['wendigo']     = results[10];
      maskScareSounds['parasite']    = results[11];

      characterFootsteps['default'] = [results[12]];

      heavyBreathingSource = results[13];
      heartBeatSource      = results[14];
      gaspBreathSource     = results[15];

      tickSource    = results[16];
      powerupSource = results[17];
      impactSource  = results[12]; // Shares Footsteps_Type_12.mp3 without double-decoding into RAM

      audioTaunts['taunt_train']  = results[18];
      audioTaunts['taunt_scrape'] = results[19];

      isInitialized = true;
    } catch (e) {
      debugPrint('AUDIO MANAGER INIT ERROR: $e');
    }
  }

  void playLocalTaunt(String tauntId) {
    if (!isInitialized) return;
    final sound = audioTaunts[tauntId];
    if (sound != null) SoLoud.instance.play(sound, volume: 1.0);
  }

  void playSpatialTaunt(String tauntId, Vector2 worldPos) {
    if (!isInitialized) return;
    final source = audioTaunts[tauntId];
    if (source == null) return;

    const double audioScale = 50.0;
    final handle = SoLoud.instance.play3d(
      source,
      worldPos.x / audioScale,
      worldPos.y / audioScale,
      0.0,
      volume: 1.0,
      paused: true, 
    );
    
    SoLoud.instance.set3dSourceMinMaxDistance(handle, 4.0, 80.0);
    SoLoud.instance.set3dSourceAttenuation(handle, 1, 1.0);
    SoLoud.instance.setPause(handle, false);
  }

  Future<void> playMenuMusic() async {
    if (menuMusic == null) return;
    isChaseMusicPlaying = false;
    await _playBgm(menuMusic!, volume: 0.5);
  }

  Future<void> playRandomInGameTrack() async {
    if (inGameTracks.isEmpty) return;
    isChaseMusicPlaying = false;
    final track = inGameTracks[Random().nextInt(inGameTracks.length)];
    await _playBgm(track, volume: 0.4);
  }

  void stopMusic() {
    if (_currentMusicHandle != null && SoLoud.instance.isInitialized) {
      SoLoud.instance.stop(_currentMusicHandle!);
      _currentMusicHandle = null;
      _currentMusicSource = null;
      isChaseMusicPlaying = false;
    }
  }

  void stopPhysiologyLoops() {
    if (_localBreathingHandle != null && SoLoud.instance.isInitialized) {
      SoLoud.instance.stop(_localBreathingHandle!);
      _localBreathingHandle = null;
    }
    // FIXED: Iterate through active SoundHandles on the AudioSource
    if (heavyBreathingSource != null && SoLoud.instance.isInitialized) {
      for (final handle in heavyBreathingSource!.handles.toList()) {
        SoLoud.instance.stop(handle);
      }
    }
  }

  Future<void> playChaseMusic() async {
    if (chaseMusic == null || isChaseMusicPlaying) return;
    isChaseMusicPlaying = true;
    await _playBgm(chaseMusic!, volume: 0.6); 
  }

  Future<void> _playBgm(AudioSource source, {double volume = 0.5}) async {
    if (_currentMusicSource == source && _currentMusicHandle != null) {
      if (SoLoud.instance.getIsValidVoiceHandle(_currentMusicHandle!)) return;
    }
    stopMusic();
    _currentMusicSource = source;
    _currentMusicHandle = SoLoud.instance.play(source, volume: volume, looping: true);
  }

  void playMaskScare(String maskId) {
    if (!isInitialized) return;
    final sound = maskScareSounds[maskId] ?? impactSource;
    if (sound != null) {
      SoLoud.instance.play(sound, volume: 1.0);
    }
  }

  void playEntityFootstep(String characterId, Vector2 worldPos, {bool isLocal = false}) {
    if (!isInitialized) return;

    final footstepBank = characterFootsteps[characterId] ?? characterFootsteps['default'];
    if (footstepBank == null || footstepBank.isEmpty) return;

    final source = footstepBank[Random().nextInt(footstepBank.length)];
    final randomPitch = 0.90 + (Random().nextDouble() * 0.20);

    if (isLocal) {
      final handle = SoLoud.instance.play(source, volume: 0.5);
      SoLoud.instance.setRelativePlaySpeed(handle, randomPitch);
    } else {
      const double audioScale = 50.0;
      final handle = SoLoud.instance.play3d(
        source,
        worldPos.x / audioScale,
        worldPos.y / audioScale,
        0.0,
        volume: 0.85,
        paused: true,
      );
      SoLoud.instance.setRelativePlaySpeed(handle, randomPitch);
      SoLoud.instance.set3dSourceMinMaxDistance(handle, 2.0, 20.0);
      SoLoud.instance.set3dSourceAttenuation(handle, 1, 1.2);
      SoLoud.instance.setPause(handle, false);
    }
  }

  void playSpatialScare(String maskId, Vector2 worldPos) {
    if (!isInitialized) return;
    final source = maskScareSounds[maskId] ?? impactSource;
    if (source == null) return;

    const double audioScale = 50.0;
    final double zAxis = (maskId == 'banshee') ? 80.0 : 0.0;

    final handle = SoLoud.instance.play3d(
      source,
      worldPos.x / audioScale,
      worldPos.y / audioScale,
      zAxis,
      volume: 0.95,
      paused: true, 
    );
    
    final maxDist = (maskId == 'banshee') ? 50.0 : 30.0;
    SoLoud.instance.set3dSourceMinMaxDistance(handle, 2.0, maxDist);
    SoLoud.instance.set3dSourceAttenuation(handle, 1, 1.2);

    SoLoud.instance.setPause(handle, false);
  }
}