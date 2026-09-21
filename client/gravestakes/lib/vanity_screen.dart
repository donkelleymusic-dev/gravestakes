import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
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
  
  // Wallets
  int _playerShadows = 0;
  int _playerCoins = 0;

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
      final responses = await Future.wait<dynamic>([
        supabase.from('cosmetics_catalog').select(),
        supabase.from('user_inventory').select('item_id').eq('user_id', userId).eq('item_type', 'cosmetic'),
        supabase.from('user_loadouts').select('slot_type, item_value').eq('user_id', userId),
        supabase.from('wallets').select('shadows, coins').eq('id', userId).single(), 
      ]);

      _catalog.clear();
      for (var row in List<Map<String, dynamic>>.from(responses[0])) {
        _catalog[row['id']] = row;
      }

      _inventory = List<Map<String, dynamic>>.from(responses[1]);

      _committedLoadout.clear();
      for (var row in List<Map<String, dynamic>>.from(responses[2])) {
        final slot = row['slot_type'] as String;
        if (['taunt_1', 'particle_trail', 'wall_skin'].contains(slot)) {
          _committedLoadout[slot] = row['item_value'] as String;
        }
      }

      final walletData = responses[3] as Map<String, dynamic>;
      _playerShadows = walletData['shadows'] ?? 0;
      _playerCoins = walletData['coins'] ?? 0;
      
      _revertDraft();
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Vanity Fetch Error: $e');
    }
  }

  Future<void> _buyCosmetic(String itemId, int price, String currency) async {
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
        'p_item_type': 'cosmetic', // Route it as a cosmetic item
        'p_item_id': itemId,
        'p_price': price,
        'p_currency': currency,
      });

      Sentry.addBreadcrumb(Breadcrumb(
        message: 'Purchased cosmetic $itemId for $price $currency',
        category: 'vanity_purchase',
      ));

      setState(() {
        if (currency == 'coins') {
          _playerCoins -= price;
        } else {
          _playerShadows -= price;
        }
        _inventory.add({'item_id': itemId});
      });

      SynthManager.instance.playMagicTap();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cosmetic acquired!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      debugPrint('Cosmetic Purchase Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Purchase failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showPurchaseConfirm(String itemId, String name, int price, String currency) {
    SynthManager.instance.playMagicTap();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text('Acquire $name?', style: const TextStyle(color: Colors.white)),
        content: Text(
          'Unlock this cosmetic for $price ${currency.toUpperCase()}?',
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
              _buyCosmetic(itemId, price, currency);
            },
            child: Text('BUY ($price ${currency.toUpperCase()})', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
      SynthManager.instance.playMagicTap();
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
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Row(
              children: [
                const Icon(Icons.dark_mode, color: Colors.redAccent, size: 14),
                const SizedBox(width: 4),
                Text('$_playerShadows', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(width: 12),
                const Icon(Icons.monetization_on, color: Colors.amber, size: 14),
                const SizedBox(width: 4),
                Text('$_playerCoins', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ),
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
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCategoryGrid('audio_taunt', 'taunt_1'),
                _buildCategoryGrid('particle_trail', 'particle_trail'),
                _buildCategoryGrid('wall_skin', 'wall_skin'),
              ],
            ),
          ),
          if (_draftLoadout.toString() != _committedLoadout.toString())
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
              color: Colors.black,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () {
                      SynthManager.instance.playMagicTap();
                      _revertDraft();
                    },
                    child: const Text('DISMISS', style: TextStyle(color: Colors.redAccent, letterSpacing: 1.5, fontSize: 13)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
                    onPressed: _commitDraft,
                    child: const Text('SAVE COSMETICS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 13)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryGrid(String targetCategory, String slotType) {
    final items = _catalog.values.where((c) => c['category'] == targetCategory).toList();

    if (items.isEmpty) {
      return const Center(child: Text('No cosmetics available.', style: TextStyle(color: Colors.white54)));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.85
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final itemId = item['id'];
        final name = item['name'].toString().toUpperCase();
        final price = item['price'] ?? 0;
        final currency = item['currency'] ?? 'shadows';
        
        final isOwned = _inventory.any((i) => i['item_id'] == itemId);
        final isEquipped = _draftLoadout[slotType] == itemId;

        return GestureDetector(
          onTap: () {
            if (isOwned) {
              _equipItem(slotType, itemId);
            } else {
              _showPurchaseConfirm(itemId, name, price, currency);
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: isEquipped ? Colors.purpleAccent.withOpacity(0.2) : Colors.black45,
              border: Border.all(
                color: isEquipped ? Colors.purpleAccent : (isOwned ? Colors.white24 : Colors.redAccent.withOpacity(0.4)), 
                width: 2
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  targetCategory == 'audio_taunt' ? Icons.music_note : (targetCategory == 'wall_skin' ? Icons.wallpaper : Icons.auto_awesome), 
                  color: isOwned ? Colors.white : Colors.white38,
                  size: 28
                ),
                const SizedBox(height: 8),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(fontSize: 9, color: isOwned ? Colors.white : Colors.white38, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                if (!isOwned)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(currency == 'coins' ? Icons.monetization_on : Icons.dark_mode, size: 10, color: currency == 'coins' ? Colors.amber : Colors.redAccent),
                      const SizedBox(width: 4),
                      Text('$price', style: TextStyle(color: currency == 'coins' ? Colors.amber : Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  )
                else if (isEquipped)
                  const Text('EQUIPPED', style: TextStyle(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold))
              ],
            ),
          ),
        );
      },
    );
  }
}