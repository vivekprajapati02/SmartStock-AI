import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/parse.dart';
import '../../data/models/catalog_models.dart';
import '../../data/models/inventory_models.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_list_view.dart';
import 'movements_controller.dart';

export 'movements_controller.dart' show MovementFormArgs;

class MovementsView extends StatelessWidget {
  const MovementsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<MovementsController>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 300,
                child: ProductPicker(
                  key: const Key('movements-product-filter'),
                  search: c.searchProducts,
                  label: 'Filter by product',
                  onSelected: c.setProduct,
                  onCleared: () => c.setProduct(null),
                ),
              ),
              Obx(() => DropdownButton<String?>(
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
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: PagedListView<Movement>(
            controller: c,
            emptyTitle: 'No stock movements yet',
            emptyMessage: 'Stock received, sold or adjusted will appear here.',
            itemBuilder: (context, m) => MovementTile(movement: m),
          ),
        ),
      ],
    );
  }
}

class MovementTile extends StatelessWidget {
  const MovementTile({super.key, required this.movement});

  final Movement movement;

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final (icon, color, sign) = switch (m.movementType) {
      MovementType.stockIn => (Icons.south_west, AppTheme.healthy, '+'),
      MovementType.stockOut => (Icons.north_east, AppTheme.stockout, '-'),
      MovementType.adjust => (
          Icons.tune,
          AppTheme.lowStock,
          m.quantity >= 0 ? '+' : ''
        ),
    };
    final details = [
      if (m.storeName != null) m.storeName!,
      DateFormat.yMMMd().add_jm().format(m.occurredAt.toLocal()),
      if (m.reference != null && m.reference!.isNotEmpty) 'Ref ${m.reference}',
    ].join(' - ');
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        foregroundColor: color,
        child: Icon(icon, size: 20),
      ),
      title: Text('${m.sku ?? ''} ${m.productName ?? ''}'.trim()),
      subtitle: Text(
        m.note == null || m.note!.isEmpty ? details : '$details\n${m.note}',
      ),
      isThreeLine: m.note != null && m.note!.isNotEmpty,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('$sign${formatQuantity(m.quantity)}',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: color)),
          Text(m.movementType.label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Server-searched product autocomplete.
class ProductPicker extends StatelessWidget {
  const ProductPicker({
    super.key,
    required this.search,
    required this.onSelected,
    this.onCleared,
    this.label = 'Product',
    this.initialText,
  });

  final Future<List<Product>> Function(String) search;
  final ValueChanged<Product> onSelected;
  final VoidCallback? onCleared;
  final String label;
  final String? initialText;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Product>(
      initialValue: TextEditingValue(text: initialText ?? ''),
      displayStringForOption: (p) => '${p.sku} ${p.name}',
      optionsBuilder: (value) => search(value.text),
      onSelected: onSelected,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextField(
        controller: controller,
        focusNode: focusNode,
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: onCleared == null
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    controller.clear();
                    onCleared!();
                  },
                ),
        ),
      ),
    );
  }
}

class MovementFormView extends StatefulWidget {
  const MovementFormView({super.key});

  @override
  State<MovementFormView> createState() => _MovementFormViewState();
}

class _MovementFormViewState extends State<MovementFormView> {
  final _quantity = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();

  MovementFormController get _c => Get.find<MovementFormController>();

  @override
  void dispose() {
    _quantity.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final movement = await _c.submit(
      quantity: _quantity.text,
      reference: _reference.text,
      note: _note.text,
    );
    if (movement != null) {
      Get.back<bool>(result: true);
      showSnack('${movement.movementType.label} of '
          '${formatQuantity(movement.quantity)} recorded');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      appBar: AppBar(title: const Text('Record stock movement')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Obx(() => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ProductPicker(
                      key: const Key('movement-product'),
                      search: c.searchProducts,
                      onSelected: c.selectProduct,
                      initialText: c.args.productLabel,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: const Key('movement-store'),
                      initialValue: c.storeId.value,
                      decoration: InputDecoration(
                        labelText: 'Store',
                        helperText: c.loadingStores.value ? 'Loading stores...' : null,
                      ),
                      items: [
                        for (final s in c.stores)
                          DropdownMenuItem(value: s.id, child: Text(s.name)),
                      ],
                      onChanged: (v) => c.storeId.value = v,
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<MovementType>(
                      key: const Key('movement-type'),
                      segments: [
                        for (final t in MovementType.values)
                          ButtonSegment(value: t, label: Text(t.label)),
                      ],
                      selected: {c.type.value},
                      onSelectionChanged: (s) => c.type.value = s.first,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('movement-quantity'),
                      controller: _quantity,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                      ],
                      decoration: InputDecoration(
                        labelText: c.type.value == MovementType.adjust
                            ? 'Change (+/-)'
                            : 'Quantity',
                        helperText: c.type.value == MovementType.adjust
                            ? 'Signed change, e.g. -3 to write off three units'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('movement-reference'),
                      controller: _reference,
                      maxLength: 120,
                      decoration: const InputDecoration(
                          labelText: 'Reference (optional)'),
                    ),
                    TextField(
                      key: const Key('movement-note'),
                      controller: _note,
                      maxLength: 500,
                      maxLines: 2,
                      decoration:
                          const InputDecoration(labelText: 'Note (optional)'),
                    ),
                    if (c.formError.value != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          c.formError.value!,
                          key: const Key('movement-error'),
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    FilledButton(
                      key: const Key('movement-submit'),
                      onPressed: c.submitting.value ? null : _submit,
                      child: c.submitting.value
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Record movement'),
                    ),
                  ],
                )),
          ),
        ),
      ),
    );
  }
}
