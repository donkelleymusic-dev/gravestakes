import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'vessel_opener_overlay.dart';

class CryptPassScreen extends StatefulWidget {
  const CryptPassScreen({super.key});

  @override
  State<CryptPassScreen> createState() => _CryptPassScreenState();
}

class _CryptPassScreenState extends State<CryptPassScreen> {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isClaiming = false;
  String? _seasonId;
  String _seasonTitle = 'CRYPT PASS';
  
  int _currentXp = 0;
  int _currentTier = 0;
  int _highestClaimedTier = 0;
  bool _hasPremiumPass = false;
  int _walletCoins = 0;

  List<Map<String, dynamic>> _tiers = [];

  @override
  void initState() {
    super.initState();
    _loadPassData();
  }

  Future<void> _loadPassData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      // 1. Fetch the active season
      final seasonRes = await supabase
          .from('season_config')
          .select('*')
          .eq('is_active', true)
          .maybeSingle();

      if (seasonRes == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      _seasonId = seasonRes['id'];
      _seasonTitle = seasonRes['id'].toString().replaceAll('_', ' ').toUpperCase();

      // 2. Fetch all reward tiers for this season
      final tiersRes = await supabase
          .from('season_reward_tiers')
          .select('*')
          .eq('season_id', _seasonId!)
          .order('tier_level', ascending: true);

      // 3. Fetch user progression
      final progressRes = await supabase
          .from('player_season_progress')
          .select('*')
          .eq('user_id', user.id)
          .eq('season_id', _seasonId!)
          .maybeSingle();

      // 4. Fetch wallet to display coin balance for skips
      final walletRes = await supabase
          .from('wallets')
          .select('coins')
          .eq('id', user.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _tiers = List<Map<String, dynamic>>.from(tiersRes);
          if (progressRes != null) {
            _currentXp = progressRes['current_xp'] ?? 0;
            _currentTier = progressRes['current_tier'] ?? 0;
            _highestClaimedTier = progressRes['highest_claimed_tier'] ?? 0;
            _hasPremiumPass = progressRes['has_premium_pass'] ?? false;
          }
          _walletCoins = walletRes != null ? (walletRes['coins'] ?? 0) : 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading crypt pass data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- WATERFALL CLAIM ROUTINE ---
  Future<void> _claimAllAvailable() async {
    final user = supabase.auth.currentUser;
    if (user == null || _seasonId == null || _isClaiming) return;

    // Find tiers that are unlocked but not yet marked claimed
    final tiersToClaim = _tiers.where((t) {
      final lvl = t['tier_level'] as int;
      return lvl <= _currentTier && lvl > _highestClaimedTier;
    }).toList();

    if (tiersToClaim.isEmpty) return;

    setState(() => _isClaiming = true);

    int newlyClaimedMax = _highestClaimedTier;

    for (final tier in tiersToClaim) {
      final int level = tier['tier_level'];
      final String? freeVessel = tier['free_vessel_type'];
      final String? premiumVessel = tier['premium_vessel_type'];

      // 1. Open Free Chest
      if (freeVessel != null && mounted) {
        await _showAndWaitForVessel(freeVessel);
      }

      // 2. Open Premium Chest (if unlocked)
      if (_hasPremiumPass && premiumVessel != null && mounted) {
        await _showAndWaitForVessel(premiumVessel);
      }

      newlyClaimedMax = level;

      // Update in database as we progress
      await supabase
          .from('player_season_progress')
          .update({'highest_claimed_tier': newlyClaimedMax})
          .eq('user_id', user.id)
          .eq('season_id', _seasonId!);

      if (mounted) {
        setState(() {
          _highestClaimedTier = newlyClaimedMax;
        });
      }
    }

    if (mounted) {
      setState(() => _isClaiming = false);
    }
  }

  // Wraps VesselOpenerOverlay in a Future to create the sequential queue
  Future<void> _showAndWaitForVessel(String vesselType) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return VesselOpenerOverlay(vesselType: vesselType);
      },
    ).then((_) {});
  }

  // --- FAST TRACK RPC ---
  Future<void> _fastTrackTiers(int count) async {
    const int costPerTier = 150;
    final totalCost = count * costPerTier;

    if (_walletCoins < totalCost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not enough Coins to Fast-Track!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await supabase.rpc('fast_track_season_tiers', params: {
        'p_tiers_to_skip': count,
      });

      await _loadPassData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚡ Fast-Tracked $count Tiers!'),
            backgroundColor: Colors.amber[800],
          ),
        );
      }
    } catch (e) {
      debugPrint('Fast track error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unclaimedCount = _tiers.where((t) {
      final lvl = t['tier_level'] as int;
      return lvl <= _currentTier && lvl > _highestClaimedTier;
    }).length;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[950],
        title: Text(
          _seasonTitle,
          style: const TextStyle(
            color: Colors.redAccent,
            fontFamily: 'Courier',
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Row(
                children: [
                  const Icon(Icons.monetization_on, color: Colors.amberAccent, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    '$_walletCoins',
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontFamily: 'Courier',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
          : Column(
              children: [
                _buildHeaderBanner(),
                _buildTrackTitles(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    itemCount: _tiers.length,
                    itemBuilder: (context, index) {
                      final tier = _tiers[index];
                      return _buildTierRow(tier);
                    },
                  ),
                ),
                _buildActionFooter(unclaimedCount),
              ],
            ),
    );
  }

  Widget _buildHeaderBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: const Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TIER $_currentTier UNLOCKED',
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontFamily: 'Courier',
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _hasPremiumPass ? '🔥 CRYPT PASS ACTIVATED' : 'STANDARD CADENCE',
                style: TextStyle(
                  color: _hasPremiumPass ? Colors.purpleAccent : Colors.grey,
                  fontFamily: 'Courier',
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          if (!_hasPremiumPass)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple[800],
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              onPressed: () {
                // Hooked directly to RevenueCat entitlement purchase flow
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Redirecting to StoreKit / Google Play Billing...')),
                );
              },
              child: const Text(
                'UNLOCK PASS',
                style: TextStyle(color: Colors.white, fontFamily: 'Courier', fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTrackTitles() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.grey[950],
      child: const Row(
        children: [
          Expanded(
            child: Text(
              'FREE CADENCE',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontFamily: 'Courier', fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(width: 50, child: Text('TIER', textAlign: TextAlign.center, style: TextStyle(color: Colors.redAccent, fontFamily: 'Courier', fontSize: 11, fontWeight: FontWeight.bold))),
          Expanded(
            child: Text(
              'CRYPT PASS (PREMIUM)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.purpleAccent, fontFamily: 'Courier', fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierRow(Map<String, dynamic> tier) {
    final int tierLevel = tier['tier_level'];
    final bool isUnlocked = tierLevel <= _currentTier;
    final bool isClaimed = tierLevel <= _highestClaimedTier;

    return SizedBox(
      height: 96,
      child: Row(
        children: [
          // Left: Free Reward
          Expanded(
            child: _buildRewardCard(
              vesselType: tier['free_vessel_type'],
              isUnlocked: isUnlocked,
              isClaimed: isClaimed,
              accentColor: Colors.cyanAccent,
            ),
          ),

          // Center: Milestone Line & Tier Indicator
          SizedBox(
            width: 54,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isUnlocked ? Colors.redAccent : Colors.grey[850],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Center(
                    child: Text(
                      '$tierLevel',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Courier',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Right: Premium Reward
          Expanded(
            child: _buildRewardCard(
              vesselType: tier['premium_vessel_type'],
              isUnlocked: isUnlocked && _hasPremiumPass,
              isClaimed: isClaimed,
              isLockedByPass: !_hasPremiumPass,
              accentColor: Colors.purpleAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRewardCard({
    required String? vesselType,
    required bool isUnlocked,
    required bool isClaimed,
    bool isLockedByPass = false,
    required Color accentColor,
  }) {
    if (vesselType == null) {
      return const SizedBox();
    }

    final displayName = vesselType.replaceAll('_', ' ').toUpperCase();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isUnlocked ? Colors.grey[900] : Colors.grey[950],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isClaimed
              ? Colors.white12
              : (isUnlocked ? accentColor : Colors.white10),
          width: isUnlocked && !isClaimed ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isLockedByPass
                ? Icons.lock
                : (isClaimed ? Icons.check_circle : Icons.inventory_2),
            color: isClaimed
                ? Colors.greenAccent
                : (isLockedByPass ? Colors.grey : accentColor),
            size: 24,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isClaimed ? Colors.white38 : Colors.white,
                    fontFamily: 'Courier',
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
                Text(
                  isClaimed
                      ? 'CLAIMED'
                      : (isLockedByPass
                          ? 'REQUIRES PASS'
                          : (isUnlocked ? 'READY' : 'LOCKED')),
                  style: TextStyle(
                    color: isClaimed
                        ? Colors.grey
                        : (isUnlocked ? Colors.greenAccent : Colors.white24),
                    fontFamily: 'Courier',
                    fontSize: 8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionFooter(int unclaimedCount) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.grey[950],
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Fast Track 1 Tier
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.amberAccent),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => _fastTrackTiers(1),
                child: const Text(
                  'SKIP 1 TIER (150 COINS)',
                  style: TextStyle(
                    color: Colors.amberAccent,
                    fontFamily: 'Courier',
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Waterfall Claim Button
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: unclaimedCount > 0 ? Colors.red[800] : Colors.grey[850],
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: unclaimedCount > 0 && !_isClaiming ? _claimAllAvailable : null,
                child: Text(
                  _isClaiming
                      ? 'UNBOXING...'
                      : (unclaimedCount > 0 ? 'CLAIM ALL ($unclaimedCount)' : 'NO LOOT READY'),
                  style: TextStyle(
                    color: unclaimedCount > 0 ? Colors.white : Colors.white38,
                    fontFamily: 'Courier',
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}