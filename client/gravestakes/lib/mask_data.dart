enum SwarmBehavior { none, scatter, homing, patrol }

class MaskData {
  final String id;
  final String name;
  final String description; // <-- Add this
  final double cooldown;
  final double energyCost;
  final double range;
  final bool isFlying;
  final SwarmBehavior swarmBehavior;
  final int swarmCount;

  MaskData({
    required this.id,
    required this.name,
    required this.description, // <-- Add this
    this.cooldown = 2.0,
    this.energyCost = 2.0,
    this.range = 250.0,
    this.isFlying = false,
    this.swarmBehavior = SwarmBehavior.none,
    this.swarmCount = 0,
  });
}

class MaskRegistry {
  static final Map<String, MaskData> allMasks = {
    'standard': MaskData(id: 'standard', name: 'Grave Stinger', description: '...', cooldown: 3.0, energyCost: 1.5, range: 300.0, isFlying: false),
    'flying': MaskData(id: 'flying', name: 'Spectral Bat', description: '...', cooldown: 5.0, energyCost: 2.5, isFlying: true),
    'vermin': MaskData(id: 'vermin', name: 'Rat Swarm', description: '...', cooldown: 6.0, energyCost: 3.5, swarmBehavior: SwarmBehavior.scatter, swarmCount: 15, isFlying: false),
    'siren': MaskData(id: 'siren', name: 'Siren', description: '...', cooldown: 15.0, energyCost: 5.5, range: 2000.0, isFlying: false),
    
    // --- THE NEW TACTICAL ROSTER ---
    'gorgon': MaskData(id: 'gorgon', name: 'Gorgon', description: '...', cooldown: 10.0, energyCost: 4.0, range: 1200.0, isFlying: false), // Massive range, but requires eye contact
    'poltergeist': MaskData(id: 'poltergeist', name: 'Poltergeist', description: '...', cooldown: 6.0, energyCost: 2.5, range: 300.0, isFlying: false), // The physical trap
    'banshee': MaskData(id: 'banshee', name: 'Banshee', description: '...', cooldown: 12.0, energyCost: 4.5, range: 1500.0, isFlying: false), // Wall-piercing, massive range
    'wendigo': MaskData(id: 'wendigo', name: 'Wendigo', description: '...', cooldown: 5.0, energyCost: 2.0, range: 0.0, isFlying: false), // Cheap decoy projectile
    'parasite': MaskData(id: 'parasite', name: 'Parasite', description: '...', cooldown: 4.0, energyCost: 2.0, range: 300.0, isFlying: false), // Short cooldown vampirism
  };

  //static MaskData? getMask(String id) => allMasks[id];
  
  // Safe fetcher
  static MaskData getMask(String id) {
    return allMasks[id] ?? allMasks['standard']!;
  }
}