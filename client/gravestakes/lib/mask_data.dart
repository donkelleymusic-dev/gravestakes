// mask_data.dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum SwarmBehavior { none, scatter, homing, patrol }

class MaskData {
  final String id;
  final String name;
  final String description;
  final double cooldown;
  final double energyCost;
  final double range;
  final bool isFlying;
  final SwarmBehavior swarmBehavior;
  final int swarmCount;

  MaskData({
    required this.id,
    required this.name,
    required this.description,
    this.cooldown = 2.0,
    this.energyCost = 2.0,
    this.range = 250.0,
    this.isFlying = false,
    this.swarmBehavior = SwarmBehavior.none,
    this.swarmCount = 0,
  });
}

class MaskRegistry {
  static bool _hasSyncedFromDb = false;

  static final Map<String, MaskData> allMasks = {
    'standard': MaskData(id: 'standard', name: 'Grave Stinger', description: 'Standard short-range acoustic stun.', cooldown: 3.0, energyCost: 1.5, range: 300.0, isFlying: false),
    'flying': MaskData(id: 'flying', name: 'Spectral Bat', description: 'Launches a homing bat projectile.', cooldown: 5.0, energyCost: 2.5, range: 400.0, isFlying: true),
    'vermin': MaskData(id: 'vermin', name: 'Rat Swarm', description: 'Unleashes a scattering swarm of 15 critters.', cooldown: 6.0, energyCost: 3.5, range: 350.0, swarmBehavior: SwarmBehavior.scatter, swarmCount: 15, isFlying: false),
    'siren': MaskData(id: 'siren', name: 'Siren', description: 'Hypnotizes targets into walking toward you.', cooldown: 15.0, energyCost: 5.5, range: 2000.0, isFlying: false),
    'gorgon': MaskData(id: 'gorgon', name: 'Gorgon', description: 'Petrifies anyone looking directly at you.', cooldown: 10.0, energyCost: 4.0, range: 1200.0, isFlying: false),
    'poltergeist': MaskData(id: 'poltergeist', name: 'Poltergeist', description: 'Plants an invisible proximity trap on the floor.', cooldown: 6.0, energyCost: 2.5, range: 300.0, isFlying: false),
    'banshee': MaskData(id: 'banshee', name: 'Banshee', description: 'Fires a wall-piercing sonic beam.', cooldown: 12.0, energyCost: 4.5, range: 1500.0, isFlying: false),
    'wendigo': MaskData(id: 'wendigo', name: 'Wendigo', description: 'Projects a sprinting holographic decoy.', cooldown: 5.0, energyCost: 2.0, range: 0.0, isFlying: false),
    'parasite': MaskData(id: 'parasite', name: 'Parasite', description: 'Drains battery and energy from your victim.', cooldown: 4.0, energyCost: 2.0, range: 300.0, isFlying: false),
  };

  /// Syncs live mask stats (including 'effect_range') from Supabase 'masks' table once per session
  static Future<void> syncFromDatabase() async {
    if (_hasSyncedFromDb) return;
    try {
      final rows = await Supabase.instance.client.from('masks').select('*');
      for (final row in rows) {
        final String id = row['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final existing = allMasks[id];

        // Read 'effect_range' from your DB schema!
        final double dbRange = (row['effect_range'] as num?)?.toDouble() 
            ?? existing?.range 
            ?? 250.0;
        final double dbCooldown = (row['cooldown'] as num?)?.toDouble() 
            ?? existing?.cooldown 
            ?? 3.0;
        final double dbEnergy = (row['energy_cost'] as num?)?.toDouble() 
            ?? existing?.energyCost 
            ?? 2.0;
        final String dbName = row['name']?.toString() ?? existing?.name ?? id;
        final String dbDesc = row['description']?.toString() ?? existing?.description ?? '';

        allMasks[id] = MaskData(
          id: id,
          name: dbName,
          description: dbDesc,
          cooldown: dbCooldown,
          energyCost: dbEnergy,
          range: dbRange,
          isFlying: existing?.isFlying ?? (id == 'flying'),
          swarmBehavior: existing?.swarmBehavior ?? (id == 'vermin' ? SwarmBehavior.scatter : SwarmBehavior.none),
          swarmCount: existing?.swarmCount ?? (id == 'vermin' ? 15 : 0),
        );
      }
      _hasSyncedFromDb = true;
    } catch (e) {
      debugPrint('MaskRegistry DB sync skipped (using defaults): $e');
    }
  }

  static MaskData getMask(String id) {
    return allMasks[id] ?? allMasks['standard']!;
  }
}