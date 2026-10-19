import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../core/session/session_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/parse.dart';
import '../../data/models/planning_models.dart';
import '../../routes/app_routes.dart';
import '../../widgets/async_state_view.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_list_view.dart';
import '../movements/movements_view.dart' show ProductPicker;
import 'planning_controllers.dart';

final _money = NumberFormat.simpleCurrency();
final _date = DateFormat.yMMMd();

Color severityColor(AlertSeverity s) => switch (s) {
      AlertSeverity.critical => AppTheme.stockout,
      AlertSeverity.high => Colors.deepOrange,
      AlertSeverity.medium => AppTheme.lowStock,
      AlertSeverity.low => Colors.blueGrey,
    };

Color poStatusColor(POStatus s) => switch (s) {
      POStatus.draft => Colors.blueGrey,
      POStatus.pending => AppTheme.lowStock,
      POStatus.approved => Colors.indigo,
      POStatus.partial => Colors.teal,
      POStatus.received => AppTheme.healthy,
      POStatus.cancelled => AppTheme.stockout,
    };

String _cap(String s) => s[0].toUpperCase() + s.substring(1);

// ---------------------------------------------------------------- alerts

class AlertsView extends StatelessWidget {
  const AlertsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<AlertsController>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Obx(() => Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final s in [null, ...AlertStatus.values])
                    ChoiceChip(
                      label: Text(s == null ? 'All' : _cap(s.name)),
                      selected: c.statusFilter.value == s,
                      onSelected: (_) => c.setStatus(s),
                    ),
                  RoleGate(
                    child: FilledButton.tonalIcon(
                      key: const Key('evaluate-alerts'),
                      onPressed: c.evaluating.value
                          ? null
                          : () async {
                              final error = await c.evaluate();
                              final r = c.lastEvaluation.value;
                              showSnack(
                                error ??
                                    'Checked stock: ${r?.created ?? 0} new, '
                                        '${r?.resolved ?? 0} resolved, ${r?.openTotal ?? 0} open',
                                error: error != null,
                              );
                            },
                      icon: const Icon(Icons.rule),
                      label: Text(c.evaluating.value ? 'Checking...' : 'Check stock now'),
                    ),
                  ),
                ],
              )),
        ),
        const Divider(height: 1),
        Expanded(
          child: PagedListView<StockAlert>(
            controller: c,
            emptyTitle: 'No alerts',
            emptyMessage: 'Use "Check stock now" to evaluate low stock, stockout risk, '
                'overstock and slow-moving rules against current data.',
            itemBuilder: (context, a) => AlertTile(alert: a, controller: c),
          ),
        ),
      ],
    );
  }
}

class AlertTile extends StatelessWidget {
  const AlertTile({super.key, required this.alert, required this.controller});

  final StockAlert alert;
  final AlertsController controller;

  @override
  Widget build(BuildContext context) {
    final a = alert;
    final color = severityColor(a.severity);
    final active = a.status == AlertStatus.open || a.status == AlertStatus.acknowledged;
    return ListTile(
      key: Key('alert-${a.id}'),
      leading: Icon(Icons.warning_amber_rounded, color: color),
      title: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('${alertTypeLabel(a.alertType)} - ${a.sku ?? ''} ${a.productName ?? ''}'),
        StatusChip(label: _cap(a.severity.name), color: color),
        if (a.status != AlertStatus.open)
          StatusChip(label: _cap(a.status.name), color: Colors.blueGrey),
      ]),
      subtitle: Text('${a.storeName ?? ''} - ${a.message}'),
      isThreeLine: true,
      trailing: active
          ? RoleGate(
              child: PopupMenuButton<AlertStatus>(
                tooltip: 'Update alert',
                onSelected: (s) async {
                  final error = await controller.setAlertStatus(a, s);
                  if (error != null) showSnack(error, error: true);
                },
                itemBuilder: (_) => [
                  if (a.status == AlertStatus.open)
                    const PopupMenuItem(
                        value: AlertStatus.acknowledged, child: Text('Acknowledge')),
                  const PopupMenuItem(value: AlertStatus.resolved, child: Text('Resolve')),
                  const PopupMenuItem(value: AlertStatus.dismissed, child: Text('Dismiss')),
                ],
              ),
            )
          : null,
    );
  }
}

// ---------------------------------------------------------------- replenishment

