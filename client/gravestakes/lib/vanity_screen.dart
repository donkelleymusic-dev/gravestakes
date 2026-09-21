import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'synth_manager.dart';

class VanityScreen extends StatefulWidget {
  const VanityScreen({super.key});

  @override
  State<VanityScreen> createState() => _VanityScreenState();
}

class _VanityScreenState extends State<VanityScreen> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late TabController _tabController;
  
  bool _isLoading = true;
  List<Map<String, dynamic>> _inventory = [];
  Map<String, Map<String, dynamic>> _catalog = {};
  
  // Committed Database State
  Map<String, String> _committedLoadout = {};
  // UI Draft State
  Map<String, String> _draftLoadout = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchCosmeticsData();
  }

  Future<void> _fetchCosmeticsData() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final responses = await Future.wait([
        supabase.from('cosmetics_catalog').select(),
        supabase.from('user_inventory').select('item_id').eq('user_id', userId).eq('item_type', 'cosmetic'),
        supabase.from('user_loadouts').select('slot_type, item_value').eq('user_id', userId),
      ]);

      _catalog.clear();
      for (var row in List<Map<String, dynamic>>.from(responses[0])) {
        _catalog[row['id']] = row;
      }

      _inventory = List<Map<String, dynamic>>.from(responses[1]);

      _committedLoadout.clear();
      for (var row in List<Map<String, dynamic>>.from(responses[2])) {
        final slot = row['slot_type'] as String;
        // Only track vanity slots here
        if (['taunt_1', 'particle_trail', 'wall_skin'].contains(slot)) {
          _committedLoadout[slot] = row['item_value'] as String;
        }
      }
      
      _revertDraft();
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Vanity Fetch Error: $e');
    }
  }

  void _revertDraft() {
    setState(() => _draftLoadout = Map.from(_committedLoadout));
  }

  Future<void> _commitDraft() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isLoading = true);
    try {
      for (String slot in ['taunt_1', 'particle_trail', 'wall_skin']) {
        if (_draftLoadout.containsKey(slot)) {
          await supabase.from('user_loadouts').upsert(
            {'user_id': userId, 'slot_type': slot, 'item_value': _draftLoadout[slot]}, 
            onConflict: 'user_id, slot_type'
          );
        } else {
          await supabase.from('user_loadouts').delete().eq('user_id', userId).eq('slot_type', slot);
        }
      }
      _committedLoadout = Map.from(_draftLoadout);
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cosmetics Saved!', style: TextStyle(color: Colors.purpleAccent))));
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _equipItem(String slotType, String itemId) {
    SynthManager.instance.playMagicTap();
    setState(() => _draftLoadout[slotType] = itemId);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: Color(0xFF111111), body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: const Text('THE ECHO CHAMBER', style: TextStyle(color: Colors.purpleAccent, letterSpacing: 2.0, fontSize: 16)),
        backgroundColor: Colors.black,
        actions: [
          if (_draftLoadout.toString() != _committedLoadout.toString())
            TextButton(
              onPressed: _commitDraft, 
              child: const Text('SAVE', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold))
            )
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.purpleAccent,
          tabs: const [
            Tab(icon: Icon(Icons.volume_up), text: 'Taunts'),
            Tab(icon: Icon(Icons.blur_on), text: 'Trails'),
            Tab(icon: Icon(Icons.wallpaper), text: 'Domains'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCategoryGrid('audio_taunt', 'taunt_1'),
          _buildCategoryGrid('particle_trail', 'particle_trail'),
          _buildCategoryGrid('wall_skin', 'wall_skin'),
        ],
      ),
    );
  }

  Widget _buildCategoryGrid(String targetCategory, String slotType) {
    final items = _catalog.values.where((c) => c['category'] == targetCategory).toList();

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isOwned = _inventory.any((i) => i['item_id'] == item['id']);
        final isEquipped = _draftLoadout[slotType] == item['id'];

        return GestureDetector(
          onTap: isOwned ? () => _equipItem(slotType, item['id']) : null,
          child: Container(
            decoration: BoxDecoration(
              color: isEquipped ? Colors.purpleAccent.withOpacity(0.2) : Colors.black45,
              border: Border.all(color: isEquipped ? Colors.purpleAccent : Colors.white24, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  targetCategory == 'audio_taunt' ? Icons.music_note : Icons.auto_awesome, 
                  color: isOwned ? Colors.white : Colors.white38,
                  size: 28
                ),
                const SizedBox(height: 8),
                Text(
                  item['name'].toString().toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: isOwned ? Colors.white : Colors.white38, fontWeight: FontWeight.bold),
                ),
                if (!isOwned)
                  const Padding(
                    padding: EdgeInsets.only(top: 4.0),
                    child: Icon(Icons.lock, size: 14, color: Colors.redAccent),
                  )
              ],
            ),
          ),
        );
      },
    );
  }
}