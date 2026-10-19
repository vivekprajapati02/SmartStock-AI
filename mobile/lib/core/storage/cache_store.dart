import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A cached JSON payload together with when it was fetched from the server.
class CachedEntry {
  const CachedEntry({required this.data, required this.savedAt});

  final Object? data;
  final DateTime savedAt;
}

/// Stores the last successful server response per key so the UI can show it,
/// clearly labelled as cached, while offline. It never synthesises data.
abstract class CacheStore {
  Future<void> write(String key, Object? json);
  Future<CachedEntry?> read(String key);
  Future<void> clear();
}

class SharedPrefsCacheStore implements CacheStore {
  static const _prefix = 'smartstock.cache.';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<void> write(String key, Object? json) async {
    final prefs = await _prefs;
    await prefs.setString(
      '$_prefix$key',
      jsonEncode({
        'saved_at': DateTime.now().toUtc().toIso8601String(),
        'data': json,
      }),
    );
  }

  @override
  Future<CachedEntry?> read(String key) async {
    final prefs = await _prefs;
    final raw = prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return CachedEntry(
        data: decoded['data'],
        savedAt: DateTime.parse(decoded['saved_at'] as String),
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> clear() async {
    final prefs = await _prefs;
    for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
      await prefs.remove(key);
    }
  }
}

class InMemoryCacheStore implements CacheStore {
  final Map<String, CachedEntry> _entries = {};

  @override
  Future<void> write(String key, Object? json) async {
    _entries[key] = CachedEntry(data: json, savedAt: DateTime.now().toUtc());
  }

  @override
  Future<CachedEntry?> read(String key) async => _entries[key];

  @override
  Future<void> clear() async => _entries.clear();
}
