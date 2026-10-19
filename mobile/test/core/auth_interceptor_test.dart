import 'package:flutter_test/flutter_test.dart';
import 'package:smartstock/core/config/app_config.dart';
import 'package:smartstock/core/network/api_client.dart';
import 'package:smartstock/core/network/api_exception.dart';
import 'package:smartstock/core/storage/token_storage.dart';
import 'package:smartstock/data/repositories/auth_repository.dart';

import '../helpers/fake_adapter.dart';
import '../helpers/fixtures.dart';

void main() {
  const config = AppConfig(apiBaseUrl: 'http://api.test');
  late InMemoryTokenStorage tokens;
  late int expiredCalls;

  setUp(() {
    tokens = InMemoryTokenStorage()
      ..accessToken = 'old-access'
      ..refreshToken = 'old-refresh';
    expiredCalls = 0;
  });

  ApiClient client(FakeAdapter adapter) => ApiClient(
        config: config,
        tokenStorage: tokens,
        adapter: adapter,
        onSessionExpired: () => expiredCalls++,
      );

  String? authOf(RecordedRequest r) => r.headers['Authorization'] as String?;

  test('injects bearer token and calls the versioned base URL', () async {
    final adapter = FakeAdapter((o) async => (200, userJson()));
    await client(adapter).get<Map<String, dynamic>>('/auth/me');
    expect(adapter.requests.single.path, '/auth/me');
    expect(authOf(adapter.requests.single), 'Bearer old-access');
    expect(config.apiV1Url, 'http://api.test/api/v1');
  });

  test('refreshes once on 401 and retries with the new token', () async {
    final adapter = FakeAdapter((o) async {
      if (o.path == '/auth/refresh') {
        expect(o.data, {'refresh_token': 'old-refresh'});
        // Real backend shape: same envelope as login.
        return (200, authJson(access: 'new-access', refresh: 'new-refresh'));
      }
      final auth = o.headers['Authorization'];
      return auth == 'Bearer new-access'
          ? (200, {'ok': true})
          : (401, errorJson('unauthenticated', 'expired'));
    });

    final result = await client(adapter).get<Map<String, dynamic>>('/inventory');

    expect(result, {'ok': true});
    expect(tokens.accessToken, 'new-access');
    expect(tokens.refreshToken, 'new-refresh');
    expect(adapter.requests.map((r) => r.path),
        ['/inventory', '/auth/refresh', '/inventory']);
    expect(expiredCalls, 0);
  });

  test('concurrent 401s share a single refresh', () async {
    var refreshes = 0;
    final adapter = FakeAdapter((o) async {
      if (o.path == '/auth/refresh') {
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return (200, authJson(access: 'new-access', refresh: 'new-refresh'));
      }
      return o.headers['Authorization'] == 'Bearer new-access'
          ? (200, {'path': o.path})
          : (401, null);
    });
    final api = client(adapter);

    final results = await Future.wait([
      api.get<Map<String, dynamic>>('/a'),
      api.get<Map<String, dynamic>>('/b'),
      api.get<Map<String, dynamic>>('/c'),
    ]);

    expect(results.map((r) => r['path']), ['/a', '/b', '/c']);
    expect(refreshes, 1);
  });

  test('failed refresh clears tokens and reports session expiry', () async {
    final adapter = FakeAdapter((o) async => o.path == '/auth/refresh'
        ? (401, errorJson('unauthenticated', 'Refresh token expired'))
        : (401, errorJson('unauthenticated', 'expired')));

    await expectLater(
      client(adapter).get<Map<String, dynamic>>('/inventory'),
      throwsA(isA<ApiException>()
          .having((e) => e.kind, 'kind', ApiErrorKind.unauthenticated)),
    );
    expect(tokens.accessToken, isNull);
    expect(tokens.refreshToken, isNull);
    expect(expiredCalls, 1);
  });

  test('login 401 is not retried through refresh', () async {
    final adapter = FakeAdapter(
        (o) async => (401, errorJson('unauthenticated', 'Invalid credentials')));
    final repo = ApiAuthRepository(client(adapter), tokens);
    await expectLater(
      repo.login(organization: 'acme', email: 'a@b.co', password: 'password-1'),
      throwsA(isA<ApiException>()
          .having((e) => e.kind, 'kind', ApiErrorKind.unauthenticated)),
    );
    expect(adapter.requests.map((r) => r.path), ['/auth/login']);
    expect(authOf(adapter.requests.single), isNull);
    // Stored session is untouched by a failed login.
    expect(tokens.refreshToken, 'old-refresh');
    expect(expiredCalls, 0);
  });
}
