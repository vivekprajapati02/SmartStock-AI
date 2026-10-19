// End-to-end contract test: runs the app's real repositories against a
// running backend. Skipped unless LIVE_API_URL is set, e.g.
//
//   LIVE_API_URL=http://localhost:8000 flutter test test/live
//
// The demo organisation must be seeded (python -m seed.generate).
@Tags(['live'])
library;

import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartstock/core/config/app_config.dart';
import 'package:smartstock/core/network/api_client.dart';
import 'package:smartstock/core/network/api_exception.dart';
import 'package:smartstock/core/storage/cache_store.dart';
import 'package:smartstock/core/storage/token_storage.dart';
import 'package:smartstock/data/models/catalog_models.dart';
import 'package:smartstock/data/models/inventory_models.dart';
import 'package:smartstock/data/repositories/analytics_repository.dart';
import 'package:smartstock/data/repositories/auth_repository.dart';
import 'package:smartstock/data/repositories/catalog_repository.dart';
import 'package:smartstock/data/repositories/inventory_repository.dart';

class _Client {
  _Client(String baseUrl) {
    config = AppConfig(apiBaseUrl: baseUrl);
    api = ApiClient(config: config, tokenStorage: tokens);
    auth = ApiAuthRepository(api, tokens);
    catalog = ApiCatalogRepository(api);
    inventory = ApiInventoryRepository(api, InMemoryCacheStore());
    analytics = ApiAnalyticsRepository(api, InMemoryCacheStore());
  }

  late final AppConfig config;
  final tokens = InMemoryTokenStorage();
  late final ApiClient api;
  late final AuthRepository auth;
  late final CatalogRepository catalog;
  late final InventoryRepository inventory;
  late final AnalyticsRepository analytics;
}

void main() {
  final baseUrl = Platform.environment['LIVE_API_URL'];
  final skip = baseUrl == null ? 'LIVE_API_URL not set' : null;

  group('live backend', skip: skip, () {
    late _Client c;

    setUp(() async {
      c = _Client(baseUrl!);
      await c.auth.login(
        organization: 'synthetic-demo',
        email: 'owner@synthetic-demo.com',
        password: 'demo-password-123',
      );
    });

    test('dashboard matches the raw API response exactly', () async {
      final parsed = (await c.analytics.getDashboard(trendDays: 30)).value;
      final raw = (await Dio().get<Map<String, dynamic>>(
        '${c.config.apiV1Url}/analytics/dashboard',
        queryParameters: {'trend_days': 30},
        options: Options(headers: {
          'Authorization': 'Bearer ${await c.tokens.readAccessToken()}',
        }),
      ))
          .data!;
      expect(parsed.inventoryValue, double.parse(raw['inventory_value'] as String));
      expect(parsed.skuCount, raw['sku_count']);
      expect(parsed.storeCount, raw['store_count']);
      expect(parsed.lowStockCount, raw['low_stock_count']);
      expect(parsed.stockoutCount, raw['stockout_count']);
      expect(parsed.pendingOrderCount, raw['pending_order_count']);
      expect(parsed.demandTrend, hasLength(30));
      expect(parsed.isDemo, isTrue);
    });

    test('movements update stock and oversell is rejected without change', () async {
      final page = (await c.inventory.listInventory(const InventoryQuery())).value;
      expect(page.items, isNotEmpty);
      final row = page.items.first;
      final before = row.quantityOnHand;

      await c.inventory.recordMovement(MovementInput(
        productId: row.productId,
        storeId: row.storeId,
        movementType: MovementType.stockIn,
        quantity: '5',
        reference: 'live-test',
      ));
      expect((await c.inventory.getInventory(row.id)).quantityOnHand, before + 5);

      await expectLater(
        c.inventory.recordMovement(MovementInput(
          productId: row.productId,
          storeId: row.storeId,
          movementType: MovementType.stockOut,
          quantity: '${(before + 1000).toInt()}',
        )),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 422)),
      );
      expect((await c.inventory.getInventory(row.id)).quantityOnHand, before + 5);

      await c.inventory.recordMovement(MovementInput(
        productId: row.productId,
        storeId: row.storeId,
        movementType: MovementType.adjust,
        quantity: '-5',
        note: 'live-test revert',
      ));
      expect((await c.inventory.getInventory(row.id)).quantityOnHand, before);

      final ledger = await c.inventory.listMovements(
          productId: row.productId, storeId: row.storeId, limit: 2);
      expect(ledger.items.first.movementType, MovementType.adjust);
      expect(ledger.items.first.quantity, -5);
    });

    test('expired access token is refreshed transparently', () async {
      final refresh = await c.tokens.readRefreshToken();
      await c.tokens.save(accessToken: 'garbage', refreshToken: refresh!);
      final user = await c.auth.restoreSession();
      expect(user!.email, 'owner@synthetic-demo.com');
      expect(await c.tokens.readAccessToken(), isNot('garbage'));
    });

    test('new organisation starts at zero and grows from real data', () async {
      final fresh = _Client(baseUrl!);
      final slug = 'live-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}';
      final user = await fresh.auth.register(
        organizationName: 'Live Test $slug',
        organizationSlug: slug,
        email: 'owner@$slug.com',
        password: 'password-123',
      );
      expect(user.canWrite, isTrue);

      final empty = (await fresh.analytics.getDashboard()).value;
      expect(empty.inventoryValue, 0);
      expect(empty.skuCount, 0);
      expect(empty.storeCount, 0);
      expect(empty.isDemo, isFalse);
      expect(empty.demandTrend.every((p) => p.quantity == 0), isTrue);

      final store = await fresh.catalog.createStore(name: 'HQ');
      final product = await fresh.catalog.createProduct(const ProductInput(
        sku: 'LIVE-1',
        name: 'Live product',
        unit: 'unit',
        unitCost: '2.00',
        unitPrice: '3.00',
        isActive: true,
      ));
      final rows = (await fresh.inventory.listInventory(const InventoryQuery())).value;
      expect(rows.items, hasLength(1));
      expect(rows.items.single.productId, product.id);
      expect(rows.items.single.storeId, store.id);
      expect(rows.items.single.quantityOnHand, 0);
      expect(rows.items.single.isStockout, isTrue);

      await fresh.inventory.recordMovement(MovementInput(
        productId: product.id,
        storeId: store.id,
        movementType: MovementType.stockIn,
        quantity: '10',
      ));
      final after = (await fresh.analytics.getDashboard()).value;
      expect(after.skuCount, 1);
      expect(after.storeCount, 1);
      expect(after.inventoryValue, 20);
      expect(after.stockoutCount, 0);

      // Cross-org access returns 404.
      await expectLater(
        c.inventory.getInventory(rows.items.single.id),
        throwsA(isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.notFound)),
      );

      // Duplicate SKU is a conflict.
      await expectLater(
        fresh.catalog.createProduct(const ProductInput(
          sku: 'LIVE-1',
          name: 'Dup',
          unit: 'unit',
          unitCost: '0',
          unitPrice: '0',
          isActive: true,
        )),
        throwsA(isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.conflict)),
      );
    });
  });
}
