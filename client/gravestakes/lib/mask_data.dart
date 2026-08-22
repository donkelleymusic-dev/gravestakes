enum SwarmBehavior { none, scatter, homing, patrol }

class MaskData {
  final String id;
  final String name;
  final double energyCost;
  final bool isFlying;
  final SwarmBehavior swarmBehavior;
  final int swarmCount;

  MaskData({
    required this.id,
    required this.name,
    required this.energyCost,
    required this.isFlying,
    this.swarmBehavior = SwarmBehavior.none,
    this.swarmCount = 0,
  });
}

class MaskRegistry {
  static final Map<String, MaskData> allMasks = {
    'standard': MaskData(id: 'standard', name: 'Grave Stinger', energyCost: 3.0, isFlying: false),
    'flying': MaskData(id: 'flying', name: 'Spectral Bat', energyCost: 5.0, isFlying: true),
    'vermin': MaskData(id: 'vermin', name: 'Rat Swarm', energyCost: 4.0, isFlying: false, swarmBehavior: SwarmBehavior.scatter, swarmCount: 15),
  };

  // Safe fetcher
  static MaskData getMask(String id) {
    return allMasks[id] ?? allMasks['standard']!;
  }
}