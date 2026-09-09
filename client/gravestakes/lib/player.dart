import 'package:flame/components.dart';
import 'package:flame/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flame/collisions.dart';
import 'dart:math';

import 'game.dart';
import 'floating_text.dart';
import 'scare_blast.dart';
import 'power_up.dart';
import 'chest_reward.dart';
import 'mask_data.dart';
import 'flying_scare_blast.dart';
import 'siren_blast.dart';
import 'critter.dart';
import 'voxel_character_component.dart';
import 'audio_manager.dart';
import 'game_map.dart';

class Player extends PositionComponent with KeyboardHandler, HasGameReference<GraveStakesGame> {
  final JoystickComponent leftJoystick;
  final JoystickComponent rightJoystick; 
  final RealtimeChannel channel; 
  final bool isGunner; 
  
  double glanceOffset = 0.0;

  int selectedMaskIndex = 0; 
  List<MaskData?> equippedMasks = List.filled(4, null);

  String get currentMaskId {
    if (selectedMaskIndex >= 0 && selectedMaskIndex < equippedMasks.length) {
      return equippedMasks[selectedMaskIndex]?.id ?? 'standard';
    }
    return 'standard';
  }

  double maxSpeed = 200.0;
  int score = 0;

  double facingAngle = 0;

  double flashlightBattery = 100.0;
  bool isFlashlightDead = false;
  bool isRecharging = false;

  bool isCharmed = false;
  double charmTimer = 0.0;
  Vector2? charmTargetPos;
  
  double _timeUntilNextFlicker = 0.0;
  double _flickerDuration = 0.0;
  bool isLightFlickeringOut = false;

  double get flashlightScale {
    if (isLightFlickeringOut) return 0.0; 
    if (isFlashlightDead && flashlightBattery <= 0) return 0.0; 
    if (isRecharging || isFlashlightDead) return (flashlightBattery / 100.0).clamp(0.1, 1.0); 
    return 1.0; 
  }

  final Map<String, dynamic> equippedWearables = {};
  bool hasActiveDefense = false;
  double activeDefenseCooldown = 0.0;

  double maskSwapAnimationTimer = 0.0;
  String? pendingMaskId;
  
  double footstepReductionMult = 1.0; 
  double maxEnergyMult = 1.0;         
  double speedMult = 1.0;             
  double energyRegenMult = 1.0;       

  final Set<String> activeCounters = {}; 
  
  double energy = 1.0; 
  double maxEnergy = 10.0;
  double energyRegenRate = 0.5;

  String equippedCharacterId = 'default';
  String species = 'humanoid';
  double swapSpeedModifier = 1.0;
  double visualScale = 1.0;

  double powerUpTimer = 0;
  bool get isPoweredUp => powerUpTimer > 0;
  
  double networkTick = 0; 
  final double networkRate = 0.12;

  Vector2 keyboardDelta = Vector2.zero();
  bool isStunned = false;
  double stunTimer = 0;
  double attackCooldown = 0;
  
  String equippedColorString = 'red'; 
  Color _baseColor = Colors.redAccent; 

  VoxelCharacterComponent? voxelComponent;
  RectangleComponent? _fallbackSprite;

  late TextComponent _buffTimerText;

  double highlightTimer = 0;
  double disguiseTimer = 0.0;
  double _tickAccumulator = 0.0;

  bool get isMoving => !keyboardDelta.isZero() || (!isGunner && !leftJoystick.delta.isZero());

  double _footstepTimer = 0.0;
  final Random _random = Random();

  bool hasInvisibilityCharge = false;
  bool isInvisible = false;
  double invisibilityTimer = 0.0;
  bool isDisguised = false;
  bool hasExtendedRange = false;
  int coinsEarned = 0;
  WallComponent? _disguiseWall;

  Vector2 charmerTarget = Vector2.zero();

  List<Vector2> _charmPath = [];
  double _pathRecalcTimer = 0.0;

  bool isPhasing = false;
  double phaseTimer = 0.0;
  final double maxPhaseDuration = 0.5; 

  bool isHoldingBreath = false;
  double breathHoldDuration = 4.0;       
  double breathHoldTimer = 0.0;
  double breathHoldCooldown = 0.0;       
  double breathExertionLevel = 0.0;      

  SoundHandle? _breathingHandle;

  void startHoldBreath() {
    if (breathHoldCooldown > 0 || isHoldingBreath || isStunned) return;
    if (breathExertionLevel > 0.7) return; 

    isHoldingBreath = true;
    breathHoldTimer = breathHoldDuration;
    
    footstepReductionMult = 0.1;
    
    if (_breathingHandle != null) {
      SoLoud.instance.stop(_breathingHandle!);
      _breathingHandle = null;
    }
  }

