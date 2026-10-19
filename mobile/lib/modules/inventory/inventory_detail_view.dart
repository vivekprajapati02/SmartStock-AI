import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../core/utils/parse.dart';
import '../../data/models/inventory_models.dart';
import '../../routes/app_routes.dart';
import '../../widgets/async_state_view.dart';
import '../../widgets/common.dart';
import '../movements/movements_view.dart';
import 'inventory_controller.dart';
import 'inventory_view.dart';

class InventoryDetailView extends StatelessWidget {
  const InventoryDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<InventoryDetailController>();
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(c.item.value?.productName ?? 'Stock item')),
      ),
      floatingActionButton: RoleGate(
        child: Obx(() {
          final item = c.item.value;
          if (item == null) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            key: const Key('detail-record-movement'),
            icon: const Icon(Icons.swap_vert),
            label: const Text('Record movement'),
            onPressed: () async {
              final recorded = await Get.toNamed<bool>(
                Routes.movementForm,
                arguments: MovementFormArgs(
                  productId: item.productId,
                  storeId: item.storeId,
                  productLabel: '${item.sku ?? ''} ${item.productName ?? ''}'.trim(),
                ),
              );
              if (recorded == true) await c.load();
            },
          );
        }),
      ),
      body: Obx(() {
        final status = c.loading.value && c.item.value == null
            ? LoadStatus.loading
            : c.item.value == null
                ? (c.offline.value ? LoadStatus.offline : LoadStatus.error)
                : LoadStatus.data;
        return AsyncStateView(
          status: status,
          errorMessage: c.error.value,
          onRetry: c.load,
          builder: (context) => RefreshIndicator(
            onRefresh: c.load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Summary(item: c.item.value!),
                const SizedBox(height: 16),
                _SettingsCard(controller: c),
                const SizedBox(height: 16),
                Text('Recent movements',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (c.recentMovements.isEmpty)
                  const Card(
                    child: ListTile(title: Text('No movements recorded yet.')),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (final m in c.recentMovements) MovementTile(movement: m),
                      ],
                    ),
                  ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = NumberFormat.simpleCurrency();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${item.sku ?? ''} - ${item.storeName ?? ''}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                ?stockChip(item),
              ],
            ),
            const SizedBox(height: 12),
            Text(formatQuantity(item.quantityOnHand),
                key: const Key('detail-qty'),
                style: theme.textTheme.displaySmall),
            Text('on hand', style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _Fact('Unit cost',
                    item.unitCost == null ? '-' : currency.format(item.unitCost)),
                _Fact(
                    'Stock value',
                    item.inventoryValue == null
                        ? '-'
                        : currency.format(item.inventoryValue)),
                _Fact('Updated',
                    DateFormat.yMMMd().add_jm().format(item.updatedAt.toLocal())),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

final _decimalInput = FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'));

String? _validateNonNegative(String? v) {
  if (v == null || v.trim().isEmpty) return 'Required';
  final parsed = double.tryParse(v.trim());
  if (parsed == null) return 'Enter a number';
  if (parsed < 0) return 'Must be 0 or more';
  return null;
}

class _SettingsCard extends StatefulWidget {
  const _SettingsCard({required this.controller});

  final InventoryDetailController controller;

  @override
  State<_SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<_SettingsCard> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _reorder;
  late final TextEditingController _safety;
  late final TextEditingController _lead;
  String? _error;

  @override
  void initState() {
    super.initState();
    final item = widget.controller.item.value!;
    _reorder = TextEditingController(text: formatQuantity(item.reorderPoint));
    _safety = TextEditingController(text: formatQuantity(item.safetyStock));
    _lead = TextEditingController(text: '${item.leadTimeDays}');
  }

  @override
  void dispose() {
    _reorder.dispose();
    _safety.dispose();
    _lead.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final error = await widget.controller.saveSettings(
      reorderPoint: _reorder.text.trim(),
      safetyStock: _safety.text.trim(),
      leadTimeDays: int.parse(_lead.text.trim()),
    );
    setState(() => _error = error);
    if (error == null) showSnack('Stock settings saved');
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Replenishment settings',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 160,
                    child: TextFormField(
                      key: const Key('settings-reorder'),
                      controller: _reorder,
                      decoration: const InputDecoration(labelText: 'Reorder point'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [_decimalInput],
                      validator: _validateNonNegative,
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: TextFormField(
                      key: const Key('settings-safety'),
                      controller: _safety,
                      decoration: const InputDecoration(labelText: 'Safety stock'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [_decimalInput],
                      validator: _validateNonNegative,
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: TextFormField(
                      key: const Key('settings-lead'),
                      controller: _lead,
                      decoration:
                          const InputDecoration(labelText: 'Lead time (days)'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) {
                        final n = int.tryParse(v?.trim() ?? '');
                        if (n == null) return 'Enter whole days';
                        if (n > 365) return 'Max 365';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 12),
              RoleGate(
                fallback: Text(
                  'Only managers and above can change these settings.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                child: Obx(() => FilledButton.tonal(
                      key: const Key('settings-save'),
                      onPressed: widget.controller.saving.value ? null : _save,
                      child: const Text('Save settings'),
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
