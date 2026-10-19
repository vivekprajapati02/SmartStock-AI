import 'package:dio/dio.dart';

/// A single field-level validation message from the backend error envelope.
class FieldError {
  const FieldError({this.field, required this.message});

  final String? field;
  final String message;
}

enum ApiErrorKind {
  offline,
  timeout,
  unauthenticated,
  forbidden,
  notFound,
  conflict,
  validation,
  server,
  unknown,
}

/// Typed failure raised by repositories. Built from the backend envelope:
/// `{"error": {"code", "message", "details", "request_id"}}`.
class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.code,
    this.details = const [],
    this.requestId,
  });

  factory ApiException.fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionError:
        return const ApiException(
          kind: ApiErrorKind.offline,
          message: 'Cannot reach the server. Check your connection.',
        );
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const ApiException(
          kind: ApiErrorKind.timeout,
          message: 'The server took too long to respond.',
        );
      case DioExceptionType.badResponse:
        return ApiException.fromResponse(
          error.response?.statusCode,
          error.response?.data,
        );
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        if (error.error is ApiException) return error.error! as ApiException;
        return ApiException(
          kind: ApiErrorKind.unknown,
          message: error.message ?? 'Unexpected network error.',
        );
    }
  }

  factory ApiException.fromResponse(int? statusCode, Object? data) {
    String? code;
    String? message;
    String? requestId;
    final details = <FieldError>[];
    if (data is Map && data['error'] is Map) {
      final body = data['error'] as Map;
      code = body['code'] as String?;
      message = body['message'] as String?;
      requestId = body['request_id'] as String?;
      final rawDetails = body['details'];
      if (rawDetails is List) {
        for (final item in rawDetails) {
          if (item is Map && item['message'] != null) {
            details.add(FieldError(
              field: item['field'] as String?,
              message: item['message'].toString(),
            ));
          }
        }
      }
    }
    final kind = _kindFor(statusCode);
    return ApiException(
      kind: kind,
      statusCode: statusCode,
      code: code,
      message: message ?? _defaultMessage(kind),
      details: details,
      requestId: requestId,
    );
  }

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;
  final String? code;
  final List<FieldError> details;
  final String? requestId;

  bool get isOffline =>
      kind == ApiErrorKind.offline || kind == ApiErrorKind.timeout;

  /// Validation messages keyed by the last segment of the field path.
  Map<String, String> get fieldErrors {
    final result = <String, String>{};
    for (final d in details) {
      final field = d.field;
      if (field == null || field.isEmpty) continue;
      final key = field.split('.').last;
      result.putIfAbsent(key, () => d.message);
    }
    return result;
  }

  /// Message suitable for display: the first detail when the summary is generic.
  String get displayMessage {
    if (kind == ApiErrorKind.validation && details.isNotEmpty) {
      return details.map((d) => d.message).join('\n');
    }
    return message;
  }

  static ApiErrorKind _kindFor(int? status) {
    if (status == null) return ApiErrorKind.unknown;
    if (status == 401) return ApiErrorKind.unauthenticated;
    if (status == 403) return ApiErrorKind.forbidden;
    if (status == 404) return ApiErrorKind.notFound;
    if (status == 409) return ApiErrorKind.conflict;
    if (status == 400 || status == 422) return ApiErrorKind.validation;
    if (status >= 500) return ApiErrorKind.server;
    return ApiErrorKind.unknown;
  }

  static String _defaultMessage(ApiErrorKind kind) {
    switch (kind) {
      case ApiErrorKind.unauthenticated:
        return 'Your session has expired. Please sign in again.';
      case ApiErrorKind.forbidden:
        return 'You do not have permission to do that.';
      case ApiErrorKind.notFound:
        return 'The requested item was not found.';
      case ApiErrorKind.conflict:
        return 'That conflicts with existing data.';
      case ApiErrorKind.validation:
        return 'Some fields are invalid.';
      case ApiErrorKind.server:
        return 'The server encountered an error.';
      case ApiErrorKind.offline:
        return 'You are offline.';
      case ApiErrorKind.timeout:
        return 'The server took too long to respond.';
      case ApiErrorKind.unknown:
        return 'Something went wrong.';
    }
  }

  @override
  String toString() => 'ApiException($kind, $statusCode, $code, $message)';
}
