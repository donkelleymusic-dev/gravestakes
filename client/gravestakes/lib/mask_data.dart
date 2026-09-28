enum SwarmBehavior { none, scatter, homing, patrol }

class MaskData {
  final String id;
  final String name;
  final double energyCost;
  final double cooldown; // Cooldown lockout between activations
  final double range;    // Balanced tactical range
  final bool isFlying;
  final SwarmBehavior swarmBehavior;
  final int swarmCount;

  MaskData({
    required this.id,
    required this.name,
    required this.energyCost,
    this.cooldown = 0.6, // Default 0.6s lockout to prevent spamming
    this.range = 250.0,//140.0,  // Balanced operational range
    required this.isFlying,
    this.swarmBehavior = SwarmBehavior.none,
    this.swarmCount = 0,
  });
}

class MaskRegistry {
  static final Map<String, MaskData> allMasks = {
    'standard': MaskData(id: 'standard', name: 'Grave Stinger', cooldown: 3.0, energyCost: 1.5, range: 300.0, isFlying: false),
    'flying': MaskData(id: 'flying', name: 'Spectral Bat', cooldown: 5.0, energyCost: 2.5, isFlying: true),
    'vermin': MaskData(id: 'vermin', name: 'Rat Swarm', cooldown: 6.0, energyCost: 3.5, swarmBehavior: SwarmBehavior.scatter, swarmCount: 15, isFlying: false),
    'siren': MaskData(id: 'siren', name: 'Siren', cooldown: 15.0, energyCost: 5.5, range: 2000.0, isFlying: false),
    
    // --- THE NEW TACTICAL ROSTER ---
    'gorgon': MaskData(id: 'gorgon', name: 'Gorgon', cooldown: 10.0, energyCost: 4.0, range: 1200.0, isFlying: false), // Massive range, but requires eye contact
    'poltergeist': MaskData(id: 'poltergeist', name: 'Poltergeist', cooldown: 6.0, energyCost: 2.5, range: 300.0, isFlying: false), // The physical trap
    'banshee': MaskData(id: 'banshee', name: 'Banshee', cooldown: 12.0, energyCost: 4.5, range: 1500.0, isFlying: false), // Wall-piercing, massive range
    'wendigo': MaskData(id: 'wendigo', name: 'Wendigo', cooldown: 5.0, energyCost: 2.0, range: 0.0, isFlying: false), // Cheap decoy projectile
    'parasite': MaskData(id: 'parasite', name: 'Parasite', cooldown: 4.0, energyCost: 2.0, range: 300.0, isFlying: false), // Short cooldown vampirism
  };

  //static MaskData? getMask(String id) => allMasks[id];
  
  // Safe fetcher
  static MaskData getMask(String id) {
    return allMasks[id] ?? allMasks['standard']!;
  }
}