  void releaseHoldBreath({bool ranOutOfAir = false}) {
    if (!isHoldingBreath) return;
    isHoldingBreath = false;
    breathHoldCooldown = 8.0;
    footstepReductionMult = 1.0;

    if (ranOutOfAir) {
      final gasp = AudioManager.instance.gaspBreathSource;
      if (gasp != null) SoLoud.instance.play(gasp, volume: 0.8);
      breathExertionLevel = 1.0; 
    }
  }

  void triggerPhaseDash() {
    isPhasing = true;
    phaseTimer = maxPhaseDuration;
    channel.sendBroadcastMessage(event: 'move', payload: {
      'id': game.mySessionId, 'x': position.x, 'y': position.y, 
      'a': facingAngle, 'm': isMoving, 'i': true, 'sp': species 
    });
  }
  
 void applyTeamColor(int teamId) {
    final teamColor = teamId == 1 ? const Color(0xFF0072B2) : const Color(0xFFE69F00);
    
    add(CircleComponent(
      radius: 20.0,
      paint: Paint()
        ..color = teamColor.withAlpha(180)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0,
      anchor: Anchor.center,
      position: size / 2,
    ));
    
    if (_fallbackSprite != null) {
      _fallbackSprite!.paint.color = teamColor;
    }
  }

  void applyCharm(double duration, Vector2 charmerPos, {String? charmerId}) {
    if (isPhasing) return;

    if (activeCounters.contains('siren') && charmerId != null) {
      game.camera.viewport.add(FloatingText(
        text: 'PHASE INVERTED!', 
        worldPosition: Vector2(position.x - 20, position.y - 40),
      ));

      game.myChannel.sendBroadcastMessage(
        event: 'charm',
        payload: {
          'id': charmerId,
          'duration': duration,
          'charmer_x': position.x,
          'charmer_y': position.y,
        },
      );
      return;
    }

    isCharmed = true;
    charmTimer = duration;
    charmTargetPos = charmerPos;
  }

  void applyStun(double duration, {bool isVermin = false, String? attackerId}) {
    if (isPhasing) {
      game.camera.viewport.add(FloatingText(
        text: 'DODGED!', 
        worldPosition: Vector2(position.x - 20, position.y - 40),
      ));
      return;
    }

    if (isVermin && activeCounters.contains('vermin')) {
      game.camera.viewport.add(FloatingText(
        text: 'SWARM FILTERED!', 
        worldPosition: Vector2(position.x - 20, position.y - 40),
      ));
      return;
    }

    double finalDuration = duration;
    if (!isVermin && activeCounters.contains('standard') && duration > 0.5) {
      finalDuration = 0.5;
      game.camera.viewport.add(FloatingText(
        text: 'SIGNAL CLIPPED! (0.5s)', 
        worldPosition: Vector2(position.x - 20, position.y - 40),
      ));
    }

    isStunned = true;
    stunTimer = finalDuration;
  }

  void rechargeFlashlight() {
    if (flashlightBattery < 100.0 && !isRecharging) {
      isRecharging = true;
    }
  }

  void applyChestReward(ChestReward reward) {
    switch (reward.type) {
      case ChestRewardType.points: score += reward.value; break;
      case ChestRewardType.currency: coinsEarned += reward.value; break;
      case ChestRewardType.invisibility: hasInvisibilityCharge = true; break;
      case ChestRewardType.disguise:
        isDisguised = true;
        disguiseTimer = 40.0; 
        _tickAccumulator = 0.0; 
        break;
      case ChestRewardType.rangeIncrease: hasExtendedRange = true; break;
      case ChestRewardType.teleport:
        game.camera.viewport.add(FloatingText(text: 'WHOOSH!', worldPosition: Vector2(position.x - 20, position.y - 40)));
        final List<Vector2> allSafeNodes = [...game.gameMap.playerSpawns, ...game.gameMap.potentialBoxSpawns];
        if (allSafeNodes.isNotEmpty) {
          allSafeNodes.shuffle();
          Vector2 bestNode = allSafeNodes.first;
          for (var node in allSafeNodes) {
            if (node.distanceTo(position) > 300.0) {
              bestNode = node;
              break;
            }
          }
          position = game.gameMap.getSafeSpawnLocation(bestNode, size);
        }
        game.camera.viewport.add(FloatingText(text: 'POOF!', worldPosition: Vector2(position.x - 20, position.y - 40)));
        networkTick = networkRate; 
        break;
    }
  }

