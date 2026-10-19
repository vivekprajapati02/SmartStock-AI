import 'package:flutter/foundation.dart' show kIsWeb;

/// Runtime configuration supplied at build time via `--dart-define`.
///
/// * `API_BASE_URL` - origin of the backend, e.g. `http://localhost:8000`.
///   On web an empty value means "same origin": the app is served behind a
///   reverse proxy that forwards `/api` to the backend (single preview port).
///   Desktop and mobile builds call the backend directly and default to
///   `http://localhost:8000`.
class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  factory AppConfig.fromEnvironment() {
    const defined = String.fromEnvironment('API_BASE_URL');
    final origin = defined.isNotEmpty
        ? defined
        : (kIsWeb ? '' : 'http://localhost:8000');
    return AppConfig(apiBaseUrl: _stripTrailingSlash(origin));
  }

  /// Backend origin without a trailing slash; empty means same origin.
  final String apiBaseUrl;

  /// Base URL for versioned API calls.
  String get apiV1Url => '$apiBaseUrl/api/v1';

  static String _stripTrailingSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}
