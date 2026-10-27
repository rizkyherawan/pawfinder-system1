# PawFinder — Flutter application

> **Penting:** buka folder proyek yang berisi `pubspec.yaml` langsung di VS Code. Folder `lib`, `assets`, `web`, `android`, dan `pubspec.yaml` harus terlihat pada level yang sama. ZIP ini sudah dikemas tanpa folder pembungkus tambahan agar tidak terbentuk `pawfinder_flutter/pawfinder_flutter`.

PawFinder sudah dipindahkan ke struktur standar aplikasi Flutter. Kode utama berada langsung di `lib/`, aset di `assets/`, dan folder platform (`android`, `ios`, `web`, `windows`, `linux`, `macos`) disediakan oleh scaffold Flutter. Tidak ada launcher khusus; jalankan aplikasi dengan Flutter CLI atau tombol **Run/Debug** di Android Studio atau VS Code.

## Persiapan

1. Install Flutter SDK dan pastikan perintah `flutter` tersedia di terminal.
2. Ekstrak folder proyek ini, lalu buka terminal di folder yang memiliki `pubspec.yaml`.
3. Jalankan:

```bash
flutter doctor
flutter clean
flutter pub get
flutter devices
```

## Menjalankan dengan Flutter

```bash
# Chrome / web
flutter run -d chrome

# Android emulator atau perangkat Android yang tersambung
flutter run -d android

# Windows desktop (jalankan dari Windows dengan Visual Studio C++ workload terpasang)
flutter run -d windows

# Linux desktop (memerlukan toolchain GTK development)
flutter run -d linux

# macOS desktop atau iOS (hanya dari macOS dengan toolchain Apple yang sesuai)
flutter run -d macos
flutter run -d ios
```

Atau gunakan `flutter run` untuk memilih perangkat yang tersedia. Untuk build web gunakan `flutter build web`; hasilnya ada di `build/web/`.

## Alur dashboard, akun, dan hewan

- Saat aplikasi dibuka, layar splash PawFinder muncul selama sekitar 3 detik, lalu aplikasi langsung menuju dashboard. Tiga halaman onboarding tidak lagi ditampilkan.
- Dashboard dapat dibuka tanpa masuk. Buka tab **Profil** untuk masuk atau membuat akun.
- Pengguna yang telah masuk dapat mengubah **nama profil pemilik** dari Profil. Email ditampilkan sebagai identitas login dan saat ini tidak dapat diubah dari aplikasi.
- Satu akun dapat mendaftarkan beberapa hewan. Daftar semua hewan ditampilkan terpisah dari kartu profil pemilik; setiap hewan tetap memiliki layar edit sendiri. Data akun dan hewan akun biasa disimpan oleh backend.
- Navigasi bawah dibuat mengambang dengan animasi pemilihan dan efek tekan. Menu **Pengaturan Aplikasi** dan **Design System** tidak lagi ditampilkan di halaman Profil.

## Mode server dan demo

- Untuk memakai fitur daftar/masuk dan menyimpan akun/hewan, jalankan backend di terminal terpisah:

```powershell
cd backend
npm start
```

- Setelah server aktif, jalankan aplikasi Flutter di terminal lain, misalnya `flutter run -d chrome`. Alamat bawaan browser adalah `http://localhost:4000`. Pada Android emulator, alamat bawaan memakai `http://10.0.2.2:4000`; perangkat fisik harus menggunakan IP komputer yang menjalankan backend.
- Jika ingin mencoba tanpa backend, buka **Profil → Masuk / Buat Akun → Coba mode demo (tanpa server)**. Mode demo digunakan untuk meninjau antarmuka, sementara akun sebenarnya membutuhkan backend.
- Google Maps memerlukan API key dan hanya dipilih pada Android/iOS; web dan desktop memakai peta ilustratif agar tidak bergantung pada API key atau plugin peta desktop.
- Pemilih foto di web dan desktop menggunakan file picker. Fitur kamera langsung tersedia pada perangkat Android/iOS.

## Catatan platform

Flutter mendukung target-target di atas, tetapi toolchain build native berbeda antar sistem operasi. Android membutuhkan Android SDK, Windows membutuhkan Visual Studio dengan workload Desktop development with C++, Linux membutuhkan paket pengembangan GTK, dan iOS/macOS hanya dapat dibangun pada macOS. Folder `ios/Flutter` berisi konfigurasi yang dibuat ulang oleh Flutter pada mesin build; file konfigurasi lokal dari komputer asal tidak disertakan.