  void activateInvisibility() {
    if (!hasInvisibilityCharge || isInvisible) return;
    hasInvisibilityCharge = false;
    isInvisible = true;
    invisibilityTimer = 15.0; 
  }

  void triggerPrivateHighlight() {
    highlightTimer = 1.0; 
    if (_fallbackSprite != null) _fallbackSprite!.paint.color = Colors.white; 
  }

  Player(this.leftJoystick, this.rightJoystick, this.channel, {this.isGunner = false}) 
    : super(size: Vector2.all(32.0), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    priority = ((position.y + 16) * 10).toInt();
    await _fetchEquippedCosmetics();
    await fetchEquippedWearables();
    
    // Ensure my specific character zip is loaded!
    await GraveStakesGame.ensureCharacterLoaded(equippedCharacterId);

    add(RectangleHitbox(size: Vector2(32, 32), anchor: Anchor.center));

    _buffTimerText = TextComponent(
      position: Vector2(size.x / 2, -15),
      anchor: Anchor.center,
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.yellowAccent,
          fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0,
          fontFamily: 'Courier', shadows: [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
    );
    add(_buffTimerText);

    try {
      await game.images.load('mask_placeholder.png');
    } catch (e) {}

    try {
      _disguiseWall = WallComponent(
        position: Vector2(-9999, -9999), 
        tileSize: 32.0,
      );
      add(_disguiseWall!);
    } catch (e) {}

    try {
      final rig = GraveStakesGame.characterRigCache[equippedCharacterId] ?? game.loadedRigData;
      if (rig == null) throw Exception('Rig data is entirely missing!');

      voxelComponent = VoxelCharacterComponent(
        images: GraveStakesGame.characterImagesCache[equippedCharacterId] ?? game.loadedAssetImages, 
        rigData: rig,
        hitboxSize: size, 
      ) ..anchor = Anchor.bottomCenter
        ..position = size / 2;
      add(voxelComponent!);
    } catch (e) {
      _fallbackSprite = RectangleComponent(size: size, paint: Paint()..color = _baseColor);
      add(_fallbackSprite!);
    }
  }

  Future<void> fetchEquippedWearables() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final res = await Supabase.instance.client
          .from('player_loadouts')
          .select('ability_id, wearables(*)')
          .eq('player_id', user.id)
          .eq('is_equipped', true);

      if (res != null) {
        footstepReductionMult = 1.0;
        maxEnergyMult = 1.0;
        speedMult = 1.0;
        energyRegenMult = 1.0;
        activeCounters.clear();
        hasActiveDefense = false; 

        for (final item in res) {
          final wearable = item['wearables'] as Map<String, dynamic>?;
          if (wearable == null) continue;

          final counterTarget = wearable['counter_target'] as String?;
          final buffStat = wearable['buff_stat'] as String?;
          final buffVal = (wearable['buff_value'] as num?)?.toDouble() ?? 1.0;
          final isActiveDef = wearable['is_active_defense'] as bool? ?? false;

          if (counterTarget != null) activeCounters.add(counterTarget);
          if (isActiveDef) hasActiveDefense = true;

          switch (buffStat) {
            case 'footprint_reduction': footstepReductionMult = buffVal; break;
            case 'energy_max': maxEnergyMult = buffVal; break;
            case 'speed': speedMult = buffVal; break;
            case 'regen': energyRegenMult = buffVal; break;
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load equipped wearables: $e');
    }
  }

  Future<void> _fetchEquippedCosmetics() async {
    final user = Supabase.instance.client.auth.currentUser;
    String? mask1Id; String? mask2Id; String? mask3Id; String? mask4Id;
    
    if (user != null) {
      try {
        final res = await Supabase.instance.client.from('user_loadouts').select('slot_type, item_value').eq('user_id', user.id);
        final loadouts = List<Map<String, dynamic>>.from(res);
        for (var row in loadouts) {
          final slot = row['slot_type'] as String;
          final val = row['item_value'] as String;
          if (slot == 'flashlight_color') {
            equippedColorString = val; 
            switch (val) {
              case 'green': _baseColor = Colors.greenAccent; break;
              case 'purple': _baseColor = Colors.purpleAccent; break;
              case 'red': default: _baseColor = Colors.redAccent; break;
            }
          } else if (slot == 'mask_1') mask1Id = val;
          else if (slot == 'mask_2') mask2Id = val;
          else if (slot == 'mask_3') mask3Id = val;
          else if (slot == 'mask_4') mask4Id = val;
          else if (slot == 'character') equippedCharacterId = val;
        }

        final charRes = await Supabase.instance.client
            .from('characters')
            .select('*')
            .eq('id', equippedCharacterId)
            .maybeSingle();

        if (charRes != null) {
          maxSpeed = (charRes['base_speed'] as num?)?.toDouble() ?? 200.0;
          maxEnergy = (charRes['max_energy'] as num?)?.toDouble() ?? 10.0;
          energyRegenRate = (charRes['energy_regen'] as num?)?.toDouble() ?? 0.5;
          swapSpeedModifier = (charRes['swap_speed_modifier'] as num?)?.toDouble() ?? 1.0;
          visualScale = (charRes['visual_scale'] as num?)?.toDouble() ?? 1.0;
          species = charRes['species'] as String? ?? 'humanoid';
          
          energy = 1.0;
          scale = Vector2.all(visualScale);
        }
      } catch (e) {}
    }

    equippedMasks = List.filled(4, null);
    if (mask1Id != null && mask1Id.isNotEmpty) equippedMasks[0] = MaskRegistry.getMask(mask1Id);
    if (mask2Id != null && mask2Id.isNotEmpty) equippedMasks[1] = MaskRegistry.getMask(mask2Id);
    if (mask3Id != null && mask3Id.isNotEmpty) equippedMasks[2] = MaskRegistry.getMask(mask3Id);
    if (mask4Id != null && mask4Id.isNotEmpty) equippedMasks[3] = MaskRegistry.getMask(mask4Id);
  }

  void triggerAttack({int? forceMaskIndex}) {
    if (attackCooldown > 0 || maskSwapAnimationTimer > 0) return;
    
    int targetIndex = forceMaskIndex ?? 0;
    if (targetIndex < 0 || targetIndex >= 4) return;

    final currentMask = equippedMasks[targetIndex];
    if (currentMask == null) {
      game.camera.viewport.add(FloatingText(text: 'EMPTY SLOT!', worldPosition: Vector2(position.x - 40, position.y - 60)));
      return;
    }

    if (currentMask.id != currentMaskId) {
      pendingMaskId = currentMask.id;
      maskSwapAnimationTimer = 0.15; 
      selectedMaskIndex = targetIndex;
      
      if (voxelComponent != null) {
        voxelComponent!.triggerSwapAnimation();
      }
    }

    if (energy < currentMask.energyCost) {
      if (currentMask.id == 'standard') {
        energy = 0; 
      } else {
        game.camera.viewport.add(FloatingText(text: 'NOT ENOUGH ENERGY!', worldPosition: Vector2(position.x - 20, position.y - 60)));
        return; 
      }
    } else {
      energy -= currentMask.energyCost;
    }
    
    selectedMaskIndex = targetIndex;
    attackCooldown = currentMask.cooldown * swapSpeedModifier; 

    if (AudioManager.instance.isInitialized) {
      if (currentMask.id == 'standard' && AudioManager.instance.impactSource != null) {
        SoLoud.instance.play(AudioManager.instance.impactSource!);
      } else if (currentMask.id == 'flying' && AudioManager.instance.maskScareSounds['flying'] != null) {
        SoLoud.instance.play(AudioManager.instance.maskScareSounds['flying']!);
      }
    }

    final masterSeed = DateTime.now().millisecondsSinceEpoch;

    if (currentMask.isFlying) {
      game.scareManager.spawnBat(FlyingScareBlast(
        position: position.clone(), 
        angle: facingAngle,
        ownerId: game.mySessionId,
      )); 
    } else if (currentMask.swarmBehavior != SwarmBehavior.none) {
      for (int i = 0; i < currentMask.swarmCount; i++) {
        game.scareManager.spawnCritter(Critter(
          position: position.clone(), behavior: currentMask.swarmBehavior,
          seed: masterSeed, index: i, initialAngle: facingAngle, ownerId: game.mySessionId,
        )); 
      }
    } else {
      if (!isGunner && currentMask.id != 'siren') {
        final forward = Vector2(sin(facingAngle), -cos(facingAngle));
        double distanceToMove = 45.0; 
        while (distanceToMove > 0) {
          double step = min(5.0, distanceToMove);
          final testPos = position + (forward * step);
          if (!game.gameMap.checkCollision(testPos, size)) { position = testPos; distanceToMove -= step;
          } else { break; }
        }
      }
      
      if (currentMask.id == 'siren') {
        add(SirenBlast()..position = size / 2);
      } else {
        game.world.add(ScareBlast(position: position.clone(), angle: facingAngle - (pi / 2))..priority = priority + 5);
      }

      int victimsHit = game.triggerLocalScare(position, facingAngle, isPoweredUp, hasExtendedRange: hasExtendedRange, range: currentMask.range, maskId: currentMask.id);

      if (victimsHit > 0) {
        int baseScore = victimsHit * 100;
        int comboBonus = (victimsHit - 1) * 50 * (victimsHit - 1); 
        score += (baseScore + comboBonus);
        String popupText = victimsHit > 1 ? '+${baseScore + comboBonus} COMBO x$victimsHit!' : '+${baseScore + comboBonus}';
        game.camera.viewport.add(FloatingText(text: popupText, worldPosition: Vector2(position.x - 20, position.y - 50)));
      }
    }
    channel.sendBroadcastMessage(event: 'scare', payload: {'id': game.mySessionId, 'x': position.x, 'y': position.y, 'a': facingAngle, 'mask_id': currentMask.id, 'seed': masterSeed});
  }

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    keyboardDelta = Vector2.zero();
    if (game.isFpsMode) {
      const double rotationSpeed = 2.2; 

      if (keysPressed.contains(LogicalKeyboardKey.keyA) || keysPressed.contains(LogicalKeyboardKey.arrowLeft)) {
        facingAngle -= rotationSpeed * 0.016; 
      }
      if (keysPressed.contains(LogicalKeyboardKey.keyD) || keysPressed.contains(LogicalKeyboardKey.arrowRight)) {
        facingAngle += rotationSpeed * 0.016; 
      }

      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.keyZ) {
          facingAngle -= (pi / 2); 
        } else if (event.logicalKey == LogicalKeyboardKey.keyC) {
          facingAngle += (pi / 2); 
        }
      }

      if (keysPressed.contains(LogicalKeyboardKey.keyQ)) {
        glanceOffset = -pi / 4; 
      } else if (keysPressed.contains(LogicalKeyboardKey.keyE)) {
        glanceOffset = pi / 4;  
      } else {
        glanceOffset = 0.0;     
      }

      bool isMovingForward = keysPressed.contains(LogicalKeyboardKey.keyW) || keysPressed.contains(LogicalKeyboardKey.arrowUp);
      bool isMovingBackward = keysPressed.contains(LogicalKeyboardKey.keyS) || keysPressed.contains(LogicalKeyboardKey.arrowDown);

      if (isMovingForward && !isMovingBackward) {
        keyboardDelta = Vector2(sin(facingAngle), -cos(facingAngle));
      } else if (isMovingBackward && !isMovingForward) {
        double reverseAngle = facingAngle + pi;
        keyboardDelta = Vector2(sin(reverseAngle), -cos(reverseAngle));
      }

    } else {
      if (keysPressed.contains(LogicalKeyboardKey.keyW) || keysPressed.contains(LogicalKeyboardKey.arrowUp)) keyboardDelta.y -= 1;
      if (keysPressed.contains(LogicalKeyboardKey.keyS) || keysPressed.contains(LogicalKeyboardKey.arrowDown)) keyboardDelta.y += 1;
      if (keysPressed.contains(LogicalKeyboardKey.keyA) || keysPressed.contains(LogicalKeyboardKey.arrowLeft)) keyboardDelta.x -= 1;
      if (keysPressed.contains(LogicalKeyboardKey.keyD) || keysPressed.contains(LogicalKeyboardKey.arrowRight)) keyboardDelta.x += 1;
      if (!keyboardDelta.isZero()) keyboardDelta.normalize();
    }
    
