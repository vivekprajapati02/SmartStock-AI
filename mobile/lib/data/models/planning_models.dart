import '../../core/utils/parse.dart';

// ---------------------------------------------------------------- replenishment

class ReplenishmentItem {
  const ReplenishmentItem({
    required this.inventoryId,
    required this.productId,
    required this.storeId,
    required this.sku,
    required this.productName,
    required this.storeName,
    this.supplierId,
    this.supplierName,
    required this.onHand,
    required this.onOrder,
    required this.inventoryPosition,
    required this.leadTimeDays,
    required this.avgDailyDemand,
    required this.demandStd,
    required this.demandSource,
    this.forecastModel,
    required this.leadTimeDemand,
    required this.safetyStock,
    required this.reorderPoint,
    required this.targetStock,
    required this.recommendedQty,
    this.daysOfCover,
    required this.needsReorder,
    required this.currentReorderPoint,
    required this.currentSafetyStock,
  });

  factory ReplenishmentItem.fromJson(Map<String, dynamic> j) => ReplenishmentItem(
        inventoryId: j['inventory_id'] as String,
        productId: j['product_id'] as String,
        storeId: j['store_id'] as String,
        sku: j['sku'] as String,
        productName: j['product_name'] as String,
        storeName: j['store_name'] as String,
        supplierId: j['supplier_id'] as String?,
        supplierName: j['supplier_name'] as String?,
        onHand: parseDouble(j['on_hand']),
        onOrder: parseDouble(j['on_order']),
        inventoryPosition: parseDouble(j['inventory_position']),
        leadTimeDays: parseInt(j['lead_time_days']),
        avgDailyDemand: parseDouble(j['avg_daily_demand']),
        demandStd: parseDouble(j['demand_std']),
        demandSource: j['demand_source'] as String? ?? 'none',
        forecastModel: j['forecast_model'] as String?,
        leadTimeDemand: parseDouble(j['lead_time_demand']),
        safetyStock: parseDouble(j['safety_stock']),
        reorderPoint: parseDouble(j['reorder_point']),
        targetStock: parseDouble(j['target_stock']),
        recommendedQty: parseDouble(j['recommended_qty']),
        daysOfCover: parseDoubleOrNull(j['days_of_cover']),
        needsReorder: j['needs_reorder'] as bool? ?? false,
        currentReorderPoint: parseDouble(j['current_reorder_point']),
        currentSafetyStock: parseDouble(j['current_safety_stock']),
      );

  final String inventoryId;
  final String productId;
  final String storeId;
  final String sku;
  final String productName;
  final String storeName;
  final String? supplierId;
  final String? supplierName;
  final double onHand;
  final double onOrder;
  final double inventoryPosition;
  final int leadTimeDays;
  final double avgDailyDemand;
  final double demandStd;

  /// `forecast`, `history` or `none`.
  final String demandSource;
  final String? forecastModel;
  final double leadTimeDemand;
  final double safetyStock;
  final double reorderPoint;
  final double targetStock;
  final double recommendedQty;
  final double? daysOfCover;
  final bool needsReorder;
  final double currentReorderPoint;
  final double currentSafetyStock;
}

// ---------------------------------------------------------------- alerts

enum AlertSeverity { critical, high, medium, low }

enum AlertStatus { open, acknowledged, resolved, dismissed }

String alertTypeLabel(String type) => switch (type) {
      'low_stock' => 'Low stock',
      'stockout_risk' => 'Stockout risk',
      'overstock' => 'Overstock',
      'slow_moving' => 'Slow moving',
      _ => type,
    };

class StockAlert {
  const StockAlert({
    required this.id,
    required this.productId,
    required this.storeId,
    this.sku,
    this.productName,
    this.storeName,
    required this.alertType,
    required this.severity,
    required this.status,
    required this.message,
    required this.createdAt,
    required this.updatedAt,
  });

  factory StockAlert.fromJson(Map<String, dynamic> j) => StockAlert(
        id: j['id'] as String,
        productId: j['product_id'] as String,
        storeId: j['store_id'] as String,
        sku: j['sku'] as String?,
        productName: j['product_name'] as String?,
        storeName: j['store_name'] as String?,
        alertType: j['alert_type'] as String,
        severity: AlertSeverity.values.firstWhere((s) => s.name == j['severity'],
            orElse: () => AlertSeverity.low),
        status: AlertStatus.values.firstWhere((s) => s.name == j['status'],
            orElse: () => AlertStatus.open),
        message: j['message'] as String? ?? '',
        createdAt: parseDateTime(j['created_at']),
        updatedAt: parseDateTime(j['updated_at']),
      );

