import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  static const appName = 'PawFinder';
  static const tagline = 'Lebih Dekat, Lebih Aman';
  static const version = '1.4.0';

  /// Lama splash sebelum otomatis masuk ke dashboard. Ketukan di layar langsung melewatinya.
  static const splashDuration = Duration(seconds: 10);

  /// Mode demo (tanpa server): akun lokal fiktif yang tidak pernah dikirim ke server mana pun.
  static const demoName = 'Pengguna Demo';
  static const demoEmail = 'demo@pawfinder.app';
  static const dailyStepGoal = 10000;

  /// Android/iOS saja: di sinilah Google Maps, izin galeri/kamera, dan kamera tersedia.
  static bool get isMobile => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// Diisi true saat build setelah API key Google Maps dipasang di AndroidManifest/AppDelegate:
  ///   flutter run --dart-define=GOOGLE_MAPS_ENABLED=true
  /// Tanpa API key, Google Maps hanya menampilkan peta abu-abu kosong, jadi aplikasi memakai peta ilustratif.
  static const googleMapsKeyConfigured = bool.fromEnvironment('GOOGLE_MAPS_ENABLED', defaultValue: false);

  /// Google Maps hanya dipakai di Android & iOS DAN bila API key sudah dipasang (lihat README).
  static bool get googleMapsSupported => isMobile && googleMapsKeyConfigured;

  /// Alamat backend bawaan. Dapat diubah dari layar Masuk atau Pengaturan.
  /// Android emulator memakai 10.0.2.2 untuk menjangkau localhost komputer.
  /// Dapat ditentukan saat build: flutter build apk --dart-define=API_BASE_URL=https://api.contoh.com
  static const _envBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get defaultBaseUrl {
    if (_envBaseUrl.isNotEmpty) return _envBaseUrl;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:4000';
    }
    return 'http://localhost:4000';
  }
}

/// Titik rumah demo (Sleman, Yogyakarta).
const kHomeLat = -7.71556;
const kHomeLng = 110.35547;
const kHomeAddress = 'Jl. Melati No. 12, Sleman, Yogyakarta';
