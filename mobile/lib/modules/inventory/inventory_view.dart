import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/parse.dart';
import '../../data/models/inventory_models.dart';
import '../../routes/app_routes.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_list_view.dart';
import 'inventory_controller.dart';

class InventoryView extends StatelessWidget {
  const InventoryView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<InventoryController>();
    return Column(
      children: [
        _Filters(controller: c),
        const Divider(height: 1),
        Expanded(
          child: PagedListView<InventoryItem>(
            controller: c,
            emptyTitle: 'No stock rows match',
            emptyMessage: 'Inventory rows are created automatically when you '
                'add products and stores in the Catalogue tab.',
            itemBuilder: (context, item) => InventoryTile(
              item: item,
              onTap: () => Get.toNamed(
                Routes.inventoryDetail,
                arguments: item.id,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.controller});

  final InventoryController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              key: const Key('inventory-search'),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                hintText: 'Search SKU or product',
              ),
              onChanged: c.setSearch,
            ),
          ),
          Obx(() => DropdownButton<String?>(
                key: const Key('inventory-store-filter'),
                value: c.storeId.value,
                hint: const Text('All stores'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('All stores')),
                  for (final s in c.stores)
                    DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                ],
                onChanged: c.setStore,
              )),
          Obx(() => FilterChip(
                key: const Key('inventory-low-stock'),
                label: const Text('Low stock only'),
                selected: c.lowStockOnly.value,
                onSelected: c.setLowStockOnly,
              )),
        ],
      ),
    );
  }
}

class InventoryTile extends StatelessWidget {
  const InventoryTile({super.key, required this.item, this.onTap});

  final InventoryItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = NumberFormat.simpleCurrency();
    return ListTile(
      key: Key('inventory-row-${item.id}'),
      onTap: onTap,
      title: Text(item.productName ?? item.productId),
      subtitle: Text([
        if (item.sku != null) item.sku!,
        if (item.storeName != null) item.storeName!,
        'Reorder at ${formatQuantity(item.reorderPoint)}',
      ].join(' - ')),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(formatQuantity(item.quantityOnHand),
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          stockChip(item) ??
              Text(
                item.inventoryValue == null
                    ? ''
                    : currency.format(item.inventoryValue),
                style: theme.textTheme.bodySmall,
              ),
        ],
      ),
    );
  }
}

Widget? stockChip(InventoryItem item) {
  if (item.isStockout) {
    return const StatusChip(label: 'Out of stock', color: AppTheme.stockout);
  }
  if (item.isLowStock) {
    return const StatusChip(label: 'Low stock', color: AppTheme.lowStock);
  }
  return null;
}
