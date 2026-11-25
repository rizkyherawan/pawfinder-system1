# Laporan QA PawFinder v1.4.0

Audit menyeluruh dilakukan dengan **membaca seluruh kode** (±10.000 baris: backend dan 48 berkas Flutter), lalu setiap temuan diperbaiki dan — untuk backend — dibuktikan dengan tes otomatis. Laporan ini juga mencatat dengan jujur **apa yang belum bisa diverifikasi** di lingkungan audit.

## 1. Cakupan dan metode

| Area | Metode | Hasil |
|---|---|---|
| Backend (API, geofence, validasi, keamanan) | Server asli + 140 pemeriksaan end-to-end | Lulus |
| Protokol alat (JSON/CSV/NMEA, framing, perintah) | 22 kelompok uji, termasuk keluaran persis sketsa Arduino | Lulus |
| Tautan USB | 31 pemeriksaan dengan port serial palsu: auto-deteksi, cabut/colok kabel, error baca, banjir data, penerima lambat, driver hilang, port sedang dipakai | Lulus |
| I/O serial sungguhan | 5 pemeriksaan lewat *pseudo-terminal* (byte nyata dibaca/ditulis) | Lulus |
| Rantai penuh | Emulator Arduino → bridge → server → geofence → notifikasi (JSON, CSV, NMEA) lewat CLI | Berhasil |
| Aplikasi Flutter | Pembacaan kode menyeluruh + pemeriksa sintaks + unit test baru | **Belum dikompilasi** (lihat bagian 5) |

Jalankan ulang kapan saja: `cd backend && npm test`.

## 2. Temuan dan perbaikan

Tingkat: **T** = tinggi (keamanan/kehilangan data/data salah), **S** = sedang, **R** = rendah.

### Keamanan

| # | T | Temuan (kondisi lama) | Perbaikan |
|---|---|---|---|
| 1 | T | **Email dan kata sandi pribadi tertanam di kode** (`seed.js`, `constants.dart`) dan tampil lewat tombol "Isi akun demo"; akun itu otomatis dibuat di server baru | Dihapus dari kode dan UI. Akun awal hanya dari `SEED_*` di `.env` (opsional) |
| 2 | T | Rahasia token JWT berupa teks tetap di kode (`pawfinder-dev-secret-change-me`) → siapa pun bisa memalsukan token | Dibuat acak otomatis dan disimpan di `data/jwt.secret`; produksi wajib `JWT_SECRET` |
| 3 | T | `npm run seed` menjalankan `--reset` → **menghapus seluruh database** tanpa konfirmasi | `seed` tidak pernah menghapus; `reset` terpisah dan wajib `--yes` |
| 4 | S | Login tanpa batas percobaan (brute-force) | 5 gagal / 10 menit per IP+email → 429; pendaftaran dibatasi per IP |
| 5 | S | Email terdaftar bisa ditebak dari waktu respons login | Waktu disamakan (hash palsu) dan pesan galat sama |
| 6 | S | `.gitignore` tidak mengecualikan `.env`, `db.json`, `jwt.secret`, foto | Ditambahkan |
| 7 | S | Server produksi dapat jalan dengan `DEVICE_KEY`/CORS bawaan | `NODE_ENV=production` menolak start sampai aman |
| 8 | R | Galat 500 membocorkan pesan internal; tanpa header `nosniff`/`no-store`; CORS selalu `*` | Pesan umum di produksi, header keamanan, `CORS_ORIGIN` |

> ⚠️ **Tindakan untuk Anda:** kata sandi lama itu **masih ada di riwayat Git** commit sebelumnya. Anggap sudah bocor: **ganti kata sandi** akun tersebut di mana pun dipakai. Bila repositori pernah dibagikan, bersihkan riwayatnya (mis. `git filter-repo`).

### Integritas data dan server

