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

Map<String, dynamic> runJson(String name, {double wape = 0.2, bool selected = false, bool baseline = true, String kind = 'backtest'}) => {
      'id': 'run-$name',
      'model_name': name,
      'kind': kind,
      'horizon': 30,
      'group_id': 'g1',
      'selected': selected,
      'is_baseline': baseline,
      'metrics': {'mae': 1.5, 'rmse': 2.25, 'wape': wape, 'bias': -0.031, 'n_points': 2700},
      'params': {'kind': kind},
      'dataset_start': '2025-09-15',
      'dataset_end': '2026-10-19',
      'trained_at': '2026-10-19T10:00:00Z',
    };

Map<String, dynamic> comparisonJson({bool empty = false, bool demo = true, String selected = 'lightgbm'}) => empty
    ? {'horizon': 30, 'models': [], 'n_series': 0, 'is_demo': demo, 'cutoffs': [], 'forecast_vs_actual': []}
    : {
        'horizon': 30,
        'group_id': 'g1',
        'run_at': '2026-10-19T10:00:00Z',
        'dataset_start': '2025-09-15',
        'dataset_end': '2026-10-19',
        'folds': 3,
        'cutoffs': ['2026-07-21', '2026-08-20', '2026-09-19'],
        'n_series': 30,
        'models': [
          runJson('lightgbm', wape: 0.156, selected: selected == 'lightgbm', baseline: false),
          runJson('moving_average', wape: 0.163, selected: selected == 'moving_average'),
          runJson('seasonal_naive', wape: 0.222),
        ],
        'selected_model': selected,
        'best_baseline': 'moving_average',
        'wape_improvement_vs_baseline': selected == 'lightgbm' ? 0.0429 : 0.0,
        'forecast_vs_actual': [
          {'day': '2026-10-18', 'actual': 700.0, 'predicted': 690.5},
          {'day': '2026-10-19', 'actual': 650.0, 'predicted': 660.0},
        ],
        'is_demo': demo,
      };

Map<String, dynamic> alertJson({String id = 'a1', String type = 'stockout_risk', String severity = 'critical', String status = 'open'}) => {
      'id': id, 'product_id': 'p1', 'store_id': 's1', 'sku': 'SKU-1', 'product_name': 'Widget',
      'store_name': 'Main', 'alert_type': type, 'severity': severity, 'status': status,
      'message': 'On hand 0 + on order 0 is below expected demand of 35 over the 7-day lead time.',
      'created_at': '2026-10-19T10:00:00Z', 'updated_at': '2026-10-19T10:00:00Z',
    };

Map<String, dynamic> replenishmentJson({bool reorder = true, String source = 'forecast'}) => {
      'inventory_id': 'inv-1', 'product_id': 'p1', 'store_id': 's1', 'sku': 'SKU-1',
      'product_name': 'Widget', 'store_name': 'Main', 'supplier_id': 'sup-1', 'supplier_name': 'Acme Supply',
      'on_hand': 10.0, 'on_order': 5.0, 'inventory_position': 15.0, 'lead_time_days': 7, 'review_days': 7,
      'avg_daily_demand': 5.0, 'demand_std': 1.009, 'demand_source': source,
      'forecast_model': source == 'forecast' ? 'lightgbm' : null,
      'lead_time_demand': 35.0, 'safety_stock': 4.391, 'reorder_point': 39.391, 'target_stock': 74.391,
      'recommended_qty': reorder ? 60.0 : 0.0, 'days_of_cover': 2.0, 'needs_reorder': reorder,
      'current_reorder_point': 0.0, 'current_safety_stock': 0.0,
    };

Map<String, dynamic> poJson({String status = 'approved', double received = 0}) => {
      'id': 'po-12345678-aaaa', 'org_id': 'o', 'supplier_id': 'sup-1', 'supplier_name': 'Acme Supply',
      'store_id': 's1', 'store_name': 'Main', 'status': status, 'reference': 'PO-1001',
      'expected_date': null, 'created_by': 'u1', 'approved_by': status == 'draft' ? null : 'u1',
      'line_count': 1, 'total_ordered': '10.000', 'total_received': '$received',
      'estimated_cost': '25.00', 'created_at': '2026-10-19T10:00:00Z', 'updated_at': '2026-10-19T10:00:00Z',
      'items': [
        {'id': 'item-1', 'product_id': 'p1', 'sku': 'SKU-1', 'product_name': 'Widget', 'unit_cost': '2.50',
         'quantity_ordered': '10.000', 'quantity_received': '$received', 'quantity_remaining': '${10 - received}'},
      ],
    };
