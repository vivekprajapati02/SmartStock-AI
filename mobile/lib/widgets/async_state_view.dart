import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The lifecycle of a screen's remote data.
enum LoadStatus { initial, loading, data, empty, error, offline }

/// One widget for every async state: loading, error (with retry), empty,
/// offline (no data at all), and data - optionally flagged as a cached copy.
class AsyncStateView extends StatelessWidget {
  const AsyncStateView({
    super.key,
    required this.status,
    required this.builder,
    this.errorMessage,
    this.onRetry,
    this.emptyTitle = 'Nothing here yet',
    this.emptyMessage,
    this.emptyAction,
    this.cachedAt,
  });

  final LoadStatus status;
  final WidgetBuilder builder;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final String emptyTitle;
  final String? emptyMessage;
  final Widget? emptyAction;

  /// When set, data is shown with a banner saying it is a cached copy.
  final DateTime? cachedAt;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case LoadStatus.initial:
      case LoadStatus.loading:
        return const Center(
          child: CircularProgressIndicator(key: Key('async-loading')),
        );
      case LoadStatus.error:
        return StateMessage(
          key: const Key('async-error'),
          icon: Icons.error_outline,
          title: 'Something went wrong',
          message: errorMessage ?? 'The request failed.',
          action: onRetry == null
              ? null
              : FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
        );
      case LoadStatus.offline:
        return StateMessage(
          key: const Key('async-offline'),
          icon: Icons.cloud_off,
          title: 'You are offline',
          message: errorMessage ??
              'Cannot reach the server and no saved copy is available.',
          action: onRetry == null
              ? null
              : OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
        );
      case LoadStatus.empty:
        return StateMessage(
          key: const Key('async-empty'),
          icon: Icons.inbox_outlined,
          title: emptyTitle,
          message: emptyMessage,
          action: emptyAction,
        );
      case LoadStatus.data:
        final content = builder(context);
        if (cachedAt == null) return content;
        return Column(
          children: [
            CachedBanner(savedAt: cachedAt!, onRetry: onRetry),
            Expanded(child: content),
          ],
        );
    }
  }
}

class CachedBanner extends StatelessWidget {
  const CachedBanner({super.key, required this.savedAt, this.onRetry});

  final DateTime savedAt;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final when = DateFormat.yMMMd().add_jm().format(savedAt.toLocal());
    return Material(
      key: const Key('async-cached-banner'),
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 18, color: scheme.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Offline - showing data saved $when',
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class StateMessage extends StatelessWidget {
  const StateMessage({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text(title,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    );
  }
}
