import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'core/config/app_config.dart';
import 'core/connectivity/connectivity_service.dart';
import 'core/network/api_client.dart';
import 'core/session/session_service.dart';
import 'core/storage/cache_store.dart';
import 'core/storage/token_storage.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/analytics_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/catalog_repository.dart';
import 'data/repositories/inventory_repository.dart';
import 'routes/app_pages.dart';
import 'routes/app_routes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initServices(
    config: AppConfig.fromEnvironment(),
    tokenStorage: SecureTokenStorage(),
    cacheStore: SharedPrefsCacheStore(),
  );
  runApp(const SmartStockApp());
}

/// Registers app-wide singletons. Tests call this with fakes.
Future<void> initServices({
  required AppConfig config,
  required TokenStorage tokenStorage,
  required CacheStore cacheStore,
}) async {
  Get.put<AppConfig>(config, permanent: true);
  Get.put<TokenStorage>(tokenStorage, permanent: true);
  Get.put<CacheStore>(cacheStore, permanent: true);

  final api = ApiClient(
    config: config,
    tokenStorage: tokenStorage,
    onSessionExpired: _onSessionExpired,
  );
  Get.put<ApiClient>(api, permanent: true);

  final authRepo = ApiAuthRepository(api, tokenStorage);
  Get.put<AuthRepository>(authRepo, permanent: true);
  Get.put<CatalogRepository>(ApiCatalogRepository(api), permanent: true);
  Get.put<InventoryRepository>(
      ApiInventoryRepository(api, cacheStore), permanent: true);
  Get.put<AnalyticsRepository>(
      ApiAnalyticsRepository(api, cacheStore), permanent: true);

  Get.put<SessionService>(SessionService(authRepo, cacheStore), permanent: true);
  await Get.putAsync<ConnectivityService>(
    () => ConnectivityService().init(),
    permanent: true,
  );
}

void _onSessionExpired() {
  if (Get.isRegistered<SessionService>()) Get.find<SessionService>().expire();
  if (Get.currentRoute != Routes.login && Get.currentRoute != Routes.register) {
    Get.offAllNamed(Routes.login);
  }
}

class SmartStockApp extends StatelessWidget {
  const SmartStockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'SmartStock AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      initialRoute: Routes.splash,
      getPages: AppPages.pages,
    );
  }
}
