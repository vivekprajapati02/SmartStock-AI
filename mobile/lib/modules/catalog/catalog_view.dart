import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/catalog_models.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_list_view.dart';
import 'catalog_controllers.dart';

class CatalogView extends StatelessWidget {
  const CatalogView({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 4,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Products'),
              Tab(text: 'Stores'),
              Tab(text: 'Categories'),
              Tab(text: 'Suppliers'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _ProductsTab(),
                _StoresTab(),
                _CategoriesTab(),
                _SuppliersTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A list with an "Add" button for writers.
class _TabScaffold extends StatelessWidget {
  const _TabScaffold({required this.body, required this.onAdd, this.header});

  final Widget body;
  final VoidCallback onAdd;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ?header,
          Expanded(child: body),
        ],
      ),
      floatingActionButton: RoleGate(
        child: FloatingActionButton(
          heroTag: null,
          tooltip: 'Add',
          onPressed: onAdd,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Products

class _ProductsTab extends StatelessWidget {
  const _ProductsTab();

  @override
  Widget build(BuildContext context) {
    final c = Get.find<ProductsController>();
    final currency = NumberFormat.simpleCurrency();
    return _TabScaffold(
      onAdd: () => _openProductForm(context, c),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextField(
          key: const Key('products-search'),
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search),
            hintText: 'Search SKU or name',
          ),
          onChanged: c.setSearch,
        ),
      ),
      body: PagedListView<Product>(
        controller: c,
        emptyTitle: 'No products',
        emptyMessage: 'Add your first product to start tracking stock.',
        itemBuilder: (context, p) => ListTile(
          key: Key('product-row-${p.id}'),
          title: Text(p.name),
          subtitle: Text('${p.sku} - ${p.unit} - cost ${currency.format(p.unitCost)}'
              ' - price ${currency.format(p.unitPrice)}'),
          trailing: p.isActive
              ? null
              : const StatusChip(label: 'Inactive', color: AppTheme.stockout),
          onTap: currentUserCanWrite()
              ? () => _openProductForm(context, c, existing: p)
              : null,
        ),
      ),
    );
  }
}

Future<void> _openProductForm(
  BuildContext context,
  ProductsController c, {
  Product? existing,
}) async {
  await c.loadLookups();
  if (!context.mounted) return;
  final sku = TextEditingController(text: existing?.sku);
  final name = TextEditingController(text: existing?.name);
  final unit = TextEditingController(text: existing?.unit ?? 'unit');
  final cost = TextEditingController(text: existing?.unitCost.toStringAsFixed(2) ?? '0');
  final price =
      TextEditingController(text: existing?.unitPrice.toStringAsFixed(2) ?? '0');
  String? categoryId = existing?.categoryId;
  String? supplierId = existing?.supplierId;
  var isActive = existing?.isActive ?? true;
  final money = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];

  await _showEditDialog(
    context,
    title: existing == null ? 'New product' : 'Edit product',
    fields: (setState) => [
      TextFormField(
        key: const Key('product-sku'),
        controller: sku,
        decoration: const InputDecoration(labelText: 'SKU'),
        validator: _requiredField,
      ),
      TextFormField(
        key: const Key('product-name'),
        controller: name,
        decoration: const InputDecoration(labelText: 'Name'),
        validator: _requiredField,
      ),
      DropdownButtonFormField<String?>(
        initialValue: categoryId,
        decoration: const InputDecoration(labelText: 'Category'),
        items: [
          const DropdownMenuItem(value: null, child: Text('None')),
          for (final cat in c.categories)
            DropdownMenuItem(value: cat.id, child: Text(cat.name)),
        ],
        onChanged: (v) => categoryId = v,
      ),
      DropdownButtonFormField<String?>(
        initialValue: supplierId,
        decoration: const InputDecoration(labelText: 'Supplier'),
        items: [
          const DropdownMenuItem(value: null, child: Text('None')),
          for (final s in c.suppliers)
            DropdownMenuItem(value: s.id, child: Text(s.name)),
        ],
        onChanged: (v) => supplierId = v,
      ),
      TextFormField(
        controller: unit,
        decoration: const InputDecoration(labelText: 'Unit'),
        validator: _requiredField,
      ),
      TextFormField(
        key: const Key('product-cost'),
        controller: cost,
        decoration: const InputDecoration(labelText: 'Unit cost'),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: money,
        validator: _nonNegativeNumber,
      ),
      TextFormField(
        key: const Key('product-price'),
        controller: price,
        decoration: const InputDecoration(labelText: 'Unit price'),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: money,
        validator: _nonNegativeNumber,
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Active'),
        value: isActive,
        onChanged: (v) => setState(() => isActive = v),
      ),
    ],
    onSave: () => c.save(
      ProductInput(
        sku: sku.text.trim(),
        name: name.text.trim(),
        categoryId: categoryId,
        supplierId: supplierId,
        unit: unit.text.trim(),
        unitCost: cost.text.trim(),
        unitPrice: price.text.trim(),
        isActive: isActive,
      ),
      id: existing?.id,
    ),
  );
}

// ---------------------------------------------------------------- Stores

class _StoresTab extends StatelessWidget {
  const _StoresTab();

