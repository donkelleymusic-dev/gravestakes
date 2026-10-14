enum ChestRewardType {
  points,
  currency,
  invisibility,
  disguise,
  rangeIncrease,
  teleport,
  cursedRelic,
}

class ChestReward {
  final ChestRewardType type;
  final String label;
  final int value;

  ChestReward({
    required this.type,
    required this.label,
    this.value = 0,
  });
}