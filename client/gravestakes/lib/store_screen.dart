import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

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
  int _playerCoins = 0;
  bool _isLoading = true;

  // Free Drop Timer Mechanics
  DateTime? _lastFreeDropTime;
  Timer? _countdownTimer;
  String _freeDropTimeRemaining = '';
  bool _canClaimFreeDrop = false;

  final GlobalKey _backKey = GlobalKey();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey _freeDropKey = GlobalKey(); // Repurposed for tutorial

  @override
  void initState() {
    super.initState();
    _loadStoreData();
    
    // Updates the countdown UI every minute
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) _updateFreeDropTimer();
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStoreData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final responses = await Future.wait<dynamic>([
        supabase.from('wallets').select('shadows, coins').eq('id', user.id).single(),
        supabase.from('abilities').select('*'),
        supabase.from('player_loadouts').select('ability_id').eq('player_id', user.id),
      ]);

      final walletData = responses[0] as Map<String, dynamic>;
      final abilityLoadouts = List<Map<String, dynamic>>.from(responses[2]); 
      
      _ownedAbilityIds = abilityLoadouts
          .where((row) => row['ability_id'] != null)
          .map((row) => row['ability_id'].toString())
          .toList();

      // Check local SharedPreferences for the last free claim time
      final prefs = await SharedPreferences.getInstance();
      final lastClaimIso = prefs.getString('last_free_drop_${user.id}');
      if (lastClaimIso != null) {
        _lastFreeDropTime = DateTime.parse(lastClaimIso);
      }

      if (mounted) {
        setState(() {
          _playerShadows = walletData['shadows'] ?? 0;
          _playerCoins = walletData['coins'] ?? 0;
          _abilities = List<Map<String, dynamic>>.from(responses[1]); 
          _isLoading = false;
        });
        _updateFreeDropTimer();
      }
    } catch (e) {
      debugPrint('Error loading Black Market: $e');
      if (mounted) setState(() => _isLoading = false);
    }

    final prefs = await SharedPreferences.getInstance();
    final currentPhase = prefs.getString('tutorial_phase') ?? 'market'; 
    
    if (currentPhase == 'market') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scaffoldKey.currentContext != null) {
          ShowCaseWidget.of(_scaffoldKey.currentContext!).startShowCase([_freeDropKey, _backKey]);
        }
      });
    }
  }

  void _updateFreeDropTimer() {
    if (_lastFreeDropTime == null) {
      setState(() {
        _canClaimFreeDrop = true;
        _freeDropTimeRemaining = 'AVAILABLE NOW';
      });
      return;
    }

    final now = DateTime.now();
    final nextAvailable = _lastFreeDropTime!.add(const Duration(hours: 12));
    final difference = nextAvailable.difference(now);

    if (difference.isNegative) {
      setState(() {
        _canClaimFreeDrop = true;
        _freeDropTimeRemaining = 'AVAILABLE NOW';
      });
    } else {
      final hours = difference.inHours;
      final minutes = difference.inMinutes.remainder(60);
      setState(() {
        _canClaimFreeDrop = false;
        _freeDropTimeRemaining = 'NEXT DROP IN ${hours}H ${minutes}M';
      });
    }
  }

  Future<void> _claimFreeDrop() async {
    final user = supabase.auth.currentUser;
    if (user == null || !_canClaimFreeDrop) return;

    // Simulate backend shard generation (to be replaced with RPC later)
    final rewardCoins = 50;
    
    try {
      await supabase.from('wallets').update({
        'coins': _playerCoins + rewardCoins
      }).eq('id', user.id);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_free_drop_${user.id}', DateTime.now().toIso8601String());

      setState(() {
        _playerCoins += rewardCoins;
        _lastFreeDropTime = DateTime.now();
      });
      
      _updateFreeDropTimer();

      Sentry.addBreadcrumb(Breadcrumb(
        message: 'Claimed free daily drop',
        category: 'store_freebie',
      ));

      _showSuccess('Smuggler\'s Drop opened! +$rewardCoins Coins');
    } catch (e) {
      _showError('Failed to claim drop: $e');
    }
  }

  Future<void> _buyVessel(String vesselType, int price, String currency) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    int currentBalance = currency == 'coins' ? _playerCoins : _playerShadows;
    if (currentBalance < price) {
      _showError('Not enough ${currency.toUpperCase()}!');
      return;
    }

    try {
      await supabase.rpc('buy_item', params: {
        'p_item_type': 'vessel',
        'p_item_id': vesselType,
        'p_price': price,
        'p_currency': currency,
      });

      setState(() {
        if (currency == 'coins') {
          _playerCoins -= price;
        } else {
          _playerShadows -= price;
        }
      });
      _showSuccess('$vesselType acquired! Check your Crypt.');
    } catch (e) {
      _showError('Transaction failed: $e');
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
      _showSuccess('Account Perk Unlocked!');
    } catch (e) {
      _showError('Transaction failed: $e');
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

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.purpleAccent, size: 20),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        ],
      ),
    );
  }

  Widget _buildFreeDropSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _canClaimFreeDrop ? Colors.green[900]?.withOpacity(0.4) : Colors.grey[900],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _canClaimFreeDrop ? Colors.greenAccent : Colors.grey[800]!, width: 2),
        ),
        child: Row(
          children: [
            const Icon(Icons.inventory, size: 48, color: Colors.white70),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('THE SMUGGLER\'S DROP', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Contains Operative Shards and Coins.', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                  const SizedBox(height: 6),
                  Text(_freeDropTimeRemaining, style: TextStyle(color: _canClaimFreeDrop ? Colors.greenAccent : Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Showcase(
              key: _freeDropKey,
              description: 'Claim your free daily supplies here.',
              disposeOnTap: true,
              onTargetClick: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('tutorial_phase', 'loadout');
                if (_canClaimFreeDrop) _claimFreeDrop();
              },
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _canClaimFreeDrop ? Colors.green[700] : Colors.grey[800],
                ),
                onPressed: _canClaimFreeDrop ? () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('tutorial_phase', 'loadout');
                  _claimFreeDrop();
                } : null,
                child: Text(_canClaimFreeDrop ? 'CLAIM' : 'WAIT', style: const TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVesselCard(String name, String desc, int price, String currency, String id, Color themeColor, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: themeColor.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 48, color: themeColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: currency == 'coins' ? Colors.amber[800] : Colors.red[800]),
            onPressed: () => _buyVessel(id, price, currency),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(currency == 'coins' ? Icons.monetization_on : Icons.dark_mode, size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text('$price', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExchangeCard(String name, int shadowCost, int coinReward) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.monetization_on, color: Colors.amber, size: 28),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text('+$coinReward Coins', style: const TextStyle(color: Colors.amber, fontSize: 12)),
                ],
              ),
            ],
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
            onPressed: () {
              // RPC for currency exchange goes here
              _showError('Exchange coming soon.');
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.dark_mode, size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text('$shadowCost', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbilitiesList() {
    if (_abilities.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: Text('No perks available.', style: TextStyle(color: Colors.grey))),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _abilities.length,
      itemBuilder: (context, index) {
        final item = _abilities[index];
        final id = item['id'].toString();
        final name = item['name'] ?? 'Unknown';
        final desc = item['description'] ?? '';
        final price = item['price'] ?? 0;
        final currency = item['currency'] ?? 'shadows';
        final isOwned = _ownedAbilityIds.contains(id);

        return Container(
          margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isOwned ? Colors.green.withOpacity(0.5) : Colors.purpleAccent.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.star, color: Colors.purpleAccent, size: 36),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (isOwned)
                const Chip(backgroundColor: Colors.green, label: Text('ACTIVE', style: TextStyle(color: Colors.white, fontSize: 10)))
              else
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: currency == 'coins' ? Colors.amber[800] : Colors.red[800]),
                  onPressed: () => _buyAbility(id, price, currency),
                  child: Text('BUY ($price)', style: const TextStyle(color: Colors.white, fontSize: 12)),
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
      builder: (context) => Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.black,
        appBar: AppBar(
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
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.red))
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. PREMIUM VESSELS FIRST
                    _buildSectionHeader('VESSELS', Icons.all_inbox),
                    _buildVesselCard(
                      'VOID CHRYSALIS', 
                      'Contains common Operative shards and base gear.', 
                      500, 'coins', 'void_chrysalis', 
                      Colors.cyanAccent, Icons.widgets
                    ),
                    _buildVesselCard(
                      'SOUL CASKET', 
                      'Guaranteed rare shards and premium modifiers.', 
                      100, 'shadows', 'soul_casket', 
                      Colors.purpleAccent, Icons.auto_awesome
                    ),

                    // 2. FREE DROP SCROLL-TRAP
                    _buildSectionHeader('DAILY SUPPLIES', Icons.access_time),
                    _buildFreeDropSection(),

                    // 3. CURRENCY EXCHANGE
                    _buildSectionHeader('CURRENCY EXCHANGE', Icons.swap_horiz),
                    _buildExchangeCard('Smuggler\'s Purse', 50, 1000),
                    _buildExchangeCard('Shadow Syndicate Vault', 250, 6000),

                    // 4. ACCOUNT PERKS
                    _buildSectionHeader('GLOBAL PERKS', Icons.bolt),
                    _buildAbilitiesList(),
                    
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }
}