  @override
  Widget build(BuildContext context) {
    final c = Get.find<StoresController>();
    return _TabScaffold(
      onAdd: () => _openStoreForm(context, c),
      body: PagedListView<Store>(
        controller: c,
        emptyTitle: 'No stores',
        emptyMessage: 'Add a store or warehouse to hold inventory.',
        itemBuilder: (context, s) => ListTile(
          leading: const Icon(Icons.storefront_outlined),
          title: Text(s.name),
          subtitle: s.location == null ? null : Text(s.location!),
          trailing: _RowActions(
            onEdit: () => _openStoreForm(context, c, existing: s),
            onDelete: () => _confirmDelete(context, s.name, () => c.remove(s.id)),
          ),
        ),
      ),
    );
  }
}

Future<void> _openStoreForm(
  BuildContext context,
  StoresController c, {
  Store? existing,
}) {
  final name = TextEditingController(text: existing?.name);
  final location = TextEditingController(text: existing?.location);
  return _showEditDialog(
    context,
    title: existing == null ? 'New store' : 'Edit store',
    fields: (_) => [
      TextFormField(
        key: const Key('store-name'),
        controller: name,
        decoration: const InputDecoration(labelText: 'Name'),
        validator: _requiredField,
      ),
      TextFormField(
        controller: location,
        decoration: const InputDecoration(labelText: 'Location (optional)'),
      ),
    ],
    onSave: () =>
        c.save(id: existing?.id, name: name.text, location: location.text),
  );
}

// ---------------------------------------------------------------- Categories

class _CategoriesTab extends StatelessWidget {
  const _CategoriesTab();

  @override
  Widget build(BuildContext context) {
    final c = Get.find<CategoriesController>();
    return _TabScaffold(
      onAdd: () => _openCategoryForm(context, c),
      body: PagedListView<Category>(
        controller: c,
        emptyTitle: 'No categories',
        itemBuilder: (context, cat) => ListTile(
          leading: const Icon(Icons.label_outline),
          title: Text(cat.name),
          trailing: _RowActions(
            onEdit: () => _openCategoryForm(context, c, existing: cat),
            onDelete: () =>
                _confirmDelete(context, cat.name, () => c.remove(cat.id)),
          ),
        ),
      ),
    );
  }
}

Future<void> _openCategoryForm(
  BuildContext context,
  CategoriesController c, {
  Category? existing,
}) {
  final name = TextEditingController(text: existing?.name);
  return _showEditDialog(
    context,
    title: existing == null ? 'New category' : 'Edit category',
    fields: (_) => [
      TextFormField(
        controller: name,
        decoration: const InputDecoration(labelText: 'Name'),
        validator: _requiredField,
      ),
    ],
    onSave: () => c.save(id: existing?.id, name: name.text),
  );
}

// ---------------------------------------------------------------- Suppliers

class _SuppliersTab extends StatelessWidget {
  const _SuppliersTab();

