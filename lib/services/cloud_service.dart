import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/cloud_defaults.dart';
import '../db/database_helper.dart';

/// Which Supabase backend the app talks to.
///
/// [storelyHosted] uses the bundled [CloudDefaults] credentials (Option A —
/// zero setup for the user). [ownSupabase] uses URL + anon key the user pastes
/// in themselves (Option B — full data ownership).
enum CloudBackendMode { storelyHosted, ownSupabase }

/// A member of a cloud shop (joined with their profile email when available).
class ShopMember {
  final String userId;
  final String role;
  final String? email;
  final DateTime? joinedAt;

  const ShopMember({
    required this.userId,
    required this.role,
    this.email,
    this.joinedAt,
  });

  bool get isOwner => role == 'owner';

  factory ShopMember.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'];
    return ShopMember(
      userId: map['user_id']?.toString() ?? '',
      role: map['role']?.toString() ?? 'staff',
      email: profile is Map ? profile['email']?.toString() : null,
      joinedAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
    );
  }
}

/// A pending invite to a cloud shop.
class ShopInvite {
  final String id;
  final String email;
  final String role;
  final DateTime? createdAt;

  const ShopInvite({
    required this.id,
    required this.email,
    required this.role,
    this.createdAt,
  });

  factory ShopInvite.fromMap(Map<String, dynamic> map) {
    return ShopInvite(
      id: map['id']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      role: map['role']?.toString() ?? 'staff',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
    );
  }
}

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
enum FirstSyncMode { uploadExisting, startFresh }

class CloudState {
  final CloudConfig? config;
  final CloudBackendMode mode;
  final User? user;
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
    User? user,
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
  static const _lastSyncStateKey = 'last_successful_cloud_sync_at';

  final state = ValueNotifier<CloudState>(const CloudState());
  final _connectivity = Connectivity();
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _autoSyncTimer;
  Timer? _debounceTimer;
  bool _clientReady = false;
  Future<void>? _syncInFlight;

  SupabaseClient? get client => _clientReady ? Supabase.instance.client : null;

