import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import 'app_settings_service.dart';
import 'home_section_prefs.dart';
import 'kpi_prefs.dart';
import 'portable_preference_keys.dart';

class _PreferenceProjection {
  final String shop;
  final String? user;
  final bool bound;
  const _PreferenceProjection(this.shop, this.user, this.bound);
  Map<String, Object?> get json => {'shop': shop, 'user': user, 'bound': bound};
}

/// One serialized projection of private cloud choices, separate from checkout's
/// durable preference_owner. Local explicit choices remain a device profile.
class PortablePreferencesService {
  static const _projectionKey = 'portable_projection_v1';
  static const _localKey = 'portable_local_choices_v1';
  static const _historyKey = 'portable_cloud_history_v1';
  static const _pendingKey = 'portable_pending_choices_v1';
  static Future<void> _tail = Future<void>.value();
  static Future<void> _ready = Future<void>.value();
  static _PreferenceProjection? _projection;
  static String? Function()? _authUser;

  static Future<void> _queue(Future<void> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.catchError((Object _) {});
    return next;
  }

  static void install({String? Function()? authUser}) {
    _authUser = authUser;
    _projection = null;
    _ready = _queue(_initialize);
    PortablePreferenceChanges.onChanged = _record;
  }

  static Future<void> ready() => _ready;

  static bool _valid(String key, Object? value) => switch (key) {
    'app_language' => {'system', 'en', 'hi'}.contains(value),
    'app_theme_preference' => {'system', 'light', 'dark'}.contains(value),
    'home_unpaid_sort' => {'newest', 'oldest', 'highest'}.contains(value),
    'billing_search_first' ||
    'home_unpaid_hidden' ||
    'home_attention_hidden' => value is bool,
    'home_unpaid_count' ||
    'home_attention_count' => value is int && value >= 1 && value <= 1000000,
    'analytics_enabled_kpis' =>
      value is List &&
          value.length <= 100 &&
          value.every((item) => item is String && item.length <= 100),
    _ => false,
  };

  static Map<String, Object> _choices(SharedPreferences prefs) => {
    for (final key in portablePreferenceKeys)
      if (_valid(key, prefs.get(key))) key: prefs.get(key)!,
  };

  static Map<String, Object> _local(SharedPreferences prefs) {
    try {
      final data = jsonDecode(prefs.getString(_localKey) ?? '{}');
      if (data is! Map<String, dynamic>) return {};
      return {
        for (final entry in data.entries)
          if (_valid(entry.key, entry.value)) entry.key: entry.value as Object,
      };
    } on Object {
      return {};
    }
  }

  static Map<String, dynamic> _pending(SharedPreferences prefs) {
    try {
      final data = jsonDecode(prefs.getString(_pendingKey) ?? '{}');
      return data is Map<String, dynamic> ? data : {};
    } on Object {
      return {};
    }
  }

  static Map<String, Object> _pendingValues(
    SharedPreferences prefs,
    String shop,
    String user,
  ) {
    final data = _pending(prefs)[jsonEncode([shop, user])];
    return data is Map
        ? {
            for (final key in portablePreferenceKeys)
              if (_valid(key, data[key])) key: data[key] as Object,
          }
        : {};
  }

