import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide FormData, MultipartFile;
import 'package:smartstock/core/files/csv_file_picker.dart';
import 'package:smartstock/data/models/import_models.dart';
import 'package:smartstock/modules/dashboard/dashboard_controller.dart';
import 'package:smartstock/modules/imports/imports_controller.dart';
import 'package:smartstock/modules/imports/imports_view.dart';

import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

class FakePicker implements CsvFilePicker {
  FakePicker(this.file);

  PickedCsv? file;
  int calls = 0;

  @override
  Future<PickedCsv?> pick() async {
    calls++;
    return file;
  }
}

/// Does not auto-load: a plain `test` has no frames, so GetX's post-frame
/// onReady would otherwise leak into the next widget test.
class _ManualDashboard extends DashboardController {
  _ManualDashboard(Harness h) : super(h.analytics);

  @override
  void onReady() {}
}

PickedCsv _csv(String text) =>
    PickedCsv(name: 'sales.csv', bytes: Uint8List.fromList(utf8.encode(text)));

void main() {
  setUp(() {
    Get.reset();
    Get.testMode = true;
  });

  test('ImportBatch parses counts and error report', () {
    final b = ImportBatch.fromJson(importJson(truncated: true));
    expect(b.status, ImportStatus.partial);
    expect((b.totalRows, b.validRows, b.invalidRows, b.duplicateRows), (4, 2, 1, 1));
    expect(b.errorCount, 2);
    expect(b.errorsTruncated, isTrue);
    expect(b.errors.first.kind, ImportErrorKind.invalid);
    expect(b.errors.first.row, 2);
    expect(b.errors.last.kind, ImportErrorKind.duplicate);
    // List endpoint omits errors.
    final summary = ImportBatch.fromJson(importJson()..remove('errors'));
    expect(summary.errors, isEmpty);
  });

  test('upload sends the file as multipart form data', () async {
    final h = Harness((o) async => (201, importJson(status: 'completed')));
    final batch = await h.imports.uploadSalesCsv(
      filename: 'sales.csv',
      bytes: Uint8List.fromList(utf8.encode('sku,store,sale_date,quantity\n')),
    );
    expect(batch.status, ImportStatus.completed);
    final req = h.adapter.requests.single;
    expect(req.method, 'POST');
    expect(req.path, '/imports');
    final form = req.body as FormData;
    expect(form.files.single.key, 'file');
    expect(form.files.single.value.filename, 'sales.csv');
    expect(form.files.single.value.length, 29);
  });

  group('ImportsController', () {
    test('uploads a picked file, records the result and refreshes history', () async {
      final h = Harness((o) async => o.method == 'POST'
          ? (201, importJson())
          : (200, pageJson([importJson()..remove('errors')])));
      final picker = FakePicker(_csv('sku,store,sale_date,quantity\nSKU-1,Main,2026-10-01,3\n'));
      final c = ImportsController(h.imports, picker);

      final batch = await c.pickAndUpload();

      expect(batch, isNotNull);
      expect(c.lastResult.value!.validRows, 2);
      expect(c.uploadError.value, isNull);
      expect(c.items, hasLength(1));
      expect(h.adapter.requests.map((r) => '${r.method} ${r.path}'),
          ['POST /imports', 'GET /imports']);
    });

    test('cancelling the picker sends nothing', () async {
      final h = Harness((o) async => (200, pageJson([])));
      final c = ImportsController(h.imports, FakePicker(null));
      expect(await c.pickAndUpload(), isNull);
      expect(h.adapter.requests, isEmpty);
      expect(c.uploadError.value, isNull);
    });

    test('request failure is shown, not swallowed', () async {
      final h = Harness((o) async =>
          (403, errorJson('permission_denied', 'Your role is not permitted to perform this action.')));
      final c = ImportsController(h.imports, FakePicker(_csv('x')));
      expect(await c.pickAndUpload(), isNull);
      expect(c.uploadError.value, 'Your role is not permitted to perform this action.');
      expect(c.uploading.value, isFalse);
    });

    test('successful rows refresh the dashboard', () async {
      final h = Harness((o) async {
        if (o.path == '/analytics/dashboard') return (200, dashboardJson());
        return o.method == 'POST' ? (201, importJson(valid: 3)) : (200, pageJson([]));
      });
      Get.put<DashboardController>(_ManualDashboard(h));
      final c = ImportsController(h.imports, FakePicker(_csv('x')));
      await c.pickAndUpload();
      await pumpEventQueue();
      expect(h.adapter.requests.map((r) => r.path), contains('/analytics/dashboard'));
    });

    test('failed batch does not refresh the dashboard', () async {
      final h = Harness((o) async => o.method == 'POST'
          ? (201, importJson(status: 'failed', valid: 0, invalid: 0, duplicate: 1))
          : (200, pageJson([])));
      Get.put<DashboardController>(_ManualDashboard(h));
      final c = ImportsController(h.imports, FakePicker(_csv('x')));
      final batch = await c.pickAndUpload();
      expect(batch!.status, ImportStatus.failed);
      expect(h.adapter.requests.map((r) => r.path), isNot(contains('/analytics/dashboard')));
    });

    test('template is fetched as plain text', () async {
      final h = Harness((o) async => (200, 'sku,store,sale_date,quantity\n'));
      final c = ImportsController(h.imports, FakePicker(null));
      final text = await c.template();
      // FakeAdapter JSON-encodes bodies; a plain response type returns raw text.
      expect(text, contains('sku,store,sale_date,quantity'));
    });
  });

  group('views', () {
    testWidgets('result shows counts, line numbers and truncation', (tester) async {
      final batch = ImportBatch.fromJson(importJson(truncated: true));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ImportResultBody(batch: batch)),
      ));
      String count(String key) => tester
          .widget<Text>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)).last)
          .data!;
      expect(count('count-total'), '4');
      expect(count('count-valid'), '2');
      expect(count('count-invalid'), '1');
      expect(count('count-duplicate'), '1');
      expect(find.text('Unknown SKU for this organisation.'), findsOneWidget);
      // Row 2 is line 3 of the file (header is line 1).
      expect(find.text('Line 3 - sku - "NOPE"'), findsOneWidget);
      expect(find.byKey(const Key('errors-truncated')), findsOneWidget);
    });

    testWidgets('clean import shows no problems', (tester) async {
      final batch = ImportBatch.fromJson(
          importJson(status: 'completed', valid: 4, invalid: 0, duplicate: 0, errors: []));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ImportResultBody(batch: batch)),
      ));
      expect(find.text('No problems - every row was imported.'), findsOneWidget);
    });

    testWidgets('viewer sees history but no upload button', (tester) async {
      final h = Harness((o) async => (200, pageJson([importJson()..remove('errors')])));
      h.register(role: 'viewer');
      Get.put(ImportsController(h.imports, FakePicker(null)));
      await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: ImportsView())));
      await tester.pumpAndSettle();
      expect(find.text('sales.csv'), findsOneWidget);
      expect(find.text('Partially imported'), findsOneWidget);
      expect(find.byKey(const Key('import-upload')), findsNothing);
      expect(find.text('Only managers and above can import.'), findsOneWidget);
    });

    testWidgets('manager sees upload button', (tester) async {
      final h = Harness((o) async => (200, pageJson([])));
      h.register(role: 'manager');
      Get.put(ImportsController(h.imports, FakePicker(null)));
      await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: ImportsView())));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('import-upload')), findsOneWidget);
      expect(find.text('No imports yet'), findsOneWidget);
    });
  });
}
