import 'sync_status.dart';
import 'app_log.dart';
import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/cloud_defaults.dart';
import '../db/database_helper.dart';
import 'api/api_client.dart';
import 'api/token_store.dart';
import 'cloud/api_cloud_backend.dart';
import 'cloud/cloud_backend.dart';
import 'cloud/supabase_cloud_backend.dart';
import 'sync/cloud_sync_engine.dart';

export 'cloud/cloud_backend.dart'
    show
        CloudEmailNotVerified,
        CloudMfaRequired,
        CloudUser,
        ShopInvite,
        ShopMember,
        SignUpOutcome;
export 'sync/cloud_sync_engine.dart' show FirstSyncMode, CloudSyncResult;

/// Which cloud the app talks to.
///
/// [storelyApi] is Storely's own server (the default for new cloud users when
/// the build knows its address). [storelyHosted] uses the bundled [CloudDefaults]
/// Supabase credentials and [ownSupabase] a URL + anon key the user pastes in;
/// both are the original setup, kept until everyone has moved to the API.
enum CloudBackendMode { storelyHosted, ownSupabase, storelyApi }

extension CloudBackendModeX on CloudBackendMode {
  /// True for the options a user sees as "Storely Cloud" (not their own Supabase).
  bool get isStorelyCloud => this != CloudBackendMode.ownSupabase;
}

class CloudConfig {
  final String url;
  final String anonKey;

  /// True for the Storely API, which has no anon key and must be https.
  final bool isApi;

  const CloudConfig({required this.url, required this.anonKey}) : isApi = false;

  const CloudConfig.api(this.url) : anonKey = '', isApi = true;

  bool get isValid {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;
    if (isApi) return uri.scheme == 'https';
    return (uri.scheme == 'https' || uri.scheme == 'http') &&
        anonKey.trim().isNotEmpty;
  }
}

enum CloudSyncPhase { idle, syncing }

/// Where the signed-in user stands relative to a cloud shop.
///
/// [unknown] — not resolved yet (not signed in, or before first sync attempt).
/// [member] — belongs to a shop; normal sync applies.
/// [needsRegistration] — signed in but belongs to no shop and has no pending
/// invite. The UI should offer "Register your shop" (owner) instead of erroring.
enum CloudMembership { unknown, member, needsRegistration }

/// How to treat existing local data on the very first cloud sync.
///
/// [uploadExisting] — push all current local data up to the cloud.
/// [startFresh] — leave existing local data local-only; only data created/edited
/// after this point syncs.

class CloudState {
  final CloudConfig? config;
  final CloudBackendMode mode;
  final CloudUser? user;
  final CloudSyncPhase phase;
  final CloudMembership membership;

  /// True when the first sync found existing local data and is waiting for the
  /// user to choose upload-existing vs start-fresh.
  final bool firstSyncChoicePending;
  final DateTime? lastSyncedAt;
  final String? message;
  final String? error;

  /// The current user's role in the cloud shop: 'owner', 'admin', 'staff',
  /// or null when not signed in / not yet resolved.
  final String? shopRole;

  const CloudState({
    this.config,
    this.mode = CloudBackendMode.storelyHosted,
    this.user,
    this.phase = CloudSyncPhase.idle,
    this.membership = CloudMembership.unknown,
    this.firstSyncChoicePending = false,
    this.lastSyncedAt,
    this.message,
    this.error,
    this.shopRole,
  });

  bool get isConfigured => config != null;
  bool get isSignedIn => user != null;
  bool get isSyncing => phase == CloudSyncPhase.syncing;

  /// True when the user is signed in but not yet attached to any cloud shop —
  /// the app should prompt them to register a shop.
  bool get needsShopRegistration =>
      isSignedIn && membership == CloudMembership.needsRegistration;

  /// True when the signed-in user is an owner or admin of the cloud shop.
  /// Also true when cloud is not configured (local-only mode — no restrictions).
  bool get isAdmin =>
      !isConfigured ||
      !isSignedIn ||
      shopRole == 'owner' ||
      shopRole == 'admin';