  static Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final db = DatabaseHelper.instance;
    final shop = await db.currentShopId();
    final owner = await db.getCloudSyncState('preference_owner');
    try {
      final marker = jsonDecode(prefs.getString(_projectionKey) ?? 'null');
      if (marker is Map &&
          marker['shop'] is String &&
          marker['bound'] is bool &&
          (marker['user'] == null || marker['user'] is String)) {
        _projection = _PreferenceProjection(
          marker['shop'] as String,
          marker['user'] as String?,
          marker['bound'] as bool,
        );
      }
    } on Object {
      /* Unknown provenance remains local and is never adopted after cloud use. */
    }
    if (!prefs.containsKey(_localKey)) {
      // Adopt unscoped legacy keys only on a provably never-cloud device.
      // Prior private projections must not become guest or another user's data.
      await prefs.setString(
        _localKey,
        jsonEncode(
          owner == null &&
                  _projection?.user == null &&
                  !prefs.containsKey(_projectionKey) &&
                  prefs.get(_historyKey) != true
              ? _choices(prefs)
              : {},
        ),
      );
    }
    if (owner != null ||
        _projection?.user != null && _projection?.bound == true ||
        prefs.containsKey(_projectionKey) && _projection == null) {
      await prefs.setBool(_historyKey, true);
    }
    _projection ??= _PreferenceProjection(shop, null, false);
  }

  static Future<void> _remember(_PreferenceProjection scope) async {
    final current = _projection;
    _projection =
        current != null &&
            current.shop == scope.shop &&
            current.user == scope.user &&
            current.bound == scope.bound
        ? current
        : scope;
    await (await SharedPreferences.getInstance()).setString(
      _projectionKey,
      jsonEncode(scope.json),
    );
  }

  static Future<void> _project(Map<String, Object> values) async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in portablePreferenceKeys) {
      await prefs.remove(key);
    }
    for (final entry in values.entries) {
      await PortablePreferenceChanges.writeLocal(
        entry.key,
        entry.value is List
            ? List<String>.from(entry.value as List)
            : entry.value,
      );
    }
    await _reload();
  }

  static Future<void> _reload() async {
    await AppSettingsService.instance.reload();
    await HomeSectionPrefs.instance.reload();
    await KpiPrefs.instance.reload();
  }

  /// Auth events may change the visible profile, never checkout ownership.
  static Future<void> onAuthChanged(String? user) => _queue(() async {
    await _ready;
    if (_authUser != null && _authUser!() != user) return;
    final db = DatabaseHelper.instance;
    final shop = await db.currentShopId();
    final current = _projection;
    if (user != null &&
        current?.user == user &&
        current?.shop == shop &&
        current?.bound == true &&
        await db.getCloudSyncState('preference_owner') == user) {
      await _apply(current!);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await _remember(_PreferenceProjection(shop, user, false));
    await _project(
      user == null ? _local(prefs) : _pendingValues(prefs, shop, user),
    );
  });

  static Future<void> clearVisibleProjection({required String? expectedUser}) =>
      _queue(() async {
        if (_authUser != null && _authUser!() != expectedUser) return;
        await _project({});
      });

  static Future<void> _record(String key, Object value) {
    if (!_valid(key, value)) {
      throw ArgumentError('Invalid portable preference value');
    }
    final captured = _projection;
    final auth = _authUser?.call();
    final initialization = _ready;
    final snapshot = value is List ? List<String>.from(value) : value;
    return _queue(() async {
      await initialization;
      final scope = captured ?? _projection!;
      if (!identical(scope, _projection)) {
        throw StateError('Preference session changed before saving.');
      }
      if (_authUser != null && scope.user != auth) {
        throw StateError('Preference account changed before saving.');
      }
      final db = DatabaseHelper.instance;
      if (scope.bound) {
        await db.savePortablePreferenceForScope(
          key,
          jsonEncode(snapshot),
          shopId: scope.shop,
          userId: scope.user!,
        );
      } else {
        final prefs = await SharedPreferences.getInstance();
        if (scope.user == null) {
          await prefs.setString(
            _localKey,
            jsonEncode({..._local(prefs), key: snapshot}),
          );
        } else {
          final pending = _pending(prefs);
          pending[jsonEncode([scope.shop, scope.user])] = {
            ..._pendingValues(prefs, scope.shop, scope.user!),
            key: snapshot,
          };
          await prefs.setString(_pendingKey, jsonEncode(pending));
        }
      }
      await PortablePreferenceChanges.writeLocal(key, snapshot);
      await _remember(scope);
      await _reload();
    });
  }

  /// Seed only a proven first local adoption. Outgoing account projections
  /// never become another account's startup defaults.
  static Future<void> prepare(String userId, {required bool restoring}) =>
      _queue(() async {
        await _ready;
        if (_authUser != null && _authUser!() != userId) {
          throw StateError('Preference account changed during sync.');
        }
        final db = DatabaseHelper.instance;
        final prefs = await SharedPreferences.getInstance();
        final shop = await db.currentShopId();
        final previous = await db.getCloudSyncState('preference_owner');
        final adopting =
            !restoring &&
            previous == null &&
            prefs.get(_historyKey) != true &&
            _projection?.bound != true;
        await db.bindCloudUserData(userId, bindPreferences: adopting);
        if (adopting) {
          for (final entry in _local(prefs).entries) {
            await db.savePortablePreferenceForScope(
              entry.key,
              jsonEncode(entry.value),
              shopId: shop,
              userId: userId,
              onlyIfMissing: true,
            );
          }
        }
        await prefs.setBool(_historyKey, true);
        final scope = _PreferenceProjection(shop, userId, true);
        await _remember(scope);
        await _apply(scope);
      });

  static Future<void> apply() => _queue(() async {
    await _ready;
    final scope = _projection;
    if (scope?.bound != true) return;
    await _apply(scope!);
  });

  static Future<void> _apply(_PreferenceProjection scope) async {
    if (_authUser != null && _authUser!() != scope.user) return;
    final rows = await DatabaseHelper.instance.portablePreferencesForScope(
      shopId: scope.shop,
      userId: scope.user!,
    );
    final values = <String, Object>{};
    for (final row in rows) {
      final key = row['key'] as String;
      try {
        final value = jsonDecode(row['value'] as String);
        if (_valid(key, value)) values[key] = value as Object;
      } on Object {
        /* A malformed private value projects the native default. */
      }
    }
    if (_authUser != null && _authUser!() != scope.user) return;
    await _project(values);
  }
}
