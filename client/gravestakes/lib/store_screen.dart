import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  final supabase = Supabase.instance.client;
  
  List<Map<String, dynamic>> _abilities = [];
  List<String> _ownedAbilityIds = [];
  int _playerShadows = 0;
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
      // Explicitly type the Future.wait list so Dart's compiler is happy
      final responses = await Future.wait<dynamic>([
        supabase.from('abilities').select('*'),
        supabase.from('wallets').select('shadows').eq('id', user.id).single(),
        supabase.from('player_loadouts').select('ability_id').eq('player_id', user.id),
      ]);

      final abilitiesData = List<Map<String, dynamic>>.from(responses[0]);
      final walletData = responses[1] as Map<String, dynamic>;
      final loadoutsData = List<Map<String, dynamic>>.from(responses[2]);

      if (mounted) {
        setState(() {
          _abilities = abilitiesData;
          _playerShadows = walletData['shadows'] ?? 0;
          _ownedAbilityIds = loadoutsData.map((item) => item['ability_id'].toString()).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading store: $e');
    }
  }

  Future<void> _buyAbility(String abilityId, int price) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (_playerShadows < price) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not enough Shadows! Go scare more people.'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      // 1. Deduct Shadows from Wallet & Insert into Loadout via a Postgres transaction/RPC or sequential calls
      // Deduct Shadows
      await supabase.from('wallets').update({
        'shadows': _playerShadows - price
      }).eq('id', user.id);

      // Add to player loadouts inventory
      await supabase.from('player_loadouts').insert({
        'player_id': user.id,
        'ability_id': abilityId,
        'is_equipped': true,
      });

      // Refresh store state locally
      setState(() {
        _playerShadows -= price;
        _ownedAbilityIds.add(abilityId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase successful! Ability acquired.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('Purchase failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Purchase failed: $e'), backgroundColor: Colors.red),
      );
    }
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
              child: Text(
                'Shadows: $_playerShadows',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : _abilities.isEmpty
              ? const Center(child: Text('No items in the Black Market yet.', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: _abilities.length,
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) {
                    final item = _abilities[index];
                    final id = item['id'];
                    final name = item['name'];
                    final description = item['description'];
                    final price = item['price'];
                    
                    final isOwned = _ownedAbilityIds.contains(id);
                    final canAfford = _playerShadows >= price;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isOwned ? Colors.green.withValues(alpha: 0.5) : Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(description ?? '', style: const TextStyle(color: Colors.grey, fontSize: 14)),
                                const SizedBox(height: 8),
                                Text('$price Shadows', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          isOwned
                              ? const Chip(
                                  backgroundColor: Colors.green,
                                  label: Text('OWNED', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                )
                              : ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: canAfford ? Colors.red[800] : Colors.grey[800],
                                  ),
                                  onPressed: canAfford ? () => _buyAbility(id, price) : null,
                                  child: const Text('BUY', style: TextStyle(color: Colors.white)),
                                ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}