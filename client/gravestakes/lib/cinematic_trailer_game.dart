import 'dart:math';
import 'package:flame/game.dart';
import 'package:flame/effects.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import 'game_map.dart';
import 'game.dart'; 
import 'voxel_character_component.dart';

class CinematicTrailerGame extends FlameGame {
  double _elapsedTime = 0.0;
  bool _scene1Triggered = false;
  bool _scene2Triggered = false;
  bool _scene3Triggered = false;
  bool _scene4Triggered = false;
  
  bool _isHeroTurning = false;
  
  late VoxelCharacterComponent actorHero;
  late VoxelCharacterComponent actorMonster;
  late RectangleComponent cinematicDarkness;

  @override
  Color backgroundColor() => const Color(0xFF000000);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // 1. Load the Map
    add(GameMap(roomId: 'cinematic_set', mapName: 'L1T1V1.0.0'));

    // 2. Fetch or Unzip Voxel Assets
    if (GraveStakesGame.characterRigCache['default'] == null) {
      debugPrint('Cache empty. Extracting default voxel assets...');
      final ByteData data = await rootBundle.load('assets/character_assets.zip');
      final archive = ZipDecoder().decodeBytes(data.buffer.asUint8List());
      
      Map<String, ui.Image> loadedImages = {};
      Map<String, dynamic>? loadedRig;
      
      for (final file in archive) {
        if (file.isFile) {
          if (file.name == 'rig.json') {
            loadedRig = jsonDecode(utf8.decode(file.content as List<int>));
          } else if (file.name.endsWith('.png')) {
            final ui.Codec codec = await ui.instantiateImageCodec(file.content as Uint8List);
            final ui.FrameInfo frameInfo = await codec.getNextFrame();
            loadedImages[file.name] = frameInfo.image;
          }
        }
      }
      if (loadedRig != null) {
        GraveStakesGame.characterRigCache['default'] = loadedRig;
        GraveStakesGame.characterImagesCache['default'] = loadedImages;
      }
    }

    final rig = GraveStakesGame.characterRigCache['default'];
    final images = GraveStakesGame.characterImagesCache['default'];

    if (rig == null || images == null) {
      debugPrint('CRITICAL: Voxel assets failed to extract.');
      return;
    }

    // 3. Spawn Voxel Actors
    actorHero = VoxelCharacterComponent(
      images: images, 
      rigData: rig, 
      hitboxSize: Vector2(64, 64),
    )
      ..position = Vector2(1000, 500)
      ..targetAngle = -pi / 2 
      ..isMoving = true
      ..priority = 10;
    
    actorMonster = VoxelCharacterComponent(
      images: images, 
      rigData: rig, 
      hitboxSize: Vector2(64, 64),
    )
      ..position = Vector2(1400, 500)
      ..targetAngle = -pi / 2 
      ..isMoving = true
      ..priority = 10;

    try {
      actorMonster.activeMaskImage = await this.images.load('siren_mask.png');
    } catch (e) {
      debugPrint('Siren mask not found, using base face.');
    }
    
    add(actorHero);
    add(actorMonster);

    // 4. Fake Darkness Overlay
    cinematicDarkness = RectangleComponent(
      size: Vector2(5000, 5000), 
      paint: Paint()..color = Colors.black.withOpacity(0.8), 
      position: Vector2(-2500, -2500),
      priority: 9, 
    );
    add(cinematicDarkness);

    camera.viewfinder.position = Vector2(500, 500); 
    camera.viewfinder.zoom = 1.2; 
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsedTime += dt;

    // Manually handle the 2.5D rotation during the jump scare reveal
    if (_isHeroTurning) {
      // Slowly rotate from 0 (facing up/away) to pi/2 (facing right)
      actorHero.targetAngle += dt * 1.5; 
      if (actorHero.targetAngle >= pi / 2) {
        actorHero.targetAngle = pi / 2;
        _isHeroTurning = false;
      }
    }

    // BEAT 1 & 2: The Fly-By (0s - 5s)
    if (_elapsedTime > 0.5 && !_scene1Triggered) {
      _scene1Triggered = true;
      debugPrint('TIMECODE [${_elapsedTime.toStringAsFixed(2)}]: HERO RUNS PAST CAMERA');
      
      actorHero.add(MoveToEffect(Vector2(-200, 500), EffectController(duration: 2.0)));
      
      Future.delayed(const Duration(milliseconds: 1800), () {
        debugPrint('TIMECODE [${_elapsedTime.toStringAsFixed(2)}]: MONSTER CHASES');
        actorMonster.add(MoveToEffect(Vector2(-200, 500), EffectController(duration: 1.2)));
      });
    }

    // BEAT 3: The Corner Hiding Spot (5s - 8s)
    if (_elapsedTime > 5.0 && !_scene2Triggered) {
      _scene2Triggered = true;
      debugPrint('TIMECODE [${_elapsedTime.toStringAsFixed(2)}]: CUT TO CORNER. HERO HIDES.');
      
      // Stop running and face the wall (Angle 0 = facing away from camera)
      actorHero.isMoving = false;
      actorHero.targetAngle = 0.0; 
      actorHero.position = Vector2(800, 800);
      
      camera.follow(actorHero);
      camera.viewfinder.zoom = 1.8; 
    }

    // BEAT 4 & 5: The Blackout (8s - 12s)
    if (_elapsedTime > 8.0 && !_scene3Triggered) {
      _scene3Triggered = true;
      debugPrint('TIMECODE [${_elapsedTime.toStringAsFixed(2)}]: FLASHLIGHT DIES.');
      
      cinematicDarkness.paint.color = Colors.black.withOpacity(1.0); // Pitch black
      
      // Teleport monster next to hero, facing left toward him
      actorMonster.isMoving = false;
      actorMonster.targetAngle = -pi / 2;
      actorMonster.position = Vector2(850, 800); 
    }

    // BEAT 6 & 7: The Reveal & Jump Scare (12s - 16s)
    if (_elapsedTime > 12.0 && !_scene4Triggered) {
      _scene4Triggered = true;
      debugPrint('TIMECODE [${_elapsedTime.toStringAsFixed(2)}]: FLASHLIGHT ON. SNAP TURN.');
      
      cinematicDarkness.paint.color = Colors.black.withOpacity(0.8); // Light back on
      
      // Trigger the slow turn logic in the update loop
      _isHeroTurning = true; 
      
      Future.delayed(const Duration(milliseconds: 2100), () {
        debugPrint('TIMECODE [${_elapsedTime.toStringAsFixed(2)}]: JUMP SCARE. CUT TO BLACK.');
        
        // Trigger the mask pop/shake animation on the Voxel engine
        actorMonster.triggerScareAnimation();
        
        Future.delayed(const Duration(milliseconds: 300), () {
           cinematicDarkness.paint.color = Colors.black.withOpacity(1.0);
        });
      });
    }
  }
}