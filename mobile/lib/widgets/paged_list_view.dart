import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/paging/paged_controller.dart';
import 'async_state_view.dart';

/// Infinite-scroll list bound to a [PagedController].
class PagedListView<T> extends StatelessWidget {
  const PagedListView({
    super.key,
    required this.controller,
    required this.itemBuilder,
    this.emptyTitle = 'Nothing here yet',
    this.emptyMessage,
    this.emptyAction,
  });

  final PagedController<T> controller;
  final Widget Function(BuildContext, T) itemBuilder;
  final String emptyTitle;
  final String? emptyMessage;
  final Widget? emptyAction;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() => AsyncStateView(
          status: c.status.value,
          errorMessage: c.error.value,
          onRetry: c.reload,
          cachedAt: c.cachedAt.value,
          emptyTitle: emptyTitle,
          emptyMessage: emptyMessage,
          emptyAction: emptyAction,
          builder: (context) => RefreshIndicator(
            onRefresh: c.reload,
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
                  c.loadMore();
                }
                return false;
              },
              child: Obx(() {
                final count = c.items.length;
                final footer = c.hasMore && c.cachedAt.value == null;
                return ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: count + (footer ? 1 : 0),
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (index >= count) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: c.loadingMore.value
                              ? const CircularProgressIndicator()
                              : TextButton(
                                  onPressed: c.loadMore,
                                  child: Text(
                                      'Load more (${c.items.length} of ${c.total.value})'),
                                ),
                        ),
                      );
                    }
                    return itemBuilder(context, c.items[index]);
                  },
                );
              }),
            ),
          ),
        ));
  }
}
