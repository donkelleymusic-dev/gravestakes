import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  final supabase = Supabase.instance.client;
  
  // Tactical Masks Catalog
  final List<Map<String, dynamic>> _marketMasks = [
    {
      'id': 'standard',
      'name': 'Scary Mask (Standard)',
      'description': 'Reliable close-range ground scare.',
      'price': 20,
      'currency': 'shadows', 
    },
    {
      'id': 'flying',
      'name': 'Spectral Bat',
      'description': 'Fires a flying spectral projectile that ignores walls.',
      'price': 30,
      'currency': 'shadows',
    },
    {
      'id': 'vermin',
      'name': 'Rat Swarm',
      'description': 'Unleashes a chaotic swarm of biting vermin.',
      'price': 30,
      'currency': 'shadows',
    },
  ];

  List<Map<String, dynamic>> _abilities = [];

  List<String> _ownedMaskIds = [];
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
        
        // Fetch ownership from the new, clean inventory table!
        supabase.from('user_inventory').select('item_id').eq('user_id', user.id).eq('item_type', 'mask'),
        
        supabase.from('abilities').select('*'),
        supabase.from('player_loadouts').select('ability_id').eq('player_id', user.id),
      ]);

      final walletData = responses[0] as Map<String, dynamic>;
      final inventoryData = List<Map<String, dynamic>>.from(responses[1]);
      final abilitiesData = List<Map<String, dynamic>>.from(responses[2]);
      final abilityLoadouts = List<Map<String, dynamic>>.from(responses[3]);

      final ownedMasks = inventoryData.map((row) => row['item_id'] as String).toList();
      final ownedAbilities = abilityLoadouts
          .where((row) => row['ability_id'] != null)
          .map((row) => row['ability_id'].toString())
          .toList();

      if (mounted) {
        setState(() {
          _playerShadows = walletData['shadows'] ?? 20;
          _playerCoins = walletData['coins'] ?? 20;
          _ownedMaskIds = ownedMasks;
          _abilities = abilitiesData;
          _ownedAbilityIds = ownedAbilities;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading store: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _buyMask(String maskId, int price) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (_playerShadows < price) {
      _showError('Not enough Shadows!');
      return;
    }

    try {
      // Use the new atomic RPC transaction!
      await supabase.rpc('buy_mask', params: {
        'p_mask_id': maskId,
        'p_price': price,
      });

      setState(() {
        _playerShadows -= price;
        if (!_ownedMaskIds.contains(maskId)) {
          _ownedMaskIds.add(maskId);
        }
      });

      _showSuccess('Mask acquired successfully!');
    } catch (e) {
      debugPrint('Purchase failed: $e');
      _showError('Purchase failed: $e');
    }
  }

  Future<void> _buyAbility(String abilityId, int price, String currencyType) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // Database is clean, no safeCurrencyType mapping needed!
    int currentCurrency = currencyType == 'coins' ? _playerCoins : _playerShadows;
    if (currentCurrency < price) {
      _showError('Not enough ${currencyType.toUpperCase()}!');
      return;
    }

    try {
      await supabase.from('wallets').update({
        currencyType: currentCurrency - price
      }).eq('id', user.id).select();

      await supabase.from('player_loadouts').upsert({
        'player_id': user.id,
        'ability_id': abilityId,
        'is_equipped': true,
      }).select();

      setState(() {
        if (currencyType == 'coins') {
          _playerCoins -= price;
        } else {
          _playerShadows -= price;
        }
        if (!_ownedAbilityIds.contains(abilityId)) {
          _ownedAbilityIds.add(abilityId);
        }
      });

      _showSuccess('Ability unlocked!');
    } catch (e) {
      debugPrint('Purchase failed: $e');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
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
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('TACTICAL MASKS', style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                const SizedBox(height: 12),
                ..._marketMasks.map((item) {
                  final id = item['id'];
                  final isOwned = _ownedMaskIds.contains(id);
                  final price = item['price'];
                  final currency = item['currency']; 
                  
                  final userCurrency = currency == 'coins' ? _playerCoins : _playerShadows;
                  final canAfford = userCurrency >= price;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isOwned ? Colors.green.withOpacity(0.5) : Colors.red.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item['name'], style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(item['description'], style: const TextStyle(color: Colors.grey, fontSize: 13)),
                              const SizedBox(height: 6),
                              Text('$price Shadows', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        isOwned
                            ? const Chip(backgroundColor: Colors.green, label: Text('OWNED', style: TextStyle(color: Colors.white, fontSize: 12)))
                            : ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: canAfford ? Colors.red[800] : Colors.grey[800]),
                                onPressed: canAfford ? () => _buyMask(id, price) : null,
                                child: const Text('BUY', style: TextStyle(color: Colors.white)),
                              ),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 32),

                const Text('ABILITIES & PERKS', style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                const SizedBox(height: 12),
                
                if (_abilities.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: Text('No abilities currently available in the Black Market.', style: TextStyle(color: Colors.grey)),
                  )
                else
                  ..._abilities.map((item) {
                    final id = item['id'].toString();
                    final name = item['name'] ?? 'Unknown Perk';
                    final description = item['description'] ?? '';
                    final price = item['price'] ?? 50;
                    final currency = item['currency_type'] ?? 'shadows'; 
                    
                    final isOwned = _ownedAbilityIds.contains(id);
                    final userCurrency = currency == 'coins' ? _playerCoins : _playerShadows;
                    final canAfford = userCurrency >= price;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isOwned ? Colors.green.withOpacity(0.5) : Colors.amber.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(description, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                                const SizedBox(height: 6),
                                Text('$price ${currency.toUpperCase()}', style: TextStyle(color: currency == 'coins' ? Colors.amber : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          isOwned
                              ? const Chip(backgroundColor: Colors.green, label: Text('OWNED', style: TextStyle(color: Colors.white, fontSize: 12)))
                              : ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: canAfford ? Colors.amber[800] : Colors.grey[800]),
                                  onPressed: canAfford ? () => _buyAbility(id, price, currency) : null,
                                  child: const Text('BUY', style: TextStyle(color: Colors.white)),
                                ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}