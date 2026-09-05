import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  final supabase = Supabase.instance.client;
  
  List<Map<String, dynamic>> _characters = [];
  List<Map<String, dynamic>> _masks = [];
  List<Map<String, dynamic>> _maps = [];
  List<Map<String, dynamic>> _abilities = [];
  List<Map<String, dynamic>> _wearables = []; // <--- Wearables store list

  //tutorial:
  //final GlobalKey _buyMaskKey = GlobalKey();
  final GlobalKey _backKey = GlobalKey();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey _buyMaskKey = GlobalKey();

  Map<String, List<String>> _ownedItems = {};
  List<String> _ownedAbilityIds = []; 
  
  int _playerShadows = 0;
  int _playerCoins = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStoreData();
  }

  Future<void> _loadStoreData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final responses = await Future.wait<dynamic>([
        supabase.from('wallets').select('shadows, coins').eq('id', user.id).single(),
        supabase.from('user_inventory').select('item_type, item_id').eq('user_id', user.id),
        supabase.from('characters').select('*').order('price'),
        supabase.from('masks').select('*').order('price'),
        supabase.from('maps').select('*').order('price'),
        supabase.from('abilities').select('*'),
        supabase.from('player_loadouts').select('ability_id').eq('player_id', user.id),
        supabase.from('wearables').select('*'), // <--- Fetch wearables catalog
      ]);

      final walletData = responses[0] as Map<String, dynamic>;
      final inventoryData = List<Map<String, dynamic>>.from(responses[1]);
      
      Map<String, List<String>> owned = {};
      for (var row in inventoryData) {
        final type = row['item_type'] as String;
        final id = row['item_id'] as String;
        owned.putIfAbsent(type, () => []).add(id);
      }

      final abilityLoadouts = List<Map<String, dynamic>>.from(responses[6]);
      final ownedAbilities = abilityLoadouts
          .where((row) => row['ability_id'] != null)
          .map((row) => row['ability_id'].toString())
          .toList();

      if (mounted) {
        setState(() {
          _playerShadows = walletData['shadows'] ?? 0;
          _playerCoins = walletData['coins'] ?? 0;
          _ownedItems = owned;
          _characters = List<Map<String, dynamic>>.from(responses[2]);
          _masks = List<Map<String, dynamic>>.from(responses[3]);
          _maps = List<Map<String, dynamic>>.from(responses[4]);
          _abilities = List<Map<String, dynamic>>.from(responses[5]);
          _ownedAbilityIds = ownedAbilities;
          _wearables = List<Map<String, dynamic>>.from(responses[7]);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading store: $e');
      if (mounted) setState(() => _isLoading = false);
    }

    final prefs = await SharedPreferences.getInstance();
    // Safely default to 'market' if the value doesn't exist yet!
    final currentPhase = prefs.getString('tutorial_phase') ?? 'market'; 
    
    if (currentPhase == 'market') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scaffoldKey.currentContext != null) {
          ShowCaseWidget.of(_scaffoldKey.currentContext!).startShowCase([_buyMaskKey, _backKey]);
        }
      });
    }
  }

  Future<void> _buyItem(String itemType, String itemId, int price, String currency) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    int currentBalance = currency == 'coins' ? _playerCoins : _playerShadows;
    if (currentBalance < price) {
      _showError('Not enough ${currency.toUpperCase()}!');
      return;
    }

    try {
      await supabase.rpc('buy_item', params: {
        'p_item_type': itemType,
        'p_item_id': itemId,
        'p_price': price,
        'p_currency': currency,
      });

      setState(() {
        if (currency == 'coins') {
          _playerCoins -= price;
        } else {
          _playerShadows -= price;
        }
        _ownedItems.putIfAbsent(itemType, () => []).add(itemId);
      });

      _showSuccess('Item acquired successfully!');
    } catch (e) {
      debugPrint('Purchase failed: $e');
      _showError('Purchase failed: $e');
    }
  }

  Future<void> _buyAbility(String abilityId, int price, String currency) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    int currentBalance = currency == 'coins' ? _playerCoins : _playerShadows;
    if (currentBalance < price) {
      _showError('Not enough ${currency.toUpperCase()}!');
      return;
    }

    try {
      await supabase.from('wallets').update({
        currency: currentBalance - price
      }).eq('id', user.id).select();

      await supabase.from('player_loadouts').upsert({
        'player_id': user.id,
        'ability_id': abilityId,
        'is_equipped': true,
      }).select();

      setState(() {
        if (currency == 'coins') _playerCoins -= price;
        else _playerShadows -= price;
        
        if (!_ownedAbilityIds.contains(abilityId)) _ownedAbilityIds.add(abilityId);
      });
      _showSuccess('Ability unlocked!');
    } catch (e) {
      _showError('Purchase failed: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  Widget _buildItemList(List<Map<String, dynamic>> items, String itemType) {
    if (items.isEmpty) {
      return const Center(child: Text('No items available.', style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final id = item['id'].toString();
        final name = item['name'] ?? 'Unknown';
        final desc = item['description'] ?? '';
        final price = item['price'] ?? 0;
        final currency = item['currency'] ?? 'shadows';
        final targetSlot = item['slot_type'] ?? itemType;
        
        final imagePath = item['asset_path'] ?? item['thumbnail_path'];

        bool isOwned = false;
        if (itemType == 'ability') {
          isOwned = _ownedAbilityIds.contains(id);
        } else {
          isOwned = (_ownedItems[targetSlot] ?? []).contains(id) || (_ownedItems[itemType] ?? []).contains(id);
        }

        final userCurrency = currency == 'coins' ? _playerCoins : _playerShadows;
        final canAfford = userCurrency >= price;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isOwned ? Colors.green.withOpacity(0.5) : (currency == 'coins' ? Colors.amber.withOpacity(0.3) : Colors.red.withOpacity(0.3))),
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                margin: const EdgeInsets.only(right: 16),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[800]!, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: (imagePath != null && imagePath.toString().isNotEmpty)
                      ? Image.asset(
                          imagePath,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.shield, color: Colors.purpleAccent, size: 32),
                        )
                      : Icon(
                          itemType == 'mask' ? Icons.masks : (itemType == 'character' ? Icons.person : Icons.shield),
                          color: Colors.grey[700],
                          size: 32,
                        ),
                ),
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 6),
                    Text('$price ${currency.toUpperCase()}', style: TextStyle(color: currency == 'coins' ? Colors.amber : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              if (isOwned)
                const Chip(backgroundColor: Colors.green, label: Text('OWNED', style: TextStyle(color: Colors.white, fontSize: 12)))
              else if (itemType == 'mask' && id == 'standard')
                // TARGET THE EXACT ID ('standard') INSTEAD OF THE INDEX
                Showcase(
                  key: _buyMaskKey,
                  description: 'Purchase your Standard Mask here.',
                  disposeOnTap: true,
                  onTargetClick: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('tutorial_phase', 'loadout');
                    _buyItem(targetSlot, id, price, currency);
                  },
                  child: ElevatedButton(
                    // Force the button to look active for the tutorial
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
                    onPressed: () async {
                      // Save progress directly before buying so it never gets stuck
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('tutorial_phase', 'loadout');
                      _buyItem(targetSlot, id, price, currency);
                    },
                    child: const Text('BUY', style: TextStyle(color: Colors.white)),
                  ),
                )
              else
                // Standard button for everything else
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: canAfford ? (currency == 'coins' ? Colors.amber[800] : Colors.red[800]) : Colors.grey[800]),
                  onPressed: canAfford ? () async {
                    itemType == 'ability' ? _buyAbility(id, price, currency) : _buyItem(targetSlot, id, price, currency);
                  } : null,
                  child: const Text('BUY', style: TextStyle(color: Colors.white)),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ShowCaseWidget(
      builder: (context) => DefaultTabController(
        length: 5, // <--- Expanded to 5 tabs
        child: Scaffold(
          key: _scaffoldKey, // YOU MUST ADD THIS EXACT LINE!
          backgroundColor: Colors.black,
          appBar: AppBar(
            // --- PASTE THIS NEW LEADING BLOCK HERE ---
            leading: Showcase(
            key: _backKey,
            description: 'STEP 2: Return to the Main Menu.',
            disposeOnTap: true,
            onTargetClick: () => Navigator.of(context).pop(),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          // ----------------------------------------
          backgroundColor: Colors.grey[900],
          title: const Text('THE BLACK MARKET', style: TextStyle(color: Colors.redAccent, letterSpacing: 1.5)),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Row(
                  children: [
                    Text('👻 $_playerShadows', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(width: 12),
                    Text('🪙 $_playerCoins', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
              ),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.redAccent,
            labelColor: Colors.redAccent,
            unselectedLabelColor: Colors.grey,
            isScrollable: true,
            tabs: [
              Tab(text: 'MASKS'),
              Tab(text: 'WEARABLES'), // <--- Added WEARABLES tab
              Tab(text: 'CHARACTERS'),
              Tab(text: 'MAPS'),
              Tab(text: 'PERKS'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.red))
            : TabBarView(
                children: [
                  _buildItemList(_masks, 'mask'),
                  _buildItemList(_wearables, 'wearable'), // <--- Added WEARABLES tab view
                  _buildItemList(_characters, 'character'),
                  _buildItemList(_maps, 'map'),
                  _buildItemList(_abilities, 'ability'),
                ],
              ),
        ), // Closes Scaffold
      ), // Closes DefaultTabController
    ); // Closes ShowCaseWidget
  }
}