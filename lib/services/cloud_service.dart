import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/database_helper.dart';

class CloudConfig {
  final String url;
  final String anonKey;

  const CloudConfig({required this.url, required this.anonKey});

  bool get isValid {
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty &&
        anonKey.trim().isNotEmpty;
  }
}

enum CloudSyncPhase { idle, syncing }

class CloudState {
  final CloudConfig? config;
  final User? user;
  final CloudSyncPhase phase;
  final DateTime? lastSyncedAt;
  final String? message;
  final String? error;

  const CloudState({
    this.config,
    this.user,
    this.phase = CloudSyncPhase.idle,
    this.lastSyncedAt,
    this.message,
    this.error,
  });

  bool get isConfigured => config != null;
  bool get isSignedIn => user != null;
  bool get isSyncing => phase == CloudSyncPhase.syncing;

  CloudState copyWith({
    CloudConfig? config,
    bool clearConfig = false,
    User? user,
    bool clearUser = false,
    CloudSyncPhase? phase,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
    String? message,
    bool clearMessage = false,
    String? error,
    bool clearError = false,
  }) {
    return CloudState(
      config: clearConfig ? null : config ?? this.config,
      user: clearUser ? null : user ?? this.user,
      phase: phase ?? this.phase,
      lastSyncedAt: clearLastSyncedAt
          ? null
          : lastSyncedAt ?? this.lastSyncedAt,
      message: clearMessage ? null : message ?? this.message,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class CloudService {
  CloudService._();

  static final instance = CloudService._();

  static const _urlKey = 'storely_cloud_url';
  static const _anonKeyKey = 'storely_cloud_anon_key';
  static const _lastSyncStateKey = 'last_successful_cloud_sync_at';
  static const _storelyShopId = 'local-shop';

  final state = ValueNotifier<CloudState>(const CloudState());
  final _connectivity = Connectivity();
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _clientReady = false;
  Future<void>? _syncInFlight;

  SupabaseClient? get client => _clientReady ? Supabase.instance.client : null;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_urlKey)?.trim();
    final anonKey = prefs.getString(_anonKeyKey)?.trim();
    final lastSync = await DatabaseHelper.instance.getCloudSyncState(
      _lastSyncStateKey,
    );
    final config =
        url == null || url.isEmpty || anonKey == null || anonKey.isEmpty
        ? null
        : CloudConfig(url: url, anonKey: anonKey);
    state.value = state.value.copyWith(
      config: config,
      lastSyncedAt: lastSync == null ? null : DateTime.tryParse(lastSync),
      clearError: true,
    );
    if (config != null) {
      await _initializeSupabase(config);
    }
    _connectivitySubscription ??= _connectivity.onConnectivityChanged.listen((
      results,
    ) {
      if (!results.contains(ConnectivityResult.none)) {
        syncNow(reason: 'Back online');
      }
    });
  }

  Future<void> saveConfig(CloudConfig config) async {
    final normalized = CloudConfig(
      url: config.url.trim().replaceFirst(RegExp(r'/+$'), ''),
      anonKey: config.anonKey.trim(),
    );
    if (!normalized.isValid) {
      throw ArgumentError('Supabase URL and anon key are required');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, normalized.url);
    await prefs.setString(_anonKeyKey, normalized.anonKey);
    await _initializeSupabase(normalized, reset: true);
    state.value = state.value.copyWith(
      config: normalized,
      user: client?.auth.currentUser,
      message: 'Cloud settings saved',
      clearError: true,
    );
  }

  Future<void> clearConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_urlKey);
    await prefs.remove(_anonKeyKey);
    await _authSubscription?.cancel();
    _authSubscription = null;
    if (_clientReady) {
      await Supabase.instance.dispose();
      _clientReady = false;
    }
    state.value = const CloudState(message: 'Cloud sync disabled');
  }

  Future<void> signIn(String email, String password) async {
    final activeClient = _requireClient();
    final response = await activeClient.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    state.value = state.value.copyWith(
      user: response.user ?? activeClient.auth.currentUser,
      message: 'Signed in',
      clearError: true,
    );
    unawaited(syncNow(reason: 'Signed in'));
  }

  Future<void> signUp(String email, String password) async {
    final activeClient = _requireClient();
    final response = await activeClient.auth.signUp(
      email: email.trim(),
      password: password,
    );
    state.value = state.value.copyWith(
      user: response.user ?? activeClient.auth.currentUser,
      message: response.session == null
          ? 'Account created. Confirm email if Supabase requires it.'
          : 'Account created',
      clearError: true,
    );
    if (response.session != null) {
      unawaited(syncNow(reason: 'Signed up'));
    }
  }

  Future<void> signOut() async {
    final activeClient = client;
    if (activeClient != null) {
      await activeClient.auth.signOut();
    }
    state.value = state.value.copyWith(
      clearUser: true,
      message: 'Signed out',
      clearError: true,
    );
  }

  Future<void> syncNow({String? reason}) {
    if (_syncInFlight != null) return _syncInFlight!;
    _syncInFlight = _sync(reason: reason).whenComplete(() {
      _syncInFlight = null;
    });
    return _syncInFlight!;
  }

  Future<void> _sync({String? reason}) async {
    final activeClient = client;
    if (activeClient == null || activeClient.auth.currentUser == null) return;
    final connected = await _connectivity.checkConnectivity();
    if (connected.contains(ConnectivityResult.none)) return;

    state.value = state.value.copyWith(
      phase: CloudSyncPhase.syncing,
      message: reason ?? 'Syncing',
      clearError: true,
    );
    try {
      await _ensureShopRowExists();
      final syncedAt = await CloudSyncEngine(
        client: activeClient,
        database: DatabaseHelper.instance,
      ).sync();
      state.value = state.value.copyWith(
        phase: CloudSyncPhase.idle,
        lastSyncedAt: syncedAt,
        message: 'Cloud sync complete',
        clearError: true,
      );
    } catch (error) {
      state.value = state.value.copyWith(
        phase: CloudSyncPhase.idle,
        error: error.toString(),
      );
    }
  }

  Future<void> _ensureShopRowExists() async {
    final profile = await DatabaseHelper.instance.getShopProfile();
    if (profile == null) return;
    await DatabaseHelper.instance.saveShopProfile(profile);
  }

  SupabaseClient _requireClient() {
    final activeClient = client;
    if (activeClient == null) {
      throw StateError('Cloud sync is not configured');
    }
    return activeClient;
  }

  Future<void> _initializeSupabase(
    CloudConfig config, {
    bool reset = false,
  }) async {
    if (_clientReady && reset) {
      await _authSubscription?.cancel();
      _authSubscription = null;
      await Supabase.instance.dispose();
      _clientReady = false;
    }
    if (!_clientReady) {
      await Supabase.initialize(url: config.url, anonKey: config.anonKey);
      _clientReady = true;
    }
    final activeClient = Supabase.instance.client;
    state.value = state.value.copyWith(user: activeClient.auth.currentUser);
    _authSubscription ??= activeClient.auth.onAuthStateChange.listen((data) {
      state.value = state.value.copyWith(user: data.session?.user);
      if (data.session?.user != null) {
        syncNow(reason: 'Auth restored');
      }
    });
  }
}

