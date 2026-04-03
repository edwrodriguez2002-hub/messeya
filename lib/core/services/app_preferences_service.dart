import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config/release_features.dart';
import '../../shared/models/remembered_account.dart';
import '../../shared/models/chat.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences no inicializadas');
});

final appPreferencesServiceProvider = Provider<AppPreferencesService>((ref) {
  return AppPreferencesService(ref.watch(sharedPreferencesProvider));
});

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  return ThemeModeController(ref.watch(appPreferencesServiceProvider));
});

final appLockControllerProvider =
    StateNotifierProvider<AppLockController, bool>((ref) {
  return AppLockController(ref.watch(appPreferencesServiceProvider));
});

final emailOtpSessionProvider =
    StateNotifierProvider<EmailOtpSessionController, EmailOtpSession>((ref) {
  return EmailOtpSessionController(ref.watch(appPreferencesServiceProvider));
});

final rememberedAccountsProvider =
    StateNotifierProvider<RememberedAccountsController, List<RememberedAccount>>(
  (ref) => RememberedAccountsController(ref.watch(appPreferencesServiceProvider)),
);

final activeSessionViewProvider =
    StateNotifierProvider<ActiveSessionViewController, String>(
  (ref) => ActiveSessionViewController(ref.watch(appPreferencesServiceProvider)),
);

final activeAccountUidProvider =
    StateNotifierProvider<ActiveAccountUidController, String>(
  (ref) => ActiveAccountUidController(ref.watch(appPreferencesServiceProvider)),
);

final cachedChatsProvider =
    StateNotifierProvider<CachedChatsController, Map<String, List<Chat>>>(
  (ref) => CachedChatsController(ref.watch(appPreferencesServiceProvider)),
);

class EmailOtpSession {
  const EmailOtpSession({
    this.pending = false,
    this.challengeId = '',
    this.email = '',
    this.expiresAtMs = 0,
    this.devCodePreview = '',
  });

  final bool pending;
  final String challengeId;
  final String email;
  final int expiresAtMs;
  final String devCodePreview;

  DateTime? get expiresAt => expiresAtMs <= 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(expiresAtMs);
  bool get isExpired =>
      expiresAtMs > 0 && DateTime.now().millisecondsSinceEpoch > expiresAtMs;
  bool get isActivePending => pending && !isExpired && challengeId.isNotEmpty;

  EmailOtpSession copyWith({
    bool? pending,
    String? challengeId,
    String? email,
    int? expiresAtMs,
    String? devCodePreview,
  }) {
    return EmailOtpSession(
      pending: pending ?? this.pending,
      challengeId: challengeId ?? this.challengeId,
      email: email ?? this.email,
      expiresAtMs: expiresAtMs ?? this.expiresAtMs,
      devCodePreview: devCodePreview ?? this.devCodePreview,
    );
  }
}

class AppPreferencesService {
  AppPreferencesService(this._preferences);

  final SharedPreferences _preferences;

