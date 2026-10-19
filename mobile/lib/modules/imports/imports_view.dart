import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/import_models.dart';
import '../../routes/app_routes.dart';
import '../../widgets/async_state_view.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_list_view.dart';
import 'imports_controller.dart';

Color importStatusColor(ImportStatus status) => switch (status) {
      ImportStatus.completed => AppTheme.healthy,
      ImportStatus.partial => AppTheme.lowStock,
      ImportStatus.failed => AppTheme.stockout,
      ImportStatus.pending => Colors.blueGrey,
    };

class ImportsView extends StatelessWidget {
  const ImportsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<ImportsController>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: _UploadCard(controller: c),
        ),
        Expanded(
          child: PagedListView<ImportBatch>(
            controller: c,
            emptyTitle: 'No imports yet',
            emptyMessage: 'Uploaded sales files and their results appear here.',
            itemBuilder: (context, b) => ImportBatchTile(
              batch: b,
              onTap: () => Get.toNamed(Routes.importDetail, arguments: b.id),
            ),
          ),
        ),
      ],
    );
  }
}

class _UploadCard extends StatelessWidget {
  const _UploadCard({required this.controller});

  final ImportsController controller;

  Future<void> _upload() async {
    final batch = await controller.pickAndUpload();
    if (batch == null) return;
    showSnack(
      '${batch.filename}: ${batch.status.label} - '
      '${batch.validRows} of ${batch.totalRows} rows imported',
      error: batch.status == ImportStatus.failed,
    );
    Get.toNamed(Routes.importDetail, arguments: batch.id);
  }

  Future<void> _showTemplate(BuildContext context) async {
    final text = await controller.template();
    if (text == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CSV template'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Save this as a .csv file. The example row uses one of your '
                  'own SKUs and stores with quantity 0 - replace it with real sales.'),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                child: SelectableText(
                  text,
                  key: const Key('template-text'),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (ctx.mounted) Navigator.of(ctx).pop();
              showSnack('Template copied');
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Import daily sales', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'CSV columns: sku, store, sale_date (YYYY-MM-DD), quantity. '
              'SKUs and store names must already exist. Rows already imported '
              'for the same SKU, store and date are reported as duplicates and '
              'not changed.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                RoleGate(
                  fallback: Text('Only managers and above can import.',
                      style: theme.textTheme.bodySmall),
                  child: Obx(() => FilledButton.icon(
                        key: const Key('import-upload'),
                        onPressed: controller.uploading.value ? null : _upload,
                        icon: controller.uploading.value
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.upload_file),
                        label: Text(controller.uploading.value
                            ? 'Uploading...'
                            : 'Choose CSV file'),
                      )),
                ),
                OutlinedButton.icon(
                  key: const Key('import-template'),
                  onPressed: () => _showTemplate(context),
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('Template'),
                ),
              ],
            ),
            Obx(() {
              final error = controller.uploadError.value;
              if (error == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error,
                    key: const Key('import-upload-error'),
                    style: TextStyle(color: theme.colorScheme.error)),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class ImportBatchTile extends StatelessWidget {
  const ImportBatchTile({super.key, required this.batch, this.onTap});

  final ImportBatch batch;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final b = batch;
    return ListTile(
      key: Key('import-row-${b.id}'),
      onTap: onTap,
      leading: const Icon(Icons.table_chart_outlined),
      title: Text(b.filename),
      subtitle: Text(
        '${DateFormat.yMMMd().add_jm().format(b.createdAt.toLocal())} - '
        '${b.validRows} imported, ${b.invalidRows} invalid, '
        '${b.duplicateRows} duplicate of ${b.totalRows}',
      ),
      trailing: StatusChip(label: b.status.label, color: importStatusColor(b.status)),
    );
  }
}

class ImportDetailView extends StatelessWidget {
  const ImportDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<ImportDetailController>();
    return Scaffold(
      appBar: AppBar(title: Obx(() => Text(c.batch.value?.filename ?? 'Import'))),
      body: Obx(() {
        final status = c.loading.value && c.batch.value == null
            ? LoadStatus.loading
            : c.batch.value == null
                ? (c.offline.value ? LoadStatus.offline : LoadStatus.error)
                : LoadStatus.data;
        return AsyncStateView(
          status: status,
          errorMessage: c.error.value,
          onRetry: c.load,
          builder: (context) => ImportResultBody(batch: c.batch.value!),
        );
      }),
    );
  }
}

class ImportResultBody extends StatelessWidget {
  const ImportResultBody({super.key, required this.batch});

  final ImportBatch batch;

  @override
  Widget build(BuildContext context) {
    final b = batch;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            StatusChip(label: b.status.label, color: importStatusColor(b.status)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                DateFormat.yMMMd().add_jm().format(b.createdAt.toLocal()),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Count('Rows in file', b.totalRows, key: const Key('count-total')),
            _Count('Imported', b.validRows,
                color: AppTheme.healthy, key: const Key('count-valid')),
            _Count('Invalid', b.invalidRows,
                color: AppTheme.stockout, key: const Key('count-invalid')),
            _Count('Duplicates', b.duplicateRows,
                color: AppTheme.lowStock, key: const Key('count-duplicate')),
          ],
        ),
        const SizedBox(height: 20),
        Text('Problems', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (b.errors.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.check_circle_outline, color: AppTheme.healthy),
              title: Text('No problems - every row was imported.'),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (final e in b.errors) _ErrorTile(error: e),
              ],
            ),
          ),
        if (b.errorsTruncated)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Showing the first ${b.errors.length} of ${b.errorCount} problems.',
              key: const Key('errors-truncated'),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.value, {super.key, this.color});

  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(NumberFormat.decimalPattern().format(value),
                  style: theme.textTheme.headlineSmall?.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorTile extends StatelessWidget {
  const _ErrorTile({required this.error});

  final ImportRowError error;

  @override
  Widget build(BuildContext context) {
    final e = error;
    final (icon, color) = switch (e.kind) {
      ImportErrorKind.duplicate => (Icons.content_copy, AppTheme.lowStock),
      ImportErrorKind.file => (Icons.insert_drive_file_outlined, AppTheme.stockout),
      ImportErrorKind.invalid => (Icons.error_outline, AppTheme.stockout),
    };
    final where = [
      if (e.row != null) 'Line ${e.row! + 1}',
      if (e.column != null) e.column!,
      if (e.value != null && e.value!.isNotEmpty) '"${e.value}"',
    ].join(' - ');
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(e.message),
      subtitle: where.isEmpty ? null : Text(where),
    );
  }
}
