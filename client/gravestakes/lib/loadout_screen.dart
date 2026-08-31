import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';

import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'voxel_character_component.dart';

// --- DATA MODELS ---
class WearableDef {
  final String id;
  final String name;
  final String slotType;
  final String counterTarget;
  final String buffStat;
  final double buffValue;

  WearableDef.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        name = json['name'] as String,
        slotType = json['slot_type'] as String,
        counterTarget = json['counter_target'] as String,
        buffStat = json['buff_stat'] as String,
        buffValue = (json['buff_value'] as num).toDouble();
}

class LoadoutScreen extends StatefulWidget {
  const LoadoutScreen({super.key});

  @override
  State<LoadoutScreen> createState() => _LoadoutScreenState();
}

class _LoadoutScreenState extends State<LoadoutScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late MannequinGame _mannequinGame;

  // State Variables
  String _equippedCharacterId = 'default';
  String? _equippedNeck;
  String? _equippedArms;
  String? _equippedBelt;
  List<String> _equippedMasks = [];

  // Data Caches
  Map<String, dynamic> _characterBaseStats = {};
  List<Map<String, dynamic>> _inventory = [];
  Map<String, WearableDef> _wearablesCatalog = {};
  Map<String, Map<String, dynamic>> _charactersCatalog = {}; // <--- NEW: Character Catalog Cache

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this); // <--- UPDATED to 5 tabs (Characters + 4 equipment tabs)
    _mannequinGame = MannequinGame();
    _fetchLoadoutData();
  }

  Future<void> _fetchLoadoutData() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Fetch wearables catalog
      final wearablesRes = await Supabase.instance.client.from('wearables').select();
      for (var row in wearablesRes) {
        final w = WearableDef.fromJson(row);
        _wearablesCatalog[w.id] = w;
      }

      // --- NEW: Fetch characters catalog so we have display names for owned characters ---
      final charactersRes = await Supabase.instance.client.from('characters').select();
      for (var row in charactersRes) {
        _charactersCatalog[row['id'].toString()] = row;
      }

      // Fetch user loadout settings
      final loadoutRes = await Supabase.instance.client
          .from('user_loadouts')
          .select('slot_type, item_value')
          .eq('user_id', userId);
          
      for (var row in loadoutRes) {
        final slot = row['slot_type'] as String;
        final val = row['item_value'] as String;
        if (slot == 'character') _equippedCharacterId = val;
        else if (slot == 'wearable_neck') _equippedNeck = val;
        else if (slot == 'wearable_arms') _equippedArms = val;
        else if (slot == 'wearable_belt') _equippedBelt = val;
        else if (slot.startsWith('mask_')) _equippedMasks.add(val);
      }

      // Fetch base stats for currently equipped character
      _characterBaseStats = await Supabase.instance.client
          .from('characters')
          .select('*')
          .eq('id', _equippedCharacterId)
          .single();

      // Fetch user inventory
      _inventory = await Supabase.instance.client
          .from('user_inventory')
          .select('item_id, item_type')
          .eq('user_id', userId);

      // Async tell the mannequin to load its graphics!
      await _mannequinGame.updateCharacter(_equippedCharacterId);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Loadout Fetch Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _equipItem(String slotType, String itemId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() {
      if (slotType == 'character') {
        _equippedCharacterId = itemId;
        // Also update local base stats cache immediately for live stat previews
        if (_charactersCatalog.containsKey(itemId)) {
          _characterBaseStats = _charactersCatalog[itemId]!;
        }
      }
      else if (slotType == 'wearable_neck') _equippedNeck = itemId;
      else if (slotType == 'wearable_arms') _equippedArms = itemId;
      else if (slotType == 'wearable_belt') _equippedBelt = itemId;
      else if (slotType == 'mask') {
        if (_equippedMasks.contains(itemId)) {
          _equippedMasks.remove(itemId); 
        } else {
          if (_equippedMasks.length < 4) {
            _equippedMasks.add(itemId);
          } else {
            _equippedMasks[0] = itemId; 
          }
        }
      }
    });

    if (slotType == 'character') {
      await _mannequinGame.updateCharacter(itemId);
    } else {
      _mannequinGame.triggerEquipAnimation();
    }

    try {
      if (slotType == 'mask') {
        for (int i = 0; i < _equippedMasks.length; i++) {
          final payload = {
            'user_id': userId,
            'slot_type': 'mask_${i + 1}',
            'item_value': _equippedMasks[i],
          };
          await Supabase.instance.client.from('user_loadouts').upsert(
            payload, 
            onConflict: 'user_id, slot_type'
          );
        }
        
        for (int i = _equippedMasks.length; i < 4; i++) {
          final targetSlot = 'mask_${i + 1}';
          await Supabase.instance.client.from('user_loadouts')
              .delete()
              .eq('user_id', userId)
              .eq('slot_type', targetSlot);
        }
      } else {
        final payload = {
          'user_id': userId,
          'slot_type': slotType == 'character' ? 'character' : slotType,
          'item_value': itemId,
        };
        await Supabase.instance.client.from('user_loadouts').upsert(
          payload, 
          onConflict: 'user_id, slot_type'
        );
      }
    } on PostgrestException catch (e) {
      debugPrint('DATABASE REJECTION: [Code ${e.code}] ${e.message} \nDetails: ${e.details}');
    } catch (e) {
      debugPrint('UNKNOWN DB ERROR: $e');
    }
  }

  double _calculateModifier(String buffStat) {
    double modifier = 1.0;
    final equippedIds = [_equippedNeck, _equippedArms, _equippedBelt];
    
    for (var id in equippedIds) {
      if (id != null && _wearablesCatalog.containsKey(id)) {
        if (_wearablesCatalog[id]!.buffStat == buffStat) {
          modifier *= _wearablesCatalog[id]!.buffValue;
        }
      }
    }
    return modifier;
  }

  Widget _buildStatRow(String label, double baseValue, double modifier, bool isLowerBetter) {
    double finalValue = baseValue * modifier;
    bool isBuffed = isLowerBetter ? (finalValue < baseValue) : (finalValue > baseValue);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: Colors.white70)),
          Row(
            children: [
              Text(baseValue.toStringAsFixed(1), style: const TextStyle(fontSize: 14, color: Colors.grey)),
              if (modifier != 1.0) ...[
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward, size: 12, color: Colors.white30),
                const SizedBox(width: 8),
                Text(
                  finalValue.toStringAsFixed(1), 
                  style: TextStyle(
                    fontSize: 16, 
                    fontWeight: FontWeight.bold,
                    color: isBuffed ? Colors.greenAccent : Colors.redAccent,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(backgroundColor: Color(0xFF111111), body: Center(child: CircularProgressIndicator(color: Colors.purpleAccent)));
    }

    double baseSpeed = (_characterBaseStats['base_speed'] as num?)?.toDouble() ?? 200.0;
    double baseEnergy = (_characterBaseStats['max_energy'] as num?)?.toDouble() ?? 10.0;
    double baseRegen = (_characterBaseStats['energy_regen'] as num?)?.toDouble() ?? 0.5;

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: const Text('RELIQUARY LOADOUT', style: TextStyle(letterSpacing: 2.0, color: Colors.purpleAccent)),
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.all(24.0),
              color: Colors.black45,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((_characterBaseStats['name'] as String?)?.toUpperCase() ?? 'OPERATIVE', 
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  const Divider(color: Colors.purpleAccent),
                  const SizedBox(height: 16),
                  _buildStatRow('Movement Speed', baseSpeed, _calculateModifier('speed'), false),
                  _buildStatRow('Energy Capacity', baseEnergy, _calculateModifier('energy_max'), false),
                  _buildStatRow('Recharge Rate', baseRegen, _calculateModifier('regen'), false),
                  _buildStatRow('Audio Footprint', 100.0, _calculateModifier('footprint_reduction'), true),
                  
                  const Spacer(),
                  const Text('ACTIVE COUNTERS', style: TextStyle(fontSize: 14, color: Colors.orangeAccent, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  if (_equippedNeck != null && _wearablesCatalog.containsKey(_equippedNeck)) 
                    Text('• ${_wearablesCatalog[_equippedNeck]!.name}: ${_wearablesCatalog[_equippedNeck]!.counterTarget.toUpperCase()} DEFENSE', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  if (_equippedArms != null && _wearablesCatalog.containsKey(_equippedArms)) 
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text('• ${_wearablesCatalog[_equippedArms]!.name}: ${_wearablesCatalog[_equippedArms]!.counterTarget.toUpperCase()} DEFENSE', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ),
                  if (_equippedBelt != null && _wearablesCatalog.containsKey(_equippedBelt)) 
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text('• ${_wearablesCatalog[_equippedBelt]!.name}: ${_wearablesCatalog[_equippedBelt]!.counterTarget.toUpperCase()} DEFENSE', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: GameWidget(game: _mannequinGame),
          ),
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.black87,
              child: Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.purpleAccent,
                    labelColor: Colors.purpleAccent,
                    unselectedLabelColor: Colors.white54,
                    isScrollable: true,
                    tabs: const [
                      Tab(icon: Icon(Icons.person), text: 'Character'), // <--- NEW TAB
                      Tab(icon: Icon(Icons.masks), text: 'Masks'),
                      Tab(icon: Icon(Icons.diamond), text: 'Neck'),
                      Tab(icon: Icon(Icons.back_hand), text: 'Arms'),
                      Tab(icon: Icon(Icons.accessibility), text: 'Belt'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildInventoryGrid('character'), // <--- NEW TAB VIEW
                        _buildInventoryGrid('mask'),
                        _buildInventoryGrid('wearable_neck'),
                        _buildInventoryGrid('wearable_arms'),
                        _buildInventoryGrid('wearable_belt'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryGrid(String targetItemType) {
    // Note: The default character 'default' is always available even if not explicitly in user_inventory.
    List<Map<String, dynamic>> items = _inventory.where((i) => i['item_type'] == targetItemType).toList();
    
    if (targetItemType == 'character') {
      // Ensure 'default' character is always listed as owned/available
      bool hasDefault = items.any((i) => i['item_id'] == 'default');
      if (!hasDefault) {
        items.insert(0, {'item_type': 'character', 'item_id': 'default'});
      }
    }

    if (items.isEmpty) {
      return const Center(child: Text('No items in this category.', style: TextStyle(color: Colors.white54)));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final itemId = items[index]['item_id'] as String;
        bool isEquipped = targetItemType == 'character' 
            ? _equippedCharacterId == itemId 
            : (_equippedNeck == itemId || _equippedArms == itemId || _equippedBelt == itemId || _equippedMasks.contains(itemId));

        String displayTitle = itemId.replaceAll('_', ' ').toUpperCase();
        if (targetItemType == 'character' && _charactersCatalog.containsKey(itemId)) {
          displayTitle = _charactersCatalog[itemId]!['name'] ?? displayTitle;
        } else if (targetItemType != 'mask' && targetItemType != 'character' && _wearablesCatalog.containsKey(itemId)) {
          displayTitle = _wearablesCatalog[itemId]!.name;
        }

        return GestureDetector(
          onTap: () => _equipItem(targetItemType, itemId),
          child: Container(
            decoration: BoxDecoration(
              color: isEquipped ? Colors.purpleAccent.withOpacity(0.15) : Colors.grey[900],
              border: Border.all(color: isEquipped ? Colors.purpleAccent : Colors.white12, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isEquipped ? Icons.check_circle : (targetItemType == 'character' ? Icons.person : Icons.inventory), 
                      size: 32, 
                      color: isEquipped ? Colors.purpleAccent : Colors.white54
                    ),
                    const SizedBox(height: 12),
                    Text(displayTitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: isEquipped ? Colors.white : Colors.white70, fontWeight: isEquipped ? FontWeight.bold : FontWeight.normal)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ==========================================
// ISOLATED MANNEQUIN ENGINE (Self-Sufficient)
// ==========================================
class MannequinGame extends FlameGame {
  VoxelCharacterComponent? mannequin;
  double _rotationTimer = 0.0;

  @override
  Color backgroundColor() => Colors.transparent; 

  Future<void> updateCharacter(String characterId) async {
    if (mannequin != null) mannequin!.removeFromParent();

    Map<String, ui.Image> images = {};
    Map<String, dynamic>? rig;

    try {
      String zipPath = 'assets/character_assets.zip'; 
      
      if (characterId != 'default') {
        final charRes = await Supabase.instance.client
            .from('characters')
            .select('zip_asset_path')
            .eq('id', characterId)
            .maybeSingle();
        if (charRes != null && charRes['zip_asset_path'] != null) {
          zipPath = charRes['zip_asset_path'];
        }
      }

      final ByteData data = await rootBundle.load(zipPath);
      final List<int> bytes = data.buffer.asUint8List();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        if (file.isFile) {
          if (file.name == 'rig.json') {
            final jsonStr = utf8.decode(file.content as List<int>);
            rig = jsonDecode(jsonStr);
          } else if (file.name.endsWith('.png')) {
            final ui.Codec codec = await ui.instantiateImageCodec(file.content as Uint8List);
            final ui.FrameInfo frameInfo = await codec.getNextFrame();
            images[file.name] = frameInfo.image;
          }
        }
      }

      if (rig != null) {
        mannequin = VoxelCharacterComponent(
          images: images,
          rigData: rig,
          hitboxSize: Vector2(160, 160), 
        );
        
        if (hasLayout) {
          mannequin!.position = size / 2;
        }
        
        add(mannequin!);
      }
    } catch (e) {
      debugPrint('Mannequin isolated loading error: $e');
    }
  }

  void triggerEquipAnimation() {
    if (mannequin != null) {
      mannequin!.isHighlighted = true;
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mannequin != null) mannequin!.isHighlighted = false;
      });
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (mannequin != null) {
      _rotationTimer += dt * 0.4;
      mannequin!.targetAngle = _rotationTimer;
      mannequin!.isMoving = true; 
    }
  }

  @override
  void onGameResize(Vector2 gameSize) {
    super.onGameResize(gameSize);
    if (mannequin != null) {
      mannequin!.position = gameSize / 2;
    }
  }
}