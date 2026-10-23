import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'vessel_opener_overlay.dart';

class GuildWarResultsOverlay extends StatefulWidget {
  final Map<String, dynamic> rewardData;
  final VoidCallback onClaimed;
  final BuildContext parentContext;

  const GuildWarResultsOverlay({
    super.key,
    required this.rewardData,
    required this.onClaimed,
    required this.parentContext,
  });

  static void show(BuildContext context, Map<String, dynamic> rewardData, VoidCallback onClaimed) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => GuildWarResultsOverlay(
        rewardData: rewardData,
        onClaimed: onClaimed,
        parentContext: context,
      ),
    );
  }

  @override
  State<GuildWarResultsOverlay> createState() => _GuildWarResultsOverlayState();
}

class _GuildWarResultsOverlayState extends State<GuildWarResultsOverlay> {
  bool _isSubmitting = false;

  Future<void> _handleClaim() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    final String? vesselType = widget.rewardData['reward_vessel_type'];

    if (user != null) {
      try {
        // 1. Execute RPC to credit coins & shadows and mark this queue entry claimed
        await supabase.rpc('claim_guild_war_reward', params: {
          'p_queue_id': widget.rewardData['id'],
        });

        // 2. Also mark any older duplicate/stale unclaimed rows for this user as claimed
        //    so they never get stuck in a repeat popup loop on future launches!
        await supabase
            .from('guild_war_rewards_queue')
            .update({'claimed': true})
            .eq('user_id', user.id)
            .eq('claimed', false);
      } catch (e) {
        debugPrint('Error claiming guild war reward: $e');
      }
    }

    if (!mounted) return;

    // 3. Close the Crypt War Results dialog first
    Navigator.of(context).pop();

    // 4. Launch the 3D Voxel Vessel Opener using the still-mounted parent MainMenu context!
    if (vesselType != null && vesselType.isNotEmpty && widget.parentContext.mounted) {
      await VesselOpenerOverlay.show(widget.parentContext, vesselType);
    }

    // 5. Refresh the Main Menu wallet & badges after unboxing finishes
    widget.onClaimed();
  }

  @override
  Widget build(BuildContext context) {
    final int guildRank = widget.rewardData['guild_rank'] ?? 1;
    final int internalRank = widget.rewardData['internal_rank'] ?? 1;
    final int totalIp = widget.rewardData['total_ip_contributed'] ?? 0;
    final int coins = widget.rewardData['reward_coins'] ?? 0;
    final int shadows = widget.rewardData['reward_shadows'] ?? 0;
    final String? vesselType = widget.rewardData['reward_vessel_type'];

    return Material(
      color: Colors.black87,
      child: Center(
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.grey[950],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.redAccent, width: 2),
            boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.3), blurRadius: 25)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'CRYPT WAR CONCLUDED',
                style: TextStyle(color: Colors.redAccent, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2, fontFamily: 'Courier'),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(8)),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Guild Global Standing:', style: TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'Courier')),
                        Text('RANK #$guildRank', style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Courier')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Your Internal Rank:', style: TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'Courier')),
                        Text('#$internalRank (IP: $totalIp)', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Courier')),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text('VAULT DIVIDEND UNLOCKED', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontFamily: 'Courier')),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    children: [
                      const Icon(Icons.bolt, color: Colors.redAccent, size: 28),
                      const SizedBox(height: 4),
                      Text('+$shadows Shadows', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Courier')),
                    ],
                  ),
                  Column(
                    children: [
                      const Icon(Icons.monetization_on, color: Colors.amberAccent, size: 28),
                      const SizedBox(height: 4),
                      Text('+$coins Coins', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Courier')),
                    ],
                  ),
                ],
              ),
              if (vesselType != null) ...[
                const SizedBox(height: 16),
                Text('Bonus Vessel: ${vesselType.replaceAll('_', ' ').toUpperCase()}', style: const TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Courier')),
              ],
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[800],
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isSubmitting ? null : _handleClaim,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('COLLECT SPOILS', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
