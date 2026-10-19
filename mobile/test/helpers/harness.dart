import 'package:get/get.dart';
import 'package:smartstock/core/config/app_config.dart';
import 'package:smartstock/core/network/api_client.dart';
import 'package:smartstock/core/session/session_service.dart';
import 'package:smartstock/core/storage/cache_store.dart';
import 'package:smartstock/core/storage/token_storage.dart';
import 'package:smartstock/data/models/auth_models.dart';
import 'package:smartstock/data/repositories/analytics_repository.dart';
import 'package:smartstock/data/repositories/auth_repository.dart';
import 'package:smartstock/data/repositories/catalog_repository.dart';
import 'package:smartstock/data/repositories/import_repository.dart';
import 'package:smartstock/data/repositories/inventory_repository.dart';

import 'fake_adapter.dart';
import 'fixtures.dart';

/// Real repositories wired to a [FakeAdapter] backend.
class Harness {
  Harness(Responder responder) : adapter = FakeAdapter(responder) {
    tokens = InMemoryTokenStorage()
      ..accessToken = 'access'
      ..refreshToken = 'refresh';
    cache = InMemoryCacheStore();
    api = ApiClient(
      config: const AppConfig(apiBaseUrl: 'http://api.test'),
      tokenStorage: tokens,
      adapter: adapter,
    );
    auth = ApiAuthRepository(api, tokens);
    catalog = ApiCatalogRepository(api);
    inventory = ApiInventoryRepository(api, cache);
    analytics = ApiAnalyticsRepository(api, cache);
    imports = ApiImportRepository(api);
    session = SessionService(auth, cache);
  }

  final FakeAdapter adapter;
  late final InMemoryTokenStorage tokens;
  late final InMemoryCacheStore cache;
  late final ApiClient api;
  late final AuthRepository auth;
  late final CatalogRepository catalog;
  late final InventoryRepository inventory;
  late final AnalyticsRepository analytics;
  late final ImportRepository imports;
  late final SessionService session;

  /// Registers repositories and a signed-in session in GetX.
  void register({String role = 'owner'}) {
    Get.testMode = true;
    Get.put<AuthRepository>(auth);
    Get.put<CatalogRepository>(catalog);
    Get.put<InventoryRepository>(inventory);
    Get.put<AnalyticsRepository>(analytics);
    Get.put<ImportRepository>(imports);
    Get.put<CacheStore>(cache);
    Get.put<SessionService>(session);
    session.setUser(User.fromJson(userJson(role: role)));
  }
}
