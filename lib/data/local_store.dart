import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Penyimpanan lokal ringan: sesi, preferensi, dan status onboarding.
class LocalStore {
  late SharedPreferences _p;

  Future<void> init() async => _p = await SharedPreferences.getInstance();

  bool get onboardingDone => _p.getBool('onboarding_done') ?? false;
  Future<void> setOnboardingDone(bool v) => _p.setBool('onboarding_done', v);

  String? get baseUrl => _p.getString('base_url');
  Future<void> setBaseUrl(String v) => _p.setString('base_url', v);

  String? get token => _p.getString('token');
  bool get demo => _p.getBool('demo') ?? false;

  AppUser? get user {
    final raw = _p.getString('user');
    if (raw == null) return null;
    try {
      return AppUser.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSession({String? token, required AppUser user, required bool demo}) async {
    if (token == null) {
      await _p.remove('token');
    } else {
      await _p.setString('token', token);
    }
    await _p.setString('user', jsonEncode(user.toJson()));
    await _p.setBool('demo', demo);
  }

  Future<void> clearSession() async {
    await _p.remove('token');
    await _p.remove('user');
    await _p.setBool('demo', false);
  }

  AppSettings get settings {
    final raw = _p.getString('settings');
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings s) => _p.setString('settings', jsonEncode(s.toJson()));
}
