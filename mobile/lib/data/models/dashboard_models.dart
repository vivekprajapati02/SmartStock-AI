import '../../core/utils/parse.dart';

class DemandPoint {
  const DemandPoint({required this.date, required this.quantity});

  factory DemandPoint.fromJson(Map<String, dynamic> json) => DemandPoint(
        date: parseDateTime(json['sale_date']),
        quantity: parseDouble(json['quantity']),
      );

  final DateTime date;
  final double quantity;
}

/// Mirrors `GET /analytics/dashboard`. Every value comes from the server.
class Dashboard {
  const Dashboard({
    required this.inventoryValue,
    required this.skuCount,
    required this.storeCount,
    required this.lowStockCount,
    required this.stockoutCount,
    required this.pendingOrderCount,
    this.openAlertCount = 0,
    required this.demandTrend,
    required this.isDemo,
  });

  factory Dashboard.fromJson(Map<String, dynamic> json) => Dashboard(
        inventoryValue: parseDouble(json['inventory_value']),
        skuCount: parseInt(json['sku_count']),
        storeCount: parseInt(json['store_count']),
        lowStockCount: parseInt(json['low_stock_count']),
        stockoutCount: parseInt(json['stockout_count']),
        pendingOrderCount: parseInt(json['pending_order_count']),
        openAlertCount: parseInt(json['open_alert_count']),
        demandTrend: (json['demand_trend'] as List? ?? const [])
            .map((e) => DemandPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        isDemo: json['is_demo'] as bool? ?? false,
      );

  final double inventoryValue;
  final int skuCount;
  final int storeCount;
  final int lowStockCount;
  final int stockoutCount;
  final int pendingOrderCount;
  final int openAlertCount;
  final List<DemandPoint> demandTrend;
  final bool isDemo;

  bool get isEmpty => skuCount == 0 && storeCount == 0;
}
