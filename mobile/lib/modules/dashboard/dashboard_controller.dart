import 'package:get/get.dart';

import '../../core/network/api_exception.dart';
import '../../core/paging/paged_controller.dart' show unexpectedResponseMessage;
import '../../data/models/dashboard_models.dart';
import '../../data/repositories/analytics_repository.dart';
import '../../widgets/async_state_view.dart';

class DashboardController extends GetxController {
  DashboardController(this._repo);

  final AnalyticsRepository _repo;

  static const trendOptions = [7, 30, 90];

  final Rx<LoadStatus> status = LoadStatus.initial.obs;
  final Rxn<Dashboard> dashboard = Rxn<Dashboard>();
  final Rxn<DateTime> cachedAt = Rxn<DateTime>();
  final RxnString error = RxnString();
  final RxInt trendDays = 30.obs;

  int _requestSeq = 0;

  @override
  void onReady() {
    super.onReady();
    load();
  }

  Future<void> setTrendDays(int days) async {
    if (trendDays.value == days) return;
    trendDays.value = days;
    await load();
  }

  Future<void> load() async {
    final seq = ++_requestSeq;
    if (dashboard.value == null) status.value = LoadStatus.loading;
    error.value = null;
    try {
      final result = await _repo.getDashboard(trendDays: trendDays.value);
      if (seq != _requestSeq) return;
      dashboard.value = result.value;
      cachedAt.value = result.cachedAt;
      status.value = LoadStatus.data;
    } on ApiException catch (e) {
      if (seq != _requestSeq) return;
      error.value = e.displayMessage;
      // Keep showing previously loaded data on refresh failure.
      if (dashboard.value != null) return;
      status.value = e.isOffline ? LoadStatus.offline : LoadStatus.error;
    } catch (_) {
      if (seq != _requestSeq) return;
      error.value = unexpectedResponseMessage;
      if (dashboard.value == null) status.value = LoadStatus.error;
    }
  }
}