  static const _themeModeKey = 'theme_mode';
  static const _notificationsKey = 'notifications_enabled';
  static const _readReceiptsKey = 'read_receipts_enabled';
  static const _autoDownloadKey = 'media_auto_download_enabled';
  static const _discreetPreviewKey = 'discreet_preview_enabled';
  static const _pinKey = 'app_pin_lock';
  static const _biometricKey = 'biometric_lock_enabled';
  static const _dmRequestLimitKey = 'dm_request_limit';
  static const _dmArchiveRejectedKey = 'dm_archive_rejected';
  static const _dmOnlyUntrustedKey = 'dm_only_untrusted';
  static const _emailOtpPendingKey = 'email_otp_pending';
  static const _emailOtpChallengeIdKey = 'email_otp_challenge_id';
  static const _emailOtpEmailKey = 'email_otp_email';
  static const _emailOtpExpiresKey = 'email_otp_expires_at_ms';
  static const _emailOtpDevCodeKey = 'email_otp_dev_code';
  static const _desktopPairingSessionIdKey = 'desktop_pairing_session_id';
  static const _desktopLinkedDeviceIdKey = 'desktop_linked_device_id';
  static const _desktopLinkedOwnerUidKey = 'desktop_linked_owner_uid';
  static const _desktopLinkedOwnerNameKey = 'desktop_linked_owner_name';
  static const _desktopLinkedOwnerUsernameKey = 'desktop_linked_owner_username';
  static const _hybridEnabledKey = 'hybrid_enabled';
  static const _hybridRelayEnabledKey = 'hybrid_relay_enabled';
  static const _hybridGatewayEnabledKey = 'hybrid_gateway_enabled';
  static const _hybridRelayTermsAcceptedKey = 'hybrid_relay_terms_accepted';
  static const _rememberedAccountsKey = 'remembered_accounts_v1';
  static const _activeSessionViewKey = 'active_session_view';
  static const _activeAccountUidKey = 'active_account_uid';
  static const _cachedChatsPrefix = 'cached_chats_v1_';
  static const _localDeviceIdKey = 'local_device_id_v1';

  // --- NUEVAS CLAVES PARA CORREO MODERNO ---
  static const _userSignatureKey = 'user_professional_signature';
  static const _draftSubjectPrefix = 'draft_subject_';
  static const _draftBodyPrefix = 'draft_body_';

  // --- MÉTODOS DE FIRMA ---
  String getUserSignature() => _preferences.getString(_userSignatureKey) ?? '';
  Future<void> setUserSignature(String value) => _preferences.setString(_userSignatureKey, value);

  // --- MÉTODOS DE BORRADORES ---
  Future<void> saveDraft(String chatId, String subject, String body) async {
    await _preferences.setString('$_draftSubjectPrefix$chatId', subject);
    await _preferences.setString('$_draftBodyPrefix$chatId', body);
  }

  Map<String, String> getDraft(String chatId) {
    return {
      'subject': _preferences.getString('$_draftSubjectPrefix$chatId') ?? '',
      'body': _preferences.getString('$_draftBodyPrefix$chatId') ?? '',
    };
  }

  Future<void> clearDraft(String chatId) async {
    await _preferences.remove('$_draftSubjectPrefix$chatId');
    await _preferences.remove('$_draftBodyPrefix$chatId');
  }

