import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:smartstock/data/models/inventory_models.dart';
import 'package:smartstock/modules/auth/auth_controller.dart';
import 'package:smartstock/modules/dashboard/dashboard_controller.dart';
import 'package:smartstock/modules/inventory/inventory_controller.dart';
import 'package:smartstock/modules/movements/movements_controller.dart';
import 'package:smartstock/widgets/async_state_view.dart';

import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

void main() {
  setUp(() {
    Get.reset();
    Get.testMode = true;
  });

  group('DashboardController', () {
    test('loads server values unchanged', () async {
      final h = Harness((o) async => (200, dashboardJson(low: 4, pending: 2)));
      final c = DashboardController(h.analytics);
      await c.load();
      expect(c.status.value, LoadStatus.data);
      expect(c.dashboard.value!.lowStockCount, 4);
      expect(c.dashboard.value!.pendingOrderCount, 2);
      expect(c.dashboard.value!.inventoryValue, 12345.5);
      expect(c.cachedAt.value, isNull);
      expect(h.adapter.requests.single.path, '/analytics/dashboard');
    });

    test('passes trend_days and reloads on change', () async {
      final h = Harness((o) async => (200, dashboardJson()));
      final c = DashboardController(h.analytics);
      await c.load();
      await c.setTrendDays(90);
      expect(h.adapter.requests.length, 2);
      expect(c.trendDays.value, 90);
    });

    test('server error shows error state', () async {
      final h = Harness((o) async => (500, errorJson('internal_error', 'Boom')));
      final c = DashboardController(h.analytics);
      await c.load();
      expect(c.status.value, LoadStatus.error);
      expect(c.error.value, 'Boom');
    });

    test('offline without cache shows offline state', () async {
      final h = Harness((o) async => (200, dashboardJson()));
      h.adapter.offline = true;
      final c = DashboardController(h.analytics);
      await c.load();
      expect(c.status.value, LoadStatus.offline);
    });

    test('offline with cache shows last saved data flagged as cached', () async {
      final h = Harness((o) async => (200, dashboardJson(skus: 9)));
      final first = DashboardController(h.analytics);
      await first.load();

      h.adapter.offline = true;
      final c = DashboardController(h.analytics);
      await c.load();
      expect(c.status.value, LoadStatus.data);
      expect(c.dashboard.value!.skuCount, 9);
      expect(c.cachedAt.value, isNotNull);
    });
  });

  group('InventoryController', () {
    test('paginates with offset and stops at total', () async {
      final h = Harness((o) async {
        if (o.path == '/stores') return (200, pageJson([]));
        final offset = o.queryParameters['offset'] as int;
        final items = [
          for (var i = offset; i < (offset + 2).clamp(0, 3); i++)
            inventoryJson(id: 'i$i'),
        ];
        return (200, pageJson(items, total: 3, limit: 2, offset: offset));
      });
      // Small pages to exercise loadMore.
      final paged = _SmallPageInventory(h);
      await paged.reload();
      expect(paged.items.map((e) => e.id), ['i0', 'i1']);
      expect(paged.hasMore, isTrue);
      await paged.loadMore();
      expect(paged.items.map((e) => e.id), ['i0', 'i1', 'i2']);
      expect(paged.hasMore, isFalse);
      expect(h.adapter.requests.map((r) => r.query['offset']), [0, 2]);
    });

    test('sends filters as query parameters', () async {
      final h = Harness((o) async => (200, pageJson([inventoryJson(low: true)])));
      final c = InventoryController(h.inventory, h.catalog);
      c.storeId.value = 'store-9';
      c.lowStockOnly.value = true;
      c.search.value = '  wid ';
      await c.reload();
      final q = h.adapter.requests.last;
      expect(q.path, '/inventory');
      expect(q.query['store_id'], 'store-9');
      expect(q.query['low_stock'], true);
      expect(q.query['search'], 'wid');
      expect(q.query['offset'], 0);
      expect(c.items.single.isLowStock, isTrue);
    });

    test('empty result is the empty state', () async {
      final h = Harness((o) async => (200, pageJson([])));
      final c = InventoryController(h.inventory, h.catalog);
      await c.reload();
      expect(c.status.value, LoadStatus.empty);
    });
  });

  group('Movement form', () {
    test('quantity validation mirrors the backend', () {
      expect(validateMovementQuantity(MovementType.stockIn, ''), isNotNull);
      expect(validateMovementQuantity(MovementType.stockIn, 'abc'), isNotNull);
      expect(validateMovementQuantity(MovementType.stockIn, '0'), isNotNull);
      expect(validateMovementQuantity(MovementType.stockOut, '-1'), isNotNull);
      expect(validateMovementQuantity(MovementType.stockOut, '2.5'), isNull);
      expect(validateMovementQuantity(MovementType.adjust, '0'), isNotNull);
      expect(validateMovementQuantity(MovementType.adjust, '-3'), isNull);
    });

    test('requires product and store before calling the API', () async {
      final h = Harness((o) async => (200, pageJson([])));
      final c = MovementFormController(h.inventory, h.catalog, const MovementFormArgs());
      c.onInit();
      expect(await c.submit(quantity: '1'), isNull);
      expect(c.formError.value, 'Choose a product');
      expect(h.adapter.requests, isEmpty);
    });

    test('shows the server message when stock would go negative', () async {
      final h = Harness((o) async => (
            422,
            errorJson('unprocessable', 'Insufficient stock: 2 on hand, 5 requested.'),
          ));
      final c = MovementFormController(
        h.inventory,
        h.catalog,
        const MovementFormArgs(productId: 'p1', storeId: 's1'),
      );
      c.onInit();
      c.type.value = MovementType.stockOut;
      final result = await c.submit(quantity: '5');
      expect(result, isNull);
      expect(c.formError.value, 'Insufficient stock: 2 on hand, 5 requested.');
      final body = h.adapter.requests.single.body as Map<String, dynamic>;
      expect(body, {
        'product_id': 'p1',
        'store_id': 's1',
        'movement_type': 'out',
        'quantity': '5',
      });
    });

    test('returns the created movement on success', () async {
      final h = Harness((o) async => (201, {
            'id': 'm1',
            'org_id': 'o',
            'product_id': 'p1',
            'store_id': 's1',
            'sku': 'SKU-1',
            'product_name': 'Widget',
            'store_name': 'Main',
            'movement_type': 'adjust',
            'quantity': '-3.000',
            'reference': null,
            'note': 'count',
            'occurred_at': '2026-10-19T08:00:00Z',
          }));
      final c = MovementFormController(
        h.inventory,
        h.catalog,
        const MovementFormArgs(productId: 'p1', storeId: 's1'),
      );
      c.onInit();
      c.type.value = MovementType.adjust;
      final m = await c.submit(quantity: '-3', note: 'count');
      expect(m, isNotNull);
      expect(m!.quantity, -3);
      expect(c.formError.value, isNull);
    });
  });

  group('AuthController', () {
    test('login stores tokens and sets the session user', () async {
      final h = Harness((o) async => (200, authJson(access: 'a2', refresh: 'r2')));
      h.tokens.accessToken = null;
      final c = AuthController(h.auth, h.session);
      final ok = await c.login(
          organization: 'acme', email: 'owner@acme.com', password: 'password-1');
      expect(ok, isTrue);
      expect(h.tokens.accessToken, 'a2');
      expect(h.session.user.value!.email, 'owner@acme.com');
      final body = h.adapter.requests.single.body as Map<String, dynamic>;
      expect(body['organization'], 'acme');
    });

    test('invalid credentials show a friendly error', () async {
      final h = Harness(
          (o) async => (401, errorJson('unauthenticated', 'Invalid credentials')));
      final c = AuthController(h.auth, h.session);
      final ok = await c.login(
          organization: 'acme', email: 'owner@acme.com', password: 'wrong-pass');
      expect(ok, isFalse);
      expect(c.formError.value, 'Organisation, email or password is incorrect.');
      expect(h.session.user.value, isNull);
    });

    test('register maps server field errors', () async {
      final h = Harness((o) async => (
            422,
            errorJson('validation_error', 'The request payload failed validation.', [
              {'field': 'body.password', 'message': 'Password must be at least 8 characters long.'},
            ]),
          ));
      final c = AuthController(h.auth, h.session);
      await c.register(
          organizationName: 'Acme', email: 'a@acme.com', password: 'short');
      expect(c.fieldErrors['password'], 'Password must be at least 8 characters long.');
    });
  });
}

class _SmallPageInventory extends InventoryController {
  _SmallPageInventory(Harness h) : super(h.inventory, h.catalog);

  @override
  int get pageSize => 2;
}
