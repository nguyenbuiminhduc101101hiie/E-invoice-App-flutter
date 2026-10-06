import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../models/models.dart';

/// Được override trong main() sau khi SharedPreferences đã load.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

const _envBaseUrl = String.fromEnvironment('API_BASE_URL');

String _defaultBaseUrl() {
  if (_envBaseUrl.isNotEmpty) return _envBaseUrl;
  // Bản web mặc định gọi về chính server đang phục vụ app
  if (kIsWeb) return Uri.base.origin;
  return '';
}

// ---------------- Cài đặt ----------------

class AppSettings {
  const AppSettings({
    required this.baseUrl,
    required this.themeMode,
    this.taxCode,
    this.templateCode,
    this.invoiceSeries,
  });

  final String baseUrl;
  final ThemeMode themeMode;

  /// Giá trị người dùng tự đặt; null = dùng mặc định từ server.
  final String? taxCode;
  final String? templateCode;
  final String? invoiceSeries;

  AppSettings copyWith({
    String? baseUrl,
    ThemeMode? themeMode,
    String? taxCode,
    String? templateCode,
    String? invoiceSeries,
  }) =>
      AppSettings(
        baseUrl: baseUrl ?? this.baseUrl,
        themeMode: themeMode ?? this.themeMode,
        taxCode: taxCode ?? this.taxCode,
        templateCode: templateCode ?? this.templateCode,
        invoiceSeries: invoiceSeries ?? this.invoiceSeries,
      );
}

class SettingsNotifier extends Notifier<AppSettings> {
  SharedPreferences get _prefs => ref.read(prefsProvider);

  @override
  AppSettings build() {
    final p = ref.read(prefsProvider);
    return AppSettings(
      baseUrl: p.getString('baseUrl') ?? _defaultBaseUrl(),
      themeMode: ThemeMode.values[p.getInt('themeMode') ?? ThemeMode.system.index],
      taxCode: p.getString('taxCode'),
      templateCode: p.getString('templateCode'),
      invoiceSeries: p.getString('invoiceSeries'),
    );
  }

  Future<void> setBaseUrl(String url) async {
    var v = url.trim();
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    await _prefs.setString('baseUrl', v);
    state = state.copyWith(baseUrl: v);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setInt('themeMode', mode.index);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setInvoiceHeader({required String taxCode, required String templateCode, required String invoiceSeries}) async {
    await _prefs.setString('taxCode', taxCode.trim());
    await _prefs.setString('templateCode', templateCode.trim());
    await _prefs.setString('invoiceSeries', invoiceSeries.trim());
    state = AppSettings(
      baseUrl: state.baseUrl,
      themeMode: state.themeMode,
      taxCode: taxCode.trim(),
      templateCode: templateCode.trim(),
      invoiceSeries: invoiceSeries.trim(),
    );
  }

  Future<void> resetInvoiceHeader() async {
    await _prefs.remove('taxCode');
    await _prefs.remove('templateCode');
    await _prefs.remove('invoiceSeries');
    state = AppSettings(baseUrl: state.baseUrl, themeMode: state.themeMode);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

// ---------------- Đăng nhập ----------------

class AuthState {
  const AuthState({this.token, this.user, this.expiresAt});
  final String? token;
  final AppUser? user;
  final DateTime? expiresAt;

  bool get isLoggedIn => token != null && user != null && (expiresAt?.isAfter(DateTime.now()) ?? false);
}

class AuthNotifier extends Notifier<AuthState> {
  SharedPreferences get _prefs => ref.read(prefsProvider);

  @override
  AuthState build() {
    final p = ref.read(prefsProvider);
    final raw = p.getString('session');
    if (raw == null) return const AuthState();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final s = AuthState(
        token: j['token'],
        user: AppUser.fromJson(j['user']),
        expiresAt: DateTime.tryParse(j['expiresAt'] ?? ''),
      );
      return s.isLoggedIn ? s : const AuthState();
    } catch (_) {
      return const AuthState();
    }
  }

  ApiClient get _api => ref.read(apiProvider);

  Future<bool> needsSetup() async {
    final res = await _api.get('/api/auth/setup-status');
    return res['needsSetup'] == true;
  }

  Future<void> login(String username, String password) async {
    final res = await _api.post('/api/auth/login', {'username': username.trim(), 'password': password});
    await _saveSession(res);
  }

  Future<void> setupFirstAdmin(String username, String password, String fullName) async {
    final res = await _api.post('/api/auth/setup', {'username': username.trim(), 'password': password, 'fullName': fullName});
    await _saveSession(res);
  }

  Future<void> _saveSession(Map<String, dynamic> res) async {
    final s = AuthState(
      token: res['token'],
      user: AppUser.fromJson(res['user']),
      expiresAt: DateTime.tryParse(res['expiresAt'] ?? ''),
    );
    await _prefs.setString(
        'session', jsonEncode({'token': s.token, 'user': s.user!.toJson(), 'expiresAt': s.expiresAt?.toIso8601String()}));
    state = s;
  }

  Future<void> logout() async {
    await _prefs.remove('session');
    state = const AuthState();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

// ---------------- API ----------------

final apiProvider = Provider<ApiClient>((ref) {
  final baseUrl = ref.watch(settingsProvider.select((s) => s.baseUrl));
  return ApiClient(
    baseUrl: baseUrl,
    tokenReader: () => ref.read(authProvider).token,
    onUnauthorized: () => ref.read(authProvider.notifier).logout(),
  );
});
