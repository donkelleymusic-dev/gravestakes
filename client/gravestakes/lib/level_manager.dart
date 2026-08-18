class LevelConfig {
  final int botCount;
  final double wanderSpeed;
  final double huntSpeed;

  LevelConfig({
    required this.botCount,
    required this.wanderSpeed,
    required this.huntSpeed,
  });
}

class LevelManager {
  // Scales the difficulty based on the Host's level
  static LevelConfig getConfigForLevel(int level) {
    if (level <= 2) {
      // Levels 1-2: Easy Tutorial Phase
      // Only 1 slow bot. Very easy to outrun.
      return LevelConfig(botCount: 1, wanderSpeed: 60.0, huntSpeed: 100.0);
    } 
    else if (level <= 5) {
      // Levels 3-5: The Training Wheels Come Off
      // 2 bots, slightly faster.
      return LevelConfig(botCount: 2, wanderSpeed: 70.0, huntSpeed: 115.0);
    } 
    else if (level <= 10) {
      // Levels 6-10: Standard Difficulty
      // 3 bots, normal speeds.
      return LevelConfig(botCount: 3, wanderSpeed: 80.0, huntSpeed: 130.0);
    } 
    else if (level <= 20) {
      // Levels 11-20: Hard Mode
      // 4 bots, hunting speed is now significantly threatening.
      return LevelConfig(botCount: 4, wanderSpeed: 90.0, huntSpeed: 145.0);
    } 
    else {
      // Levels 21+: Nightmare Mode
      // 5+ bots that wander fast and hunt even faster.
      return LevelConfig(botCount: 5, wanderSpeed: 100.0, huntSpeed: 160.0);
    }
  }
}