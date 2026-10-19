import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../core/session/session_service.dart';
import '../modules/auth/auth_controller.dart';
import '../modules/auth/auth_views.dart';
import '../modules/auth/splash_view.dart';
import '../modules/catalog/catalog_controllers.dart';
import '../modules/dashboard/dashboard_controller.dart';
import '../modules/forecasting/forecasting_controllers.dart';
import '../modules/imports/imports_controller.dart';
import '../modules/imports/imports_view.dart';
import '../modules/inventory/inventory_controller.dart';
import '../modules/inventory/inventory_detail_view.dart';
import '../modules/movements/movements_controller.dart';
import '../modules/movements/movements_view.dart';
import '../modules/shell/home_view.dart';
import 'app_routes.dart';

/// Sends unauthenticated users to the login screen.
class AuthMiddleware extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    final session = Get.find<SessionService>();
    return session.isAuthenticated ? null : const RouteSettings(name: Routes.login);
  }
}

class AuthBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => AuthController(Get.find(), Get.find()), fenix: true);
  }
}

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(HomeController.new);
    Get.lazyPut(() => DashboardController(Get.find()));
    Get.lazyPut(() => InventoryController(Get.find(), Get.find()));
    Get.lazyPut(() => MovementsController(Get.find(), Get.find()));
    Get.lazyPut(() => ProductsController(Get.find()));
    Get.lazyPut(() => StoresController(Get.find()));
    Get.lazyPut(() => CategoriesController(Get.find()));
    Get.lazyPut(() => SuppliersController(Get.find()));
    Get.lazyPut(() => ImportsController(Get.find(), Get.find()));
    Get.lazyPut(() => ForecastController(Get.find(), Get.find()));
    Get.lazyPut(() => EvaluationController(Get.find()));
  }
}

class InventoryDetailBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => InventoryDetailController(Get.find(), Get.arguments as String),
    );
  }
}

class ImportDetailBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => ImportDetailController(Get.find(), Get.arguments as String));
  }
}

class MovementFormBinding extends Bindings {
  @override
  void dependencies() {
    final args = Get.arguments is MovementFormArgs
        ? Get.arguments as MovementFormArgs
        : const MovementFormArgs();
    Get.lazyPut(() => MovementFormController(Get.find(), Get.find(), args));
  }
}

abstract class AppPages {
  static final pages = <GetPage<dynamic>>[
    GetPage(name: Routes.splash, page: () => const SplashView()),
    GetPage(
      name: Routes.login,
      page: () => const LoginView(),
      binding: AuthBinding(),
    ),
    GetPage(
      name: Routes.register,
      page: () => const RegisterView(),
      binding: AuthBinding(),
    ),
    GetPage(
      name: Routes.home,
      page: () => const HomeView(),
      binding: HomeBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: Routes.inventoryDetail,
      page: () => const InventoryDetailView(),
      binding: InventoryDetailBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: Routes.movementForm,
      page: () => const MovementFormView(),
      binding: MovementFormBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: Routes.importDetail,
      page: () => const ImportDetailView(),
      binding: ImportDetailBinding(),
      middlewares: [AuthMiddleware()],
    ),
  ];
}
