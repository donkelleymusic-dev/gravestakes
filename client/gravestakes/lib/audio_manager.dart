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

  // Music Sources
  AudioSource? menuMusic;
  final List<AudioSource> inGameTracks = [];

  // Mask Scare SFX Map (Key: maskId -> 'standard', 'siren', 'flying', 'vermin', etc.)
  final Map<String, AudioSource> maskScareSounds = {};

  // Character Footstep & Mechanical Sound Profiles (Key: characterId)
  final Map<String, List<AudioSource>> characterFootsteps = {};
  final Map<String, AudioSource> characterIdleLoops = {}; // e.g. Steampunk hiss/gears

  // Player Physiology SFX
  AudioSource? heavyBreathingSource;
  AudioSource? heartBeatSource;
  AudioSource? gaspBreathSource;
  SoundHandle? _localBreathingHandle;

  // Global SFX
  AudioSource? tickSource;
  AudioSource? powerupSource;
  AudioSource? impactSource;

  Future<void> init() async {
    if (isInitialized) return;
    try {
      if (!SoLoud.instance.isInitialized) {
        try {
          await SoLoud.instance.init();
          SoLoud.instance.setMaxActiveVoiceCount(64);
        } catch (e) {
          // Catch the native C++ hot-restart desync
          debugPrint('Native audio engine desync detected. Forcing reset...');
          SoLoud.instance.deinit();
          await Future.delayed(const Duration(milliseconds: 100)); // Give C++ memory a beat to clear
          await SoLoud.instance.init();
        }
      }

      // 1. Preload Music
      menuMusic = await SoLoud.instance.loadAsset('assets/audio/music/menu_theme.mp3');
      // inGameTracks.add(await SoLoud.instance.loadAsset('assets/audio/music/crypt_ambience_1.mp3'));
      // inGameTracks.add(await SoLoud.instance.loadAsset('assets/audio/music/crypt_ambience_2.mp3'));

      // 2. Preload Mask SFX
      maskScareSounds['standard'] = await SoLoud.instance.loadAsset('assets/audio/ElevenLabs_Impact.mp3');
      maskScareSounds['flying']   = await SoLoud.instance.loadAsset('assets/audio/bat.mp3');
      maskScareSounds['vermin']   = await SoLoud.instance.loadAsset('assets/audio/bugs.mp3');
      // maskScareSounds['siren']    = await SoLoud.instance.loadAsset('assets/audio/siren_wail.mp3');

      // 3. Preload Character-Specific Footsteps (Human vs Steampunk Robot)
      characterFootsteps['default'] = [
        await SoLoud.instance.loadAsset('assets/audio/footstep.mp3'),
      ];
      // characterFootsteps['steampunk_automaton'] = [
      //   await SoLoud.instance.loadAsset('assets/audio/robot/servo_step_1.mp3'),
      //   await SoLoud.instance.loadAsset('assets/audio/robot/servo_step_2.mp3'),
      //   await SoLoud.instance.loadAsset('assets/audio/robot/clank_step.mp3'),
      // ];
      // characterIdleLoops['steampunk_automaton'] = await SoLoud.instance.loadAsset('assets/audio/robot/steam_vent_loop.mp3');

      // 4. Preload Physiology / Breathing
      // heavyBreathingSource = await SoLoud.instance.loadAsset('assets/audio/player/heavy_breathing.mp3');
      // heartBeatSource = await SoLoud.instance.loadAsset('assets/audio/player/heartbeat.mp3');
      // gaspBreathSource = await SoLoud.instance.loadAsset('assets/audio/player/gasp_in.mp3');

      // 5. Shared SFX
      tickSource = await SoLoud.instance.loadAsset('assets/audio/tick.mp3');
      powerupSource = await SoLoud.instance.loadAsset('assets/audio/ElevenLabs_Scary_stinger.mp3');
      impactSource = await SoLoud.instance.loadAsset('assets/audio/ElevenLabs_Impact.mp3');

      isInitialized = true;
      debugPrint('AudioManager initialized successfully.');
    } catch (e) {
      debugPrint('AUDIO MANAGER INIT ERROR: $e');
    }
  }

  // --- MUSIC PLAYBACK & CROSSFADE ---
  Future<void> playMenuMusic() async {
    if (menuMusic == null) return;
    await _playBgm(menuMusic!, volume: 0.5);
  }

  Future<void> playRandomInGameTrack() async {
    if (inGameTracks.isEmpty) return;
    final track = inGameTracks[Random().nextInt(inGameTracks.length)];
    await _playBgm(track, volume: 0.4);
  }

  void stopMusic() {
    if (_currentMusicHandle != null) {
      SoLoud.instance.stop(_currentMusicHandle!);
      _currentMusicHandle = null;
    }
  }

  Future<void> _playBgm(AudioSource source, {double volume = 0.5}) async {
    // Prevent restarting the track if it's already playing
    if (_currentMusicSource == source && _currentMusicHandle != null) return;
    
    stopMusic();
    _currentMusicSource = source;
    _currentMusicHandle = SoLoud.instance.play(source, volume: volume, looping: true);
  }

  // --- MASK SCARE TRIGGER ---
  void playMaskScare(String maskId) {
    final sound = maskScareSounds[maskId] ?? impactSource;
    if (sound != null) {
      SoLoud.instance.play(sound, volume: 1.0);
    }
  }

  void playEntityFootstep(String characterId, Vector2 worldPos, {bool isLocal = false}) {
    if (!isInitialized) {
      debugPrint('Cannot play footstep: AudioManager is not initialized!');
      return;
    }

    final footstepBank = characterFootsteps[characterId] ?? characterFootsteps['default'];
    if (footstepBank == null || footstepBank.isEmpty) {
      debugPrint('No footstep sounds registered for character: $characterId');
      return;
    }

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
      );
      SoLoud.instance.setRelativePlaySpeed(handle, randomPitch);
      SoLoud.instance.set3dSourceMinMaxDistance(handle, 2.0, 20.0);
      SoLoud.instance.set3dSourceAttenuation(handle, 1, 1.2);
    }
  }

  void playSpatialScare(String maskId, Vector2 worldPos) {
    if (!isInitialized) return;
    final source = maskScareSounds[maskId] ?? impactSource;
    if (source == null) return;

    const double audioScale = 50.0;
    final handle = SoLoud.instance.play3d(
      source,
      worldPos.x / audioScale,
      worldPos.y / audioScale,
      0.0,
      volume: 0.95,
    );
    SoLoud.instance.set3dSourceMinMaxDistance(handle, 2.0, 30.0);
    SoLoud.instance.set3dSourceAttenuation(handle, 1, 1.2);
  }
}