import 'package:flutter/material.dart';

class LumenTier {
  final String name;
  final Color color;
  final IconData icon;
  final int minLumen;

  const LumenTier(this.name, this.color, this.icon, this.minLumen);
}

class LumenSystem {
  static const List<LumenTier> tiers = [
    LumenTier('EMBER', Colors.grey, Icons.blur_circular, 0),
    LumenTier('SPARK', Colors.orangeAccent, Icons.flash_on, 500),
    LumenTier('CANDLE', Colors.yellowAccent, Icons.local_fire_department, 1200),
    LumenTier('LANTERN', Colors.lightGreenAccent, Icons.wb_iridescent, 2500),
    LumenTier('TORCH', Colors.cyanAccent, Icons.wb_incandescent, 4500),
    LumenTier('BEACON', Colors.purpleAccent, Icons.cell_tower, 7000),
    LumenTier('RADIANT', Colors.white, Icons.ac_unit, 10000),
  ];

  static LumenTier getTier(int currentLumen) {
    for (int i = tiers.length - 1; i >= 0; i--) {
      if (currentLumen >= tiers[i].minLumen) {
        return tiers[i];
      }
    }
    return tiers.first;
  }
}
