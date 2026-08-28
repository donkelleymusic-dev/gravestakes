class WearableData {
  final String id;
  final String name;
  final String slotType; // 'neck', 'arms', 'belt'
  final String counterTarget; 
  final String buffStat;
  final double buffValue;
  final String description;
  final String assetPath;

  WearableData({
    required this.id,
    required this.name,
    required this.slotType,
    required this.counterTarget,
    required this.buffStat,
    required this.buffValue,
    required this.description,
    this.assetPath = '',
  });

  factory WearableData.fromJson(Map<String, dynamic> json) {
    return WearableData(
      id: json['id'] as String,
      name: json['name'] as String,
      slotType: json['slot_type'] as String,
      counterTarget: json['counter_target'] as String,
      buffStat: json['buff_stat'] as String,
      buffValue: (json['buff_value'] as num).toDouble(),
      description: json['description'] as String,
      assetPath: json['asset_path'] as String? ?? '',
    );
  }
}