  CloudState copyWith({
    CloudConfig? config,
    bool clearConfig = false,
    CloudBackendMode? mode,
    CloudUser? user,
    bool clearUser = false,
    CloudSyncPhase? phase,
    CloudMembership? membership,
    bool? firstSyncChoicePending,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
    String? message,
    bool clearMessage = false,
    String? error,
    bool clearError = false,
    String? shopRole,
    bool clearShopRole = false,
  }) {
    return CloudState(
      config: clearConfig ? null : config ?? this.config,
      mode: mode ?? this.mode,
      user: clearUser ? null : user ?? this.user,
      phase: phase ?? this.phase,
      membership: membership ?? this.membership,
      firstSyncChoicePending:
          firstSyncChoicePending ?? this.firstSyncChoicePending,
      lastSyncedAt: clearLastSyncedAt
          ? null
          : lastSyncedAt ?? this.lastSyncedAt,
      message: clearMessage ? null : message ?? this.message,
      error: clearError ? null : error ?? this.error,
      shopRole: clearShopRole ? null : shopRole ?? this.shopRole,
    );
  }
}

class CloudService with WidgetsBindingObserver {
  CloudService._();

  static final instance = CloudService._();

  static const _urlKey = 'storely_cloud_url';
  static const _anonKeyKey = 'storely_cloud_anon_key';
  static const _modeKey = 'storely_cloud_backend_mode';
  static const _apiUserKey = 'storely_api_last_user';
  static const _lastSyncStateKey = CloudSyncEngine.lastSyncStateKey;

  final state = ValueNotifier<CloudState>(const CloudState());
  final _connectivity = Connectivity();
  CloudBackend? _backend;
  StreamSubscription<CloudUser?>? _userSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _autoSyncTimer;
  Timer? _debounceTimer;
  Future<void>? _syncInFlight;

  /// True when sign-up is confirmed with a code typed into the app and passwords
  /// can be reset from the app (the Storely API), not by emailed link.
  bool get supportsEmailCodes => _backend?.supportsEmailCodes ?? false;