    if (keysPressed.contains(LogicalKeyboardKey.space)) triggerAttack();
    if (keysPressed.contains(LogicalKeyboardKey.keyF) || keysPressed.contains(LogicalKeyboardKey.keyR)) {
      rechargeFlashlight();
    }
  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyM) {
    game.mapOverlay.toggle();
  }
    return true; 
  }

  @override
  void update(double dt) {    
    priority = ((position.y + 16) * 10).toInt();
    if (!game.gameStarted) return; 
    super.update(dt);

    game.gameMap.revealRadius(position, radius: 2);

    if (breathHoldCooldown > 0) breathHoldCooldown -= dt;

    if (isHoldingBreath) {
      breathHoldTimer -= dt;
      if (breathHoldTimer <= 0) {
        releaseHoldBreath(ranOutOfAir: true);
      }
    } else {
      if (isMoving) {
        breathExertionLevel = (breathExertionLevel + (dt * 0.25)).clamp(0.0, 1.0);
      } else {
        breathExertionLevel = (breathExertionLevel - (dt * 0.15)).clamp(0.0, 1.0);
      }

      if (breathExertionLevel > 0.4 && _breathingHandle == null && AudioManager.instance.heavyBreathingSource != null) {
        _breathingHandle = SoLoud.instance.play(AudioManager.instance.heavyBreathingSource!, volume: breathExertionLevel * 0.6, looping: true);
      } else if (_breathingHandle != null) {
        if (breathExertionLevel <= 0.1) {
          SoLoud.instance.stop(_breathingHandle!);
          _breathingHandle = null;
        } else {
          SoLoud.instance.setVolume(_breathingHandle!, breathExertionLevel * 0.6);
        }
      }
    }

    if (isPhasing) {
      phaseTimer -= dt;
      if (_fallbackSprite != null) {
        _fallbackSprite!.paint.color = _fallbackSprite!.paint.color.withOpacity(0.3);
      }
      if (phaseTimer <= 0) {
        isPhasing = false;
        if (_fallbackSprite != null) {
           _fallbackSprite!.paint.color = _fallbackSprite!.paint.color.withOpacity(1.0);
        }
      }
    }

    if (voxelComponent != null) {
      voxelComponent!.targetAngle = facingAngle - (pi / 2); 
      voxelComponent!.isMoving = isMoving;

      voxelComponent!.attackCooldown = attackCooldown;
      try {
        voxelComponent!.activeMaskImage = game.images.fromCache('${currentMaskId}_mask.png');
      } catch (e) {}
    }

    if (attackCooldown > 0) attackCooldown -= dt;
    if (maskSwapAnimationTimer > 0) maskSwapAnimationTimer -= dt;
    if (activeDefenseCooldown > 0) activeDefenseCooldown -= dt;
    
    bool isBuffActive = false;
    double lowestTimer = 999.0;
    List<String> activeBuffs = [];

    if (isDisguised) {
      disguiseTimer -= dt; 
      isBuffActive = true;
      if (disguiseTimer < lowestTimer) lowestTimer = disguiseTimer;
      activeBuffs.add('WALL: ${disguiseTimer.ceil()}s'); 
      
      if (disguiseTimer <= 0) { 
        isDisguised = false; 
        disguiseTimer = 0.0; 
      }
    }

    if (isDisguised) {
      if (voxelComponent != null) {
        voxelComponent!.isVisible = false;
      }
      if (_fallbackSprite != null) {
        _fallbackSprite!.paint.color = _fallbackSprite!.paint.color.withOpacity(0.0);
      }
    } else {
      if (voxelComponent != null) {
        voxelComponent!.isVisible = true;
        voxelComponent!.isInvisible = isInvisible; 
      }
      if (_fallbackSprite != null) {
        _fallbackSprite!.paint.color = _fallbackSprite!.paint.color.withOpacity(isInvisible ? 0.3 : 1.0);
      }
    }

    if (isDisguised) {
      if (_disguiseWall != null) _disguiseWall!.position = Vector2(-16, -16);
    } else {
      if (_disguiseWall != null) _disguiseWall!.position = Vector2(-9999, -9999);
    }

    if (isInvisible) {
      invisibilityTimer -= dt; isBuffActive = true;
      if (invisibilityTimer < lowestTimer) lowestTimer = invisibilityTimer;
      activeBuffs.add('INVIS: ${invisibilityTimer.ceil()}s');
      if (invisibilityTimer <= 0) { isInvisible = false; invisibilityTimer = 0.0; }
    }

    if (powerUpTimer > 0) {
      powerUpTimer -= dt; isBuffActive = true;
      if (powerUpTimer < lowestTimer) lowestTimer = powerUpTimer;
      if (powerUpTimer > 0) activeBuffs.add('POWER: ${powerUpTimer.ceil()}s');
    }

    _buffTimerText.text = activeBuffs.join('\n'); 

    if (isBuffActive) {
      _tickAccumulator += dt;
      if (_tickAccumulator >= 1.0) {
        _tickAccumulator -= 1.0;
        if (AudioManager.instance.isInitialized && AudioManager.instance.tickSource != null) {
          final tickVolume = lowestTimer <= 8.0 ? 1.0 : 0.05;
          SoLoud.instance.play(AudioManager.instance.tickSource!, volume: tickVolume);
        }
      }
    } else { _tickAccumulator = 0.0; }

    if (voxelComponent != null) {
      if (highlightTimer > 0) {
        highlightTimer -= dt; 
        voxelComponent!.isHighlighted = true;
      } else {
        voxelComponent!.isHighlighted = false;
      }
      if (isDisguised) {
        if (voxelComponent != null) voxelComponent!.isVisible = false;
        if (_fallbackSprite != null) _fallbackSprite!.paint.color = _fallbackSprite!.paint.color.withOpacity(0.0);
      } else {
        if (voxelComponent != null) {
          voxelComponent!.isVisible = true;
          voxelComponent!.isInvisible = isInvisible; 
        }
        if (_fallbackSprite != null) {
          _fallbackSprite!.paint.color = _fallbackSprite!.paint.color.withOpacity(isInvisible ? 0.3 : 1.0);
        }
      }
    }

   if (isDisguised) {
      if (_disguiseWall != null && _disguiseWall!.parent == null) add(_disguiseWall!);
    } else {
      if (_disguiseWall != null && _disguiseWall!.parent != null) _disguiseWall!.removeFromParent();
    }

    final worldComponents = game.world.children.toList();
    List<PowerUp> powerUpsToRemove = [];
    for (var comp in worldComponents) {
      if (comp is PowerUp) {
        if (position.distanceTo(comp.position) < 30) {
          powerUpTimer = 10.0; 
          try { if (AudioManager.instance.isInitialized && AudioManager.instance.powerupSource != null) SoLoud.instance.play(AudioManager.instance.powerupSource!); } catch (e) {}
          powerUpsToRemove.add(comp);
          channel.sendBroadcastMessage(event: 'consume_powerup', payload: {'id': comp.id});
          
          networkTick += dt;
          if (networkTick >= networkRate) {
            networkTick = 0;
            channel.sendBroadcastMessage(event: 'move', payload: {'id': game.mySessionId, 'x': position.x, 'y': position.y, 'a': facingAngle, 'c': equippedColorString, 's': score, 'd': isDisguised, 'm': isMoving, 'i': isInvisible,
              'f': flashlightScale, 'mask_id': currentMaskId, 'sp': species});
          }
        }
      }
    }
    for (var spark in powerUpsToRemove) spark.removeFromParent();

    if (isStunned) {
      stunTimer -= dt;
      if (voxelComponent != null) {
        voxelComponent!.isStunned = true;
        voxelComponent!.stunTimer = stunTimer;
      }
      if (_fallbackSprite != null) {
         int alpha = (150 + sin(stunTimer * 30) * 105).toInt().clamp(0, 255);
         _fallbackSprite!.paint.color = Colors.cyanAccent.withAlpha(alpha);
         _fallbackSprite!.position = Vector2(sin(stunTimer * 50) * 4, 0);
      }
      if (stunTimer <= 0) {
        isStunned = false; 
        if (voxelComponent != null) voxelComponent!.isStunned = false;
        if (_fallbackSprite != null) {
           _fallbackSprite!.paint.color = _baseColor;
           _fallbackSprite!.position = Vector2.zero();
        }
      }
      return; 
    }

    if (!rightJoystick.delta.isZero()) facingAngle = rightJoystick.delta.screenAngle();

    if (isCharmed) {
      charmTimer -= dt;
      if (charmTimer <= 0) {
        isCharmed = false;
        _charmPath.clear();
      } else {
        _pathRecalcTimer -= dt;
        if (_pathRecalcTimer <= 0) {
          _charmPath = game.gameMap.findPath(position, charmerTarget);
          _pathRecalcTimer = 0.25; 
        }

        Vector2 forcedDelta = Vector2.zero();

        if (_charmPath.isNotEmpty) {
          if (position.distanceTo(_charmPath.first) < 15.0) {
            _charmPath.removeAt(0);
          }
          
          if (_charmPath.isNotEmpty) {
            forcedDelta = (_charmPath.first - position).normalized();
          } else {
            forcedDelta = (charmerTarget - position).normalized();
          }
        } else {
           forcedDelta = (charmerTarget - position).normalized();
        }

        facingAngle = forcedDelta.screenAngle();
        
        final potentialPosition = position + (forcedDelta * 120.0 * dt);
        if (!game.gameMap.checkCollision(Vector2(potentialPosition.x, position.y), size)) position.x = potentialPosition.x;
        if (!game.gameMap.checkCollision(Vector2(position.x, potentialPosition.y), size)) position.y = potentialPosition.y;
      }
      
    } else if (!isGunner) {
      Vector2 movementDelta = Vector2.zero();

      if (!keyboardDelta.isZero()) { 
        movementDelta = keyboardDelta;
      } else if (!leftJoystick.delta.isZero()) { 
        if (game.isFpsMode) {
          const double touchRotationSpeed = 2.5;
          facingAngle += leftJoystick.relativeDelta.x * touchRotationSpeed * dt;

          double forwardStep = -leftJoystick.relativeDelta.y; 
          
          if (forwardStep.abs() > 0.1) {
            final forwardVector = Vector2(sin(facingAngle), -cos(facingAngle));
            movementDelta = forwardVector * forwardStep;
          } else {
            movementDelta = Vector2.zero();
          }

        } else {
          movementDelta = leftJoystick.relativeDelta;
        }
      }

      if (!movementDelta.isZero()) {
        if (!game.isFpsMode && rightJoystick.delta.isZero()) {
          facingAngle = movementDelta.screenAngle();
        }

        double currentSpeed = isPoweredUp ? 280.0 : maxSpeed;
        final potentialPosition = position + (movementDelta * currentSpeed * dt);
        final oldPosition = position.clone();

        if (!game.gameMap.checkCollision(Vector2(potentialPosition.x, position.y), size)) position.x = potentialPosition.x;
        if (!game.gameMap.checkCollision(Vector2(position.x, potentialPosition.y), size)) position.y = potentialPosition.y;

        double actualVelocity = position.distanceTo(oldPosition) / dt; 
        if (actualVelocity > 5.0) {
           double dynamicInterval = 0.40 * (200.0 / actualVelocity);
           dynamicInterval += (_random.nextDouble() * 0.1) - 0.05; 
           _footstepTimer += dt;
           
           if (_footstepTimer >= dynamicInterval) {
             _footstepTimer = 0.0; 
             AudioManager.instance.playEntityFootstep(equippedCharacterId, position, isLocal: true);
             
             if (actualVelocity > 100) {
                double timeRemaining = game.gameTimer.timeLeft;
                double panicMultiplier = 1.0 + ((180.0 - timeRemaining) / 180.0) * 2.0;
                
                double noiseRadius = 100 * panicMultiplier * footstepReductionMult;
                
                for (var bot in game.bots) {
                  if (bot.position.distanceTo(position) <= noiseRadius) {
                    bot.hearLoudNoise(position);
                  }
                }
              }
           }
        } else { _footstepTimer = 0.0; }
      } else { _footstepTimer = 0.0; }
    }

    double timeRemaining = game.gameTimer.timeLeft;
    double regenMultiplier = 0.4; 
    if (timeRemaining <= 120 && timeRemaining > 60) regenMultiplier = 0.7; 
    if (timeRemaining <= 60) regenMultiplier = 1.3; 
    
    energy = (energy + (energyRegenRate * regenMultiplier * dt)).clamp(0.0, maxEnergy);

    if (isRecharging) {
      flashlightBattery += (100.0 / 6.0) * dt; 
      isLightFlickeringOut = false;
      
      if (flashlightBattery >= 100.0) {
        flashlightBattery = 100.0;
        isRecharging = false;
        isFlashlightDead = false;
      }
    } else if (!isFlashlightDead) {
      flashlightBattery -= (100.0 / 70.0) * dt;
      
      if (flashlightBattery <= 0.0) {
        flashlightBattery = 0.0;
        isFlashlightDead = true;
        hasExtendedRange = false; 
        isLightFlickeringOut = false;
      } 
      else if (flashlightBattery < 15.0) {
        if (_flickerDuration > 0) {
          _flickerDuration -= dt;
          isLightFlickeringOut = true;
        } else {
          isLightFlickeringOut = false;
          _timeUntilNextFlicker -= dt;
          if (_timeUntilNextFlicker <= 0) {
            _flickerDuration = 0.1 + (_random.nextDouble() * 0.3); 
            _timeUntilNextFlicker = 1.0 + (_random.nextDouble() * 3.0); 
          }
        }
      } else {
        isLightFlickeringOut = false;
      }
    }

    networkTick += dt;
    if (networkTick >= networkRate) {
      networkTick = 0;
      channel.sendBroadcastMessage(event: 'move', payload: {'id': game.mySessionId, 'x': position.x, 'y': position.y, 'a': facingAngle, 'c': equippedColorString, 's': score, 'd': isDisguised, 'm': isMoving, 'i': isInvisible,
              'f': flashlightScale, 'mask_id': currentMaskId, 'sp': species});
    }
  }
}