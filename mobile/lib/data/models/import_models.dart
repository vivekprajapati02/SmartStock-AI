import '../../core/utils/parse.dart';

enum ImportStatus {
  pending('Pending'),
  completed('Completed'),
  partial('Partially imported'),
  failed('Failed');

  const ImportStatus(this.label);

  final String label;

  static ImportStatus parse(String? value) => ImportStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => ImportStatus.pending,
      );
}

enum ImportErrorKind { invalid, duplicate, file }

class ImportRowError {
  const ImportRowError({
    this.row,
    this.column,
    this.value,
    required this.message,
    required this.kind,
  });

  factory ImportRowError.fromJson(Map<String, dynamic> json) => ImportRowError(
        row: json['row'] as int?,
        column: json['column'] as String?,
        value: json['value'] as String?,
        message: json['message'] as String? ?? '',
        kind: ImportErrorKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => ImportErrorKind.invalid,
        ),
      );

  /// 1-based data row; the line in the file is `row + 1` (header).
  final int? row;
  final String? column;
  final String? value;
  final String message;
  final ImportErrorKind kind;
}

/// An import batch. [errors] is only populated by the detail/upload endpoints.
class ImportBatch {
  const ImportBatch({
    required this.id,
    required this.filename,
    required this.status,
    required this.totalRows,
    required this.validRows,
    required this.invalidRows,
    required this.duplicateRows,
    required this.errorCount,
    required this.createdAt,
    this.errors = const [],
    this.errorsTruncated = false,
  });

  factory ImportBatch.fromJson(Map<String, dynamic> json) => ImportBatch(
        id: json['id'] as String,
        filename: json['filename'] as String? ?? '',
        status: ImportStatus.parse(json['status'] as String?),
        totalRows: parseInt(json['total_rows']),
        validRows: parseInt(json['valid_rows']),
        invalidRows: parseInt(json['invalid_rows']),
        duplicateRows: parseInt(json['duplicate_rows']),
        errorCount: parseInt(json['error_count']),
        createdAt: parseDateTime(json['created_at']),
        errors: (json['errors'] as List? ?? const [])
            .map((e) => ImportRowError.fromJson(e as Map<String, dynamic>))
            .toList(),
        errorsTruncated: json['errors_truncated'] as bool? ?? false,
      );

  final String id;
  final String filename;
  final ImportStatus status;
  final int totalRows;
  final int validRows;
  final int invalidRows;
  final int duplicateRows;
  final int errorCount;
  final DateTime createdAt;
  final List<ImportRowError> errors;
  final bool errorsTruncated;
}
