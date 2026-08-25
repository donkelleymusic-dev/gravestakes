import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoadoutScreen extends StatefulWidget {
  const LoadoutScreen({super.key});

  @override
  State<LoadoutScreen> createState() => _LoadoutScreenState();
}

class _LoadoutScreenState extends State<LoadoutScreen> {
  final supabase = Supabase.instance.client;
  
  bool _isLoading = true;
  String _equippedColor = 'red'; 
  String? _equippedMask1;
  String? _equippedMask2;
  String _selectedMap = 'L1T1V1.0.0';

  final List<Map<String, dynamic>> _availableColors = [
    {'name': 'Blood Red (Default)', 'value': 'red', 'color': Colors.redAccent},
    {'name': 'Ecto Green', 'value': 'green', 'color': Colors.greenAccent},
    {'name': 'Void Purple', 'value': 'purple', 'color': Colors.purpleAccent},
    {'name': 'Phantom Blue', 'value': 'blue', 'color': Colors.cyanAccent},
  ];

  List<String> _ownedMasks = [];
  final List<String> _availableMaps = ['L1T1V1.0.0', 'L1T2V1.0.0'];

  @override
  void initState() {
    super.initState();
    _fetchLoadoutData();
  }

  Future<void> _fetchLoadoutData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      // Fetch equipped items AND owned inventory at the same time
      final responses = await Future.wait([
        supabase.from('user_loadouts').select('slot_type, item_value').eq('user_id', user.id),
        supabase.from('user_inventory').select('item_id').eq('user_id', user.id).eq('item_type', 'mask'),
      ]);

