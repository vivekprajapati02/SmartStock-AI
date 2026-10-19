import 'package:flutter_test/flutter_test.dart';
import 'package:smartstock/data/models/auth_models.dart';
import 'package:smartstock/data/models/catalog_models.dart';
import 'package:smartstock/data/models/dashboard_models.dart';
import 'package:smartstock/data/models/inventory_models.dart';
import 'package:smartstock/data/models/page_result.dart';

import '../helpers/fixtures.dart';

void main() {
  test('AuthResponse parses user and tokens', () {
    final r = AuthResponse.fromJson(authJson());
    expect(r.user.email, 'owner@acme.com');
    expect(r.user.role, UserRole.owner);
    expect(r.user.canWrite, isTrue);
    expect(r.tokens.accessToken, 'access-1');
    expect(r.tokens.expiresIn, 1800);
  });

  test('role ranks gate writes at manager', () {
    expect(UserRole.parse('viewer').atLeast(UserRole.manager), isFalse);
    expect(UserRole.parse('manager').atLeast(UserRole.manager), isTrue);
    expect(UserRole.parse('admin').atLeast(UserRole.manager), isTrue);
    expect(UserRole.parse('unknown'), UserRole.viewer);
  });

  test('InventoryItem parses decimal strings', () {
    final item = InventoryItem.fromJson(
        inventoryJson(qty: '3.500', reorder: '5.000', low: true));
    expect(item.quantityOnHand, 3.5);
    expect(item.reorderPoint, 5);
    expect(item.unitCost, 2.5);
    expect(item.inventoryValue, 30);
    expect(item.isLowStock, isTrue);
    expect(item.updatedAt, DateTime.utc(2026, 10, 18, 9, 30));
  });

  test('PageResult parses envelope and hasMore', () {
    final page = PageResult.fromJson(
      pageJson([inventoryJson(id: 'a'), inventoryJson(id: 'b')], total: 5),
      InventoryItem.fromJson,
    );
    expect(page.items.map((e) => e.id), ['a', 'b']);
    expect(page.total, 5);
    expect(page.hasMore, isTrue);
  });

  test('Dashboard parses numbers from strings and keeps zeros', () {
    final d = Dashboard.fromJson(dashboardJson(
      value: '0',
      skus: 0,
      stores: 0,
      low: 0,
      stockout: 0,
      demo: false,
      trend: ['0', '0'],
    ));
    expect(d.inventoryValue, 0);
    expect(d.isEmpty, isTrue);
    expect(d.isDemo, isFalse);
    expect(d.demandTrend, hasLength(2));
    expect(d.demandTrend.first.date, DateTime(2026, 10, 10));
  });

  test('Product parses nullable relations and decimals', () {
    final p = Product.fromJson({
      'id': 'p1',
      'org_id': 'o',
      'sku': 'SKU-1',
      'name': 'Thing',
      'category_id': null,
      'supplier_id': 's1',
      'unit': 'box',
      'unit_cost': '1.25',
      'unit_price': '3.00',
      'is_active': false,
      'created_at': '2026-10-01T00:00:00Z',
    });
    expect(p.categoryId, isNull);
    expect(p.supplierId, 's1');
    expect(p.unitCost, 1.25);
    expect(p.unitPrice, 3);
    expect(p.isActive, isFalse);
  });

  test('MovementInput serialises api enum values and omits blanks', () {
    const input = MovementInput(
      productId: 'p',
      storeId: 's',
      movementType: MovementType.stockOut,
      quantity: '2',
      reference: '',
    );
    expect(input.toJson(), {
      'product_id': 'p',
      'store_id': 's',
      'movement_type': 'out',
      'quantity': '2',
    });
    expect(MovementType.parse('adjust'), MovementType.adjust);
  });
}
