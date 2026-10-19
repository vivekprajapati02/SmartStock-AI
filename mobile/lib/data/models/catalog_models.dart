import '../../core/utils/parse.dart';

class Category {
  const Category({required this.id, required this.name});

  factory Category.fromJson(Map<String, dynamic> json) =>
      Category(id: json['id'] as String, name: json['name'] as String);

  final String id;
  final String name;
}

class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.contactEmail,
    this.phone,
    required this.leadTimeDays,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
        id: json['id'] as String,
        name: json['name'] as String,
        contactEmail: json['contact_email'] as String?,
        phone: json['phone'] as String?,
        leadTimeDays: parseInt(json['lead_time_days']),
      );

  final String id;
  final String name;
  final String? contactEmail;
  final String? phone;
  final int leadTimeDays;
}

class Store {
  const Store({required this.id, required this.name, this.location});

  factory Store.fromJson(Map<String, dynamic> json) => Store(
        id: json['id'] as String,
        name: json['name'] as String,
        location: json['location'] as String?,
      );

  final String id;
  final String name;
  final String? location;
}

class Product {
  const Product({
    required this.id,
    required this.sku,
    required this.name,
    this.categoryId,
    this.supplierId,
    required this.unit,
    required this.unitCost,
    required this.unitPrice,
    required this.isActive,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        sku: json['sku'] as String,
        name: json['name'] as String,
        categoryId: json['category_id'] as String?,
        supplierId: json['supplier_id'] as String?,
        unit: json['unit'] as String? ?? 'unit',
        unitCost: parseDouble(json['unit_cost']),
        unitPrice: parseDouble(json['unit_price']),
        isActive: json['is_active'] as bool? ?? true,
      );

  final String id;
  final String sku;
  final String name;
  final String? categoryId;
  final String? supplierId;
  final String unit;
  final double unitCost;
  final double unitPrice;
  final bool isActive;
}

/// Payload for creating or updating a product.
class ProductInput {
  const ProductInput({
    required this.sku,
    required this.name,
    this.categoryId,
    this.supplierId,
    required this.unit,
    required this.unitCost,
    required this.unitPrice,
    required this.isActive,
  });

  final String sku;
  final String name;
  final String? categoryId;
  final String? supplierId;
  final String unit;
  final String unitCost;
  final String unitPrice;
  final bool isActive;

  Map<String, dynamic> toJson() => {
        'sku': sku,
        'name': name,
        'category_id': categoryId,
        'supplier_id': supplierId,
        'unit': unit,
        'unit_cost': unitCost,
        'unit_price': unitPrice,
        'is_active': isActive,
      };
}
