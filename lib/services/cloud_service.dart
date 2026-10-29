import 'sync_status.dart';
import 'app_log.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/cloud_defaults.dart';
import '../db/database_helper.dart';
import 'api/api_client.dart';
import 'api/http_client_factory.dart';
import 'api/token_store.dart';
import 'cloud/account_actions.dart';
import 'cloud/api_cloud_backend.dart';
import 'cloud/cloud_backend.dart';
import 'cloud/retired_cloud_settings.dart';
import 'cloud/premium_request_service.dart';
import 'backup_service.dart';
import 'portable_preferences_service.dart';
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

/// Storely's API is the only supported cloud backend.
enum CloudBackendMode { storelyApi }

class CloudConfig {
  final String url;
  const CloudConfig.api(this.url);

  bool get isValid {
    final uri = Uri.tryParse(url);
    return uri != null && uri.host.isNotEmpty && uri.scheme == 'https';
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
    this.mode = CloudBackendMode.storelyApi,
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

class CloudService with WidgetsBindingObserver implements AccountActions {
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
  bool _activationInProgress = false;

  /// True when sign-up is confirmed with a code typed into the app and passwords
  /// can be reset from the app (the Storely API), not by emailed link.
  bool get supportsEmailCodes => _backend?.supportsEmailCodes ?? false;

  Future<void> initialize() async {
    PortablePreferencesService.install();
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
    await retireLegacyCloudSettings(prefs);
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

  /// Enable Storely API access explicitly. Local-only use never enables it.
  Future<void> useStorelyCloud() async {
    if (!CloudDefaults.isAvailable) {
      throw StateError(
        'Cloud activation is not available in this build. Your data stays on this device.',
      );
    }
    final config = CloudConfig.api(
      CloudDefaults.apiUrl.replaceFirst(RegExp(r'/+$'), ''),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, CloudBackendMode.storelyApi.name);
    await prefs.remove(_urlKey);
    await prefs.remove(_anonKeyKey);
    await _startBackend(config, CloudBackendMode.storelyApi, reset: true);
    state.value = state.value.copyWith(
      config: config,
      mode: CloudBackendMode.storelyApi,
      user: _backend?.currentUser,
      message: 'Storely Cloud enabled',
      clearError: true,
    );
  }

  CloudBackendMode _readMode(SharedPreferences prefs) =>
      CloudBackendMode.storelyApi;

  CloudConfig? _resolveConfig(SharedPreferences prefs, CloudBackendMode mode) {
    // Only an explicitly saved API mode can reconnect. Legacy preferences never
    // migrate into an account or upload local records automatically.
    if (prefs.getString(_modeKey) != CloudBackendMode.storelyApi.name ||
        !CloudDefaults.isAvailable) {
      return null;
    }
    return CloudConfig.api(
      CloudDefaults.apiUrl.replaceFirst(RegExp(r'/+$'), ''),
    );
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

  @override
  Future<void> signIn(
    String email,
    String password, {
    bool syncAfterAuth = true,
  }) async {
    final user = await _requireBackend().signIn(email, password);
    _signedIn(user, 'Signed in', syncAfterAuth);
  }

  /// Second step of signing in, after [CloudMfaRequired].
  @override
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
  @override
  Future<void> verifyEmail(String email, String code) =>
      _requireBackend().verifyEmail(email, code);

  @override
  Future<void> resendVerificationCode(String email) =>
      _requireBackend().resendVerificationCode(email);

  /// Emails a code for resetting the password.
  @override
  Future<void> forgotPassword(String email) =>
      _requireBackend().forgotPassword(email);

  @override
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

  Future<bool> findWebPremiumRequest() async {
    final backend = _requireBackend() as ApiCloudBackend;
    final user = backend.currentUser;
    if (user == null) {
      throw StateError('Sign in with the account used on the web.');
    }
    final shopId = await DatabaseHelper.instance.currentShopId();
    final rows =
        (await backend.api.getJson('/v1/me/premium-requests'))['value'] as List;
    if (backend.currentUser?.id != user.id) {
      throw StateError('The account changed. Sign in and try again.');
    }
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      if (row['channel'] == 'web' &&
          row['request_kind'] == 'existing_android' &&
          row['local_shop_id'] == shopId) {
        await PremiumRequestService.instance.importWebRequest(
          row,
          shopId: shopId,
          userId: user.id,
        );
        return true;
      }
    }
    return false;
  }

  /// Activate only after explicit upload consent, keeping a durable local backup.
  Future<void> activatePremium() async {
    if (_activationInProgress || _syncInFlight != null) {
      throw StateError('Wait for the current sync to finish.');
    }
    final backend = _requireBackend() as ApiCloudBackend;
    final user = backend.currentUser;
    if (user == null) {
      throw StateError('Sign in with the account approved by the developer.');
    }
    final requests = PremiumRequestService.instance;
    final draft = await requests.load();
    if (draft == null) throw StateError('Submit a premium request first.');
    final body = draft['body'] as Map;
    if (draft['channel'] == 'web' && draft['requested_user'] != user.id) {
      throw StateError(
        'Sign in with the account that submitted this web request.',
      );
    }
    final shopId = await DatabaseHelper.instance.currentShopId();
    if (body['local_shop_id'] != shopId) {
      throw StateError('This request belongs to a different local shop.');
    }
    if (_syncInFlight != null) {
      throw StateError('Wait for the current sync to finish.');
    }
    _activationInProgress = true;
    try {
      final support = await getApplicationSupportDirectory();
      final folder = await Directory(
        '${support.path}/premium_backups/${DateTime.now().microsecondsSinceEpoch}',
      ).create(recursive: true);
      final backup = await BackupService.createBackupFile(workDir: folder);
      final response = draft['channel'] == 'web'
          ? await backend.api.postJson(
              '/v1/me/premium-requests/${body['id']}/claim-android',
              {'shop_id': shopId},
            )
          : await backend.api.postJson(
              '/v1/premium-requests/${body['id']}/claim',
              {'receipt_secret': body['receipt_secret']},
            );
      await requests.authorizeUpload(response, user.id, backup.path);
      state.value = state.value.copyWith(
        membership: CloudMembership.member,
        shopRole: 'owner',
        message: 'Premium activated. Uploading existing data…',
        clearError: true,
      );
    } finally {
      _activationInProgress = false;
    }
    await syncNow(
      reason: 'Premium activated',
      firstSyncMode: FirstSyncMode.uploadExisting,
    );
    if (state.value.error != null) throw StateError(state.value.error!);
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
    if (backend == null ||
        backend.currentUser == null ||
        _activationInProgress) {
      return;
    }
    // A request never authorizes upload. Even auth-restoration/background events
    // must wait for the approved account, local backup and explicit consent.
    if (CloudDefaults.apiAvailable) {
      Map<String, dynamic>? draft;
      try {
        draft = await PremiumRequestService.instance.load();
      } catch (error) {
        state.value = state.value.copyWith(
          error: 'Cannot read premium request safely: $error',
        );
        return;
      }
      if (draft != null &&
          (draft['body'] as Map)['local_shop_id'] ==
              await DatabaseHelper.instance.currentShopId()) {
        if (draft['upload_user'] != backend.currentUser!.id) {
          state.value = state.value.copyWith(
            membership: CloudMembership.needsRegistration,
            message: 'Open your premium request to activate cloud upload.',
          );
          return;
        }
        firstSyncMode ??= FirstSyncMode.uploadExisting;
      }
    }
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
        prepareUserData: (restoring) => PortablePreferencesService.prepare(
          backend.currentUser!.id,
          restoring: restoring,
        ),
        applyUserData: PortablePreferencesService.apply,
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
      // Entitlement expiry pauses transport, not the owner's offline business.
      // Resolve the current role through the unpaid control endpoint, including
      // a fresh sign-in whose local role has not been populated yet.
      if (error is ApiException && error.code == 'premium_required') {
        final role = await backend.fetchRole(
          await DatabaseHelper.instance.currentShopId(),
        );
        if (role != null) {
          state.value = state.value.copyWith(
            membership: CloudMembership.member,
            shopRole: role,
          );
        }
      }
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
        httpClient: createApiHttpClient(),
        tokens: SecureTokenStore(),
        userAgent: agent,
      ),
      preferredShopId: DatabaseHelper.instance.currentShopId,
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
