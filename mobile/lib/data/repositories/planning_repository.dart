import '../../core/network/api_client.dart';
import '../models/page_result.dart';
import '../models/planning_models.dart';

abstract class PlanningRepository {
  Future<PageResult<ReplenishmentItem>> replenishment({
    String? storeId,
    bool? needsReorder,
    int limit = 50,
    int offset = 0,
  });
  Future<int> applyReplenishment({String? storeId});

  Future<PageResult<StockAlert>> alerts({
    AlertStatus? status,
    String? alertType,
    int limit = 50,
    int offset = 0,
  });
  Future<EvaluateResult> evaluateAlerts();
  Future<StockAlert> updateAlert(String id, AlertStatus status);

  Future<PageResult<PurchaseOrder>> purchaseOrders({
    POStatus? status,
    int limit = 50,
    int offset = 0,
  });
  Future<PurchaseOrder> purchaseOrder(String id);
  Future<PurchaseOrder> createPurchaseOrder({
    required String supplierId,
    required String storeId,
    String? reference,
    required List<POLineInput> lines,
  });

  /// `submit`, `approve` or `cancel`.
  Future<PurchaseOrder> transition(String id, String action);
  Future<PurchaseOrder> receive(String id, Map<String, String> quantitiesByItem,
      {String? note});
  Future<FromRecommendationsResult> fromRecommendations(String storeId);
}

class ApiPlanningRepository implements PlanningRepository {
  ApiPlanningRepository(this._api);

  final ApiClient _api;

  @override
  Future<PageResult<ReplenishmentItem>> replenishment({
    String? storeId,
    bool? needsReorder,
    int limit = 50,
    int offset = 0,
  }) async =>
      PageResult.fromJson(
        await _api.get<Map<String, dynamic>>('/replenishment', query: {
          'store_id': storeId,
          'needs_reorder': needsReorder,
          'limit': limit,
          'offset': offset,
        }),
        ReplenishmentItem.fromJson,
      );

  @override
  Future<int> applyReplenishment({String? storeId}) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/replenishment/apply',
      data: {'store_id': ?storeId},
    );
    return json['updated'] as int? ?? 0;
  }

  @override
  Future<PageResult<StockAlert>> alerts({
    AlertStatus? status,
    String? alertType,
    int limit = 50,
    int offset = 0,
  }) async =>
      PageResult.fromJson(
        await _api.get<Map<String, dynamic>>('/alerts', query: {
          'status': status?.name,
          'alert_type': alertType,
          'limit': limit,
          'offset': offset,
        }),
        StockAlert.fromJson,
      );

  @override
  Future<EvaluateResult> evaluateAlerts() async => EvaluateResult.fromJson(
      await _api.post<Map<String, dynamic>>('/alerts:evaluate', data: {}));

  @override
  Future<StockAlert> updateAlert(String id, AlertStatus status) async =>
      StockAlert.fromJson(await _api.patch<Map<String, dynamic>>('/alerts/$id',
          data: {'status': status.name}));

  @override
  Future<PageResult<PurchaseOrder>> purchaseOrders({
    POStatus? status,
    int limit = 50,
    int offset = 0,
  }) async =>
      PageResult.fromJson(
        await _api.get<Map<String, dynamic>>('/purchase-orders', query: {
          'status': status?.name,
          'limit': limit,
          'offset': offset,
        }),
        PurchaseOrder.fromJson,
      );

  @override
  Future<PurchaseOrder> purchaseOrder(String id) async => PurchaseOrder.fromJson(
      await _api.get<Map<String, dynamic>>('/purchase-orders/$id'));

  @override
  Future<PurchaseOrder> createPurchaseOrder({
    required String supplierId,
    required String storeId,
    String? reference,
    required List<POLineInput> lines,
  }) async {
    final ref = reference?.trim();
    return PurchaseOrder.fromJson(
        await _api.post<Map<String, dynamic>>('/purchase-orders', data: {
      'supplier_id': supplierId,
      'store_id': storeId,
      if (ref != null && ref.isNotEmpty) 'reference': ref,
      'items': [for (final l in lines) l.toJson()],
    }));
  }

  @override
  Future<PurchaseOrder> transition(String id, String action) async =>
      PurchaseOrder.fromJson(
          await _api.post<Map<String, dynamic>>('/purchase-orders/$id/$action'));

  @override
  Future<PurchaseOrder> receive(
    String id,
    Map<String, String> quantitiesByItem, {
    String? note,
  }) async =>
      PurchaseOrder.fromJson(
          await _api.post<Map<String, dynamic>>('/purchase-orders/$id/receive', data: {
        'lines': [
          for (final e in quantitiesByItem.entries) {'item_id': e.key, 'quantity': e.value},
        ],
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      }));

  @override
  Future<FromRecommendationsResult> fromRecommendations(String storeId) async =>
      FromRecommendationsResult.fromJson(await _api.post<Map<String, dynamic>>(
        '/purchase-orders/from-recommendations',
        data: {'store_id': storeId},
      ));
}
