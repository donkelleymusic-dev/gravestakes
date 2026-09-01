import 'package:flutter/material.dart';
import 'item_thumbnail.dart'; // Reference your buildSafeItemThumbnail helper

class InventoryGrid extends StatelessWidget {
  final String targetItemType;
  final List<Map<String, dynamic>> items;
  final Set<String> equippedItemIds;
  final Map<String, Map<String, dynamic>> catalog;
  final Function(String itemType, String itemId) onItemTap;
  final Function(String itemType, String itemId)? onItemPreviewStart;
  final VoidCallback? onItemPreviewEnd;

  const InventoryGrid({
    super.key,
    required this.targetItemType,
    required this.items,
    required this.equippedItemIds,
    required this.catalog,
    required this.onItemTap,
    this.onItemPreviewStart,
    this.onItemPreviewEnd,
  });

  @override
  Widget build(BuildContext context) {
    // Inject default character if displaying character list
    List<Map<String, dynamic>> displayItems = List.from(items);
    if (targetItemType == 'character') {
      bool hasDefault = displayItems.any((i) => i['item_id'] == 'default');
      if (!hasDefault) {
        displayItems.insert(0, {'item_type': 'character', 'item_id': 'default'});
      }
    }

    if (displayItems.isEmpty) {
      return const Center(
        child: Text('No items in this category.', style: TextStyle(color: Colors.white54)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: displayItems.length,
      itemBuilder: (context, index) {
        final itemId = displayItems[index]['item_id'] as String;
        final bool isEquipped = equippedItemIds.contains(itemId);

        String displayTitle = itemId.replaceAll('_', ' ').toUpperCase();
        String? assetPath;

        if (catalog.containsKey(itemId)) {
          final itemData = catalog[itemId]!;
          displayTitle = itemData['name'] ?? displayTitle;
          assetPath = itemData['asset_path'] ?? itemData['thumbnail_path'];
        }

        return MouseRegion(
          onEnter: (_) => onItemPreviewStart?.call(targetItemType, itemId),
          onExit: (_) => onItemPreviewEnd?.call(),
          child: GestureDetector(
            onLongPressStart: (_) => onItemPreviewStart?.call(targetItemType, itemId),
            onLongPressEnd: (_) => onItemPreviewEnd?.call(),
            onLongPressCancel: () => onItemPreviewEnd?.call(),
            onTap: () => onItemTap(targetItemType, itemId),
            child: Container(
              decoration: BoxDecoration(
                color: isEquipped ? Colors.purpleAccent.withOpacity(0.15) : Colors.grey[900],
                border: Border.all(color: isEquipped ? Colors.purpleAccent : Colors.white12, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      buildSafeItemThumbnail(
                        assetPath: assetPath,
                        slotType: targetItemType,
                        size: 36.0,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        displayTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: isEquipped ? Colors.white : Colors.white70,
                          fontWeight: isEquipped ? FontWeight.bold : FontWeight.normal,
                          fontFamily: 'Courier',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}