  // --- MÉTODOS EXISTENTES ---
  ThemeMode getThemeMode() {
    final value = _preferences.getString(_themeModeKey);
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) {
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    };
    return _preferences.setString(_themeModeKey, value);
  }

  bool getNotificationsEnabled() =>
      _preferences.getBool(_notificationsKey) ?? true;

  Future<void> setNotificationsEnabled(bool value) {
    return _preferences.setBool(_notificationsKey, value);
  }

  bool getReadReceiptsEnabled() =>
      _preferences.getBool(_readReceiptsKey) ?? true;

  Future<void> setReadReceiptsEnabled(bool value) {
    return _preferences.setBool(_readReceiptsKey, value);
  }

  bool getMediaAutoDownloadEnabled() =>
      _preferences.getBool(_autoDownloadKey) ?? true;

  Future<void> setMediaAutoDownloadEnabled(bool value) {
    return _preferences.setBool(_autoDownloadKey, value);
  }

  bool getDiscreetPreviewEnabled() =>
      _preferences.getBool(_discreetPreviewKey) ?? false;

  Future<void> setDiscreetPreviewEnabled(bool value) {
    return _preferences.setBool(_discreetPreviewKey, value);
  }

  String getAppPin() => _preferences.getString(_pinKey) ?? '';

  Future<void> setAppPin(String value) {
    return _preferences.setString(_pinKey, value);
  }

  Future<void> clearAppPin() {
    return _preferences.remove(_pinKey);
  }

  bool getBiometricEnabled() => _preferences.getBool(_biometricKey) ?? false;

  Future<void> setBiometricEnabled(bool value) {
    return _preferences.setBool(_biometricKey, value);
  }

  int getDirectMessageRequestLimit() =>
      _preferences.getInt(_dmRequestLimitKey) ?? 3;

  Future<void> setDirectMessageRequestLimit(int value) {
    return _preferences.setInt(_dmRequestLimitKey, value.clamp(1, 10));
  }

  bool getArchiveRejectedRequests() =>
      _preferences.getBool(_dmArchiveRejectedKey) ?? true;

  Future<void> setArchiveRejectedRequests(bool value) {
    return _preferences.setBool(_dmArchiveRejectedKey, value);
  }

  bool getOnlyRequestForUntrustedContacts() =>
      _preferences.getBool(_dmOnlyUntrustedKey) ?? true;

  Future<void> setOnlyRequestForUntrustedContacts(bool value) {
    return _preferences.setBool(_dmOnlyUntrustedKey, value);
  }

  EmailOtpSession getEmailOtpSession() {
    return EmailOtpSession(
      pending: _preferences.getBool(_emailOtpPendingKey) ?? false,
      challengeId: _preferences.getString(_emailOtpChallengeIdKey) ?? '',
      email: _preferences.getString(_emailOtpEmailKey) ?? '',
      expiresAtMs: _preferences.getInt(_emailOtpExpiresKey) ?? 0,
      devCodePreview: _preferences.getString(_emailOtpDevCodeKey) ?? '',
    );
  }

  Future<void> setEmailOtpSession(EmailOtpSession session) async {
    await _preferences.setBool(_emailOtpPendingKey, session.pending);
    await _preferences.setString(_emailOtpChallengeIdKey, session.challengeId);
    await _preferences.setString(_emailOtpEmailKey, session.email);
    await _preferences.setInt(_emailOtpExpiresKey, session.expiresAtMs);
    await _preferences.setString(_emailOtpDevCodeKey, session.devCodePreview);
  }

  Future<void> clearEmailOtpSession() async {
    await _preferences.remove(_emailOtpPendingKey);
    await _preferences.remove(_emailOtpChallengeIdKey);
    await _preferences.remove(_emailOtpEmailKey);
    await _preferences.remove(_emailOtpExpiresKey);
    await _preferences.remove(_emailOtpDevCodeKey);
  }

  String getDesktopPairingSessionId() =>
      _preferences.getString(_desktopPairingSessionIdKey) ?? '';

  Future<void> setDesktopPairingSessionId(String value) {
    return _preferences.setString(_desktopPairingSessionIdKey, value);
  }

  Future<void> clearDesktopPairingSessionId() {
    return _preferences.remove(_desktopPairingSessionIdKey);
  }

  String getDesktopLinkedDeviceId() =>
      _preferences.getString(_desktopLinkedDeviceIdKey) ?? '';

  Future<void> setDesktopLinkedDeviceId(String value) {
    return _preferences.setString(_desktopLinkedDeviceIdKey, value);
  }

  Future<void> clearDesktopLinkedDeviceId() {
    return _preferences.remove(_desktopLinkedDeviceIdKey);
  }

  String getDesktopLinkedOwnerUid() =>
      _preferences.getString(_desktopLinkedOwnerUidKey) ?? '';

  Future<void> setDesktopLinkedOwnerUid(String value) {
    return _preferences.setString(_desktopLinkedOwnerUidKey, value);
  }

  String getDesktopLinkedOwnerName() =>
      _preferences.getString(_desktopLinkedOwnerNameKey) ?? '';

  Future<void> setDesktopLinkedOwnerName(String value) {
    return _preferences.setString(_desktopLinkedOwnerNameKey, value);
  }

  String getDesktopLinkedOwnerUsername() =>
      _preferences.getString(_desktopLinkedOwnerUsernameKey) ?? '';

  Future<void> setDesktopLinkedOwnerUsername(String value) {
    return _preferences.setString(_desktopLinkedOwnerUsernameKey, value);
  }

  Future<void> clearDesktopLinkedIdentity() async {
    await _preferences.remove(_desktopLinkedOwnerUidKey);
    await _preferences.remove(_desktopLinkedOwnerNameKey);
    await _preferences.remove(_desktopLinkedOwnerUsernameKey);
  }

  bool getHybridEnabled() =>
      ReleaseFeatures.hybridNetworkPubliclyEnabled &&
      (_preferences.getBool(_hybridEnabledKey) ?? true);

  Future<void> setHybridEnabled(bool value) {
    if (!ReleaseFeatures.hybridNetworkPubliclyEnabled) {
      return _preferences.remove(_hybridEnabledKey);
    }
    return _preferences.setBool(_hybridEnabledKey, value);
  }

  bool getHybridRelayEnabled() =>
      ReleaseFeatures.hybridNetworkPubliclyEnabled &&
      (_preferences.getBool(_hybridRelayEnabledKey) ?? true);

  Future<void> setHybridRelayEnabled(bool value) {
    if (!ReleaseFeatures.hybridNetworkPubliclyEnabled) {
      return _preferences.remove(_hybridRelayEnabledKey);
    }
    return _preferences.setBool(_hybridRelayEnabledKey, value);
  }

  bool getHybridGatewayEnabled() =>
      ReleaseFeatures.hybridNetworkPubliclyEnabled &&
      (_preferences.getBool(_hybridGatewayEnabledKey) ?? true);

  Future<void> setHybridGatewayEnabled(bool value) {
    if (!ReleaseFeatures.hybridNetworkPubliclyEnabled) {
      return _preferences.remove(_hybridGatewayEnabledKey);
    }
    return _preferences.setBool(_hybridGatewayEnabledKey, value);
  }

  bool getHybridRelayTermsAccepted() =>
      ReleaseFeatures.hybridNetworkPubliclyEnabled &&
      (_preferences.getBool(_hybridRelayTermsAcceptedKey) ?? false);

  Future<void> setHybridRelayTermsAccepted(bool value) {
    if (!ReleaseFeatures.hybridNetworkPubliclyEnabled) {
      return _preferences.remove(_hybridRelayTermsAcceptedKey);
    }
    return _preferences.setBool(_hybridRelayTermsAcceptedKey, value);
  }

  List<RememberedAccount> getRememberedAccounts() {
    final raw = _preferences.getString(_rememberedAccountsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((item) => RememberedAccount.fromMap(item.cast<String, dynamic>()))
          .where((account) => account.uid.isNotEmpty)
          .toList()
        ..sort((a, b) => b.lastUsedAtMs.compareTo(a.lastUsedAtMs));
    } catch (_) {
      return const [];
    }
  }

  Future<void> setRememberedAccounts(List<RememberedAccount> accounts) {
    final payload = jsonEncode(accounts.map((account) => account.toMap()).toList());
    return _preferences.setString(_rememberedAccountsKey, payload);
  }

  String getActiveSessionView() =>
      _preferences.getString(_activeSessionViewKey) ?? 'all';

  Future<void> setActiveSessionView(String value) {
    return _preferences.setString(_activeSessionViewKey, value);
  }

  String getActiveAccountUid() =>
      _preferences.getString(_activeAccountUidKey) ?? '';

  Future<void> setActiveAccountUid(String value) {
    return _preferences.setString(_activeAccountUidKey, value);
  }

  Map<String, List<Chat>> getAllCachedChats() {
    final keys = _preferences
        .getKeys()
        .where((key) => key.startsWith(_cachedChatsPrefix));
    final result = <String, List<Chat>>{};
    for (final key in keys) {
      final uid = key.replaceFirst(_cachedChatsPrefix, '');
      final raw = _preferences.getString(key);
      if (uid.isEmpty || raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        result[uid] = decoded
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .map((item) {
              final id = item['id']?.toString() ?? '';
              return Chat.fromMap(id, item);
            })
            .where((chat) => chat.id.isNotEmpty)
            .toList();
      } catch (_) {
        result[uid] = const [];
      }
    }
    return result;
  }

  Future<void> setCachedChatsForUser(String uid, List<Chat> chats) {
    final key = '$_cachedChatsPrefix$uid';
    final payload = jsonEncode(
      chats
          .map((chat) => {
                'id': chat.id,
                ...chat.toMap(),
              })
          .toList(),
    );
    return _preferences.setString(key, payload);
  }

  String getOrCreateLocalDeviceId() {
    final existing = _preferences.getString(_localDeviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final created = const Uuid().v4();
    _preferences.setString(_localDeviceIdKey, created);
    return created;
  }
}

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._service) : super(_service.getThemeMode());

  final AppPreferencesService _service;

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _service.setThemeMode(mode);
  }
}

