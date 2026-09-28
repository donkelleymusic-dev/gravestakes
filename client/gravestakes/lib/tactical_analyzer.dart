import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class TacticalAnalyzer {
  
  /// Fetches the last 10 matches and returns a customized profile map
  static Future<Map<String, String>?> generateDossier() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      final response = await Supabase.instance.client
          .from('player_tactics_log')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(10);

      if (response.isEmpty) {
        return {
          'title': 'NO TELEMETRY',
          'body': 'Complete more matches to generate a tactical profile.',
          'suggested_item': 'standard'
        };
      }

      final logs = List<Map<String, dynamic>>.from(response);
      
      int totalAttempted = 0;
      int totalLanded = 0;
      double totalZeroEnergyTime = 0.0;
      int totalSwarmHits = 0;
      int totalSirenHits = 0;
      int totalStandardHits = 0;
      double totalSprinted = 0.0;

      for (var log in logs) {
        totalAttempted += (log['scares_attempted'] as int? ?? 0);
        totalLanded += (log['scares_landed'] as int? ?? 0);
        totalZeroEnergyTime += (log['time_zero_energy'] as num? ?? 0).toDouble();
        totalSwarmHits += (log['times_hit_swarm'] as int? ?? 0);
        totalSirenHits += (log['times_charmed_siren'] as int? ?? 0);
        totalStandardHits += (log['times_stunned_standard'] as int? ?? 0);
        totalSprinted += (log['distance_sprinted'] as num? ?? 0).toDouble();
      }

      double accuracy = totalAttempted > 0 ? (totalLanded / totalAttempted) : 0.0;
      double avgZeroEnergy = totalZeroEnergyTime / logs.length;
      int totalMatches = logs.length;

      // 1. The Hunted (Susceptible to specialized crowd control)
      if (totalSwarmHits > totalMatches * 2 || totalSirenHits > totalMatches * 1.5) {
        return {
          'title': 'VULNERABILITY DETECTED',
          'body': 'Telemetry shows high susceptibility to swarm and trance tactics. Invest in defensive Wards to automatically filter these specialized threats.',
          'suggested_item': 'vermin' // Or a specific defensive ward ID once you add them
        };
      }

      // 2. The Reckless Aggressor (Low accuracy, high exhaustion)
      if (accuracy < 0.35 && avgZeroEnergy > 15.0) {
        return {
          'title': 'RECKLESS EXERTION',
          'body': 'Your operative spends too much time exhausted after missing targets. Equip Max Energy Wards, or switch to the Parasite Mask to vampirize energy on hit.',
          'suggested_item': 'parasite' 
        };
      }

      // 3. The Ghost (High mobility, low engagement)
      if (totalSprinted > (totalMatches * 1500) && totalAttempted < (totalMatches * 2)) {
        return {
          'title': 'EVASIVE TENDENCIES',
          'body': 'Your evasion metrics are excellent, but offensive output is lacking. Equip the Poltergeist mask to drop traps while you run, punishing anyone following your trail.',
          'suggested_item': 'poltergeist'
        };
      }

      // 4. The Brawler (Takes a lot of direct hits)
      if (totalStandardHits > totalMatches * 4) {
        return {
          'title': 'FRONTAL ASSAULTS',
          'body': 'You engage in heavy face-to-face combat and take immense damage. Equip the Gorgon mask to instantly petrify anyone looking directly at you during these standoffs.',
          'suggested_item': 'gorgon'
        };
      }

      // Default / Well-Rounded Performance
      return {
        'title': 'OPTIMAL PERFORMANCE',
        'body': 'Your metrics are balanced across all tactical vectors. Consider experimenting with the Banshee mask to execute advanced wall-piercing strikes.',
        'suggested_item': 'banshee'
      };

    } catch (e) {
      debugPrint('Tactical Analyzer Error: $e');
      return null;
    }
  }
}