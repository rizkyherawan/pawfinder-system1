import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  static const appName = 'PawFinder';
  static const tagline = 'Lebih Dekat, Lebih Aman';
  static const version = '1.3.0';
  // Akun pengembangan (tombol "Isi akun demo"). Ganti/hapus sebelum aplikasi dibagikan.
  static const demoName = 'Muhammad Rizky Herawan';
  static const demoEmail = 'muhammadrizkyherawan@gmail.com';
  static const demoPassword = '3Oktober2004';
  static const dailyStepGoal = 10000;

  /// Android/iOS saja: di sinilah Google Maps, izin galeri/kamera, dan kamera tersedia.
  static bool get isMobile => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// Google Maps hanya didukung di Android & iOS. Di Chrome/Windows dipakai peta ilustratif.
  static bool get googleMapsSupported => isMobile;

  /// Alamat backend bawaan. Dapat diubah dari layar Masuk atau Pengaturan.
  /// Android emulator memakai 10.0.2.2 untuk menjangkau localhost komputer.
  static String get defaultBaseUrl {
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