class ReplenishmentView extends StatelessWidget {
  const ReplenishmentView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<ReplenishmentController>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Obx(() => Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<String?>(
                    value: c.storeId.value,
                    hint: const Text('All stores'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('All stores')),
                      for (final s in c.stores)
                        DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                    ],
                    onChanged: c.setStore,
                  ),
                  FilterChip(
                    key: const Key('reorder-only'),
                    label: const Text('Needs reorder only'),
                    selected: c.reorderOnly.value,
                    onSelected: c.setReorderOnly,
                  ),
                  RoleGate(
                    child: Wrap(spacing: 8, children: [
                      OutlinedButton(
                        key: const Key('apply-settings'),
                        onPressed: c.busy.value
                            ? null
                            : () async => showSnack(await c.applySettings()),
                        child: const Text('Save as stock settings'),
                      ),
                      FilledButton(
                        key: const Key('create-draft-pos'),
                        onPressed: c.busy.value
                            ? null
                            : () async {
                                final (result, error) = await c.createDraftOrders();
                                if (error != null) {
                                  showSnack(error, error: true);
                                  return;
                                }
                                final r = result!;
                                showSnack('Created ${r.created.length} draft order(s)'
                                    '${r.skipped.isEmpty ? '' : '; no supplier for ${r.skipped.join(', ')}'}');
                              },
                        child: const Text('Draft purchase orders'),
                      ),
                    ]),
                  ),
                ],
              )),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            '95% service level, 7-day review period. Demand from the latest stored '
            'forecast when it covers lead time + review, otherwise the last 56 days of sales.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: PagedListView<ReplenishmentItem>(
            controller: c,
            emptyTitle: 'Nothing to reorder',
            emptyMessage: 'No SKU/store is at or below its computed reorder point.',
            itemBuilder: (context, item) => ReplenishmentTile(item: item),
          ),
        ),
      ],
    );
  }
}

class ReplenishmentTile extends StatelessWidget {
  const ReplenishmentTile({super.key, required this.item});

  final ReplenishmentItem item;

  @override
  Widget build(BuildContext context) {
    final i = item;
    final theme = Theme.of(context);
    final source = switch (i.demandSource) {
      'forecast' => 'Forecast (${i.forecastModel ?? ''})',
      'history' => '56-day sales history',
      _ => 'No sales data',
    };
    return ExpansionTile(
      key: Key('replenishment-${i.inventoryId}'),
      title: Text('${i.sku} ${i.productName}'),
      subtitle: Text('${i.storeName} - on hand ${formatQuantity(i.onHand)}'
          '${i.onOrder > 0 ? ' + ${formatQuantity(i.onOrder)} on order' : ''}'
          ' - reorder at ${formatQuantity(i.reorderPoint)}'),
      trailing: i.needsReorder
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Order ${formatQuantity(i.recommendedQty)}',
                    style: theme.textTheme.titleSmall?.copyWith(color: AppTheme.lowStock)),
                Text(i.supplierName ?? 'No supplier', style: theme.textTheme.bodySmall),
              ],
            )
          : const StatusChip(label: 'OK', color: AppTheme.healthy),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedAlignment: Alignment.centerLeft,
      children: [
        Wrap(spacing: 24, runSpacing: 6, children: [
          _kv('Demand source', source),
          _kv('Avg daily demand', formatQuantity(i.avgDailyDemand)),
          _kv('Daily std dev', formatQuantity(i.demandStd)),
          _kv('Lead time', '${i.leadTimeDays} days'),
          _kv('Lead-time demand', formatQuantity(i.leadTimeDemand)),
          _kv('Safety stock', formatQuantity(i.safetyStock)),
          _kv('Reorder point', formatQuantity(i.reorderPoint)),
          _kv('Target stock', formatQuantity(i.targetStock)),
          _kv('Days of cover', i.daysOfCover == null ? 'n/a' : formatQuantity(i.daysOfCover!)),
          _kv('Saved settings',
              'ROP ${formatQuantity(i.currentReorderPoint)}, SS ${formatQuantity(i.currentSafetyStock)}'),
        ]),
      ],
    );
  }

  static Widget _kv(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(k, style: const TextStyle(fontSize: 11)),
          Text(v),
        ],
      );
}

// ---------------------------------------------------------------- purchase orders

