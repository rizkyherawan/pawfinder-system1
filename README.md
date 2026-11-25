# PawFinder 🐾 — pelacak hewan peliharaan (Flutter + Node.js + alat Arduino)

Aplikasi PawFinder terdiri dari **tiga bagian** yang saling terhubung:

```
                 ┌──────────────────────────────┐
  Kalung GPS     │  Backend Node.js (backend/)  │      Aplikasi Flutter
  (Arduino Uno)  │  REST API · Geofence · SSE   │      (lib/) Android · iOS · Web · Desktop
       │         │  Penyimpanan JSON            │            ▲
  kabel USB      │                              │            │ HTTP (Bearer token)
       │         │   ┌──────────────────────┐   │            │
       └────────►│   │ Gateway alat         │◄──┼────────────┘
   (serial 9600) │   │ USB / HTTP / bridge  │   │
                 │   └──────────────────────┘   │
                 └──────────────────────────────┘
```

| Bagian | Folder | Fungsi |
|---|---|---|
| Aplikasi | `lib/` | Beranda, peta, geofence, aktivitas, kesehatan, riwayat, notifikasi, **Koneksi Alat** |
| Backend | `backend/` | Akun, data hewan, geofence, penerima data alat (USB/HTTP), notifikasi |
| Firmware | `firmware/` | Sketsa Arduino Uno untuk kalung (dan sketsa uji tanpa sensor) |
| Dokumen | `docs/` | Panduan untuk tim hardware (`HARDWARE.md`) dan laporan QA (`QA_REPORT.md`) |