| # | T | Temuan | Perbaikan |
|---|---|---|---|
| 9 | T | `db.json` rusak → server diam-diam membuat DB kosong dan **menimpa** berkas (data hilang permanen) | Berkas rusak dipindah ke `db.json.rusak-<waktu>` lalu mulai baru |
| 10 | S | Body JSON `null` / array / teks → **HTTP 500** | 400 dengan pesan jelas |
| 11 | S | URL berparameter `%` rusak → 500 | 400 |
| 12 | S | Foto 750–800 KB ditolak dengan "Payload terlalu besar" (413): batas body 1 MB < ukuran base64 | Batas khusus rute foto; pesan ukuran jelas |
| 13 | R | Tanda tangan file foto hanya diperiksa 2 byte pertama (mudah dipalsukan) | Diperiksa 3 byte (JPEG) / 4 byte (PNG) |
| 14 | S | Ubah profil hewan: nama > 30 dipotong diam-diam; validasi gagal di tengah meninggalkan data setengah berubah | Validasi semua dulu, baru simpan (atomik); pesan galat |
| 15 | R | Daftar notifikasi mengirim hingga 1000 item tiap 5 detik | `limit` (bawaan 200) |
| 16 | R | Folder web bawaan menunjuk ke `web/` (templat Flutter mentah, bukan hasil build) | Menunjuk ke `build/web` |
| 17 | R | Timeout permintaan bawaan Node terlalu longgar (5 menit); port bentrok memberi galat mentah | Timeout 30 dtk; pesan jelas untuk `EADDRINUSE` |

### Alat nyata (hal yang baru terlihat saat menyambung hardware)

| # | T | Temuan | Perbaikan |
|---|---|---|---|
| 18 | T | **Simulator aktif bawaan**: kalung asli yang baru dipasangkan langsung tampil "Online" dengan data **palsu** | Simulator mati bawaan; alat yang terdeteksi nyata tidak pernah disimulasikan |
| 19 | T | Telemetri wajib berisi koordinat: GPS tanpa sinyal tidak bisa tampil online; koordinat `0,0` diterima sebagai lokasi sungguhan | Mode *heartbeat* (online tanpa lokasi); `0,0` dibuang |
| 20 | S | Geofence bawaan selalu berpusat di Sleman → alat di kota lain langsung "di luar area" | Pusat dipindah ke lokasi pertama alat bila jauh (sekali, tercatat di Riwayat) |
| 21 | S | Alamat selalu berupa nama jalan Sleman walau alat di Jakarta | Hanya bila < 3 km dari landmark; selain itu tampil koordinat |
| 22 | S | Getaran GPS saat diam dihitung sebagai langkah (ribuan langkah palsu) | Ambang 3 m dan batas kecepatan |
| 23 | S | Kabel dicabut → status baru berubah setelah ≥ 90 detik | Offline seketika + notifikasi |
| 24 | R | "Bunyikan Kalung" selalu sukses walau alat offline dan tidak mengirim apa pun | Hanya saat Online; perintah benar-benar dikirim ke alat |

### Aplikasi Flutter

| # | T | Temuan | Perbaikan |
|---|---|---|---|
| 25 | S | Email kosong → "Format email tidak valid"; sandi kosong → "minimal 6 karakter" (**tidak ada pesan "wajib diisi"**) | Pesan khusus untuk kosong vs tidak valid, di semua form (masuk, daftar, hewan, kesehatan, pairing, akun) |
| 26 | S | Tanggal lahir opsional dan diam-diam kosong | **Wajib**, pesan "Tanggal lahir wajib diisi" di bawah kolom |
| 27 | S | Date picker bisa **crash** (assertion Flutter) pada kasus tepi: tanggal awal di luar rentang (mis. tanggal lahir > 30 tahun) | Tanggal awal dijepit ke rentang |
| 28 | T | Splash bisa **macet selamanya** bila pemuatan data awal melempar galat tak terduga | `ready` selalu terpenuhi (try/finally) |
| 29 | S | Pembaruan otomatis (timer) melempar galat tak tertangkap pada respons aneh | Ditangkap |
| 30 | S | Alamat server tidak divalidasi (`Uri.parse` melempar); sheet kehilangan status saat keyboard muncul; server yang bukan PawFinder tidak dikenali | Validasi, `StatefulWidget` tersendiri, deteksi respons non-JSON |
| 31 | S | Layar Geofence berputar selamanya bila gagal memuat | Pesan galat + "Coba Lagi" |
| 32 | S | Tampil "di dalam area aman" padahal alat belum punya lokasi | Status "mencari satelit GPS" |
| 33 | S | Google Maps tanpa API key → peta abu-abu kosong di HP (key tidak ada di mana pun) | Opt-in; bawaan peta ilustratif |
| 34 | R | Tombol kirim bisa ditekan ganda (tombol Enter) di beberapa form | Penjaga `_saving`/`_loading` |
| 35 | R | Inisial nama memakai `substring(0,1)` → emoji bisa rusak | Memakai code point |
| 36 | R | Menu Pengaturan menyebut Bluetooth; tombol contoh pairing tampil di rilis; FAQ usang | Diganti Koneksi Alat; contoh hanya debug/demo; FAQ diperbarui |
| 37 | R | Tarik-segarkan saat belum masuk memicu panggilan 401 sia-sia | Dilewati |