class PurchaseOrdersView extends StatelessWidget {
  const PurchaseOrdersView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<PurchaseOrdersController>();
    return Scaffold(
      floatingActionButton: RoleGate(
        child: FloatingActionButton.extended(
          key: const Key('new-po'),
          heroTag: null,
          onPressed: () => Get.toNamed(Routes.purchaseOrderForm),
          icon: const Icon(Icons.add),
          label: const Text('New order'),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Obx(() => Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in [null, ...POStatus.values])
                    ChoiceChip(
                      label: Text(s?.label ?? 'All'),
                      selected: c.statusFilter.value == s,
                      onSelected: (_) => c.setStatus(s),
                    ),
                ])),
          ),
          const Divider(height: 1),
          Expanded(
            child: PagedListView<PurchaseOrder>(
              controller: c,
              emptyTitle: 'No purchase orders',
              emptyMessage: 'Create one here or draft them from Replenishment.',
              itemBuilder: (context, po) => ListTile(
                key: Key('po-${po.id}'),
                onTap: () => Get.toNamed(Routes.purchaseOrderDetail, arguments: po.id),
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text('${po.displayRef} - ${po.supplierName ?? ''}'),
                subtitle: Text('${po.storeName ?? ''} - ${po.lineCount} lines - '
                    '${formatQuantity(po.totalReceived)}/${formatQuantity(po.totalOrdered)} received - '
                    'est. ${_money.format(po.estimatedCost)}'),
                trailing: StatusChip(label: po.status.label, color: poStatusColor(po.status)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PODetailView extends StatelessWidget {
  const PODetailView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<PODetailController>();
    return Scaffold(
      appBar: AppBar(title: Obx(() => Text(c.order.value?.displayRef ?? 'Purchase order'))),
      body: Obx(() {
        final po = c.order.value;
        final status = c.loading.value && po == null
            ? LoadStatus.loading
            : po == null
                ? (c.offline.value ? LoadStatus.offline : LoadStatus.error)
                : LoadStatus.data;
        return AsyncStateView(
          status: status,
          errorMessage: c.error.value,
          onRetry: c.load,
          builder: (context) => _PODetailBody(order: po!, controller: c),
        );
      }),
    );
  }
}

class _PODetailBody extends StatelessWidget {
  const _PODetailBody({required this.order, required this.controller});

  final PurchaseOrder order;
  final PODetailController controller;

  Future<void> _act(String action) async {
    const done = {'submit': 'submitted', 'approve': 'approved', 'cancel': 'cancelled'};
    final error = await controller.transition(action);
    showSnack(error ?? 'Order ${done[action]}', error: error != null);
  }

  Future<void> _receive(BuildContext context) async {
    final fields = {
      for (final i in order.items.where((i) => i.quantityRemaining > 0))
        i.id: TextEditingController(text: formatQuantity(i.quantityRemaining)),
    };
    final note = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Receive delivery'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final i in order.items.where((i) => fields.containsKey(i.id)))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      key: Key('receive-${i.id}'),
                      controller: fields[i.id],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      decoration: InputDecoration(
                        labelText: '${i.sku} ${i.productName}',
                        helperText: '${formatQuantity(i.quantityRemaining)} remaining - '
                            'leave blank to skip',
                      ),
                    ),
                  ),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: 'Note (optional)'),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!,
                        key: const Key('receive-error'),
                        style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              key: const Key('receive-confirm'),
              onPressed: () async {
                final result = await controller.receive(
                  {for (final e in fields.entries) e.key: e.value.text},
                  note: note.text,
                );
                if (!ctx.mounted) return;
                if (result == null) {
                  Navigator.of(ctx).pop();
                  showSnack('Receipt recorded; stock updated');
                } else {
                  setState(() => error = result);
                }
              },
              child: const Text('Receive'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final po = order;
    final theme = Theme.of(context);
    final session = Get.isRegistered<SessionService>() ? Get.find<SessionService>() : null;
    final canWrite = session?.canWrite ?? false;
    final isAdmin = session?.isAdmin ?? false;
    final busy = controller.busy.value;
    final actions = <Widget>[
      if (canWrite && po.status == POStatus.draft)
        FilledButton(
            key: const Key('po-submit'),
            onPressed: busy ? null : () => _act('submit'),
            child: const Text('Submit for approval')),
      if (isAdmin && po.status == POStatus.pending)
        FilledButton(
            key: const Key('po-approve'),
            onPressed: busy ? null : () => _act('approve'),
            child: const Text('Approve')),
      if (canWrite && (po.status == POStatus.approved || po.status == POStatus.partial))
        FilledButton(
            key: const Key('po-receive'),
            onPressed: busy ? null : () => _receive(context),
            child: const Text('Receive delivery')),
      if (canWrite &&
          (po.status == POStatus.draft ||
              po.status == POStatus.pending ||
              po.status == POStatus.approved))
        OutlinedButton(
            key: const Key('po-cancel'),
            onPressed: busy
                ? null
                : () async {
                    final ok = await confirmDialog(context,
                        title: 'Cancel ${po.displayRef}?',
                        message: 'Cancelled orders cannot be reopened.',
                        confirmLabel: 'Cancel order');
                    if (ok) await _act('cancel');
                  },
            child: const Text('Cancel order')),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                StatusChip(label: po.status.label, color: poStatusColor(po.status)),
                const SizedBox(width: 12),
                Text('Created ${_date.format(po.createdAt.toLocal())}',
                    style: theme.textTheme.bodySmall),
              ]),
              const SizedBox(height: 8),
              Text('${po.supplierName ?? ''} -> ${po.storeName ?? ''}',
                  style: theme.textTheme.titleMedium),
              Text('Estimated cost ${_money.format(po.estimatedCost)} at current unit costs'
                  '${po.expectedDate == null ? '' : ' - expected ${_date.format(po.expectedDate!)}'}'),
              if (po.status == POStatus.pending && !isAdmin)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Waiting for an admin or owner to approve.',
                      style: theme.textTheme.bodySmall),
                ),
            ]),
          ),
        ),
        if (actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Wrap(spacing: 8, runSpacing: 8, children: actions),
          ),
        Card(
          child: Column(children: [
            for (final i in po.items)
              ListTile(
                key: Key('po-line-${i.id}'),
                title: Text('${i.sku ?? ''} ${i.productName ?? ''}'),
                subtitle: Text('Received ${formatQuantity(i.quantityReceived)} of '
                    '${formatQuantity(i.quantityOrdered)}'),
                trailing: i.quantityRemaining > 0
                    ? Text('${formatQuantity(i.quantityRemaining)} to come')
                    : const Icon(Icons.check_circle, color: AppTheme.healthy),
              ),
          ]),
        ),
      ],
    );
  }
}

