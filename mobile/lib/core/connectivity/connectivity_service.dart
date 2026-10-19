import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get/get.dart';

/// Exposes the device's network reachability as reactive state.
///
/// Connectivity only reports whether a network interface is up; requests can
/// still fail, so repositories also treat connection errors as "offline".
class ConnectivityService extends GetxService {
  ConnectivityService([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  final RxBool isOnline = true.obs;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  Future<ConnectivityService> init() async {
    try {
      _update(await _connectivity.checkConnectivity());
      _subscription = _connectivity.onConnectivityChanged.listen(_update);
    } catch (_) {
      // Plugin unavailable (e.g. tests); assume online and rely on request errors.
      isOnline.value = true;
    }
    return this;
  }

  void _update(List<ConnectivityResult> results) {
    isOnline.value = results.any((r) => r != ConnectivityResult.none);
  }

  @override
  void onClose() {
    _subscription?.cancel();
    super.onClose();
  }
}
