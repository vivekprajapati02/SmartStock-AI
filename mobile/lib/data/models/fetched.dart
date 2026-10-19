/// A value plus whether it came from the offline cache.
class Fetched<T> {
  const Fetched(this.value, {this.cachedAt});

  final T value;

  /// Non-null when the server was unreachable and a cached copy was used.
  final DateTime? cachedAt;

  bool get isCached => cachedAt != null;
}