  Future<void> initialize() async {
    DatabaseHelper.instance.assertAdminMutation = () async {
      if (!state.value.isAdmin) {
        throw StateError(
          'Only a shop owner/admin can change catalog or store settings.',
        );
      }
    };
    DatabaseHelper.instance.isAdminMutationAllowed = () => state.value.isAdmin;
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
      await _initializeSupabase(config);
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

  /// Enable cloud sync against the Storely-hosted backend (Option A).
  ///
  /// Uses the bundled [CloudDefaults] credentials — the user never has to enter
  /// a URL or anon key.
  Future<void> useStorelyCloud() async {
    if (!CloudDefaults.isAvailable) {
      throw StateError(
        'Storely Cloud is not available in this build. Use your own Supabase project instead.',
      );
    }
    final config = CloudConfig(
      url: CloudDefaults.url.replaceFirst(RegExp(r'/+$'), ''),
      anonKey: CloudDefaults.anonKey,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, CloudBackendMode.storelyHosted.name);
    // Stored creds aren't needed for hosted mode; clear any stale own-Supabase
    // values so a later switch doesn't accidentally reuse them.
    await prefs.remove(_urlKey);
    await prefs.remove(_anonKeyKey);
    await _initializeSupabase(config, reset: true);
    state.value = state.value.copyWith(
      config: config,
      mode: CloudBackendMode.storelyHosted,
      user: client?.auth.currentUser,
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
    await _initializeSupabase(normalized, reset: true);
    state.value = state.value.copyWith(
      config: normalized,
      mode: CloudBackendMode.ownSupabase,
      user: client?.auth.currentUser,
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
    if (mode == CloudBackendMode.storelyHosted) {
      if (!CloudDefaults.isAvailable) return null;
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
    // Reset the first-sync watermark so reconnecting cloud is a true fresh
    // start: the upload-vs-fresh choice will be offered again, instead of the
    // device assuming everything was already synced.
    await DatabaseHelper.instance.clearCloudSyncState(_lastSyncStateKey);
    await _authSubscription?.cancel();
    _authSubscription = null;
    if (_clientReady) {
      await Supabase.instance.dispose();
      _clientReady = false;
    }
    state.value = const CloudState(message: 'Cloud sync disabled');
  }

  Future<void> signIn(
    String email,
    String password, {
    bool syncAfterAuth = true,
  }) async {
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
    if (syncAfterAuth) unawaited(syncNow(reason: 'Signed in'));
  }

  Future<void> signUp(
    String email,
    String password, {
    bool syncAfterAuth = true,
  }) async {
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
    if (syncAfterAuth && response.session != null) {
      unawaited(syncNow(reason: 'Signed up'));
    }
  }

  Future<bool> currentUserHasShopMembership() async {
    final activeClient = _requireClient();
    final user = activeClient.auth.currentUser;
    if (user == null) return false;
    final rows = await activeClient
        .from('shop_members')
        .select('shop_id')
        .eq('user_id', user.id)
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  /// Register the local shop in the cloud and make the signed-in user its
  /// owner (atomic via the create_shop RPC), then run a full sync.
  ///
  /// Used by the "Register your shop" flow when a signed-in owner belongs to no
  /// cloud shop yet.
  Future<void> registerShop() async {
    final activeClient = _requireClient();
    if (activeClient.auth.currentUser == null) {
      throw StateError('Sign in before registering a shop.');
    }
    final profile = await DatabaseHelper.instance.getShopProfile();
    final shopId = await DatabaseHelper.instance.currentShopId();
    await activeClient.rpc(
      'create_shop',
      params: {
        'target_shop_id': shopId,
        'shop_name': profile?.name ?? 'My Shop',
        'shop_phone': profile?.phone,
        'shop_email': profile?.email,
        'shop_gstin': profile?.gstin,
        'shop_address': profile?.address,
        'shop_created_at': profile?.createdAt.toIso8601String(),
        'shop_updated_at': profile?.updatedAt.toIso8601String(),
      },
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
    await DatabaseHelper.instance.clearCloudSyncState(_lastSyncStateKey);
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

  // ── Member management (owner/admin only; enforced by RLS) ──────────────

  /// Invite a person to the current shop by email. They sign up themselves and
  /// are linked on their first sync (see accept_invite). Owner/admin only.
  Future<void> inviteMember(String email, String role) async {
    final activeClient = _requireClient();
    final user = activeClient.auth.currentUser;
    if (user == null) throw StateError('Sign in first.');
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw ArgumentError('Enter a valid email address.');
    }
    final shopId = await DatabaseHelper.instance.currentShopId();
    await activeClient.from('shop_invites').insert({
      'shop_id': shopId,
      'email': normalizedEmail,
      'role': role,
      'invited_by': user.id,
    });
  }

  /// The current shop's members (owner/admin only — RLS gated).
  Future<List<ShopMember>> listMembers() async {
    final activeClient = _requireClient();
    final shopId = await DatabaseHelper.instance.currentShopId();
    final rows = await activeClient
        .from('shop_members')
        .select('user_id, role, created_at, profiles(email)')
        .eq('shop_id', shopId);
    return (rows as List)
        .map((row) => ShopMember.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  /// Pending (not yet accepted) invites for the current shop.
  Future<List<ShopInvite>> listPendingInvites() async {
    final activeClient = _requireClient();
    final shopId = await DatabaseHelper.instance.currentShopId();
    final rows = await activeClient
        .from('shop_invites')
        .select('id, email, role, created_at')
        .eq('shop_id', shopId)
        .filter('accepted_at', 'is', null);
    return (rows as List)
        .map((row) => ShopInvite.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  /// Change a member's role. Cannot target owners (RLS rejects). Owner/admin.
  Future<void> changeMemberRole(String userId, String role) async {
    final activeClient = _requireClient();
    final shopId = await DatabaseHelper.instance.currentShopId();
    await activeClient
        .from('shop_members')
        .update({'role': role})
        .eq('shop_id', shopId)
        .eq('user_id', userId);
  }

  /// Remove a member from the shop. Cannot remove owners (RLS rejects).
  Future<void> removeMember(String userId) async {
    final activeClient = _requireClient();
    final shopId = await DatabaseHelper.instance.currentShopId();
    await activeClient
        .from('shop_members')
        .delete()
        .eq('shop_id', shopId)
        .eq('user_id', userId);
  }

  /// Revoke a pending invite.
  Future<void> revokeInvite(String inviteId) async {
    final activeClient = _requireClient();
    await activeClient.from('shop_invites').delete().eq('id', inviteId);
  }

  Future<void> signOut() async {
    final activeClient = client;
    if (activeClient != null) {
      await activeClient.auth.signOut();
    }
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
        });
    return _syncInFlight!;
  }

  Future<void> _sync({String? reason, FirstSyncMode? firstSyncMode}) async {
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
      // When we already know the user's role locally (e.g. right after they
      // registered their own shop), pass it through so the engine doesn't depend
      // on a racy is_shop_admin round-trip to decide the first-sync upload.
      final knownRole = state.value.shopRole;
      final knownIsAdmin = knownRole == null
          ? null
          : (knownRole == 'owner' || knownRole == 'admin');
      final result = await CloudSyncEngine(
        client: activeClient,
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
      final role = await _fetchUserRole(activeClient);

      state.value = state.value.copyWith(
        phase: CloudSyncPhase.idle,
        membership: CloudMembership.member,
        firstSyncChoicePending: false,
        lastSyncedAt: result.syncedAt,
        shopRole: role,
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

  /// Query the user's role from cloud shop_members.
  Future<String?> _fetchUserRole(SupabaseClient activeClient) async {
    final user = activeClient.auth.currentUser;
    if (user == null) return null;
    try {
      final rows = await activeClient
          .from('shop_members')
          .select('role')
          .eq('shop_id', await DatabaseHelper.instance.currentShopId())
          .eq('user_id', user.id)
          .limit(1);
      if ((rows as List).isEmpty) return null;
      return rows.first['role']?.toString();
    } catch (_) {
      return null;
    }
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

/// Outcome of a sync attempt.
///
/// [syncedAt] is non-null only when a real sync ran. [needsRegistration] means
/// the user belongs to no shop yet. [needsFirstSyncChoice] means this is the
/// first sync and the device has existing local data, so the user must choose
/// whether to upload it or start fresh.
class CloudSyncResult {
  final DateTime? syncedAt;
  final bool needsRegistration;
  final bool needsFirstSyncChoice;

  const CloudSyncResult.synced(DateTime this.syncedAt)
    : needsRegistration = false,
      needsFirstSyncChoice = false;
  const CloudSyncResult.needsRegistration()
    : syncedAt = null,
      needsRegistration = true,
      needsFirstSyncChoice = false;
  const CloudSyncResult.needsFirstSyncChoice()
    : syncedAt = null,
      needsRegistration = false,
      needsFirstSyncChoice = true;
}

class CloudSyncEngine {
  final SupabaseClient client;
  final DatabaseHelper database;

  /// Locally-known admin status, set when the caller already knows the user is
  /// an owner/admin (e.g. immediately after registering their own shop). When
  /// non-null it takes precedence over the [_isShopAdmin] cloud round-trip,
  /// which can momentarily return false right after registration (RLS / role
  /// propagation) and would otherwise wrongly skip the first-sync upload.
  final bool? knownIsAdmin;

  CloudSyncEngine({
    required this.client,
    required this.database,
    this.knownIsAdmin,
  });

  static const _adminManagedTables = {
    'app_settings',
    'bill_settings',
    'categories',
    'units',
    'suppliers',
    'products',
    'invoice_series',
  };

  Future<CloudSyncResult> sync({FirstSyncMode? firstSyncMode}) async {
    final syncStartedAt = DateTime.now().toUtc();
    var shopId = await database.currentShopId();

    // Resolve which shop (if any) this user belongs to. Joining a shop the
    // user was invited to also happens here.
    final memberShopId = await _resolveMembershipShopId();

    // Signed in but attached to no shop and no pending invite → the app should
    // prompt the owner to register a shop. Stop cleanly (no RLS error).
    if (memberShopId == null) {
      return const CloudSyncResult.needsRegistration();
    }

    if (memberShopId != shopId) {
      if (await database.hasLocalBusinessDataForCloud()) {
        throw StateError(
          'This user belongs to a different cloud shop, but this device already has local business data. Export or clear local data before joining that shop.',
        );
      }
      await database.adoptCloudShopId(memberShopId);
      shopId = memberShopId;
    }
    final lastSync = await database.getCloudSyncState(
      CloudService._lastSyncStateKey,
    );

    // Prefer the locally-known role; only fall back to the cloud check when we
    // don't already know (avoids the post-registration race that skipped the
    // first-sync upload).
    final canPushAdminTables = knownIsAdmin ?? await _isShopAdmin(shopId);
    final pullFirst = lastSync == null;

    // First sync on a device that already has local data: the user must decide
    // whether to upload that data or start fresh. Ask once (unless they joined
    // an existing shop as staff, where cloud is the source of truth).
    if (pullFirst &&
        firstSyncMode == null &&
        canPushAdminTables &&
        await database.hasLocalBusinessDataForCloud()) {
      return const CloudSyncResult.needsFirstSyncChoice();
    }

    // Whether to push pre-existing local data on this first sync.
    final uploadExisting =
        pullFirst && firstSyncMode != FirstSyncMode.startFresh;

    // Pull shop data (all members can read).
    try {
      final shopRows = await _pullTable(
        'shops',
        shopId: shopId,
        updatedAfter: pullFirst ? null : lastSync,
      );
      await database.cloudImportRows('shops', shopRows);
    } catch (_) {
      // Staff might not see shop on first pull — not fatal.
    }

    // Push shop data only if user is admin/owner.
    await _pushShopIfAdmin(shopId);

    if (pullFirst) {
      for (final table in storelyCloudTables) {
        final rows = await _pullTable(table, shopId: shopId);
        await database.cloudImportRows(table, rows);
      }
      // uploadExisting → push ALL local rows (updatedAfter: null).
      // startFresh → push nothing now; only future edits sync (they will have
      // updated_at > syncStartedAt, picked up by the lastSync baseline below).
      if (uploadExisting) {
        for (final table in storelyCloudTables) {
          await _pushTable(
            table,
            updatedAfter: null,
            canPushAdminTables: canPushAdminTables,
          );
        }
      }
    } else {
      for (final table in storelyCloudTables) {
        final rows = await _pullTable(
          table,
          shopId: shopId,
          updatedAfter: lastSync,
        );
        await database.cloudImportRows(table, rows);
      }
      for (final table in storelyCloudTables) {
        await _pushTable(
          table,
          updatedAfter: lastSync,
          canPushAdminTables: canPushAdminTables,
        );
      }
    }

    await database.setCloudSyncState(
      CloudService._lastSyncStateKey,
      syncStartedAt.toIso8601String(),
    );
    return CloudSyncResult.synced(syncStartedAt);
  }

  /// Resolve which cloud shop the current user belongs to, or null when they
  /// belong to none.
  ///
  /// Order of checks (no implicit owner creation — registration is explicit):
  ///   1. Existing membership → return that shop id.
  ///   2. A pending invite → redeem it via accept_invite, then return the shop.
  ///   3. Otherwise null → caller prompts the owner to register a shop.
  Future<String?> _resolveMembershipShopId() async {
    final user = client.auth.currentUser;
    if (user == null) return null;

    // 1. Already a member?
    final rows = await client
        .from('shop_members')
        .select('shop_id')
        .eq('user_id', user.id)
        .limit(1);
    if ((rows as List).isNotEmpty) {
      final value = rows.first['shop_id']?.toString();
      if (value != null && value.isNotEmpty) return value;
    }

    // 2. Invited somewhere? Redeem the invite and join.
    final invitedShopId = await _pendingInviteShopId();
    if (invitedShopId != null) {
      final result = await client.rpc(
        'accept_invite',
        params: {'target_shop_id': invitedShopId},
      );
      if (result == 'joined' || result == 'already_member') {
        return invitedShopId;
      }
    }

    // 3. No membership, no invite.
    return null;
  }

  Future<String?> _pendingInviteShopId() async {
    try {
      final result = await client.rpc('my_pending_invite_shop');
      final value = result?.toString();
      return value == null || value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  /// Push shop data only if the current user is admin/owner.
  Future<void> _pushShopIfAdmin(String shopId) async {
    if (!await _isShopAdmin(shopId)) return; // Staff — skip shop push.
    final rows = await database.cloudExportRows('shops');
    if (rows.isEmpty) return;
    await client.from('shops').upsert(rows, onConflict: 'uuid');
  }

  Future<void> _pushTable(
    String table, {
    String? updatedAfter,
    required bool canPushAdminTables,
  }) async {
    if (_adminManagedTables.contains(table) && !canPushAdminTables) return;
    var rows = await database.cloudExportRows(
      table,
      updatedAfter: updatedAfter,
    );
    rows = await _onlyRowsNewerThanCloud(table, rows);
    if (rows.isEmpty) return;
    await client
        .from(table)
        .upsert(
          rows,
          onConflict: table == 'app_settings' ? 'shop_id,key' : 'uuid',
        );
  }

  Future<bool> _isShopAdmin(String shopId) async {
    try {
      final result = await client.rpc(
        'is_shop_admin',
        params: {'target_shop_id': shopId},
      );
      return result == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> _onlyRowsNewerThanCloud(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return rows;

    if (table == 'app_settings') {
      final shopIds = rows
          .map((row) => row['shop_id']?.toString())
          .whereType<String>()
          .toSet();
      final remoteRows = <Map<String, dynamic>>[];
      for (final shopId in shopIds) {
        final response = await client
            .from(table)
            .select('shop_id,key,updated_at')
            .eq('shop_id', shopId);
        remoteRows.addAll(
          (response as List).map(
            (row) => Map<String, dynamic>.from(row as Map),
          ),
        );
      }
      final remoteUpdatedByKey = {
        for (final row in remoteRows)
          '${row['shop_id']}::${row['key']}': row['updated_at']?.toString(),
      };
      return rows.where((row) {
        final key = '${row['shop_id']}::${row['key']}';
        return _timestampIsNewer(
          row['updated_at']?.toString(),
          remoteUpdatedByKey[key],
        );
      }).toList();
    }

    final uuids = rows
        .map((row) => row['uuid']?.toString())
        .whereType<String>()
        .where((uuid) => uuid.isNotEmpty)
        .toList();
    if (uuids.isEmpty) return rows;

    final remoteUpdatedByUuid = <String, String?>{};
    for (var start = 0; start < uuids.length; start += 100) {
      final end = start + 100 < uuids.length ? start + 100 : uuids.length;
      final response = await client
          .from(table)
          .select('uuid,updated_at')
          .inFilter('uuid', uuids.sublist(start, end));
      for (final row in response as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final uuid = map['uuid']?.toString();
        if (uuid != null && uuid.isNotEmpty) {
          remoteUpdatedByUuid[uuid] = map['updated_at']?.toString();
        }
      }
    }

    return rows.where((row) {
      final uuid = row['uuid']?.toString();
      if (uuid == null || uuid.isEmpty) return false;
      return _timestampIsNewer(
        row['updated_at']?.toString(),
        remoteUpdatedByUuid[uuid],
      );
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _pullTable(
    String table, {
    required String shopId,
    String? updatedAfter,
  }) async {
    dynamic query = client.from(table).select();
    if (table == 'shops') {
      query = query.eq('uuid', shopId);
    } else if (table != 'profiles') {
      query = query.eq('shop_id', shopId);
    }
    if (updatedAfter != null) {
      query = query.gt('updated_at', updatedAfter);
    }
    final response = await query.order('updated_at', ascending: true);
    return (response as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }
}

bool _timestampIsNewer(String? candidate, String? existing) {
  if (candidate == null || candidate.isEmpty) return false;
  if (existing == null || existing.isEmpty) return true;
  final candidateDate = DateTime.tryParse(candidate);
  final existingDate = DateTime.tryParse(existing);
  if (candidateDate != null && existingDate != null) {
    return candidateDate.isAfter(existingDate);
  }
  return candidate.compareTo(existing) > 0;
}
