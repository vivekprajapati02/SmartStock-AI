import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:smartstock/data/models/catalog_models.dart';
import 'package:smartstock/data/models/planning_models.dart';
import 'package:smartstock/modules/planning/planning_controllers.dart';
import 'package:smartstock/modules/planning/planning_views.dart';

import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _product = Product(
  id: 'p1', sku: 'SKU-1', name: 'Widget', unit: 'unit',
  unitCost: 2.5, unitPrice: 5, isActive: true,
);

void main() {
  setUp(() {
    Get.reset();
    Get.testMode = true;
  });

  test('models parse decimal strings and nullable values', () {
    final po = PurchaseOrder.fromJson(poJson(status: 'partial', received: 4));
    expect(po.status, POStatus.partial);
    expect(po.items.single.quantityRemaining, 6);
    expect(po.estimatedCost, 25);
    expect(po.displayRef, 'PO-1001');
    final r = ReplenishmentItem.fromJson(replenishmentJson()..['days_of_cover'] = null);
    expect(r.daysOfCover, isNull);
    expect(r.forecastModel, 'lightgbm');
    final a = StockAlert.fromJson(alertJson());
    expect(a.severity, AlertSeverity.critical);
    expect(alertTypeLabel(a.alertType), 'Stockout risk');
  });

  group('AlertsController', () {
    test('defaults to open alerts and evaluates then reloads', () async {
      final h = Harness((o) async => o.path == '/alerts:evaluate'
          ? (200, {'created': 2, 'updated': 0, 'resolved': 1, 'open_total': 2, 'evaluated_items': 30})
          : (200, pageJson([alertJson()])));
      final c = AlertsController(h.planning);
      await c.reload();
      expect(h.adapter.requests.last.query['status'], 'open');
      expect(await c.evaluate(), isNull);
      expect(c.lastEvaluation.value!.resolved, 1);
      expect(h.adapter.requests.map((r) => r.path).toList(), ['/alerts', '/alerts:evaluate', '/alerts']);
    });

    test('status update patches the alert', () async {
      final h = Harness((o) async => o.method == 'PATCH'
          ? (200, alertJson(status: 'dismissed'))
          : (200, pageJson([])));
      final c = AlertsController(h.planning);
      await c.setAlertStatus(StockAlert.fromJson(alertJson()), AlertStatus.dismissed);
      final patch = h.adapter.requests.firstWhere((r) => r.method == 'PATCH');
      expect(patch.path, '/alerts/a1');
      expect(patch.body, {'status': 'dismissed'});
    });
  });

  group('ReplenishmentController', () {
    test('requests reorder-only items by default', () async {
      final h = Harness((o) async => (200, pageJson([replenishmentJson()])));
      final c = ReplenishmentController(h.planning, h.catalog);
      await c.reload();
      expect(h.adapter.requests.last.query['needs_reorder'], true);
      expect(c.items.single.recommendedQty, 60);
    });

    test('draft orders need a store', () async {
      final h = Harness((o) async => (200, pageJson([])));
      final c = ReplenishmentController(h.planning, h.catalog);
      final (result, error) = await c.createDraftOrders();
      expect(result, isNull);
      expect(error, 'Choose a store first');
    });

    test('draft orders report created and skipped', () async {
      final h = Harness((o) async => o.path == '/purchase-orders/from-recommendations'
          ? (201, {'created': [poJson(status: 'draft')..remove('items')], 'skipped': [
              {'product_id': 'p9', 'sku': 'NOSUP', 'reason': 'Product has no supplier.'},
            ]})
          : (200, pageJson([])));
      final c = ReplenishmentController(h.planning, h.catalog);
      c.storeId.value = 's1';
      final (result, error) = await c.createDraftOrders();
      expect(error, isNull);
      expect(result!.created.single.status, POStatus.draft);
      expect(result.skipped, ['NOSUP']);
    });
  });

  group('PODetailController receive', () {
    test('validates quantities before calling the API', () async {
      final h = Harness((o) async => (200, poJson()));
      final c = PODetailController(h.planning, 'po-1');
      expect(await c.receive({'item-1': ''}), 'Enter a quantity for at least one line');
      expect(await c.receive({'item-1': '-2'}), 'Quantities must be positive numbers');
      expect(h.adapter.requests, isEmpty);
    });

    test('sends only filled lines and shows server rejection', () async {
      final h = Harness((o) async => (
            422,
            errorJson('unprocessable', 'Cannot receive 12 - only 10 remaining on this line.'),
          ));
      final c = PODetailController(h.planning, 'po-1');
      final error = await c.receive({'item-1': '12', 'item-2': ' '}, note: 'truck');
      expect(error, 'Cannot receive 12 - only 10 remaining on this line.');
      final req = h.adapter.requests.single;
      expect(req.path, '/purchase-orders/po-1/receive');
      expect(req.body, {
        'lines': [{'item_id': 'item-1', 'quantity': '12'}],
        'note': 'truck',
      });
    });

    test('transition updates the order', () async {
      final h = Harness((o) async => (200, poJson(status: 'pending')));
      final c = PODetailController(h.planning, 'po-1');
      expect(await c.transition('submit'), isNull);
      expect(c.order.value!.status, POStatus.pending);
      expect(h.adapter.requests.single.path, '/purchase-orders/po-1/submit');
    });
  });

  group('POFormController', () {
    test('validates before saving and posts lines', () async {
      final h = Harness((o) async => (201, poJson(status: 'draft')));
      final c = POFormController(h.planning, h.catalog);
      expect(await c.save(), isNull);
      expect(c.formError.value, 'Choose a supplier');
      c.supplierId.value = 'sup-1';
      c.storeId.value = 's1';
      expect(await c.save(), isNull);
      expect(c.formError.value, 'Add at least one product');
      c.addProduct(_product);
      c.addProduct(_product);
      expect(c.formError.value, 'SKU-1 is already on this order');
      c.lines.single.quantity = '0';
      expect(await c.save(), isNull);
      expect(c.formError.value, contains('greater than zero'));
      c.lines.single.quantity = '12';
      final po = await c.save(reference: ' PO-77 ');
      expect(po, isNotNull);
      expect(h.adapter.requests.single.body, {
        'supplier_id': 'sup-1',
        'store_id': 's1',
        'reference': 'PO-77',
        'items': [{'product_id': 'p1', 'quantity_ordered': '12'}],
      });
    });
  });

  group('views', () {
    testWidgets('approve is only offered to admins', (tester) async {
      final h = Harness((o) async => (200, poJson(status: 'pending')));
      h.register(role: 'manager');
      Get.put(PODetailController(h.planning, 'po-1'));
      await tester.pumpWidget(GetMaterialApp(home: const PODetailView()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('po-approve')), findsNothing);
      expect(find.text('Waiting for an admin or owner to approve.'), findsOneWidget);
      expect(find.byKey(const Key('po-cancel')), findsOneWidget);
    });

    testWidgets('admin can approve; received order has no actions', (tester) async {
      final h = Harness((o) async => (200, poJson(status: 'pending')));
      h.register(role: 'admin');
      Get.put(PODetailController(h.planning, 'po-1'));
      await tester.pumpWidget(GetMaterialApp(home: const PODetailView()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('po-approve')), findsOneWidget);

      Get.reset();
      Get.testMode = true;
      final h2 = Harness((o) async => (200, poJson(status: 'received', received: 10)));
      h2.register(role: 'owner');
      Get.put(PODetailController(h2.planning, 'po-1'));
      await tester.pumpWidget(GetMaterialApp(key: UniqueKey(), home: const PODetailView()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('po-receive')), findsNothing);
      expect(find.byKey(const Key('po-cancel')), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('alerts list shows severity and hides actions for viewers', (tester) async {
      final h = Harness((o) async => (200, pageJson([alertJson()])));
      h.register(role: 'viewer');
      Get.put(AlertsController(h.planning));
      await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: AlertsView())));
      await tester.pumpAndSettle();
      expect(find.textContaining('Stockout risk - SKU-1 Widget'), findsOneWidget);
      expect(find.text('Critical'), findsOneWidget);
      expect(find.byKey(const Key('evaluate-alerts')), findsNothing);
      expect(find.byType(PopupMenuButton<AlertStatus>), findsNothing);
    });

    testWidgets('replenishment tile shows the recommendation and its inputs', (tester) async {
      final h = Harness((o) async => o.path == '/stores'
          ? (200, pageJson([]))
          : (200, pageJson([replenishmentJson()])));
      h.register(role: 'manager');
      Get.put(ReplenishmentController(h.planning, h.catalog));
      await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: ReplenishmentView())));
      await tester.pumpAndSettle();
      expect(find.text('Order 60'), findsOneWidget);
      expect(find.text('Acme Supply'), findsOneWidget);
      await tester.tap(find.text('SKU-1 Widget'));
      await tester.pumpAndSettle();
      expect(find.text('Forecast (lightgbm)'), findsOneWidget);
      expect(find.text('39.39'), findsOneWidget);
      expect(find.byKey(const Key('create-draft-pos')), findsOneWidget);
    });
  });
}
