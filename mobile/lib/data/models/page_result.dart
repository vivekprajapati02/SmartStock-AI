import '../../core/utils/parse.dart';

/// The backend list envelope: `{items, total, limit, offset}`.
class PageResult<T> {
  const PageResult({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  factory PageResult.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) itemFromJson,
  ) {
    final raw = json['items'] as List? ?? const [];
    return PageResult(
      items: raw.map((e) => itemFromJson(e as Map<String, dynamic>)).toList(),
      total: parseInt(json['total']),
      limit: parseInt(json['limit'], fallback: raw.length),
      offset: parseInt(json['offset']),
    );
  }

  final List<T> items;
  final int total;
  final int limit;
  final int offset;

  bool get hasMore => offset + items.length < total;
}
