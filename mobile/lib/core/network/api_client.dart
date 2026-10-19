import 'dart:math';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';
import 'auth_interceptor.dart';

/// Thin wrapper over Dio that converts every failure into [ApiException].
class ApiClient {
  ApiClient({
    required AppConfig config,
    required TokenStorage tokenStorage,
    void Function()? onSessionExpired,
    HttpClientAdapter? adapter,
  }) {
    final options = BaseOptions(
      baseUrl: config.apiV1Url,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    );
    final bare = Dio(options);
    dio = Dio(options);
    if (adapter != null) {
      bare.httpClientAdapter = adapter;
      dio.httpClientAdapter = adapter;
    }
    dio.interceptors.addAll([
      InterceptorsWrapper(onRequest: (o, h) {
        o.headers['X-Request-ID'] = _requestId();
        h.next(o);
      }),
      AuthInterceptor(
        tokenStorage: tokenStorage,
        bareDio: bare,
        onSessionExpired: onSessionExpired,
      ),
    ]);
  }

  late final Dio dio;

  static final _random = Random();

  static String _requestId() =>
      List.generate(16, (_) => _random.nextInt(16).toRadixString(16)).join();

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    Options? options,
  }) =>
      _send(() => dio.get<T>(path, queryParameters: _clean(query), options: options));

  Future<T> post<T>(String path, {Object? data, Options? options}) =>
      _send(() => dio.post<T>(path, data: data, options: options));

  Future<T> patch<T>(String path, {Object? data}) =>
      _send(() => dio.patch<T>(path, data: data));

  Future<void> delete(String path) => _send(() => dio.delete<void>(path));

  Future<T> _send<T>(Future<Response<T>> Function() call) async {
    try {
      final response = await call();
      return response.data as T;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Drops null and empty-string query values so filters are optional.
  static Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null) return null;
    return Map.fromEntries(query.entries.where(
      (e) => e.value != null && !(e.value is String && (e.value as String).isEmpty),
    ));
  }
}