  final String id;
  final String productId;
  final String storeId;
  final String? sku;
  final String? productName;
  final String? storeName;
  final String alertType;
  final AlertSeverity severity;
  final AlertStatus status;
  final String message;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class EvaluateResult {
  const EvaluateResult({
    required this.created,
    required this.updated,
    required this.resolved,
    required this.openTotal,
  });

  factory EvaluateResult.fromJson(Map<String, dynamic> j) => EvaluateResult(
        created: parseInt(j['created']),
        updated: parseInt(j['updated']),
        resolved: parseInt(j['resolved']),
        openTotal: parseInt(j['open_total']),
      );

  final int created;
  final int updated;
  final int resolved;
  final int openTotal;
}

// ---------------------------------------------------------------- purchase orders

enum POStatus {
  draft('Draft'),
  pending('Pending approval'),
  approved('Approved'),
  partial('Partially received'),
  received('Received'),
  cancelled('Cancelled');

  const POStatus(this.label);

  final String label;

  static POStatus parse(String? v) =>
      POStatus.values.firstWhere((s) => s.name == v, orElse: () => POStatus.draft);
}

class POItem {
  const POItem({
    required this.id,
    required this.productId,
    this.sku,
    this.productName,
    this.unitCost,
    required this.quantityOrdered,
    required this.quantityReceived,
    required this.quantityRemaining,
  });

  factory POItem.fromJson(Map<String, dynamic> j) => POItem(
        id: j['id'] as String,
        productId: j['product_id'] as String,
        sku: j['sku'] as String?,
        productName: j['product_name'] as String?,
        unitCost: parseDoubleOrNull(j['unit_cost']),
        quantityOrdered: parseDouble(j['quantity_ordered']),
        quantityReceived: parseDouble(j['quantity_received']),
        quantityRemaining: parseDouble(j['quantity_remaining']),
      );

  final String id;
  final String productId;
  final String? sku;
  final String? productName;
  final double? unitCost;
  final double quantityOrdered;
  final double quantityReceived;
  final double quantityRemaining;
}

class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.supplierId,
    this.supplierName,
    required this.storeId,
    this.storeName,
    required this.status,
    this.reference,
    this.expectedDate,
    this.approvedBy,
    required this.lineCount,
    required this.totalOrdered,
    required this.totalReceived,
    required this.estimatedCost,
    required this.createdAt,
    this.items = const [],
  });

  factory PurchaseOrder.fromJson(Map<String, dynamic> j) => PurchaseOrder(
        id: j['id'] as String,
        supplierId: j['supplier_id'] as String,
        supplierName: j['supplier_name'] as String?,
        storeId: j['store_id'] as String,
        storeName: j['store_name'] as String?,
        status: POStatus.parse(j['status'] as String?),
        reference: j['reference'] as String?,
        expectedDate: j['expected_date'] == null ? null : parseDateTime(j['expected_date']),
        approvedBy: j['approved_by'] as String?,
        lineCount: parseInt(j['line_count']),
        totalOrdered: parseDouble(j['total_ordered']),
        totalReceived: parseDouble(j['total_received']),
        estimatedCost: parseDouble(j['estimated_cost']),
        createdAt: parseDateTime(j['created_at']),
        items: (j['items'] as List? ?? const [])
            .map((e) => POItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String id;
  final String supplierId;
  final String? supplierName;
  final String storeId;
  final String? storeName;
  final POStatus status;
  final String? reference;
  final DateTime? expectedDate;
  final String? approvedBy;
  final int lineCount;
  final double totalOrdered;
  final double totalReceived;
  final double estimatedCost;
  final DateTime createdAt;
  final List<POItem> items;

  String get displayRef => reference ?? 'PO-${id.substring(0, 8)}';
}

class POLineInput {
  const POLineInput(this.productId, this.quantity);

  final String productId;
  final String quantity;

  Map<String, dynamic> toJson() => {'product_id': productId, 'quantity_ordered': quantity};
}

class FromRecommendationsResult {
  const FromRecommendationsResult({required this.created, required this.skipped});

  factory FromRecommendationsResult.fromJson(Map<String, dynamic> j) =>
      FromRecommendationsResult(
        created: (j['created'] as List? ?? const [])
            .map((e) => PurchaseOrder.fromJson(e as Map<String, dynamic>))
            .toList(),
        skipped: (j['skipped'] as List? ?? const [])
            .map((e) => (e as Map)['sku'] as String)
            .toList(),
      );

  final List<PurchaseOrder> created;

  /// SKUs that need reordering but have no supplier.
  final List<String> skipped;
}
