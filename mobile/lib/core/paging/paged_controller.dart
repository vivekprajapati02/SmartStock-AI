import 'package:get/get.dart';

import '../../data/models/fetched.dart';
import '../../data/models/page_result.dart';
import '../../widgets/async_state_view.dart';
import '../network/api_exception.dart';

const unexpectedResponseMessage =
    'The server returned data this app version does not understand.';

/// Shared offset pagination for list screens backed by the `{items, total,
/// limit, offset}` envelope. Subclasses only implement [fetchPage].
abstract class PagedController<T> extends GetxController {
  PagedController({this.pageSize = 50});

  final int pageSize;

  final RxList<T> items = <T>[].obs;
  final Rx<LoadStatus> status = LoadStatus.initial.obs;
  final RxnString error = RxnString();
  final Rxn<DateTime> cachedAt = Rxn<DateTime>();
  final RxInt total = 0.obs;
  final RxBool loadingMore = false.obs;

  int _seq = 0;

  bool get hasMore => items.length < total.value;

  Future<Fetched<PageResult<T>>> fetchPage(int offset, int limit);

  /// Whether to load automatically when the controller becomes ready.
  bool get autoLoad => true;

  @override
  void onReady() {
    super.onReady();
    if (autoLoad) reload();
  }

  Future<void> reload() async {
    final seq = ++_seq;
    if (items.isEmpty) status.value = LoadStatus.loading;
    error.value = null;
    try {
      final result = await fetchPage(0, pageSize);
      if (seq != _seq) return;
      items.assignAll(result.value.items);
      total.value = result.value.total;
      cachedAt.value = result.cachedAt;
      status.value = items.isEmpty ? LoadStatus.empty : LoadStatus.data;
    } on ApiException catch (e) {
      if (seq != _seq) return;
      error.value = e.displayMessage;
      items.clear();
      total.value = 0;
      cachedAt.value = null;
      status.value = e.isOffline ? LoadStatus.offline : LoadStatus.error;
    } catch (e) {
      if (seq != _seq) return;
      error.value = unexpectedResponseMessage;
      items.clear();
      total.value = 0;
      cachedAt.value = null;
      status.value = LoadStatus.error;
    }
  }

  Future<void> loadMore() async {
    if (loadingMore.value || !hasMore || status.value != LoadStatus.data) return;
    if (cachedAt.value != null) return; // Cached snapshot: no further pages.
    final seq = _seq;
    loadingMore.value = true;
    try {
      final result = await fetchPage(items.length, pageSize);
      if (seq != _seq) return;
      items.addAll(result.value.items);
      total.value = result.value.total;
    } on ApiException catch (e) {
      if (seq != _seq) return;
      error.value = e.displayMessage;
    } catch (_) {
      if (seq != _seq) return;
      error.value = unexpectedResponseMessage;
    } finally {
      loadingMore.value = false;
    }
  }
}