> **Koneksi alat memakai kabel USB atau nomor seri (ID) — tanpa Bluetooth.** Penjelasan lengkap ada di bagian [Koneksi alat](#koneksi-alat-nyata-usb--id).

---

## 1. Mulai cepat (±10 menit)

**Syarat:** [Node.js](https://nodejs.org) 18 atau lebih baru (LTS), [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.24+ (Dart ≥ 3.5), dan Git.

### Langkah 1 — jalankan backend

```powershell
cd backend
copy .env.example .env        # Linux/macOS: cp .env.example .env
npm start
```

Server siap bila terminal menampilkan `PawFinder backend berjalan` beserta alamat API-nya. Cek di browser: <http://localhost:4000/api/ping> harus menjawab `{"status":"ok",...}`.

Backend **tidak memerlukan `npm install`** (tanpa dependensi). `npm install` hanya dibutuhkan bila memakai kabel USB di Windows (lihat bagian USB).

### Langkah 2 — jalankan aplikasi

```bash
flutter clean
flutter pub get
flutter run -d chrome          # atau: -d android | -d windows
```

### Langkah 3 — buat akun lalu coba

1. Buka tab **Profil → Masuk / Buat Akun → Daftar**. Kata sandi minimal **8 karakter, mengandung huruf dan angka**.
2. Tambahkan hewan (nama, jenis, kelamin, **tanggal lahir wajib**).
3. Hubungkan kalung (lihat bagian 4). Tanpa alat asli, nyalakan simulator: `npm run start:sim` (di backend) lalu pairing nomor seri apa pun, atau pakai **Coba mode demo** di layar Masuk.

Akun awal untuk pengembangan bersifat **opsional**: isi `SEED_EMAIL` dan `SEED_PASSWORD` di `backend/.env` (kosong = tidak ada akun bawaan).

---

## 2. Menghubungkan aplikasi ke server

Aplikasi perlu tahu alamat backend. Alamat bawaan: `http://localhost:4000` (web/desktop) dan `http://10.0.2.2:4000` (emulator Android). Ubah kapan saja di layar **Masuk → baris "Server: …"** (ada tombol *Uji Koneksi*).

| Perangkat yang menjalankan aplikasi | Alamat server yang diisi |
|---|---|
| Chrome / Windows / Linux / macOS (satu komputer dengan backend) | `http://localhost:4000` |
| Android **emulator** | `http://10.0.2.2:4000` |
| **HP Android/iOS asli**, satu Wi-Fi dengan komputer | `http://IP-KOMPUTER:4000` (mis. `http://192.168.1.10:4000`) |
| HP Android asli lewat kabel USB debugging | jalankan `adb reverse tcp:4000 tcp:4000`, lalu pakai `http://localhost:4000` |

**Mencari IP komputer:** saat start, backend mencetak baris `HP asli (WiFi): http://…`. Atau jalankan `ipconfig` (Windows) / `ip addr` (Linux) dan ambil alamat IPv4 Wi-Fi.

**Firewall Windows** sering memblokir HP asli. Buka PowerShell **sebagai Administrator** sekali saja:

```powershell
New-NetFirewallRule -DisplayName "PawFinder 4000" -Direction Inbound -Protocol TCP -LocalPort 4000 -Action Allow -Profile Private
```

Mengatur alamat saat build (untuk rilis): `flutter build apk --dart-define=API_BASE_URL=https://api.contoh.com`.

### Peta
Google Maps **tidak aktif secara bawaan** karena membutuhkan API key (tanpa key, petanya abu-abu kosong). Aplikasi memakai peta ilustratif yang berfungsi tanpa key. Untuk mengaktifkan Google Maps di Android/iOS:

1. Buat API key (Maps SDK for Android/iOS) di Google Cloud Console.
2. Android: tambahkan di `android/app/src/main/AndroidManifest.xml`, di dalam `<application>`:
   `<meta-data android:name="com.google.android.geo.API_KEY" android:value="KEY_ANDA"/>`
3. iOS: panggil `GMSServices.provideAPIKey("KEY_ANDA")` di `ios/Runner/AppDelegate.swift`.
4. Jalankan dengan `flutter run --dart-define=GOOGLE_MAPS_ENABLED=true`.

---

## 3. Alur aplikasi

- **Splash 10 detik**, atau **ketuk di mana saja / tombol "Lewati"** untuk langsung ke dashboard. Jika data awal belum selesai dimuat, dashboard muncul begitu siap; splash tidak pernah macet walau server mati.
- Dashboard dapat dibuka tanpa masuk. Masuk/daftar dilakukan dari tab **Profil**.
- Satu akun dapat memiliki banyak hewan (maks. 30). Hewan baru **belum terhubung**: tidak ada lokasi, baterai, atau status online sampai alat benar-benar mengirim data.
- **Riwayat dan Notifikasi memakai satu log kejadian yang sama**, jadi isinya selalu konsisten.
- Mode demo (tanpa server) hanya untuk meninjau antarmuka; datanya simulasi lokal.

### Aturan isian (ditegakkan di aplikasi **dan** di server)

| Isian | Aturan | Pesan bila salah |
|---|---|---|
| Email | wajib, format valid, ≤254 | "Email wajib diisi" / "Format email tidak valid" |
| Kata sandi (login) | wajib | "Kata sandi wajib diisi" |
| Kata sandi (daftar) | min. 8, maks. 128, huruf **dan** angka | "Kata sandi minimal 8 karakter" / "…harus mengandung huruf dan angka" |
| Nama pemilik | wajib, 2–60 karakter | "Nama wajib diisi" / "Nama minimal 2 karakter" |
| Nama hewan | wajib, ≤30 karakter | "Nama hewan wajib diisi" |
| **Tanggal lahir hewan** | **wajib**, tidak di masa depan, ≤40 tahun lalu | "Tanggal lahir wajib diisi" |
| Nomor seri alat | wajib, format `PF-XXX-000000` | "Nomor seri wajib diisi" / "Format nomor seri tidak valid" |
| Berat (kesehatan) | wajib, 0,1–200 kg | "Berat wajib diisi" |
| Tanggal catatan | wajib, tidak di masa depan | "Tanggal wajib diisi" |
| Radius geofence | 50 m – 5 km | "Radius harus antara 50 m dan 5 km" |

Login juga dibatasi: **5 kali gagal** per (IP + email) dalam 10 menit → diblokir sementara (HTTP 429).

---

## 4. Koneksi alat nyata (USB & ID)

Kalung memakai **Arduino Uno**, yang tidak punya Wi-Fi/seluler sendiri. Maka untuk prototipe, Arduino dihubungkan **lewat kabel USB** ke komputer, dan data mengalir **real-time**:

```
Arduino ──USB serial──► [A] backend (USB langsung)         ──► aplikasi
                    └─► [B] usb-bridge ──HTTP──► backend   ──► aplikasi
Alat jaringan (kelak ESP32/GSM) ──HTTP POST──► backend     ──► aplikasi
```

Identitas alat adalah **nomor seri (ID)** berformat `PF-XXX-000000`, dicetak/diprogram pada alat dan **dipasangkan ke satu hewan** di aplikasi. Semua jalur memakai pintu yang sama sehingga hasilnya identik.

### Jalur A — Arduino dicolok ke komputer yang menjalankan backend (paling mudah)

1. **Pasang driver serial** (Windows, di folder `backend`; macOS/Linux bisa dilewati):
   ```powershell
   cd backend
   npm install              # memasang paket "serialport" (opsional)
   npm run ports            # menampilkan port yang terdeteksi
   ```
   Contoh keluaran: `COM3  Arduino LLC · VID:2341  <-- kemungkinan Arduino`.
2. Upload firmware ke Arduino (lihat `firmware/` dan [docs/HARDWARE.md](docs/HARDWARE.md)). Ubah `DEVICE_ID` di sketsa.
3. **Tutup Serial Monitor Arduino IDE** (satu port tidak bisa dipakai dua program).
4. Jalankan backend dengan USB aktif:
   ```powershell
   npm run start:usb                 # deteksi Arduino otomatis
   # atau tentukan port:  node src/server.js --usb=COM3
   ```
   Atau tetap di `.env`: `USB_PORT=auto` (atau `COM3`, `/dev/ttyACM0`, `/dev/cu.usbmodem1101`).
5. Di aplikasi: **Beranda → hewan → Hubungkan GPS → tab "Kabel USB"**. Alat yang terdeteksi muncul otomatis; ketuk **Pasangkan**. (Atau tab "Nomor Seri (ID)" dan ketik ID-nya.)
6. Status berubah **Online (hijau)** saat paket pertama masuk. Buka **Detail Perangkat → Koneksi Alat** untuk monitor langsung (jalur, paket terakhir, satelit, baterai, sensor, status tautan USB, dan diagnosis otomatis).

Perilaku yang sudah ditangani:
- **Kabel dicabut** → alat langsung Offline + notifikasi; **dicolok lagi** → tersambung ulang otomatis.
- **GPS belum dapat satelit** (di dalam ruangan) → alat tetap *Online* dengan status "mencari satelit"; lokasi terakhir dipertahankan; geofence tidak dievaluasi dengan data palsu.
- Koordinat `0,0` dari modul GPS tanpa sinyal **tidak** dianggap lokasi.
- Tombol **Bunyikan Kalung** dan **interval GPS** di aplikasi dikirim ke Arduino sebagai perintah `PING` / `INTERVAL n`.
- Prototipe **tanpa modul GPS**: isi `USB_FALLBACK_LAT` / `USB_FALLBACK_LNG` agar alat tampil di satu titik tetap (ditandai "koordinat tetap").

### Jalur B — Arduino dicolok ke komputer LAIN (mis. laptop di lab), backend di tempat lain

Jalankan **bridge** di komputer yang memegang Arduino:

```powershell
cd backend
npm install
node tools/usb-bridge.js --server http://192.168.1.10:4000 --key KUNCI_DEVICE --port auto
# opsi lain: --port COM3  --baud 9600  --serial PF-ABC-123456  --lat -7.7 --lng 110.3
```
`--key` harus sama dengan `DEVICE_KEY` di `.env` server. Bridge menyambung ulang sendiri bila kabel dicabut, dan meneruskan perintah dari aplikasi ke Arduino.

### Jalur C — alat jaringan / uji dengan `curl` (tanpa hardware)

```bash
curl -X POST http://localhost:4000/api/device/telemetry \
  -H "Content-Type: application/json" -H "x-device-key: pawfinder-device-key" \
  -d '{"serial":"PF-ABC-123456","lat":-7.71556,"lng":110.35547,"battery":87,"signal":"Kuat"}'
```
Respons memuat `commands` (perintah untuk alat) dan `config.intervalSec`. Alat tanpa lokasi cukup kirim `{"serial":"…","fix":0,"battery":80}`.

### Uji tanpa hardware sama sekali
```bash
cd backend
node tools/emulate-arduino.js --serial PF-EMU-000001 --format json | node tools/usb-bridge.js --stdin --server http://localhost:4000
#   --format json|csv|nmea    --mode circle|exit|nofix   (exit = keluar geofence → memicu notifikasi)
node tools/simulate-device.js --serial PF-EMU-000001 --mode exit     # langsung via HTTP
```
Pasangkan dulu `PF-EMU-000001` ke satu hewan di aplikasi.

### Protokol data alat (ringkas)
Satu baris teks per paket (UTF-8, akhiran `\n`), 9600 baud, 8N1. Tiga format diterima:

```
JSON : {"serial":"PF-ABC-123456","lat":-7.71556,"lng":110.35547,"fix":1,"bat":87,"sig":"Kuat","hr":96,"temp":38.6,"sat":7}
CSV  : PF,PF-ABC-123456,-7.71556,110.35547,87,1,96,38.6,7      (hemat RAM Uno; kolom kosong = tidak tersedia)
NMEA : $GPGGA / $GPRMC / $GNGGA / $GNRMC langsung dari modul GPS (ID diisi lewat USB_SERIAL atau --serial)
Perkenalan: {"hello":"PF-ABC-123456","fw":"1.0.0"}  atau  PF,HELLO,PF-ABC-123456,1.0.0
Server → alat: PING | INTERVAL <detik> | WHO          Alat → server: PF,ACK,<PERINTAH>
```
Baris berawalan `#` = komentar debug (diabaikan). Spesifikasi lengkap beserta pemasangan kabel ada di **[docs/HARDWARE.md](docs/HARDWARE.md)**.

---

## 5. Konfigurasi backend (`backend/.env`)

| Variabel | Bawaan | Keterangan |
|---|---|---|
| `PORT` / `HOST` | `4000` / `0.0.0.0` | Alamat server |
| `NODE_ENV` | `development` | `production` menolak start bila kunci masih bawaan |
| `JWT_SECRET` | *(otomatis)* | Kosong = dibuat acak & disimpan di `data/jwt.secret`. Produksi: ≥32 karakter |
| `DEVICE_KEY` | `pawfinder-device-key` | Kunci rahasia alat/bridge (header `x-device-key`). **Ganti di produksi** |
| `CORS_ORIGIN` | `*` | Produksi: alamat aplikasi web, pisahkan koma |
| `TRUST_PROXY` | `0` | `1` bila di belakang Nginx/Caddy (agar IP klien benar untuk pembatas login) |
| `SEED_EMAIL`, `SEED_PASSWORD`, `SEED_NAME` | kosong | Akun awal opsional (tidak ada akun bawaan di kode) |
| `USB_PORT` | kosong | `auto`, `COM3`, `/dev/ttyACM0`… kosong = USB nonaktif |
| `USB_BAUD` | `9600` | Harus sama dengan firmware |
| `USB_SERIAL` | kosong | ID alat bila firmware/GPS tidak mengirim ID (NMEA murni) |
| `USB_FALLBACK_LAT/LNG` | kosong | Koordinat tetap untuk prototipe tanpa GPS |
| `OFFLINE_AFTER_SEC` | `90` | Detik tanpa data sebelum alat Offline (min. 15; juga ≥ 3× interval) |
| `SIMULATOR` | `off` | `on` = data **palsu** untuk demo. Matikan saat memakai alat asli |
| `DATA_FILE` | `./data/db.json` | Lokasi database JSON (foto di `data/photos/`) |
| `WEB_DIR` | `../build/web` | Folder hasil `flutter build web`; bila ada, disajikan di `/` |

Perintah npm (di `backend/`): `start`, `start:usb`, `start:sim`, `dev` (auto-restart), `seed` (buat akun awal), `reset` (**hapus semua data**), `ports`, `bridge`, `simulate`, `test`.

---

## 6. API (ringkas)

Semua JSON. Kecuali yang ditandai, memakai `Authorization: Bearer <token>`. Galat berbentuk `{"error":"pesan","field":"nama-kolom"}`.

| Metode & path | Keterangan |
|---|---|
| `GET /api/ping` *(publik)* | Status server, versi, fitur aktif (usb/simulator) |
| `POST /api/auth/register`, `/login` *(publik)* | Daftar / masuk → `{token,user}` |
| `GET·PUT /api/auth/me` | Profil pemilik |
| `GET·POST /api/pets`, `GET·PUT·DELETE /api/pets/:id` | Data hewan |
| `PUT·GET·DELETE /api/pets/:id/photo` | Foto (JPG/PNG ≤ 800 KB) |
| `POST /api/pets/:id/device/pair` · `/unpair` | Pasangkan / putuskan alat (`{serial}`) |
| `PUT /api/pets/:id/device` | Interval GPS (10/30/60/300 dtk) → dikirim ke firmware |
| `POST /api/pets/:id/device/ping` | Bunyikan kalung (harus Online) |
| `GET /api/pets/:id/device/live` | Data langsung alat (layar Koneksi Alat) |
| `GET /api/devices/discovered` | Alat yang mengirim data tetapi belum dipasangkan |
| `GET /api/usb/status` · `/ports` | Status tautan USB di server / daftar port |
| `GET·PUT /api/pets/:id/geofence` | Area aman |
| `GET /api/history?date=&petId=&category=` | Riwayat (log kejadian) |
| `GET /api/pets/:id/activity` · `/health` · `POST …/health-records` · `DELETE …/health-records/:rid` | Aktivitas & kesehatan |
| `GET /api/notifications?limit=` · `POST /read-all` · `PATCH /:id/read` · `DELETE …` | Notifikasi |
| `GET·PUT /api/settings` | Pengaturan |
| `POST /api/device/telemetry` *(header `x-device-key`)* | Paket dari alat/bridge |
| `GET /api/device/commands?serial=` *(header `x-device-key`)* | Perintah menunggu untuk alat |
| `GET /api/stream?token=` | Live stream SSE (`pet`, `notification`) |

---

## 7. Pengujian

```bash
cd backend && npm test        # 4 suite: protokol alat, API end-to-end, tautan USB (port palsu), I/O serial nyata (pty)
flutter test                  # uji unit model, format, mode demo, validasi alamat server
flutter analyze
```
`npm test` memakai database sementara dan tidak menyentuh data Anda. Hasil audit QA lengkap (bug yang ditemukan, perbaikan, matriks uji) ada di **[docs/QA_REPORT.md](docs/QA_REPORT.md)**.

---

## 8. Menuju produksi (daftar periksa)

- [ ] `NODE_ENV=production`, `JWT_SECRET` ≥32 acak, `DEVICE_KEY` ≥16 acak, `CORS_ORIGIN` diisi, `SIMULATOR=off`. Server **menolak start** bila ada yang belum aman.
- [ ] Jalankan di belakang **HTTPS** (Caddy/Nginx + `TRUST_PROXY=1`). Alat dan aplikasi memakai alamat `https://…`.
- [ ] Android: ubah `android:usesCleartextTraffic="true"` menjadi `false` di `AndroidManifest.xml` setelah memakai HTTPS. Ganti `applicationId` (`com.example.pawfinder`) dan tanda tangan rilis.
- [ ] Jalankan dengan pengelola proses (`pm2 start src/server.js --name pawfinder` atau systemd/Docker) agar hidup ulang otomatis.
- [ ] **Backup** folder `backend/data/` (database + foto) berkala. File `db.json` yang rusak otomatis dicadangkan, bukan ditimpa.
- [ ] Ganti kata sandi pribadi yang pernah tertulis di kode versi lama (lihat catatan keamanan di QA_REPORT).
- [ ] Penyimpanan JSON cocok untuk ratusan pengguna/prototipe. Untuk skala besar, pindahkan ke database (SQLite/PostgreSQL): seluruh akses data lewat `store.data` di `backend/src/`.
- [ ] Font memakai `google_fonts` (diunduh saat pertama jalan). Untuk aplikasi yang dipakai tanpa internet, sertakan berkas font di `assets/`.

---

## 9. Pemecahan masalah

| Gejala | Penyebab & solusi |
|---|---|
| Splash lama / aplikasi "diam" | Ketuk layar untuk lanjut. Server mati tidak lagi menahan splash. |
| "Tidak dapat terhubung ke server" | Backend belum jalan, alamat salah (lihat tabel bagian 2), atau firewall memblokir port 4000. Tes: buka `http://ALAMAT:4000/api/ping` di browser HP. |
| `Port 4000 sudah dipakai` | Ada backend lain yang masih berjalan. Tutup, atau ubah `PORT` di `.env` (lalu ubah alamat di aplikasi). |
| Daftar ditolak "huruf dan angka" | Kata sandi harus ≥8 karakter dengan huruf **dan** angka. |
| "Terlalu banyak percobaan masuk" | Tunggu ±10 menit (anti brute-force), atau restart backend saat pengembangan. |
| Peta abu-abu kosong (Android/iOS) | Google Maps tanpa API key. Biarkan peta ilustratif, atau pasang key (bagian 2). |
| `npm run ports` kosong | Kabel USB hanya-charger (pakai kabel **data**), driver CH340/FTDI belum terpasang (papan klon), atau coba port USB lain. |
| Status USB "Terputus: Access denied / busy" | Port dipakai program lain: **tutup Serial Monitor Arduino IDE**. |
| Server mencetak "Driver serial tidak ditemukan" | Jalankan `npm install` di `backend/` (memasang `serialport`). |
| Alat tidak muncul di tab Kabel USB | Lihat Koneksi Alat → *Diagnosis*: baud tidak sama, format baris salah ("baris tak dikenali" menampilkan contoh), atau ID belum sesuai. |
| Alat Online tetapi tanpa lokasi | Normal di dalam ruangan: modul GPS perlu langit terbuka, 1–5 menit (cold start). |
| Alat langsung dianggap "di luar area" | Pusat geofence bawaan otomatis dipindah ke lokasi pertama alat; atau atur sendiri di menu Geofence. |
| Data demo muncul padahal pakai alat asli | `SIMULATOR` masih `on`. Setel `off` dan restart. |

---

## 10. Struktur proyek

```
lib/                      Aplikasi Flutter
  core/                   konstanta, tema, util, rute
  data/                   model, DataSource (remote & demo)
  state/app_state.dart    state aplikasi (Provider)
  screens/                auth, home, tracking (peta, detail, Koneksi Alat), geofence, history, profil
  widgets/                komponen UI (input, tombol, sheet pairing, peta)
backend/
  src/server.js           entry point (HTTP + USB + simulator)
  src/routes/index.js     seluruh endpoint
  src/services/           engine (geofence, status), device-gateway, device-protocol,
                          usb-link, serial-io, simulator
  tools/                  usb-bridge, list-ports, emulate-arduino, simulate-device
  test/                   suite uji otomatis
firmware/                 sketsa Arduino (pawfinder_collar, pawfinder_usb_test)
docs/                     HARDWARE.md, QA_REPORT.md
```

> Buka folder yang berisi `pubspec.yaml` langsung di VS Code/Android Studio. Folder platform (`android`, `ios`, `web`, `windows`, `linux`, `macos`) berasal dari scaffold Flutter; `flutter clean && flutter pub get` membuat ulang berkas lokal.
