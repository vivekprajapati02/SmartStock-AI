import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:smartstock/modules/auth/auth_controller.dart';
import 'package:smartstock/modules/auth/auth_views.dart';
import 'package:smartstock/modules/dashboard/dashboard_controller.dart';
import 'package:smartstock/modules/dashboard/dashboard_view.dart';
import 'package:smartstock/modules/inventory/inventory_controller.dart';
import 'package:smartstock/modules/inventory/inventory_view.dart';
import 'package:smartstock/modules/shell/home_view.dart';
import 'package:smartstock/modules/movements/movements_controller.dart';
import 'package:smartstock/modules/catalog/catalog_controllers.dart';
import 'package:smartstock/widgets/async_state_view.dart';

import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

Widget _app(Widget child) =>
    GetMaterialApp(home: Scaffold(body: child));

void main() {
  setUp(() {
    Get.reset();
    Get.testMode = true;
  });

  group('AsyncStateView', () {
    Widget view(LoadStatus status, {DateTime? cachedAt}) => MaterialApp(
          home: Scaffold(
            body: AsyncStateView(
              status: status,
              errorMessage: 'Server said no',
              onRetry: () {},
              cachedAt: cachedAt,
              emptyTitle: 'Nothing',
              builder: (_) => const Text('DATA'),
            ),
          ),
        );

    testWidgets('renders each state', (tester) async {
      await tester.pumpWidget(view(LoadStatus.loading));
      expect(find.byKey(const Key('async-loading')), findsOneWidget);

      await tester.pumpWidget(view(LoadStatus.error));
      expect(find.byKey(const Key('async-error')), findsOneWidget);
      expect(find.text('Server said no'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.pumpWidget(view(LoadStatus.offline));
      expect(find.byKey(const Key('async-offline')), findsOneWidget);

      await tester.pumpWidget(view(LoadStatus.empty));
      expect(find.text('Nothing'), findsOneWidget);

      await tester.pumpWidget(view(LoadStatus.data));
      expect(find.text('DATA'), findsOneWidget);
      expect(find.byKey(const Key('async-cached-banner')), findsNothing);

      await tester.pumpWidget(view(LoadStatus.data, cachedAt: DateTime(2026, 10, 1)));
      expect(find.text('DATA'), findsOneWidget);
      expect(find.byKey(const Key('async-cached-banner')), findsOneWidget);
    });
  });

  testWidgets('login form validates before calling the API', (tester) async {
    final h = Harness((o) async => (200, authJson()));
    Get.put(AuthController(h.auth, h.session));
    await tester.pumpWidget(GetMaterialApp(home: const LoginView()));

    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    expect(find.text('Organisation is required'), findsOneWidget);
    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login-email')), 'not-an-email');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(h.adapter.requests, isEmpty);
  });

  testWidgets('login shows server rejection', (tester) async {
    final h = Harness(
        (o) async => (401, errorJson('unauthenticated', 'Invalid credentials')));
    Get.put(AuthController(h.auth, h.session));
    await tester.pumpWidget(GetMaterialApp(home: const LoginView()));

    await tester.enterText(find.byKey(const Key('login-org')), 'acme');
    await tester.enterText(find.byKey(const Key('login-email')), 'a@acme.com');
    await tester.enterText(find.byKey(const Key('login-password')), 'password-1');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth-form-error')), findsOneWidget);
    expect(find.text('Organisation, email or password is incorrect.'), findsOneWidget);
  });

  testWidgets('dashboard renders KPI values from the API', (tester) async {
    final h = Harness((o) async => (200, dashboardJson(
          value: '12345.50',
          skus: 15,
          stores: 2,
          low: 3,
          stockout: 1,
          pending: 0,
        )));
    h.register();
    Get.put(DashboardController(h.analytics));

    await tester.pumpWidget(_app(const DashboardView()));
    await tester.pumpAndSettle();

    String kpi(String key) => (tester
            .widget<Text>(find.descendant(
              of: find.byKey(Key(key)),
              matching: find.byType(Text),
            ).last))
        .data!;
    expect(kpi('kpi-inventory-value'), r'$12,345.50');
    expect(kpi('kpi-sku-count'), '15');
    expect(kpi('kpi-store-count'), '2');
    expect(kpi('kpi-low-stock'), '3');
    expect(kpi('kpi-stockout'), '1');
    expect(kpi('kpi-pending-orders'), '0');
    expect(find.byKey(const Key('demo-badge')), findsOneWidget);
    expect(find.textContaining('total 17.50'), findsOneWidget);
  });

  testWidgets('empty organisation shows zeros and no demo badge', (tester) async {
    final h = Harness((o) async => (200, dashboardJson(
          value: '0',
          skus: 0,
          stores: 0,
          low: 0,
          stockout: 0,
          demo: false,
          trend: ['0', '0', '0'],
        )));
    h.register();
    Get.put(DashboardController(h.analytics));

    await tester.pumpWidget(_app(const DashboardView()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('demo-badge')), findsNothing);
    expect(find.byKey(const Key('dashboard-empty-hint')), findsOneWidget);
    expect(find.byKey(const Key('trend-empty')), findsOneWidget);
    expect(find.text(r'$0.00'), findsOneWidget);
  });

  testWidgets('inventory list shows rows and stock badges', (tester) async {
    final h = Harness((o) async {
      if (o.path == '/stores') {
        return (200, pageJson([
          {'id': 'store-1', 'org_id': 'o', 'name': 'Main Store', 'location': null,
           'created_at': '2026-10-01T00:00:00Z'},
        ]));
      }
      return (200, pageJson([
        inventoryJson(id: 'a', name: 'Apples', qty: '3.000', low: true),
        inventoryJson(id: 'b', name: 'Bananas', qty: '0.000', stockout: true),
        inventoryJson(id: 'c', name: 'Cherries', qty: '40.000'),
      ]));
    });
    h.register();
    Get.put(InventoryController(h.inventory, h.catalog));

    await tester.pumpWidget(_app(const InventoryView()));
    await tester.pumpAndSettle();

    expect(find.text('Apples'), findsOneWidget);
    expect(find.text('Bananas'), findsOneWidget);
    expect(find.text('Cherries'), findsOneWidget);
    expect(find.text('Low stock'), findsOneWidget);
    expect(find.text('Out of stock'), findsOneWidget);
  });

  testWidgets('viewer does not see write actions', (tester) async {
    final h = Harness((o) async => (200, switch (o.path) {
          '/analytics/dashboard' => dashboardJson(),
          '/inventory' => pageJson([inventoryJson()]),
          _ => pageJson([]),
        }));
    h.register(role: 'viewer');
    Get.put(HomeController());
    Get.put(DashboardController(h.analytics));
    Get.put(InventoryController(h.inventory, h.catalog));
    Get.put(MovementsController(h.inventory, h.catalog));
    Get.put(ProductsController(h.catalog));

    await tester.pumpWidget(GetMaterialApp(home: const HomeView()));
    Get.find<HomeController>().tab.value = 1;
    await tester.pumpAndSettle();
    expect(find.text('Widget'), findsOneWidget);
    expect(find.byKey(const Key('home-record-movement')), findsNothing);
  });

  testWidgets('manager sees record movement action', (tester) async {
    final h = Harness((o) async =>
        (200, o.path == '/inventory' ? pageJson([inventoryJson()]) : pageJson([])));
    h.register(role: 'manager');
    Get.put(HomeController()..tab.value = 1);
    Get.put(InventoryController(h.inventory, h.catalog));

    await tester.pumpWidget(GetMaterialApp(home: const HomeView()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-record-movement')), findsOneWidget);
  });
}
