import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:showcaseview/showcaseview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'voxel_character_component.dart';
import 'character_asset_manager.dart';

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
  final int price;
  final String currency;
  final String? assetPath;

  WearableDef.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        name = json['name'] as String,
        slotType = json['slot_type'] as String,
        counterTarget = json['counter_target'] as String? ?? '',
        buffStat = json['buff_stat'] as String? ?? '',
        buffValue = (json['buff_value'] as num?)?.toDouble() ?? 1.0,
        isActiveDefense = json['is_active_defense'] as bool? ?? false, 
        energyCost = (json['energy_cost'] as num?)?.toDouble() ?? 0.0,
        price = (json['price'] as num?)?.toInt() ?? 0,
        currency = json['currency'] as String? ?? 'shadows',
        assetPath = json['asset_path'] ?? json['thumbnail_path'];
}

class LoadoutScreen extends StatefulWidget {
  const LoadoutScreen({super.key});

  @override
  State<LoadoutScreen> createState() => _LoadoutScreenState();
}

class _LoadoutScreenState extends State<LoadoutScreen> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  late TabController _tabController;
  late MannequinGame _mannequinGame;

  // --- COMMITTED STATE (Database) ---
  String _committedCharacterId = 'default';
  Map<String, String> _committedLoadout = {};
  List<String> _committedMasks = ['', '', '', ''];

  // tutorial keys:
  final GlobalKey _maskSlotKey = GlobalKey();
  final GlobalKey _sealKey = GlobalKey();
  final GlobalKey _loadoutBackKey = GlobalKey();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey _masksTabKey = GlobalKey();
  final GlobalKey _inventoryMaskKey = GlobalKey();

  // --- DRAFT STATE (UI) ---
  String _draftCharacterId = 'default';
  Map<String, String> _draftLoadout = {};
  List<String> _draftMasks = ['', '', '', ''];

  // --- SELECTION STATE ---
  String? _selectedInventoryId;
  String? _selectedItemType;

  // --- DATA CACHES ---
  List<Map<String, dynamic>> _inventory = [];
  Map<String, WearableDef> _wearablesCatalog = {};
  Map<String, Map<String, dynamic>> _masksCatalog = {};
  Map<String, Map<String, dynamic>> _charactersCatalog = {}; 

  int _playerShadows = 0;
  int _playerCoins = 0;
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
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final responses = await Future.wait<dynamic>([
        supabase.from('wallets').select('shadows, coins').eq('id', userId).single(), // [0]
        supabase.from('wearables').select(),                                         // [1]
        supabase.from('masks').select().order('price'),                             // [2]
        supabase.from('characters').select(),                                       // [3]
        supabase.from('user_loadouts').select('slot_type, item_value').eq('user_id', userId), // [4]
        supabase.from('user_inventory').select('item_id, item_type').eq('user_id', userId),   // [5]
      ]);

      final walletData = responses[0] as Map<String, dynamic>;
      _playerShadows = walletData['shadows'] ?? 0;
      _playerCoins = walletData['coins'] ?? 0;

      final wearablesRes = List<Map<String, dynamic>>.from(responses[1]);
      _wearablesCatalog.clear();
      for (var row in wearablesRes) {
        final w = WearableDef.fromJson(row);
        _wearablesCatalog[w.id] = w;
      }

      final masksRes = List<Map<String, dynamic>>.from(responses[2]);
      _masksCatalog.clear();
      for (var row in masksRes) {
        _masksCatalog[row['id'].toString()] = row;
      }

      final charactersRes = List<Map<String, dynamic>>.from(responses[3]);
      _charactersCatalog.clear();
      for (var row in charactersRes) {
        _charactersCatalog[row['id'].toString()] = row;
      }

      final loadoutRes = List<Map<String, dynamic>>.from(responses[4]);
      _committedCharacterId = 'default';
      _committedLoadout.clear();
      _committedMasks = ['', '', '', ''];

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

      _inventory = List<Map<String, dynamic>>.from(responses[5]);

      _revertDraft(); 

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Crypt Fetch Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('tutorial_phase') == 'loadout') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scaffoldKey.currentContext != null) {
          ShowCaseWidget.of(_scaffoldKey.currentContext!).startShowCase([_masksTabKey]);
        }
      });
    }
  }

  Future<void> _buyItem(String itemType, String itemId, int price, String currency) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    int currentBalance = currency == 'coins' ? _playerCoins : _playerShadows;
    if (currentBalance < price) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Not enough ${currency.toUpperCase()}!'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      await supabase.rpc('buy_item', params: {
        'p_item_type': itemType,
        'p_item_id': itemId,
        'p_price': price,
        'p_currency': currency,
      });

      Sentry.addBreadcrumb(Breadcrumb(
        message: 'Purchased $itemId in Crypt for $price $currency',
        category: 'crypt_purchase',
      ));

      setState(() {
        if (currency == 'coins') {
          _playerCoins -= price;
        } else {
          _playerShadows -= price;
        }
        _inventory.add({'item_id': itemId, 'item_type': itemType});
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$itemId acquired!'), backgroundColor: Colors.green),
      );

      _selectInventoryItem(itemType, itemId);
    } catch (e) {
      debugPrint('Crypt Purchase Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Purchase failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showPurchaseConfirm({
    required String itemType,
    required String itemId,
    required String name,
    required int price,
    required String currency,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text('Acquire $name?', style: const TextStyle(color: Colors.white)),
        content: Text(
          'Unlock this $itemType for $price ${currency.toUpperCase()}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: currency == 'coins' ? Colors.amber[800] : Colors.red[800],
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _buyItem(itemType, itemId, price, currency);
            },
            child: Text('BUY ($price ${currency.toUpperCase()})', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
    final userId = supabase.auth.currentUser?.id;
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
          await supabase.from('user_loadouts')
              .delete().eq('user_id', userId).eq('slot_type', 'mask_${i + 1}');
        }
      }

      for (var payload in basePayloads) {
        await supabase.from('user_loadouts').upsert(payload, onConflict: 'user_id, slot_type');
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
    
    if (assetPath.startsWith('http')) {
      return Image.network(
        assetPath, width: size, height: size, fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Icon(fallbackIcon, size: size, color: iconColor),
      );
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
    double baseSwapSpeed = (activeCharData['swap_speed_modifier'] as num?)?.toDouble() ?? 1.0;
    double baseFootprint = 1.0;

    return ShowCaseWidget(
      builder: (context) => Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xFF111111),
        appBar: AppBar(
          title: const Text('THE CRYPT', style: TextStyle(letterSpacing: 2.0, color: Colors.purpleAccent, fontSize: 16)),
          backgroundColor: Colors.black,
          elevation: 0,
          leading: Showcase(
            key: _loadoutBackKey,
            description: 'STEP 9: Return to the Main Menu.',
            disposeOnTap: true,
            onTargetClick: () => Navigator.of(context).pop(),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Row(
                children: [
                  Text('👻 $_playerShadows', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 10),
                  Text('🪙 $_playerCoins', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        body: Column(
          children: [
          Container(
            height: 165,
            color: Colors.black54,
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Row(
              children: [
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
                      _buildStatRow('Swap Time', baseSwapSpeed, _getDraftStat('swap_speed_modifier', baseSwapSpeed), true),
                      _buildStatRow('Footstep Noise', baseFootprint, _getDraftStat('footprint_reduction', baseFootprint), true),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
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
                    tabs: [
                      const Tab(icon: Icon(Icons.person, size: 18), text: 'Char'),
                      Showcase(
                        key: _masksTabKey,
                        description: 'STEP 5: Tap here to view your Masks.',
                        disposeOnTap: true,
                        onTargetClick: () {
                          _tabController.animateTo(1);
                          Future.delayed(const Duration(milliseconds: 400), () {
                            if (mounted && _scaffoldKey.currentContext != null) {
                              ShowCaseWidget.of(_scaffoldKey.currentContext!).startShowCase([_inventoryMaskKey]);
                            }
                          });
                        },
                        child: const Tab(icon: Icon(Icons.masks, size: 18), text: 'Masks'),
                      ),
                      const Tab(icon: Icon(Icons.diamond, size: 18), text: 'Neck'),
                      const Tab(icon: Icon(Icons.back_hand, size: 18), text: 'Arms'),
                      const Tab(icon: Icon(Icons.accessibility, size: 18), text: 'Belt'),
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
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(4, (i) {
                    String mId = _draftMasks[i];
                    bool isSelected = _selectedItemType == 'mask';
                    
                    Widget slot = GestureDetector(
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

                    if (i == 0) {
                      return Showcase(
                        key: _maskSlotKey,
                        description: 'STEP 7: Tap this empty slot to bind your mask.',
                        disposeOnTap: true,
                        onTargetClick: () {
                          if (mId.isEmpty && isSelected) {
                            _assignSelectedToSlot('mask_${i + 1}');
                          } else {
                            _clearSlot('mask_${i + 1}');
                          }
                          Future.delayed(const Duration(milliseconds: 300), () {
                            if (mounted && _scaffoldKey.currentContext != null) {
                              ShowCaseWidget.of(_scaffoldKey.currentContext!).startShowCase([_sealKey]);
                            }
                          });
                        },
                        child: slot,
                      );
                    }
                    return slot;
                  }),
                ),
                const SizedBox(height: 8),

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
                  Showcase(
                    key: _sealKey,
                    description: 'STEP 8: Seal your attunement to save changes.',
                    disposeOnTap: true,
                    onTargetClick: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('tutorial_phase', 'match');
                      _commitDraft();
                      Future.delayed(const Duration(milliseconds: 500), () {
                        if (mounted && _scaffoldKey.currentContext != null) {
                          ShowCaseWidget.of(_scaffoldKey.currentContext!).startShowCase([_loadoutBackKey]);
                        }
                      });
                    },
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      ),
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        if (prefs.getString('tutorial_phase') == 'loadout') {
                          await prefs.setString('tutorial_phase', 'match');
                        }
                        _commitDraft();
                      },
                      child: const Text('SEAL ATTUNEMENT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
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
    if (targetItemType == 'character') {
      return _buildCharacterCryptGrid();
    }

    List<Map<String, dynamic>> allCatalogItems = [];
    if (targetItemType == 'mask') {
      allCatalogItems = _masksCatalog.values.toList();
    } else {
      allCatalogItems = _wearablesCatalog.values
          .where((w) => w.slotType == targetItemType)
          .map((w) => {
                'id': w.id,
                'name': w.name,
                'slot_type': w.slotType,
                'price': w.price,
                'currency': w.currency,
                'asset_path': w.assetPath,
              })
          .toList();
    }

    if (allCatalogItems.isEmpty) {
      return const Center(child: Text('No relics cataloged.', style: TextStyle(color: Colors.white54)));
    }
    
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 125), 
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          scrollDirection: Axis.horizontal, 
          itemCount: allCatalogItems.length,
          separatorBuilder: (context, index) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final item = allCatalogItems[index];
            final itemId = item['id'].toString();
            final name = item['name'] ?? itemId.replaceAll('_', ' ').toUpperCase();
            final price = item['price'] ?? 0;
            final currency = item['currency'] ?? 'shadows';
            final assetPath = item['asset_path'] ?? item['thumbnail_path'];

            bool isOwned = _inventory.any((i) => i['item_id'] == itemId && (i['item_type'] == targetItemType || targetItemType.startsWith('wearable')));
            bool isSelected = _selectedInventoryId == itemId;

            Color borderColor = Colors.white12;
            if (isSelected) borderColor = Colors.purpleAccent;
            else if (!isOwned) borderColor = (currency == 'coins' ? Colors.amber.withOpacity(0.4) : Colors.redAccent.withOpacity(0.4));

            Widget card = SizedBox(
              width: 95, 
              child: GestureDetector(
                onTap: () {
                  if (isOwned) {
                    _selectInventoryItem(targetItemType, itemId);
                  } else {
                    _showPurchaseConfirm(
                      itemType: targetItemType,
                      itemId: itemId,
                      name: name,
                      price: price,
                      currency: currency,
                    );
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? Colors.purpleAccent.withOpacity(0.2) 
                        : (isOwned ? Colors.grey[900] : Colors.black54),
                    border: Border.all(color: borderColor, width: isSelected ? 2 : 1.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          buildSafeItemThumbnail(assetPath: assetPath, slotType: targetItemType, size: 28.0),
                          const SizedBox(height: 6),
                          Text(
                            name, 
                            textAlign: TextAlign.center, 
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9, 
                              color: isSelected ? Colors.white : (isOwned ? Colors.white70 : Colors.white38),
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              fontFamily: 'Courier',
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (!isOwned)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(currency == 'coins' ? Icons.monetization_on : Icons.dark_mode, size: 9, color: currency == 'coins' ? Colors.amber : Colors.redAccent),
                                const SizedBox(width: 2),
                                Text('$price', style: TextStyle(color: currency == 'coins' ? Colors.amber : Colors.redAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                              ],
                            )
                          else
                            const Text('OWNED', style: TextStyle(color: Colors.greenAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );

            if (targetItemType == 'mask' && itemId == 'standard' && isOwned) {
              return Showcase(
                key: _inventoryMaskKey,
                description: 'STEP 6: Tap the Standard Mask to select it.',
                disposeOnTap: true,
                onTargetClick: () {
                  _selectInventoryItem(targetItemType, itemId);
                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (mounted && _scaffoldKey.currentContext != null) {
                      ShowCaseWidget.of(_scaffoldKey.currentContext!).startShowCase([_maskSlotKey]);
                    }
                  });
                },
                child: card,
              );
            }
            return card;
          },
        ),
      ),
    );
  }

  Widget _buildCharacterCryptGrid() {
    Map<String, List<Map<String, dynamic>>> groupedChars = {};

    _charactersCatalog.forEach((charId, charData) {
      String species = (charData['species'] ?? 'UNKNOWN').toString().toUpperCase();
      
      bool isOwned = charId == 'default' || _inventory.any((i) => i['item_id'] == charId);
      int currentShards = 0;
      int maxShards = charData['unlock_threshold'] ?? 50; 
      
      String state = isOwned ? 'owned' : (charData['currency'] != null ? 'store' : 'progression');

      groupedChars.putIfAbsent(species, () => []).add({
        'id': charId,
        'state': state, 
        'name': charData['name'] ?? charId,
        'thumbnail_path': charData['thumbnail_path'],
        'price': charData['price'] ?? 0,
        'currency': charData['currency'] ?? 'shadows',
        'current_shards': currentShards,
        'max_shards': maxShards,
      });
    });

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: groupedChars.keys.length,
      itemBuilder: (context, sectionIndex) {
        String speciesName = groupedChars.keys.elementAt(sectionIndex);
        List<Map<String, dynamic>> charsInSpecies = groupedChars[speciesName]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12, left: 4),
              child: Text(
                '$speciesName OPERATIVES', 
                style: const TextStyle(color: Colors.purpleAccent, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2.0)
              ),
            ),
            
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, 
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.70,
              ),
              itemCount: charsInSpecies.length,
              itemBuilder: (context, index) {
                final char = charsInSpecies[index];
                final charId = char['id'];
                final state = char['state'];
                
                bool isEquipped = _draftCharacterId == charId;
                
                Color borderColor = Colors.white12;
                if (isEquipped) borderColor = Colors.greenAccent;
                else if (state == 'store') borderColor = Colors.amber.withOpacity(0.5);
                else if (state == 'progression') borderColor = Colors.purpleAccent.withOpacity(0.5);

                return GestureDetector(
                  onTap: () {
                    if (state == 'owned') {
                      _selectInventoryItem('character', charId);
                    } else if (state == 'store') {
                      _showPurchaseConfirm(
                        itemType: 'character',
                        itemId: charId,
                        name: char['name'] ?? charId,
                        price: char['price'],
                        currency: char['currency'],
                      );
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isEquipped ? Colors.greenAccent.withOpacity(0.1) : Colors.black45,
                      border: Border.all(color: borderColor, width: isEquipped ? 2 : 1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Center(
                            child: buildSafeItemThumbnail(assetPath: char['thumbnail_path'], slotType: 'character', size: 36.0),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          decoration: const BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.vertical(bottom: Radius.circular(5)),
                          ),
                          child: Column(
                            children: [
                              Text(
                                char['name'].toString().toUpperCase(),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              
                              if (isEquipped)
                                const Text('EQUIPPED', textAlign: TextAlign.center, style: TextStyle(color: Colors.greenAccent, fontSize: 8, fontWeight: FontWeight.bold))
                              
                              else if (state == 'owned')
                                const Text('TAP TO BIND', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 8))
                              
                              else if (state == 'store')
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(char['currency'] == 'coins' ? Icons.monetization_on : Icons.dark_mode, size: 10, color: char['currency'] == 'coins' ? Colors.amber : Colors.redAccent),
                                    const SizedBox(width: 2),
                                    Text('${char['price']}', style: TextStyle(color: char['currency'] == 'coins' ? Colors.amber : Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                                  ],
                                )
                              
                              else if (state == 'progression')
                                Column(
                                  children: [
                                    Text('${char['current_shards']} / ${char['max_shards']}', style: const TextStyle(color: Colors.grey, fontSize: 8)),
                                    const SizedBox(height: 2),
                                    LinearProgressIndicator(
                                      value: char['current_shards'] / char['max_shards'],
                                      backgroundColor: Colors.black,
                                      color: Colors.purpleAccent,
                                      minHeight: 2,
                                    ),
                                  ],
                                )
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

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

      List<int> bytes = await CharacterAssetManager.getZipBytes(zipPath);

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