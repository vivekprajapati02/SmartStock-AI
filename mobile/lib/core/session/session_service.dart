import 'package:get/get.dart';

import '../../data/models/auth_models.dart';
import '../../data/repositories/auth_repository.dart';
import '../storage/cache_store.dart';

/// Holds the signed-in user for the whole app.
class SessionService extends GetxService {
  SessionService(this._auth, this._cache);

  final AuthRepository _auth;
  final CacheStore _cache;

  final Rxn<User> user = Rxn<User>();

  bool get isAuthenticated => user.value != null;

  bool get canWrite => user.value?.canWrite ?? false;

  void setUser(User value) => user.value = value;

  /// Loads the current user from stored tokens. Returns null if not signed in
  /// or the stored session is no longer valid.
  Future<User?> restore() async {
    try {
      final restored = await _auth.restoreSession();
      user.value = restored;
      return restored;
    } catch (_) {
      user.value = null;
      rethrow;
    }
  }

  Future<void> logout() async {
    await _auth.logout();
    await _cache.clear();
    user.value = null;
  }

  /// Called when token refresh fails; tokens are already cleared.
  void expire() {
    user.value = null;
  }
}
