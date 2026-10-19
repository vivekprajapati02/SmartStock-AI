import '../../core/network/api_client.dart';
import '../../core/network/auth_interceptor.dart';
import '../../core/storage/token_storage.dart';
import '../models/auth_models.dart';

abstract class AuthRepository {
  Future<User> login({
    required String organization,
    required String email,
    required String password,
  });

  Future<User> register({
    required String organizationName,
    String? organizationSlug,
    required String email,
    required String password,
    String? fullName,
  });

  /// Returns the current user, or null when there is no stored session.
  Future<User?> restoreSession();

  Future<void> logout();
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStorage _tokens;

  @override
  Future<User> login({
    required String organization,
    required String email,
    required String password,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/auth/login',
      data: {
        'organization': organization.trim(),
        'email': email.trim(),
        'password': password,
      },
      options: AuthInterceptor.skipAuth(),
    );
    return _persist(AuthResponse.fromJson(json));
  }

  @override
  Future<User> register({
    required String organizationName,
    String? organizationSlug,
    required String email,
    required String password,
    String? fullName,
  }) async {
    final slug = organizationSlug?.trim();
    final name = fullName?.trim();
    final json = await _api.post<Map<String, dynamic>>(
      '/auth/register',
      data: {
        'organization_name': organizationName.trim(),
        if (slug != null && slug.isNotEmpty) 'organization_slug': slug,
        'email': email.trim(),
        'password': password,
        if (name != null && name.isNotEmpty) 'full_name': name,
      },
      options: AuthInterceptor.skipAuth(),
    );
    return _persist(AuthResponse.fromJson(json));
  }

  @override
  Future<User?> restoreSession() async {
    final token = await _tokens.readAccessToken();
    if (token == null || token.isEmpty) return null;
    final json = await _api.get<Map<String, dynamic>>('/auth/me');
    return User.fromJson(json);
  }

  @override
  Future<void> logout() => _tokens.clear();

  Future<User> _persist(AuthResponse response) async {
    await _tokens.save(
      accessToken: response.tokens.accessToken,
      refreshToken: response.tokens.refreshToken,
    );
    return response.user;
  }
}
