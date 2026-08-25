import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  final supabase = Supabase.instance.client;
  
  // 1. Tactical Masks Catalog
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

  // 2. Abilities & Perks Catalog
  List<Map<String, dynamic>> _abilities = [];

  // User Inventory & Wallets
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
        
        // FIX: Fetch ALL loadout rows for the user, stop filtering out the new masks!
        supabase.from('user_loadouts').select('slot_type, item_value').eq('user_id', user.id),
        
        supabase.from('abilities').select('*'),
        supabase.from('player_loadouts').select('ability_id').eq('player_id', user.id),
      ]);

      final walletData = responses[0] as Map<String, dynamic>;
      final allLoadouts = List<Map<String, dynamic>>.from(responses[1]);
      final abilitiesData = List<Map<String, dynamic>>.from(responses[2]);
      final abilityLoadouts = List<Map<String, dynamic>>.from(responses[3]);

      // FIX: Check for both old and new save formats safely
      final ownedMasks = <String>[];
      for (var row in allLoadouts) {
        final slot = row['slot_type'] as String? ?? '';
        final val = row['item_value'] as String?;
        if (val != null && (slot == 'inventory_mask' || slot.startsWith('unlocked_mask_'))) {
          if (!ownedMasks.contains(val)) ownedMasks.add(val);
        }
      }

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
      // 1. Force a 200 OK response by appending .select() to bypass the Flutter Web 204 crash
      await supabase.from('wallets').update({
        'shadows': _playerShadows - price
      }).eq('id', user.id).select();

      // 2. Use Upsert with .select() to prevent duplicate key crashes
      await supabase.from('user_loadouts').upsert({
        'user_id': user.id,
        'slot_type': 'unlocked_mask_$maskId',
        'item_value': maskId,
      }, onConflict: 'user_id, slot_type').select();

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

    // GUARD: If legacy DB rows still say 'stakes', map it to 'coins' safely
    final safeCurrencyType = currencyType == 'stakes' ? 'coins' : currencyType;
    
    int currentCurrency = safeCurrencyType == 'coins' ? _playerCoins : _playerShadows;
    if (currentCurrency < price) {
      _showError('Not enough $safeCurrencyType!');
      return;
    }

    try {
      // 1. Force a 200 OK response with .select() 
      await supabase.from('wallets').update({
        safeCurrencyType: currentCurrency - price
      }).eq('id', user.id).select();

      // 2. Use UPSERT instead of INSERT so rebuying/equipping doesn't crash on constraints
      await supabase.from('player_loadouts').upsert({
        'player_id': user.id,
        'ability_id': abilityId,
        'is_equipped': true,
      }).select();

      setState(() {
        if (safeCurrencyType == 'coins') {
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
                  final canAfford = _playerShadows >= price;

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