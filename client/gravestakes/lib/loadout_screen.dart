import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
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
  final bool isActiveDefense;
  final double energyCost; 

  WearableDef.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        name = json['name'] as String,
        slotType = json['slot_type'] as String,
        counterTarget = json['counter_target'] as String,
        buffStat = json['buff_stat'] as String,
        buffValue = (json['buff_value'] as num).toDouble(),
        isActiveDefense = json['is_active_defense'] as bool? ?? false, 
        energyCost = (json['energy_cost'] as num?)?.toDouble() ?? 0.0;
}

class LoadoutScreen extends StatefulWidget {
  const LoadoutScreen({super.key});

  @override
  State<LoadoutScreen> createState() => _LoadoutScreenState();
}

class _LoadoutScreenState extends State<LoadoutScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late MannequinGame _mannequinGame;

  // --- COMMITTED STATE (Database) ---
  String _committedCharacterId = 'default';
  Map<String, String> _committedLoadout = {};
  List<String> _committedMasks = ['', '', '', ''];

  // --- DRAFT STATE (UI) ---
  String _draftCharacterId = 'default';
  Map<String, String> _draftLoadout = {};
  List<String> _draftMasks = ['', '', '', ''];

  // --- SELECTION STATE ---
  String? _selectedInventoryId;
  String? _selectedItemType; // 'character', 'mask', 'wearable_neck', etc.

  // --- DATA CACHES ---
  Map<String, dynamic> _characterBaseStats = {};
  List<Map<String, dynamic>> _inventory = [];
  Map<String, WearableDef> _wearablesCatalog = {};
  Map<String, Map<String, dynamic>> _charactersCatalog = {}; 

  bool _isLoading = true;

  bool get _hasUnsavedChanges => 
      _draftCharacterId != _committedCharacterId ||
      !mapEquals(_committedLoadout, _draftLoadout) || 
      !listEquals(_committedMasks, _draftMasks);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this); 
    _mannequinGame = MannequinGame();
    _fetchLoadoutData();
  }

  Future<void> _fetchLoadoutData() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final wearablesRes = await Supabase.instance.client.from('wearables').select();
      for (var row in wearablesRes) {
        final w = WearableDef.fromJson(row);
        _wearablesCatalog[w.id] = w;
      }

      final charactersRes = await Supabase.instance.client.from('characters').select();
      for (var row in charactersRes) {
        _charactersCatalog[row['id'].toString()] = row;
      }

      final loadoutRes = await Supabase.instance.client
          .from('user_loadouts')
          .select('slot_type, item_value')
          .eq('user_id', userId);
          
      for (var row in loadoutRes) {
        final slot = row['slot_type'] as String;
        final val = row['item_value'] as String;
        
        if (slot == 'character') {
          _committedCharacterId = val;
        } else if (slot.startsWith('mask_')) {
          int index = int.parse(slot.split('_')[1]) - 1;
          if (index >= 0 && index < 4) _committedMasks[index] = val;
        } else {
          _committedLoadout[slot] = val;
        }
      }

      _inventory = await Supabase.instance.client
          .from('user_inventory')
          .select('item_id, item_type')
          .eq('user_id', userId);

      _revertDraft(); 

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Loadout Fetch Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- DRAFT MECHANICS ---
  void _revertDraft() {
    setState(() {
      _draftCharacterId = _committedCharacterId;
      _draftLoadout = Map.from(_committedLoadout);
      _draftMasks = List.from(_committedMasks);
      _selectedInventoryId = null;
      _selectedItemType = null;
    });
    _mannequinGame.loadBaseCharacter(_draftCharacterId);
    if (_draftMasks[0].isNotEmpty) {
      _mannequinGame.setPreviewMask(_draftMasks[0]);
    } else {
      _mannequinGame.setPreviewMask(null);
    }
  }

  Future<void> _commitDraft() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isLoading = true);

    try {
      final basePayloads = [
        {'user_id': userId, 'slot_type': 'character', 'item_value': _draftCharacterId}
      ];
      _draftLoadout.forEach((slot, val) {
        basePayloads.add({'user_id': userId, 'slot_type': slot, 'item_value': val});
      });

      for (int i = 0; i < 4; i++) {
        final maskVal = _draftMasks[i];
        if (maskVal.isNotEmpty) {
          basePayloads.add({'user_id': userId, 'slot_type': 'mask_${i + 1}', 'item_value': maskVal});
        } else {
          await Supabase.instance.client.from('user_loadouts')
              .delete().eq('user_id', userId).eq('slot_type', 'mask_${i + 1}');
        }
      }

      for (var payload in basePayloads) {
        await Supabase.instance.client.from('user_loadouts').upsert(payload, onConflict: 'user_id, slot_type');
      }

      setState(() {
        _committedCharacterId = _draftCharacterId;
        _committedLoadout = Map.from(_draftLoadout);
        _committedMasks = List.from(_draftMasks);
        _selectedInventoryId = null;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Commit Error: $e');
      setState(() => _isLoading = false);
    }
  }

  void _selectInventoryItem(String itemType, String itemId) {
    setState(() {
      _selectedItemType = itemType;
      _selectedInventoryId = itemId;
    });

    if (itemType == 'character') {
      _draftCharacterId = itemId;
      _mannequinGame.loadBaseCharacter(itemId);
    } else if (itemType == 'mask') {
      _mannequinGame.setPreviewMask(itemId); 
    }
  }

  void _assignSelectedToSlot(String targetSlot) {
    if (_selectedInventoryId == null || _selectedItemType == null) return;

    setState(() {
      if (targetSlot.startsWith('mask_') && _selectedItemType == 'mask') {
        int index = int.parse(targetSlot.split('_')[1]) - 1;
        _draftMasks[index] = _selectedInventoryId!;
        _mannequinGame.setPreviewMask(_selectedInventoryId);
      } else if (_selectedItemType == targetSlot) {
        _draftLoadout[targetSlot] = _selectedInventoryId!;
        _mannequinGame.triggerEquipAnimation();
      }
    });
  }

  void _clearSlot(String targetSlot) {
    setState(() {
      if (targetSlot.startsWith('mask_')) {
        int index = int.parse(targetSlot.split('_')[1]) - 1;
        _draftMasks[index] = '';
        _mannequinGame.setPreviewMask(null);
      } else {
        _draftLoadout.remove(targetSlot);
      }
    });
  }

  // --- STAT CALCULATIONS ---
  double _getDraftStat(String buffStat, double baseValue) {
    double modifier = 1.0;
    _draftLoadout.forEach((slot, itemId) {
      if (_wearablesCatalog.containsKey(itemId) && _wearablesCatalog[itemId]!.buffStat == buffStat) {
        modifier *= _wearablesCatalog[itemId]!.buffValue;
      }
    });
    return baseValue * modifier;
  }

  Widget buildSafeItemThumbnail({required String? assetPath, required String slotType, double size = 26.0}) {
    IconData fallbackIcon = Icons.shield;
    Color iconColor = Colors.purpleAccent;

    if (slotType.contains('neck')) { fallbackIcon = Icons.diamond; iconColor = Colors.cyanAccent; } 
    else if (slotType.contains('arms')) { fallbackIcon = Icons.back_hand; iconColor = Colors.greenAccent; } 
    else if (slotType.contains('belt')) { fallbackIcon = Icons.accessibility; iconColor = Colors.orangeAccent; } 
    else if (slotType.contains('mask')) { fallbackIcon = Icons.masks; iconColor = Colors.redAccent; } 
    else if (slotType.contains('character')) { fallbackIcon = Icons.person; iconColor = Colors.purpleAccent; }

    if (assetPath == null || assetPath.trim().isEmpty) {
      return Icon(fallbackIcon, size: size, color: iconColor);
    }
    return Image.asset(
      assetPath, width: size, height: size, fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Icon(fallbackIcon, size: size, color: iconColor),
    );
  }

  Widget _buildStatRow(String label, double baseValue, double draftValue, bool isLowerBetter) {
    bool isBuffed = isLowerBetter ? (draftValue < baseValue) : (draftValue > baseValue);
    bool isNerfed = isLowerBetter ? (draftValue > baseValue) : (draftValue < baseValue);
    Color valColor = isBuffed ? Colors.greenAccent : (isNerfed ? Colors.redAccent : Colors.grey);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          Text(draftValue.toStringAsFixed(1), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: valColor)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(backgroundColor: Color(0xFF111111), body: Center(child: CircularProgressIndicator(color: Colors.purpleAccent)));
    }

    final activeCharData = _charactersCatalog[_draftCharacterId] ?? {};
    double baseSpeed = (activeCharData['base_speed'] as num?)?.toDouble() ?? 200.0;
    double baseEnergy = (activeCharData['max_energy'] as num?)?.toDouble() ?? 10.0;
    double baseRegen = 0.5;

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: const Text('VESSEL ATTUNEMENT', style: TextStyle(letterSpacing: 2.0, color: Colors.purpleAccent, fontSize: 16)),
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // ==========================================
          // ROW 1: CHARACTER STATS (75%) & 3D RIG (25%)
          // ==========================================
          Container(
            height: 125,
            color: Colors.black54,
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Row(
              children: [
                // LEFT: 75% Width Column
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          (activeCharData['name'] as String?)?.toUpperCase() ?? 'OPERATIVE', 
                          maxLines: 1,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.0),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Divider(color: Colors.purpleAccent, height: 6, thickness: 1),
                      _buildStatRow('Speed', baseSpeed, _getDraftStat('speed', baseSpeed), false),
                      _buildStatRow('Max Energy', baseEnergy, _getDraftStat('energy_max', baseEnergy), false),
                      _buildStatRow('Regen', baseRegen, _getDraftStat('regen', baseRegen), false),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // RIGHT: 25% Width Column for Voxel Mannequin
                Expanded(
                  flex: 1,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      _mannequinGame.isAutoRotating = false;
                      if (_mannequinGame.mannequin != null) {
                        _mannequinGame.mannequin!.targetAngle += details.delta.dx * 0.02;
                      }
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        color: Colors.black38,
                        child: GameWidget(game: _mannequinGame),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ==========================================
          // ROW 2: INVENTORY DECK (FULL-WIDTH EXPANDED)
          // ==========================================
          Expanded(
            child: Container(
              color: Colors.black87,
              child: Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.purpleAccent,
                    labelColor: Colors.purpleAccent,
                    unselectedLabelColor: Colors.white54,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 10),
                    tabs: const [
                      Tab(icon: Icon(Icons.person, size: 18), text: 'Char'),
                      Tab(icon: Icon(Icons.masks, size: 18), text: 'Masks'),
                      Tab(icon: Icon(Icons.diamond, size: 18), text: 'Neck'),
                      Tab(icon: Icon(Icons.back_hand, size: 18), text: 'Arms'),
                      Tab(icon: Icon(Icons.accessibility, size: 18), text: 'Belt'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildInventoryGrid('character'),
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

          // ==========================================
          // ROW 3: ATTUNED WARDS & MASKS DOCK
          // ==========================================
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            decoration: const BoxDecoration(
              color: Color(0xFF0D0D12),
              border: Border(top: BorderSide(color: Colors.purpleAccent, width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('ATTUNED WARDS & MASKS', 
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orangeAccent, letterSpacing: 1.0)),
                    Text(
                      _selectedInventoryId != null ? 'TAP SLOT TO BIND' : 'TAP TO DISMISS',
                      style: const TextStyle(fontSize: 9, color: Colors.white38),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                
                // Mask Slots (4 Across)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(4, (i) {
                    String mId = _draftMasks[i];
                    bool isSelected = _selectedItemType == 'mask';
                    return GestureDetector(
                      onTap: () => mId.isEmpty && isSelected ? _assignSelectedToSlot('mask_${i + 1}') : _clearSlot('mask_${i + 1}'),
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          border: Border.all(color: isSelected && mId.isEmpty ? Colors.greenAccent : Colors.white24),
                          color: mId.isNotEmpty ? Colors.redAccent.withOpacity(0.25) : Colors.black45,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: mId.isNotEmpty 
                          ? const Icon(Icons.masks, size: 22, color: Colors.redAccent) 
                          : const Icon(Icons.add, size: 18, color: Colors.white24),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 8),

                // Wearable Slots (3 Across)
                Row(
                  children: [
                    Expanded(child: _buildWearableSlot('wearable_neck', 'Neck', Icons.diamond, Colors.cyanAccent)),
                    const SizedBox(width: 6),
                    Expanded(child: _buildWearableSlot('wearable_arms', 'Arms', Icons.back_hand, Colors.greenAccent)),
                    const SizedBox(width: 6),
                    Expanded(child: _buildWearableSlot('wearable_belt', 'Belt', Icons.accessibility, Colors.orangeAccent)),
                  ],
                ),
              ],
            ),
          ),

          // ==========================================
          // BOTTOM CONFIRMATION / PURGE BAR
          // ==========================================
          if (_hasUnsavedChanges)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
              color: Colors.black,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _revertDraft,
                    child: const Text('DISMISS', style: TextStyle(color: Colors.redAccent, letterSpacing: 1.5, fontSize: 13)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    onPressed: _commitDraft,
                    child: const Text('SEAL ATTUNEMENT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 13)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWearableSlot(String slotKey, String label, IconData icon, Color color) {
    String? assignedId = _draftLoadout[slotKey];
    bool isSelected = _selectedItemType == slotKey;
    
    return GestureDetector(
      onTap: () => assignedId == null && isSelected ? _assignSelectedToSlot(slotKey) : _clearSlot(slotKey),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: isSelected && assignedId == null ? Colors.greenAccent : Colors.white24),
          color: assignedId != null ? color.withOpacity(0.15) : Colors.black45,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon, color: assignedId != null ? color : Colors.white30, size: 16),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                assignedId != null ? _wearablesCatalog[assignedId]?.name ?? 'UNKNOWN' : label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: assignedId != null ? Colors.white : Colors.white54,
                  fontSize: 10,
                  fontWeight: assignedId != null ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            Icon(
              assignedId == null ? Icons.add : Icons.close, 
              color: assignedId == null ? Colors.white24 : Colors.redAccent, 
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryGrid(String targetItemType) {
    List<Map<String, dynamic>> items = _inventory.where((i) => i['item_type'] == targetItemType).toList();
    if (targetItemType == 'character' && !items.any((i) => i['item_id'] == 'default')) {
      items.insert(0, {'item_type': 'character', 'item_id': 'default'});
    }

    if (items.isEmpty) return const Center(child: Text('No relics found in crypt.', style: TextStyle(color: Colors.white54)));

    // Center vertically in the available Expanded space
    return Center(
      child: ConstrainedBox(
        // Enforce a strict max height so cards never cause vertical overflow
        constraints: const BoxConstraints(maxHeight: 110), 
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          // Force horizontal scrolling ONLY
          scrollDirection: Axis.horizontal, 
          itemCount: items.length,
          separatorBuilder: (context, index) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final itemId = items[index]['item_id'] as String;
            bool isSelected = _selectedInventoryId == itemId;
            String displayTitle = itemId.replaceAll('_', ' ').toUpperCase();
            
            if (targetItemType == 'character' && _charactersCatalog.containsKey(itemId)) {
              displayTitle = _charactersCatalog[itemId]!['name'] ?? displayTitle;
            } else if (targetItemType != 'character' && targetItemType != 'mask' && _wearablesCatalog.containsKey(itemId)) {
              displayTitle = _wearablesCatalog[itemId]!.name;
            }

            return SizedBox(
              width: 90, // Fixed width for each horizontal card
              child: GestureDetector(
                onTap: () => _selectInventoryItem(targetItemType, itemId),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.purpleAccent.withOpacity(0.2) : Colors.grey[900],
                    border: Border.all(color: isSelected ? Colors.purpleAccent : Colors.white12, width: 1.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          buildSafeItemThumbnail(assetPath: null, slotType: targetItemType, size: 28.0),
                          const SizedBox(height: 8),
                          Text(
                            displayTitle, 
                            textAlign: TextAlign.center, 
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9, 
                              color: isSelected ? Colors.white : Colors.white70, 
                              fontFamily: 'Courier',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ==========================================
// SAFE MANNEQUIN ENGINE
// ==========================================
class MannequinGame extends FlameGame {
  VoxelCharacterComponent? mannequin;
  double _rotationTimer = 0.0;
  bool isAutoRotating = true; 

  @override
  Color backgroundColor() => Colors.transparent; 

  Future<void> loadBaseCharacter(String characterId) async {
    Map<String, ui.Image> images = {};
    Map<String, dynamic>? rig;

    try {
      String zipPath = 'assets/character_assets.zip'; 
      if (characterId != 'default') {
        final charRes = await Supabase.instance.client
            .from('characters').select('zip_asset_path').eq('id', characterId).maybeSingle();
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
            rig = jsonDecode(utf8.decode(file.content as List<int>));
          } else if (file.name.endsWith('.png')) {
            final codec = await ui.instantiateImageCodec(file.content as Uint8List);
            final frameInfo = await codec.getNextFrame();
            images[file.name] = frameInfo.image;
          }
        }
      }

      if (rig != null) {
        // Scaled down hitbox from (160, 160) to (54, 54) to shrink preview model ~3x
        final newMannequin = VoxelCharacterComponent(images: images, rigData: rig, hitboxSize: Vector2(54, 54));
        if (hasLayout) newMannequin.position = size / 2;
        
        removeWhere((component) => component is VoxelCharacterComponent);
        mannequin = newMannequin;
        add(mannequin!);
      }
    } catch (e) {
      debugPrint('Character ZIP load error: $e');
    }
  }

  Future<void> setPreviewMask(String? maskId) async {
    if (mannequin == null) return;
    
    isAutoRotating = false;
    mannequin!.targetAngle = 0.0; 

    if (maskId == null || maskId.isEmpty) {
      mannequin!.activeMaskImage = null;
      return;
    }
    try {
      mannequin!.activeMaskImage = await images.load('${maskId}_mask.png');
    } catch (e) {
      debugPrint('Mask asset missing: $e');
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
    if (mannequin != null && isAutoRotating) {
      _rotationTimer += dt * 0.4;
      mannequin!.targetAngle = _rotationTimer;
      mannequin!.isMoving = true; 
    }
  }

  @override
  void onGameResize(Vector2 gameSize) {
    super.onGameResize(gameSize);
    if (mannequin != null) mannequin!.position = gameSize / 2;
  }
}