class AppLockController extends StateNotifier<bool> {
  AppLockController(this._service) : super(false);

  final AppPreferencesService _service;

  bool get hasPin => _service.getAppPin().isNotEmpty;
  String get currentPin => _service.getAppPin();
  bool get biometricEnabled => _service.getBiometricEnabled();

  void unlock() => state = true;
  void lock() => state = false;

  Future<void> setPin(String pin) async {
    await _service.setAppPin(pin);
    state = true;
  }

  Future<void> clearPin() async {
    await _service.clearAppPin();
    await _service.setBiometricEnabled(false);
    state = true;
  }

  Future<void> setBiometricEnabled(bool value) async {
    await _service.setBiometricEnabled(value);
  }
}

class EmailOtpSessionController extends StateNotifier<EmailOtpSession> {
  EmailOtpSessionController(this._service)
      : super(_normalized(_service.getEmailOtpSession(), _service));

  final AppPreferencesService _service;

  EmailOtpSession get currentSession => state;

  Future<void> setPending(EmailOtpSession session) async {
    state = session.copyWith(pending: true);
    await _service.setEmailOtpSession(state);
  }

  Future<void> clear() async {
    state = const EmailOtpSession();
    await _service.clearEmailOtpSession();
  }

  static EmailOtpSession _normalized(
    EmailOtpSession session,
    AppPreferencesService service,
  ) {
    if (session.pending && session.isExpired) {
      unawaited(service.clearEmailOtpSession());
      return const EmailOtpSession();
    }
    return session;
  }
}