class POFormView extends StatefulWidget {
  const POFormView({super.key});

  @override
  State<POFormView> createState() => _POFormViewState();
}

class _POFormViewState extends State<POFormView> {
  final _reference = TextEditingController();

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Get.find<POFormController>();
    return Scaffold(
      appBar: AppBar(title: const Text('New purchase order')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Obx(() => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DropdownButtonFormField<String>(
                    key: const Key('po-supplier'),
                    initialValue: c.supplierId.value,
                    decoration: const InputDecoration(labelText: 'Supplier'),
                    items: [
                      for (final s in c.suppliers)
                        DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ],
                    onChanged: (v) => c.supplierId.value = v,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const Key('po-store'),
                    initialValue: c.storeId.value,
                    decoration: const InputDecoration(labelText: 'Deliver to store'),
                    items: [
                      for (final s in c.stores) DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ],
                    onChanged: (v) => c.storeId.value = v,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _reference,
                    maxLength: 120,
                    decoration: const InputDecoration(labelText: 'Reference (optional)'),
                  ),
                  ProductPicker(
                    key: ValueKey('po-product-${c.lines.length}'),
                    search: c.searchProducts,
                    onSelected: c.addProduct,
                    label: 'Add product',
                  ),
                  const SizedBox(height: 8),
                  for (final line in c.lines)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${line.product.sku} ${line.product.name}'),
                      subtitle: Text('Unit cost ${_money.format(line.product.unitCost)}'),
                      trailing: SizedBox(
                        width: 170,
                        child: Row(children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: line.quantity,
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(isDense: true, labelText: 'Qty'),
                              onChanged: (v) => line.quantity = v,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.close),
                            onPressed: () => c.removeLine(line),
                          ),
                        ]),
                      ),
                    ),
                  if (c.formError.value != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(c.formError.value!,
                          key: const Key('po-form-error'),
                          style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('po-save'),
                    onPressed: c.saving.value
                        ? null
                        : () async {
                            final po = await c.save(reference: _reference.text);
                            if (po != null) {
                              Get.offNamed(Routes.purchaseOrderDetail, arguments: po.id);
                              showSnack('Draft ${po.displayRef} created');
                            }
                          },
                    child: const Text('Save draft'),
                  ),
                ],
              )),
        ),
      ),
    );
  }
}
