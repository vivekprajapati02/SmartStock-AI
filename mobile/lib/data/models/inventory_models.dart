import '../../core/utils/parse.dart';

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.productId,
    required this.storeId,
    this.sku,
    this.productName,
    this.storeName,
    this.unitCost,
    required this.quantityOnHand,
    required this.reorderPoint,
    required this.safetyStock,
    required this.leadTimeDays,
    this.inventoryValue,
    required this.isLowStock,
    required this.isStockout,
    required this.updatedAt,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> json) => InventoryItem(
        id: json['id'] as String,
        productId: json['product_id'] as String,
        storeId: json['store_id'] as String,
        sku: json['sku'] as String?,
        productName: json['product_name'] as String?,
        storeName: json['store_name'] as String?,
        unitCost: parseDoubleOrNull(json['unit_cost']),
        quantityOnHand: parseDouble(json['quantity_on_hand']),
        reorderPoint: parseDouble(json['reorder_point']),
        safetyStock: parseDouble(json['safety_stock']),
        leadTimeDays: parseInt(json['lead_time_days']),
        inventoryValue: parseDoubleOrNull(json['inventory_value']),
        isLowStock: json['is_low_stock'] as bool? ?? false,
        isStockout: json['is_stockout'] as bool? ?? false,
        updatedAt: parseDateTime(json['updated_at']),
      );

  final String id;
  final String productId;
  final String storeId;
  final String? sku;
  final String? productName;
  final String? storeName;
  final double? unitCost;
  final double quantityOnHand;
  final double reorderPoint;
  final double safetyStock;
  final int leadTimeDays;
  final double? inventoryValue;
  final bool isLowStock;
  final bool isStockout;
  final DateTime updatedAt;
}

enum MovementType {
  stockIn('in', 'Stock in'),
  stockOut('out', 'Stock out'),
  adjust('adjust', 'Adjustment');

  const MovementType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static MovementType parse(String? value) => MovementType.values.firstWhere(
        (m) => m.apiValue == value,
        orElse: () => MovementType.adjust,
      );
}

class Movement {
  const Movement({
    required this.id,
    required this.productId,
    required this.storeId,
    this.sku,
    this.productName,
    this.storeName,
    required this.movementType,
    required this.quantity,
    this.reference,
    this.note,
    required this.occurredAt,
  });

  factory Movement.fromJson(Map<String, dynamic> json) => Movement(
        id: json['id'] as String,
        productId: json['product_id'] as String,
        storeId: json['store_id'] as String,
        sku: json['sku'] as String?,
        productName: json['product_name'] as String?,
        storeName: json['store_name'] as String?,
        movementType: MovementType.parse(json['movement_type'] as String?),
        quantity: parseDouble(json['quantity']),
        reference: json['reference'] as String?,
        note: json['note'] as String?,
        occurredAt: parseDateTime(json['occurred_at']),
      );

  final String id;
  final String productId;
  final String storeId;
  final String? sku;
  final String? productName;
  final String? storeName;
  final MovementType movementType;
  final double quantity;
  final String? reference;
  final String? note;
  final DateTime occurredAt;
}

class MovementInput {
  const MovementInput({
    required this.productId,
    required this.storeId,
    required this.movementType,
    required this.quantity,
    this.reference,
    this.note,
  });

  final String productId;
  final String storeId;
  final MovementType movementType;

  /// Decimal string; signed for adjustments, positive for in/out.
  final String quantity;
  final String? reference;
  final String? note;

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'store_id': storeId,
        'movement_type': movementType.apiValue,
        'quantity': quantity,
        if (reference != null && reference!.isNotEmpty) 'reference': reference,
        if (note != null && note!.isNotEmpty) 'note': note,
      };
}