  Future<void> initialize() async {
    DatabaseHelper.instance.assertAdminMutation = () async {
      if (!state.value.isAdmin) {
        throw StateError(
          'Only a shop owner/admin can change catalog or store settings.',
        );
      }
    };
    DatabaseHelper.instance.isAdminMutationAllowed = () => state.value.isAdmin;
    DatabaseHelper.instance.auditActor = () => state.value.user?.email;
    final prefs = await SharedPreferences.getInstance();
    final mode = _readMode(prefs);
    final lastSync = await DatabaseHelper.instance.getCloudSyncState(
      _lastSyncStateKey,
    );
    final config = _resolveConfig(prefs, mode);
    state.value = state.value.copyWith(
      config: config,
      mode: mode,
      lastSyncedAt: lastSync == null ? null : DateTime.tryParse(lastSync),
      clearError: true,
    );
    if (config != null) {
      await _startBackend(config, mode);
    }
    _connectivitySubscription ??= _connectivity.onConnectivityChanged.listen((
      results,
    ) {
      if (!results.contains(ConnectivityResult.none)) {
        syncNow(reason: 'Back online');
      }
    });

    WidgetsBinding.instance.addObserver(this);
    _autoSyncTimer ??= Timer.periodic(const Duration(minutes: 3), (_) {
      if (state.value.isConfigured && state.value.isSignedIn) {
        syncNow(reason: 'Auto sync');
      }
    });

    DatabaseHelper.instance.onDatabaseChanged = () {
      if (!state.value.isConfigured || !state.value.isSignedIn) return;
      SyncStatus.instance.refresh();
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(seconds: 2), () {
        syncNow(reason: 'Local data changed');
      });
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (this.state.value.isConfigured && this.state.value.isSignedIn) {
        syncNow(reason: 'App resumed');
      }
    }
  }

  /// Enable cloud sync against Storely Cloud.
  ///
  /// Uses the Storely API when this build knows its address, otherwise the
  /// bundled [CloudDefaults] Supabase credentials. Either way the user never has
  /// to enter a URL or key.
  Future<void> useStorelyCloud() async {
    final CloudConfig config;
    final CloudBackendMode mode;
    if (CloudDefaults.apiAvailable) {
      config = CloudConfig.api(
        CloudDefaults.apiUrl.replaceFirst(RegExp(r'/+$'), ''),
      );
      mode = CloudBackendMode.storelyApi;
    } else if (CloudDefaults.supabaseAvailable) {
      config = CloudConfig(
        url: CloudDefaults.url.replaceFirst(RegExp(r'/+$'), ''),
        anonKey: CloudDefaults.anonKey,
      );
      mode = CloudBackendMode.storelyHosted;
    } else {
      throw StateError(
        'Storely Cloud is not available in this build. Use your own Supabase project instead.',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
    // Stored creds aren't needed for hosted modes; clear any stale own-Supabase
    // values so a later switch doesn't accidentally reuse them.
    await prefs.remove(_urlKey);
    await prefs.remove(_anonKeyKey);
    await _startBackend(config, mode, reset: true);
    state.value = state.value.copyWith(
      config: config,
      mode: mode,
      user: _backend?.currentUser,
      message: 'Storely Cloud enabled',
      clearError: true,
    );
  }

  /// Enable cloud sync against the user's own Supabase project (Option B).
  Future<void> saveConfig(CloudConfig config) async {
    final normalized = CloudConfig(
      url: config.url.trim().replaceFirst(RegExp(r'/+$'), ''),
      anonKey: config.anonKey.trim(),
    );
    if (!normalized.isValid) {
      throw ArgumentError('Supabase URL and anon key are required');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, CloudBackendMode.ownSupabase.name);
    await prefs.setString(_urlKey, normalized.url);
    await prefs.setString(_anonKeyKey, normalized.anonKey);
    await _startBackend(normalized, CloudBackendMode.ownSupabase, reset: true);
    state.value = state.value.copyWith(
      config: normalized,
      mode: CloudBackendMode.ownSupabase,
      user: _backend?.currentUser,
      message: 'Cloud settings saved',
      clearError: true,
    );
  }

  CloudBackendMode _readMode(SharedPreferences prefs) {
    final stored = prefs.getString(_modeKey);
    return CloudBackendMode.values.firstWhere(
      (m) => m.name == stored,
      orElse: () => CloudBackendMode.ownSupabase,
    );
  }

  /// Resolve the active [CloudConfig] for [mode], or null when not configured.
  CloudConfig? _resolveConfig(SharedPreferences prefs, CloudBackendMode mode) {
    if (mode == CloudBackendMode.storelyApi) {
      if (!CloudDefaults.apiAvailable) return null;
      return CloudConfig.api(
        CloudDefaults.apiUrl.replaceFirst(RegExp(r'/+$'), ''),
      );
    }
    if (mode == CloudBackendMode.storelyHosted) {
      if (!CloudDefaults.supabaseAvailable) return null;
      return CloudConfig(
        url: CloudDefaults.url.replaceFirst(RegExp(r'/+$'), ''),
        anonKey: CloudDefaults.anonKey,
      );
    }
    final url = prefs.getString(_urlKey)?.trim();
    final anonKey = prefs.getString(_anonKeyKey)?.trim();
    if (url == null || url.isEmpty || anonKey == null || anonKey.isEmpty) {
      return null;
    }
    return CloudConfig(url: url, anonKey: anonKey);
  }

  Future<void> clearConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_urlKey);
    await prefs.remove(_anonKeyKey);
    await prefs.remove(_modeKey);
    await prefs.remove(_apiUserKey);
    // Reset the first-sync watermark so reconnecting cloud is a true fresh
    // start: the upload-vs-fresh choice will be offered again, instead of the
    // device assuming everything was already synced.
    await CloudSyncEngine.resetProgress(DatabaseHelper.instance);
    final backend = _backend;
    if (backend is ApiCloudBackend) {
      // Turning cloud off should also end this phone's session on the server.
      try {
        await backend.signOut();
      } on Object {
        // Offline: the token is wiped locally either way.
      }
    }
    await _stopBackend();
    state.value = const CloudState(message: 'Cloud sync disabled');
  }

  Future<void> signIn(
    String email,
    String password, {
    bool syncAfterAuth = true,
  }) async {
    final user = await _requireBackend().signIn(email, password);
    _signedIn(user, 'Signed in', syncAfterAuth);
  }

  /// Second step of signing in, after [CloudMfaRequired].
  Future<void> completeMfa(String code, {bool syncAfterAuth = true}) async {
    final user = await _requireBackend().completeMfa(code);
    _signedIn(user, 'Signed in', syncAfterAuth);
  }

  Future<SignUpOutcome> signUp(
    String email,
    String password, {
    bool syncAfterAuth = true,
  }) async {
    final result = await _requireBackend().signUp(email, password);
    state.value = state.value.copyWith(
      user: result.user,
      message: switch (result.outcome) {
        SignUpOutcome.signedIn => 'Account created',
        SignUpOutcome.confirmByEmailLink =>
          'Account created. Confirm email if Supabase requires it.',
        SignUpOutcome.emailCodeSent =>
          'Account created. Enter the code we emailed you.',
      },
      clearError: true,
    );
    if (syncAfterAuth && result.outcome == SignUpOutcome.signedIn) {
      unawaited(syncNow(reason: 'Signed up'));
    }
    return result.outcome;
  }

  /// Confirms a new account with the 6-digit code that was emailed.
  Future<void> verifyEmail(String email, String code) =>
      _requireBackend().verifyEmail(email, code);

  Future<void> resendVerificationCode(String email) =>
      _requireBackend().resendVerificationCode(email);

  /// Emails a code for resetting the password.
  Future<void> forgotPassword(String email) =>
      _requireBackend().forgotPassword(email);

  Future<void> resetPassword(String email, String code, String newPassword) =>
      _requireBackend().resetPassword(email, code, newPassword);

  void _signedIn(CloudUser user, String message, bool syncAfterAuth) {
    state.value = state.value.copyWith(
      user: user,
      message: message,
      clearError: true,
    );
    if (syncAfterAuth) unawaited(syncNow(reason: message));
  }

  Future<bool> currentUserHasShopMembership() async {
    final backend = _requireBackend();
    if (backend.currentUser == null) return false;
    return backend.hasShopMembership();
  }

  /// Register the local shop in the cloud and make the signed-in user its
  /// owner (atomic on the server), then run a full sync.
  ///
  /// Used by the "Register your shop" flow when a signed-in owner belongs to no
  /// cloud shop yet.
  Future<void> registerShop() async {
    final backend = _requireBackend();
    if (backend.currentUser == null) {
      throw StateError('Sign in before registering a shop.');
    }
    final profile = await DatabaseHelper.instance.getShopProfile();
    final shopId = await DatabaseHelper.instance.currentShopId();
    await backend.registerShop(
      ShopRegistration(
        shopId: shopId,
        name: profile?.name ?? 'My Shop',
        phone: profile?.phone,
        email: profile?.email,
        gstin: profile?.gstin,
        address: profile?.address,
        createdAt: profile?.createdAt,
        updatedAt: profile?.updatedAt,
      ),
    );
    state.value = state.value.copyWith(
      membership: CloudMembership.member,
      shopRole: 'owner',
      message: 'Shop registered',
      clearError: true,
    );
    await syncNow(reason: 'Shop registered');
  }

  /// Lets an existing owner/admin member re-offer the first-sync data choice.
  ///
  /// Resets the local sync baseline so the next sync is treated as a first sync.
  /// Use this when a device already belongs to a cloud shop but local data was
  /// never uploaded (e.g. an earlier sync finalized without pushing). Re-running
  /// sync will surface the "upload existing vs start fresh" prompt again.
  Future<void> resyncExistingData() async {
    await CloudSyncEngine.resetProgress(DatabaseHelper.instance);
    state.value = state.value.copyWith(
      clearLastSyncedAt: true,
      message: 'Checking existing data…',
      clearError: true,
    );
    await syncNow(reason: 'Re-checking existing data');
  }

  /// Resolve the first-sync data choice: upload existing local data, or start
  /// fresh (existing data stays local-only). Runs the sync with that decision.
  Future<void> chooseFirstSync(FirstSyncMode mode) async {
    state.value = state.value.copyWith(firstSyncChoicePending: false);
    await syncNow(
      reason: mode == FirstSyncMode.uploadExisting
          ? 'Uploading existing data'
          : 'Starting fresh',
      firstSyncMode: mode,
    );
  }

  // ── Member management (owner/admin only; enforced by the server) ───────

  /// Invite a person to the current shop by email. They sign up themselves and
  /// are linked on their first sync. Owner/admin only.
  Future<void> inviteMember(String email, String role) async {
    final backend = _requireBackend();
    if (backend.currentUser == null) throw StateError('Sign in first.');
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw ArgumentError('Enter a valid email address.');
    }
    await backend.inviteMember(
      await DatabaseHelper.instance.currentShopId(),
      normalizedEmail,
      role,
    );
  }

  /// The current shop's members (owner/admin only).
  Future<List<ShopMember>> listMembers() async => _requireBackend().listMembers(
    await DatabaseHelper.instance.currentShopId(),
  );

  /// Pending (not yet accepted) invites for the current shop.
  Future<List<ShopInvite>> listPendingInvites() async => _requireBackend()
      .listPendingInvites(await DatabaseHelper.instance.currentShopId());

  /// Change a member's role. Cannot target owners. Owner/admin.
  Future<void> changeMemberRole(String userId, String role) async =>
      _requireBackend().changeMemberRole(
        await DatabaseHelper.instance.currentShopId(),
        userId,
        role,
      );

  /// Remove a member from the shop. Cannot remove owners.
  Future<void> removeMember(String userId) async => _requireBackend()
      .removeMember(await DatabaseHelper.instance.currentShopId(), userId);

  /// Revoke a pending invite.
  Future<void> revokeInvite(String inviteId) async => _requireBackend()
      .revokeInvite(await DatabaseHelper.instance.currentShopId(), inviteId);

  Future<void> signOut() async {
    final backend = _backend;
    if (backend != null) {
      await backend.signOut();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiUserKey);
    state.value = state.value.copyWith(
      clearUser: true,
      clearShopRole: true,
      message: 'Signed out',
      clearError: true,
    );
  }

  Future<void> syncNow({String? reason, FirstSyncMode? firstSyncMode}) {
    if (_syncInFlight != null) return _syncInFlight!;
    _syncInFlight = _sync(reason: reason, firstSyncMode: firstSyncMode)
        .whenComplete(() {
          _syncInFlight = null;
          SyncStatus.instance.refresh();
        });
    return _syncInFlight!;
  }

  Future<void> _sync({String? reason, FirstSyncMode? firstSyncMode}) async {
    final backend = _backend;
    if (backend == null || backend.currentUser == null) return;
    final connected = await _connectivity.checkConnectivity();
    if (connected.contains(ConnectivityResult.none)) return;

    state.value = state.value.copyWith(
      phase: CloudSyncPhase.syncing,
      message: reason ?? 'Syncing',
      clearError: true,
    );
    try {
      // When we already know the user's role locally (e.g. right after they
      // registered their own shop), pass it through so the engine doesn't depend
      // on a racy is_shop_admin round-trip to decide the first-sync upload.
      final knownRole = state.value.shopRole;
      final knownIsAdmin = knownRole == null
          ? null
          : (knownRole == 'owner' || knownRole == 'admin');
      final result = await CloudSyncEngine(
        backend: backend.sync,
        database: DatabaseHelper.instance,
        knownIsAdmin: knownIsAdmin,
      ).sync(firstSyncMode: firstSyncMode);

      if (result.needsRegistration) {
        state.value = state.value.copyWith(
          phase: CloudSyncPhase.idle,
          membership: CloudMembership.needsRegistration,
          clearShopRole: true,
          message: 'Register your shop to start syncing',
          clearError: true,
        );
        return;
      }

      if (result.needsFirstSyncChoice) {
        // Membership is established; we just need the user's data choice.
        state.value = state.value.copyWith(
          phase: CloudSyncPhase.idle,
          membership: CloudMembership.member,
          firstSyncChoicePending: true,
          message: 'Choose how to sync your existing data',
          clearError: true,
        );
        return;
      }

      // Fetch the user's role after sync completes.
      final role = await backend.fetchRole(
        await DatabaseHelper.instance.currentShopId(),
      );

      state.value = state.value.copyWith(
        phase: CloudSyncPhase.idle,
        membership: CloudMembership.member,
        firstSyncChoicePending: false,
        lastSyncedAt: result.syncedAt,
        shopRole: role,
        message: result.conflicts.isEmpty
            ? 'Cloud sync complete'
            : 'Synced. ${result.conflicts.length} change(s) could not sync',
        clearError: true,
      );
    } catch (error, stack) {
      AppLog.error('Sync', error, stack);
      state.value = state.value.copyWith(
        phase: CloudSyncPhase.idle,
        error: error.toString(),
      );
    }
  }

  CloudBackend _requireBackend() {
    final backend = _backend;
    if (backend == null) {
      throw StateError('Cloud sync is not configured');
    }
    return backend;
  }

  Future<void> _stopBackend() async {
    await _userSubscription?.cancel();
    _userSubscription = null;
    final backend = _backend;
    _backend = null;
    if (backend != null) await backend.dispose();
  }

  Future<CloudBackend> _createBackend(
    CloudConfig config,
    CloudBackendMode mode,
  ) async {
    if (mode != CloudBackendMode.storelyApi) {
      return SupabaseCloudBackend.start(config.url, config.anonKey);
    }
    var agent = 'StorelyApp';
    try {
      final info = await PackageInfo.fromPlatform();
      agent = 'StorelyApp/${info.version}+${info.buildNumber}';
    } on Object {
      // A missing version only costs a less specific label in the sign-in alert.
    }
    return ApiCloudBackend(
      ApiClient(
        baseUrl: Uri.parse(config.url),
        httpClient: http.Client(),
        tokens: SecureTokenStore(),
        userAgent: agent,
      ),
    );
  }

  Future<void> _startBackend(
    CloudConfig config,
    CloudBackendMode mode, {
    bool reset = false,
  }) async {
    if (_backend != null && reset) await _stopBackend();
    _backend ??= await _createBackend(config, mode);
    final backend = _backend!;
    if (backend is ApiCloudBackend) await _restoreApiSession(backend);
    state.value = state.value.copyWith(
      user: backend.currentUser,
      clearUser: backend.currentUser == null,
    );
    _userSubscription ??= backend.userChanges.listen((user) {
      state.value = user == null
          ? state.value.copyWith(clearUser: true)
          : state.value.copyWith(user: user);
      if (backend is ApiCloudBackend) unawaited(_rememberApiUser(user));
      if (user != null) syncNow(reason: 'Auth restored');
    });
  }

  /// Picks up the session a previous launch left behind. With no network the
  /// last known person is shown as signed in (their token is exchanged on the
  /// first request that has signal); if the server says the session is over,
  /// they are signed out.
  Future<void> _restoreApiSession(ApiCloudBackend backend) async {
    final api = backend.api;
    if (api.user != null || !await api.hasStoredSession()) return;
    try {
      await api.restoreSession();
    } on Object {
      final cached = await _readApiUser();
      if (cached != null) api.adoptUser(cached);
    }
  }

  Future<void> _rememberApiUser(CloudUser? user) async {
    final prefs = await SharedPreferences.getInstance();
    if (user == null) {
      await prefs.remove(_apiUserKey);
    } else {
      await prefs.setString(
        _apiUserKey,
        jsonEncode({'id': user.id, 'email': user.email}),
      );
    }
  }

  Future<ApiUser?> _readApiUser() async {
    final raw = (await SharedPreferences.getInstance()).getString(_apiUserKey);
    if (raw == null) return null;
    try {
      return ApiUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }
}