      if (mounted) {
        String? m1;
        String? m2;
        String color = 'red';
        String map = 'L1T1V1.0.0';

        // 1. Process what the player is actively wearing
        final loadouts = List<Map<String, dynamic>>.from(responses[0]);
        for (var row in loadouts) {
          final slot = row['slot_type'] as String? ?? '';
          final val = row['item_value'] as String?;

          if (val == null) continue;
          if (slot == 'flashlight_color') color = val;
          if (slot == 'mask_1') m1 = val;
          if (slot == 'mask_2') m2 = val;
          if (slot == 'preferred_map') map = val;
        }

        // 2. Process what the player actually owns
        final inventory = List<Map<String, dynamic>>.from(responses[1]);
        List<String> owned = inventory.map((row) => row['item_id'] as String).toList();

        setState(() {
          _equippedColor = color;
          // Ensure equipped masks are actually owned, otherwise set to null
          _equippedMask1 = (m1 != null && owned.contains(m1)) ? m1 : null;
          _equippedMask2 = (m2 != null && owned.contains(m2)) ? m2 : null;
          _selectedMap = map;
          _ownedMasks = owned;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading loadout: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _equipItem(String slotType, String? itemValue) async {
    final user = supabase.auth.currentUser;
    if (user == null || itemValue == null) return;

    String? slotToClear;
    final isClearing = itemValue == 'none';

    setState(() {
      if (slotType == 'mask_1') {
        if (!isClearing && _equippedMask2 == itemValue) {
          _equippedMask2 = null;
          slotToClear = 'mask_2';
        }
        _equippedMask1 = isClearing ? null : itemValue;
      } else if (slotType == 'mask_2') {
        if (!isClearing && _equippedMask1 == itemValue) {
          _equippedMask1 = null;
          slotToClear = 'mask_1';
        }
        _equippedMask2 = isClearing ? null : itemValue;
      } else if (slotType == 'flashlight_color') {
        _equippedColor = itemValue;
      } else if (slotType == 'preferred_map') {
        _selectedMap = itemValue;
      }
    });

    try {
      if (isClearing) {
        await supabase.from('user_loadouts').delete().eq('user_id', user.id).eq('slot_type', slotType);
      } else {
        await supabase.from('user_loadouts').upsert({
          'user_id': user.id,
          'slot_type': slotType,
          'item_value': itemValue,
        }, onConflict: 'user_id, slot_type');
      }

      final clearSlot = slotToClear;
      if (clearSlot != null) {
        await supabase.from('user_loadouts').delete().eq('user_id', user.id).eq('slot_type', clearSlot);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Loadout updated!'), backgroundColor: Colors.green, duration: Duration(milliseconds: 800)),
        );
      }
    } catch (e) {
      debugPrint('Error equipping item: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: const Text('LOADOUT & PREFERENCES', style: TextStyle(color: Colors.redAccent, letterSpacing: 1.5)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                const Text('FLASHLIGHT AURA COLOR', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 100,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _availableColors.length,
                    itemBuilder: (context, index) {
                      final item = _availableColors[index];
                      final isEquipped = _equippedColor == item['value'];

                      return GestureDetector(
                        onTap: () => _equipItem('flashlight_color', item['value']),
                        child: Container(
                          width: 110,
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey[900],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isEquipped ? Colors.amber : Colors.transparent, width: 2),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(width: 24, height: 24, decoration: BoxDecoration(color: item['color'], shape: BoxShape.circle)),
                              const SizedBox(height: 6),
                              Text(item['value'].toUpperCase(), style: TextStyle(color: isEquipped ? Colors.white : Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 24),

                const Text('MASK DECK (SLOT 1 & SLOT 2)', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                const SizedBox(height: 8),
                _ownedMasks.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text('You own no masks! Visit the Black Market to purchase your first Scary Mask.', style: TextStyle(color: Colors.redAccent)),
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Slot 1', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  value: _equippedMask1 ?? 'none',
                                  dropdownColor: Colors.grey[900],
                                  style: const TextStyle(color: Colors.white),
                                  items: [
                                    const DropdownMenuItem(value: 'none', child: Text('EMPTY SLOT', style: TextStyle(color: Colors.grey))),
                                    ..._ownedMasks.map((mask) {
                                      final isOtherSlot = _equippedMask2 == mask;
                                      final label = isOtherSlot ? 'MOVE ${mask.toUpperCase()} HERE' : mask.toUpperCase();
                                      return DropdownMenuItem(
                                        value: mask,
                                        child: Text(label, style: TextStyle(color: isOtherSlot ? Colors.amber : Colors.white, fontWeight: isOtherSlot ? FontWeight.bold : FontWeight.normal)),
                                      );
                                    }),
                                  ],
                                  onChanged: (val) => _equipItem('mask_1', val),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                const Text('Slot 2', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  value: _equippedMask2 ?? 'none',
                                  dropdownColor: Colors.grey[900],
                                  style: const TextStyle(color: Colors.white),
                                  items: [
                                    const DropdownMenuItem(value: 'none', child: Text('EMPTY SLOT', style: TextStyle(color: Colors.grey))),
                                    ..._ownedMasks.map((mask) {
                                      final isOtherSlot = _equippedMask1 == mask;
                                      final label = isOtherSlot ? 'MOVE ${mask.toUpperCase()} HERE' : mask.toUpperCase();
                                      return DropdownMenuItem(
                                        value: mask,
                                        child: Text(label, style: TextStyle(color: isOtherSlot ? Colors.amber : Colors.white, fontWeight: isOtherSlot ? FontWeight.bold : FontWeight.normal)),
                                      );
                                    }),
                                  ],
                                  onChanged: (val) => _equipItem('mask_2', val),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                const SizedBox(height: 24),

                const Text('PREFERRED MATCH MAP', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedMap,
                  dropdownColor: Colors.grey[900],
                  style: const TextStyle(color: Colors.white),
                  items: _availableMaps.map((map) => DropdownMenuItem(value: map, child: Text('Map Asset: $map'))).toList(),
                  onChanged: (val) => _equipItem('preferred_map', val),
                ),
              ],
            ),
    );
  }
}