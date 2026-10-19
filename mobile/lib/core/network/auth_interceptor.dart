import 'package:dio/dio.dart';

import '../storage/token_storage.dart';

/// Injects the bearer token and transparently refreshes it on a 401.
///
/// It is a [QueuedInterceptor], so concurrent failures are handled one at a
/// time: the first 401 performs the refresh, and later ones notice the stored
/// token has already changed and simply retry with it. Refresh and retry go
/// through [_bareDio] (no interceptors) to avoid recursion and queue deadlocks.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required TokenStorage tokenStorage,
    required Dio bareDio,
    this.onSessionExpired,
  })  : _tokens = tokenStorage,
        _bareDio = bareDio; // ignore: prefer_initializing_formals

  static const _retriedKey = 'auth_retried';
  static const _skipAuthKey = 'skip_auth';

  final TokenStorage _tokens;
  final Dio _bareDio;

  /// Called after a refresh fails and tokens are cleared.
  final void Function()? onSessionExpired;

  /// Marks a request as not needing (or not allowed to send) a bearer token.
  static Options skipAuth([Options? options]) {
    final base = options ?? Options();
    return base.copyWith(extra: {...?base.extra, _skipAuthKey: true});
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[_skipAuthKey] != true) {
      final token = await _tokens.readAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final request = err.requestOptions;
    final eligible = err.response?.statusCode == 401 &&
        request.extra[_skipAuthKey] != true &&
        request.extra[_retriedKey] != true;
    if (!eligible) {
      handler.next(err);
      return;
    }

    final usedHeader = request.headers['Authorization'] as String?;
    final current = await _tokens.readAccessToken();

    // Another queued request already refreshed: just retry with the new token.
    if (current != null && usedHeader != null && usedHeader != 'Bearer $current') {
      await _retry(request, current, err, handler);
      return;
    }

    final refreshToken = await _tokens.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await _expire();
      handler.next(err);
      return;
    }

    try {
      final response = await _bareDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      // The backend answers with the same `{user, tokens}` envelope as login.
      final data = response.data ?? const {};
      final pair = data['tokens'] is Map ? data['tokens'] as Map : data;
      final access = pair['access_token'] as String?;
      final refresh = pair['refresh_token'] as String?;
      if (access == null || refresh == null) {
        throw StateError('Refresh response missing tokens');
      }
      await _tokens.save(accessToken: access, refreshToken: refresh);
      await _retry(request, access, err, handler);
    } catch (_) {
      await _expire();
      handler.next(err);
    }
  }

  Future<void> _retry(
    RequestOptions request,
    String accessToken,
    DioException original,
    ErrorInterceptorHandler handler,
  ) async {
    final retryOptions = request.copyWith(
      headers: {...request.headers, 'Authorization': 'Bearer $accessToken'},
      extra: {...request.extra, _retriedKey: true},
    );
    try {
      final response = await _bareDio.fetch<dynamic>(retryOptions);
      handler.resolve(response);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) await _expire();
      handler.next(e);
    }
  }

  Future<void> _expire() async {
    await _tokens.clear();
    onSessionExpired?.call();
  }
}
