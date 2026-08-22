enum ChestRewardType {
  points,
  currency,
  invisibility,
  disguise,
  rangeIncrease,
  teleport,
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