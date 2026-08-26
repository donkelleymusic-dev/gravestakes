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
  String? _equippedCharacter;
  String? _equippedMask1;
  String? _equippedMask2;
  String? _equippedPerk;
  String _selectedMap = 'L1T1V1.0.0';

  final List<Map<String, dynamic>> _availableColors = [
    {'name': 'Blood Red (Default)', 'value': 'red', 'color': Colors.redAccent},
    {'name': 'Ecto Green', 'value': 'green', 'color': Colors.greenAccent},
    {'name': 'Void Purple', 'value': 'purple', 'color': Colors.purpleAccent},
    {'name': 'Phantom Blue', 'value': 'blue', 'color': Colors.cyanAccent},
  ];

  // Dynamic inventory tracking
  List<String> _ownedCharacters = ['default']; 
  List<String> _ownedMasks = [];
  List<String> _ownedMaps = ['L1T1V1.0.0']; 
  List<String> _ownedPerks = [];

  @override
  void initState() {
    super.initState();
    _fetchLoadoutData();
  }

  Future<void> _fetchLoadoutData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final responses = await Future.wait<dynamic>([
        supabase.from('user_loadouts').select('slot_type, item_value').eq('user_id', user.id),
        supabase.from('user_inventory').select('item_type, item_id').eq('user_id', user.id),
        // Included legacy abilities table if you haven't migrated them to inventory yet
        supabase.from('player_loadouts').select('ability_id').eq('player_id', user.id), 
      ]);

      if (mounted) {
        String? char = 'default';
        String? m1;
        String? m2;
        String? perk;
        String color = 'red';
        String map = 'L1T1V1.0.0';

        // 1. Process Active Loadout
        final loadouts = List<Map<String, dynamic>>.from(responses[0]);
        for (var row in loadouts) {
          final slot = row['slot_type'] as String? ?? '';
          final val = row['item_value'] as String?;

          if (val == null) continue;
          if (slot == 'flashlight_color') color = val;
          if (slot == 'character') char = val;
          if (slot == 'mask_1') m1 = val;
          if (slot == 'mask_2') m2 = val;
          if (slot == 'perk') perk = val;
          if (slot == 'preferred_map') map = val;
        }

        // 2. Process Owned Inventory
        List<String> ownedChars = ['default'];
        List<String> ownedMasks = [];
        List<String> ownedMaps = ['L1T1V1.0.0'];
        
        final inventory = List<Map<String, dynamic>>.from(responses[1]);
        for (var row in inventory) {
          final type = row['item_type'] as String;
          final id = row['item_id'] as String;
          
          if (type == 'character' && !ownedChars.contains(id)) ownedChars.add(id);
          if (type == 'mask' && !ownedMasks.contains(id)) ownedMasks.add(id);
          if (type == 'map' && !ownedMaps.contains(id)) ownedMaps.add(id);
        }

        // 3. Process Legacy Perks (Abilities)
        List<String> ownedPerks = [];
        final abilityLoadouts = List<Map<String, dynamic>>.from(responses[2]);
        for (var row in abilityLoadouts) {
          final id = row['ability_id']?.toString();
          if (id != null && !ownedPerks.contains(id)) ownedPerks.add(id);
        }

        setState(() {
          _equippedColor = color;
          _equippedCharacter = ownedChars.contains(char) ? char : 'default';
          _equippedMask1 = (m1 != null && ownedMasks.contains(m1)) ? m1 : null;
          _equippedMask2 = (m2 != null && ownedMasks.contains(m2)) ? m2 : null;
          _equippedPerk = (perk != null && ownedPerks.contains(perk)) ? perk : null;
          _selectedMap = ownedMaps.contains(map) ? map : 'L1T1V1.0.0';
          
          _ownedCharacters = ownedChars;
          _ownedMasks = ownedMasks;
          _ownedMaps = ownedMaps;
          _ownedPerks = ownedPerks;
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
      if (slotType == 'character') _equippedCharacter = itemValue;
      else if (slotType == 'perk') _equippedPerk = isClearing ? null : itemValue;
      else if (slotType == 'preferred_map') _selectedMap = itemValue;
      else if (slotType == 'flashlight_color') _equippedColor = itemValue;
      else if (slotType == 'mask_1') {
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

      if (slotToClear != null) {
        await supabase.from('user_loadouts').delete().eq('user_id', user.id).eq('slot_type', slotToClear!); 
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

  Widget _buildDropdown(String label, String? value, List<String> items, String slotType, {bool allowClear = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: value ?? (allowClear ? 'none' : items.first),
          dropdownColor: Colors.grey[900],
          style: const TextStyle(color: Colors.white),
          items: [
            if (allowClear) const DropdownMenuItem(value: 'none', child: Text('EMPTY SLOT', style: TextStyle(color: Colors.grey))),
            ...items.map((item) => DropdownMenuItem(value: item, child: Text(item.toUpperCase()))),
          ],
          onChanged: (val) => _equipItem(slotType, val),
        ),
      ],
    );
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
                const Text('PHYSICAL VESSEL', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                const SizedBox(height: 12),
                _buildDropdown('Equipped Character', _equippedCharacter, _ownedCharacters, 'character'),
                
                const SizedBox(height: 24),
                const Text('FLASHLIGHT AURA', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
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
                const Text('TACTICAL DECK', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                const SizedBox(height: 12),
                _ownedMasks.isEmpty
                    ? const Text('You own no masks! Visit the Black Market.', style: TextStyle(color: Colors.grey))
                    : Row(
                        children: [
                          Expanded(child: _buildDropdown('Slot 1', _equippedMask1, _ownedMasks, 'mask_1', allowClear: true)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildDropdown('Slot 2', _equippedMask2, _ownedMasks, 'mask_2', allowClear: true)),
                        ],
                      ),

                const SizedBox(height: 24),
                const Text('PASSIVE PERKS', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                const SizedBox(height: 12),
                _ownedPerks.isEmpty
                    ? const Text('No perks unlocked yet.', style: TextStyle(color: Colors.grey))
                    : _buildDropdown('Equipped Perk', _equippedPerk, _ownedPerks, 'perk', allowClear: true),

                const SizedBox(height: 24),
                const Text('PREFERRED MATCH MAP', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                const SizedBox(height: 12),
                _buildDropdown('Map Asset', _selectedMap, _ownedMaps, 'preferred_map'),
              ],
            ),
    );
  }
}