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
  String _equippedColor = 'red'; // Default

  // Hardcoded for now. Later, this could be fetched from an 'inventory' table.
  final List<Map<String, dynamic>> _availableColors = [
    {'name': 'Blood Red (Default)', 'value': 'red', 'color': Colors.redAccent},
    {'name': 'Ecto Green', 'value': 'green', 'color': Colors.greenAccent},
    {'name': 'Void Purple', 'value': 'purple', 'color': Colors.purpleAccent},
    {'name': 'Phantom Blue', 'value': 'blue', 'color': Colors.cyanAccent},
  ];

  @override
  void initState() {
    super.initState();
    _fetchEquippedLoadout();
  }

  Future<void> _fetchEquippedLoadout() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final res = await supabase
          .from('user_loadouts')
          .select('item_value')
          .eq('user_id', user.id)
          .eq('slot_type', 'flashlight_color')
          .maybeSingle();

      if (mounted) {
        setState(() {
          if (res != null) {
            _equippedColor = res['item_value'] as String;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading loadout: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _equipItem(String slotType, String itemValue) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // Optimistic UI update for snappy feel
    setState(() {
      _equippedColor = itemValue;
    });

    try {
      await supabase.from('user_loadouts').upsert({
        'user_id': user.id,
        'slot_type': slotType,
        'item_value': itemValue,
      }, onConflict: 'user_id, slot_type');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Equipped $itemValue aura!'), 
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error equipping item: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to equip item.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: const Text('LOADOUT', style: TextStyle(color: Colors.redAccent, letterSpacing: 1.5)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AURA & FLASHLIGHT COLORS',
                    style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _availableColors.length,
                      itemBuilder: (context, index) {
                        final item = _availableColors[index];
                        final isEquipped = _equippedColor == item['value'];

                        return GestureDetector(
                          onTap: () => _equipItem('flashlight_color', item['value']),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[900],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isEquipped ? Colors.amber : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: item['color'],
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: (item['color'] as Color).withValues(alpha: 0.5),
                                            blurRadius: 8,
                                            spreadRadius: 2,
                                          )
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Text(
                                      item['name'],
                                      style: TextStyle(
                                        color: isEquipped ? Colors.white : Colors.grey[400],
                                        fontSize: 16,
                                        fontWeight: isEquipped ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                                if (isEquipped)
                                  const Icon(Icons.check_circle, color: Colors.amber)
                                else
                                  const Icon(Icons.circle_outlined, color: Colors.grey),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}