class RememberedAccountsController extends StateNotifier<List<RememberedAccount>> {
  RememberedAccountsController(this._service)
      : super(_service.getRememberedAccounts());

  final AppPreferencesService _service;

  Future<void> remember(RememberedAccount account) async {
    final updated = [
      account,
      ...state.where((item) => item.uid != account.uid),
    ]..sort((a, b) => b.lastUsedAtMs.compareTo(a.lastUsedAtMs));
    state = updated;
    await _service.setRememberedAccounts(updated);
  }

  Future<void> remove(String uid) async {
    state = state.where((item) => item.uid != uid).toList();
    await _service.setRememberedAccounts(state);
  }
}

class ActiveSessionViewController extends StateNotifier<String> {
  ActiveSessionViewController(this._service)
      : super(_service.getActiveSessionView());

  final AppPreferencesService _service;

  Future<void> setView(String value) async {
    state = value;
    await _service.setActiveSessionView(value);
  }
}

class ActiveAccountUidController extends StateNotifier<String> {
  ActiveAccountUidController(this._service)
      : super(_service.getActiveAccountUid());

  final AppPreferencesService _service;

  Future<void> setUid(String value) async {
    state = value;
    await _service.setActiveAccountUid(value);
  }
}

class CachedChatsController extends StateNotifier<Map<String, List<Chat>>> {
  CachedChatsController(this._service) : super(_service.getAllCachedChats());

  final AppPreferencesService _service;

  Future<void> setChatsForUser(String uid, List<Chat> chats) async {
    state = {
      ...state,
      uid: chats,
    };
    await _service.setCachedChatsForUser(uid, chats);
  }
}
