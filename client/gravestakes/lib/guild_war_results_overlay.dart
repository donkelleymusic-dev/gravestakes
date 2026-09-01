import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'vessel_opener_overlay.dart';

class GuildWarResultsOverlay extends StatelessWidget {
  final Map<String, dynamic> rewardData;
  final VoidCallback onClaimed;

  const GuildWarResultsOverlay({
    super.key,
    required this.rewardData,
    required this.onClaimed,
  });

  @override
  Widget build(BuildContext context) {
    final int guildRank = rewardData['guild_rank'] ?? 1;
    final int internalRank = rewardData['internal_rank'] ?? 1;
    final int totalIp = rewardData['total_ip_contributed'] ?? 0;
    final int coins = rewardData['reward_coins'] ?? 0;
    final int shadows = rewardData['reward_shadows'] ?? 0;
    final String? vesselType = rewardData['reward_vessel_type'];

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
                onPressed: () async {
                  final supabase = Supabase.instance.client;
                  final user = supabase.auth.currentUser;
                  if (user != null) {
                    try {
                      // Execute safe RPC to transfer escrow rewards into actual wallet/inventory
                      await supabase.rpc('claim_guild_war_reward', params: {
                        'p_queue_id': rewardData['id'],
                      });
                    } catch (e) {
                      debugPrint('Error claiming reward: $e');
                    }
                  }
                  Navigator.of(context).pop();
                  onClaimed();

                  if (vesselType != null && context.mounted) {
                    VesselOpenerOverlay.show(context, vesselType);
                  }
                },
                child: const Text('COLLECT SPOILS', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void show(BuildContext context, Map<String, dynamic> rewardData, VoidCallback onClaimed) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => GuildWarResultsOverlay(rewardData: rewardData, onClaimed: onClaimed),
    );
  }
}