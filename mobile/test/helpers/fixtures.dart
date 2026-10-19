// JSON shaped exactly like the FastAPI responses (Decimals as strings).

Map<String, dynamic> userJson({String role = 'owner'}) => {
      'id': '11111111-1111-1111-1111-111111111111',
      'org_id': '22222222-2222-2222-2222-222222222222',
      'email': 'owner@acme.com',
      'full_name': 'Ada Owner',
      'role': role,
      'is_active': true,
      'created_at': '2026-10-01T10:00:00Z',
    };

Map<String, dynamic> authJson({String access = 'access-1', String refresh = 'refresh-1'}) => {
      'user': userJson(),
      'tokens': {
        'access_token': access,
        'refresh_token': refresh,
        'token_type': 'bearer',
        'expires_in': 1800,
      },
    };

Map<String, dynamic> inventoryJson({
  String id = 'inv-1',
  String qty = '12.000',
  String reorder = '5.000',
  bool low = false,
  bool stockout = false,
  String name = 'Widget',
}) =>
    {
      'id': id,
      'org_id': 'org',
      'product_id': 'prod-$id',
      'store_id': 'store-1',
      'sku': 'SKU-$id',
      'product_name': name,
      'store_name': 'Main Store',
      'unit_cost': '2.50',
      'quantity_on_hand': qty,
      'reorder_point': reorder,
      'safety_stock': '1.000',
      'lead_time_days': 7,
      'inventory_value': '30.00',
      'is_low_stock': low,
      'is_stockout': stockout,
      'updated_at': '2026-10-18T09:30:00Z',
    };

Map<String, dynamic> pageJson(List<Map<String, dynamic>> items,
        {int? total, int limit = 50, int offset = 0}) =>
    {
      'items': items,
      'total': total ?? items.length,
      'limit': limit,
      'offset': offset,
    };

Map<String, dynamic> dashboardJson({
  String value = '12345.50',
  int skus = 15,
  int stores = 2,
  int low = 3,
  int stockout = 1,
  int pending = 0,
  bool demo = true,
  List<String> trend = const ['10.000', '0', '7.500'],
}) =>
    {
      'inventory_value': value,
      'sku_count': skus,
      'store_count': stores,
      'low_stock_count': low,
      'stockout_count': stockout,
      'pending_order_count': pending,
      'demand_trend': [
        for (var i = 0; i < trend.length; i++)
          {'sale_date': '2026-10-${(10 + i).toString().padLeft(2, '0')}', 'quantity': trend[i]},
      ],
      'is_demo': demo,
    };

Map<String, dynamic> errorJson(String code, String message,
        [List<Map<String, dynamic>>? details]) =>
    {
      'error': {
        'code': code,
        'message': message,
        'details': details,
        'request_id': 'req-123',
      },
    };

Map<String, dynamic> importJson({
  String id = 'imp-1',
  String status = 'partial',
  int total = 4,
  int valid = 2,
  int invalid = 1,
  int duplicate = 1,
  List<Map<String, dynamic>>? errors,
  bool truncated = false,
}) =>
    {
      'id': id,
      'org_id': 'org',
      'filename': 'sales.csv',
      'status': status,
      'total_rows': total,
      'valid_rows': valid,
      'invalid_rows': invalid,
      'duplicate_rows': duplicate,
      'error_count': invalid + duplicate,
      'created_at': '2026-10-19T10:00:00Z',
      'errors': errors ??
          [
            {'row': 2, 'column': 'sku', 'value': 'NOPE', 'message': 'Unknown SKU for this organisation.', 'kind': 'invalid'},
            {'row': 4, 'column': 'sale_date', 'value': '2026-10-01', 'message': 'Same SKU, store and date as row 3 in this file.', 'kind': 'duplicate'},
          ],
      'errors_truncated': truncated,
    };
