import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/network/api_exception.dart';
import '../../core/session/session_service.dart';
import '../../routes/app_routes.dart';
import '../../widgets/async_state_view.dart';

/// Resolves a stored session before showing the app.
class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  String? _error;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve() async {
    setState(() {
      _error = null;
      _offline = false;
    });
    final session = Get.find<SessionService>();
    try {
      final user = await session.restore();
      Get.offAllNamed(user == null ? Routes.login : Routes.home);
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.unauthenticated) {
        Get.offAllNamed(Routes.login);
        return;
      }
      setState(() {
        _offline = e.isOffline;
        _error = e.displayMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _error == null
        ? LoadStatus.loading
        : (_offline ? LoadStatus.offline : LoadStatus.error);
    return Scaffold(
      body: AsyncStateView(
        status: status,
        errorMessage: _error,
        onRetry: _resolve,
        builder: (_) => const SizedBox.shrink(),
      ),
    );
  }
}