## 3. Perubahan perilaku yang disengaja (bisa Anda balik)

Ini keputusan produk, bukan bug. Bila tidak setuju, perubahannya kecil:

| Perubahan | Cara membalik |
|---|---|
| **Tanggal lahir wajib** (permintaan Anda tentang "tanggal tidak diisi") | Server: `birthDateOf` di `routes/index.js`; app: `add_pet_screen.dart` & `pet_edit_screen.dart` |
| Kata sandi daftar minimal **8 karakter + huruf & angka** (dulu 6) | `passwordProblem` di `auth.js` dan `passwordPolicy` di `auth_screen.dart` |
| Simulator **mati** bawaan | `SIMULATOR=on` / `npm run start:sim` |
| Google Maps **opt-in** | `--dart-define=GOOGLE_MAPS_ENABLED=true` |
| Geofence otomatis dipusatkan ke lokasi pertama alat | `fence.auto` di `engine.js` |

## 4. Matriks skenario yang diuji (backend)

Daftar/masuk (kosong, format salah, sandi lemah, ganda, huruf besar-kecil, spasi, brute-force) · profil · tambah/ubah/hapus hewan (kosong, terlalu panjang, jenis/kelamin salah, tanggal: kosong/salah/30 Feb/masa depan/terlalu lampau) · foto (bukan gambar, terlalu besar, valid) · pairing (kosong, salah format, ganda, alat nyata vs simulator) · telemetri (tanpa key, key salah, tanpa ID, ID salah, koordinat di luar rentang/bukan angka/0,0, heartbeat) · online/offline/kembali online · geofence (radius, pusat, tipe notifikasi; keluar/masuk; pusat otomatis) · aktivitas (getaran vs gerak) · kesehatan (berat, tanggal, judul, jenis) · riwayat = notifikasi · isolasi antar akun (hewan, foto, riwayat, alat) · token (tanpa, palsu, tanda tangan salah) · DB rusak · USB (cabut/colok, EIO, banjir, lambat, driver hilang, port dipakai, banyak port) · perintah ke alat.

## 5. Yang BELUM terverifikasi (harap diuji di mesin Anda)

Lingkungan audit tidak memiliki Flutter SDK, Android/iOS, Arduino, maupun jaringan. Karena itu:

1. **Aplikasi Flutter belum dikompilasi dan belum dijalankan.** Semua perubahan Dart ditulis dengan hati-hati dan diperiksa sintaksnya (kurung/string/import), tetapi **jalankan `flutter analyze` dan `flutter test` lebih dulu**. Bila ada galat kompilasi, kemungkinan besar kecil (nama/tipe) dan lokasinya jelas di berkas: `device_connection_screen.dart` (baru), `pair_sheet.dart`, `auth_screen.dart`, `models.dart`, `demo_data_source.dart`, `splash_screen.dart`.
2. **Sketsa Arduino belum dikompilasi** (tanpa Arduino IDE). Format keluarannya sudah dibuktikan terbaca oleh server; sintaks C++ perlu dicoba di IDE (butuh library TinyGPSPlus).
3. **Paket `serialport` di Windows** belum dicoba (jalur utama di Windows). Logikanya diuji lewat port palsu dan pseudo-terminal Linux, tetapi bukan driver aslinya.
4. **Perangkat keras asli** (Arduino, GPS, kabel) belum pernah tersambung.
5. iOS, Web, Desktop: tidak dijalankan.

## 6. Keterbatasan yang diketahui (bukan bug, tetapi perlu untuk produk publik)

- **Tidak ada notifikasi push**: pemberitahuan hanya tampil saat aplikasi terbuka (polling 5 detik). Untuk notifikasi saat aplikasi tertutup perlu FCM/APNs.
- Belum ada **ubah/lupa kata sandi**, **verifikasi email**, dan **hapus akun** (Google Play mewajibkan hapus akun dalam aplikasi untuk aplikasi dengan pendaftaran).
- Penyimpanan JSON dan seluruh data di memori: cocok untuk prototipe/ratusan pengguna, bukan jutaan.
- Satu `DEVICE_KEY` untuk semua alat (bukan kunci per alat). Aman selama dirahasiakan; kunci per alat disarankan sebelum produksi massal.
- Arduino Uno tidak punya radio: jalur USB hanya untuk prototipe. Jalur nirkabel (ESP32/GSM/LoRa) belum diputuskan — kontrak HTTP-nya sudah siap (`docs/HARDWARE.md` bagian 6).
- Sensor detak jantung belum ada di firmware (kolom dikosongkan).
