import 'package:get/get.dart';

import '../../core/network/api_exception.dart';
import '../../core/session/session_service.dart';
import '../../data/repositories/auth_repository.dart';
import '../../routes/app_routes.dart';

/// Drives the login and register forms.
class AuthController extends GetxController {
  AuthController(this._auth, this._session);

  final AuthRepository _auth;
  final SessionService _session;

  final RxBool submitting = false.obs;
  final RxnString formError = RxnString();
  final RxMap<String, String> fieldErrors = <String, String>{}.obs;

  Future<bool> login({
    required String organization,
    required String email,
    required String password,
  }) =>
      _run(() => _auth.login(
            organization: organization,
            email: email,
            password: password,
          ));

  Future<bool> register({
    required String organizationName,
    String? organizationSlug,
    required String email,
    required String password,
    String? fullName,
  }) =>
      _run(() => _auth.register(
            organizationName: organizationName,
            organizationSlug: organizationSlug,
            email: email,
            password: password,
            fullName: fullName,
          ));

  Future<bool> _run(Future<dynamic> Function() action) async {
    if (submitting.value) return false;
    submitting.value = true;
    formError.value = null;
    fieldErrors.clear();
    try {
      final user = await action();
      _session.setUser(user);
      Get.offAllNamed(Routes.home);
      return true;
    } on ApiException catch (e) {
      fieldErrors.assignAll(e.fieldErrors);
      formError.value = e.kind == ApiErrorKind.unauthenticated
          ? 'Organisation, email or password is incorrect.'
          : e.displayMessage;
      return false;
    } finally {
      submitting.value = false;
    }
  }
}