  @override
  Widget build(BuildContext context) {
    final c = Get.find<SuppliersController>();
    return _TabScaffold(
      onAdd: () => _openSupplierForm(context, c),
      body: PagedListView<Supplier>(
        controller: c,
        emptyTitle: 'No suppliers',
        itemBuilder: (context, s) => ListTile(
          leading: const Icon(Icons.local_shipping_outlined),
          title: Text(s.name),
          subtitle: Text([
            'Lead time ${s.leadTimeDays} days',
            if (s.contactEmail != null) s.contactEmail!,
            if (s.phone != null) s.phone!,
          ].join(' - ')),
          trailing: _RowActions(
            onEdit: () => _openSupplierForm(context, c, existing: s),
            onDelete: () => _confirmDelete(context, s.name, () => c.remove(s.id)),
          ),
        ),
      ),
    );
  }
}

Future<void> _openSupplierForm(
  BuildContext context,
  SuppliersController c, {
  Supplier? existing,
}) {
  final name = TextEditingController(text: existing?.name);
  final email = TextEditingController(text: existing?.contactEmail);
  final phone = TextEditingController(text: existing?.phone);
  final lead = TextEditingController(text: '${existing?.leadTimeDays ?? 7}');
  return _showEditDialog(
    context,
    title: existing == null ? 'New supplier' : 'Edit supplier',
    fields: (_) => [
      TextFormField(
        controller: name,
        decoration: const InputDecoration(labelText: 'Name'),
        validator: _requiredField,
      ),
      TextFormField(
        controller: email,
        decoration: const InputDecoration(labelText: 'Contact email (optional)'),
        keyboardType: TextInputType.emailAddress,
      ),
      TextFormField(
        controller: phone,
        decoration: const InputDecoration(labelText: 'Phone (optional)'),
      ),
      TextFormField(
        controller: lead,
        decoration: const InputDecoration(labelText: 'Lead time (days)'),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        validator: (v) {
          final n = int.tryParse(v ?? '');
          if (n == null) return 'Enter whole days';
          return n > 365 ? 'Max 365' : null;
        },
      ),
    ],
    onSave: () => c.save(
      id: existing?.id,
      name: name.text,
      contactEmail: email.text,
      phone: phone.text,
      leadTimeDays: int.parse(lead.text),
    ),
  );
}

// ---------------------------------------------------------------- Shared

String? _requiredField(String? v) =>
    (v == null || v.trim().isEmpty) ? 'Required' : null;

String? _nonNegativeNumber(String? v) {
  final n = double.tryParse(v?.trim() ?? '');
  if (n == null) return 'Enter a number';
  return n < 0 ? 'Must be 0 or more' : null;
}

class _RowActions extends StatelessWidget {
  const _RowActions({required this.onEdit, required this.onDelete});

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return RoleGate(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
              tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
          IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete),
        ],
      ),
    );
  }
}

Future<void> _confirmDelete(
  BuildContext context,
  String name,
  Future<String?> Function() remove,
) async {
  final ok = await confirmDialog(
    context,
    title: 'Delete "$name"?',
    message: 'This cannot be undone.',
  );
  if (!ok) return;
  final error = await remove();
  showSnack(error ?? 'Deleted "$name"', error: error != null);
}

/// Modal form that stays open and shows the server error if saving fails.
Future<void> _showEditDialog(
  BuildContext context, {
  required String title,
  required List<Widget> Function(StateSetter setState) fields,
  required Future<String?> Function() onSave,
}) {
  final formKey = GlobalKey<FormState>();
  String? error;
  var saving = false;
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final f in fields(setState))
                    Padding(padding: const EdgeInsets.only(bottom: 12), child: f),
                  if (error != null)
                    Text(error!,
                        key: const Key('edit-dialog-error'),
                        style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('edit-dialog-save'),
            onPressed: saving
                ? null
                : () async {
                    if (!formKey.currentState!.validate()) return;
                    setState(() {
                      saving = true;
                      error = null;
                    });
                    final result = await onSave();
                    if (!ctx.mounted) return;
                    if (result == null) {
                      Navigator.of(ctx).pop();
                      showSnack('Saved');
                    } else {
                      setState(() {
                        saving = false;
                        error = result;
                      });
                    }
                  },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