class CloudSyncEngine {
  final SupabaseClient client;
  final DatabaseHelper database;

  CloudSyncEngine({required this.client, required this.database});

  Future<DateTime> sync() async {
    final syncStartedAt = DateTime.now().toUtc();
    final lastSync = await database.getCloudSyncState(
      CloudService._lastSyncStateKey,
    );

    final createdCloudShop = await _ensureCloudAccess();
    final pullFirst = lastSync == null && !createdCloudShop;

    if (pullFirst) {
      for (final table in storelyCloudTables) {
        final rows = await _pullTable(table);
        await database.cloudImportRows(table, rows);
      }
      for (final table in storelyCloudTables) {
        await _pushTable(table, updatedAfter: syncStartedAt.toIso8601String());
      }
    } else {
      for (final table in storelyCloudTables) {
        await _pushTable(table, updatedAfter: lastSync);
      }
      for (final table in storelyCloudTables) {
        final rows = await _pullTable(table, updatedAfter: lastSync);
        await database.cloudImportRows(table, rows);
      }
    }

    await database.setCloudSyncState(
      CloudService._lastSyncStateKey,
      syncStartedAt.toIso8601String(),
    );
    return syncStartedAt;
  }

  Future<bool> _ensureCloudAccess() async {
    final user = client.auth.currentUser;
    if (user == null) return false;
    final memberships = await client
        .from('shop_members')
        .select('role')
        .eq('shop_id', CloudService._storelyShopId)
        .eq('user_id', user.id)
        .limit(1);
    if ((memberships as List).isNotEmpty) return false;

    final shops = await database.cloudExportRows('shops');
    if (shops.isEmpty) return false;
    final shop = shops.first;
    final shopId = shop['uuid']?.toString();
    if (shopId == null || shopId.isEmpty) return false;

    await client
        .from('shops')
        .upsert([shop], onConflict: 'uuid', ignoreDuplicates: true);
    await client.from('shop_members').insert({
      'shop_id': shopId,
      'user_id': user.id,
      'role': 'owner',
    });
    return true;
  }

  Future<void> _pushTable(String table, {String? updatedAfter}) async {
    final rows = await database.cloudExportRows(
      table,
      updatedAfter: updatedAfter,
    );
    if (rows.isEmpty) return;
    await client
        .from(table)
        .upsert(
          rows,
          onConflict: table == 'app_settings' ? 'shop_id,key' : 'uuid',
        );
  }

  Future<List<Map<String, dynamic>>> _pullTable(
    String table, {
    String? updatedAfter,
  }) async {
    dynamic query = client.from(table).select();
    if (updatedAfter != null) {
      query = query.gt('updated_at', updatedAfter);
    }
    final response = await query.order('updated_at', ascending: true);
    return (response as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }
}
