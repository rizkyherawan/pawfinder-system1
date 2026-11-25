# Panduan Hardware PawFinder (untuk tim Teknik Komputer)

Dokumen ini adalah **kontrak** antara alat (kalung GPS) dan aplikasi. Selama alat mengikuti kontrak ini, tim Informatika tidak perlu tahu detail rangkaian, dan tim Teknik Komputer tidak perlu tahu detail aplikasi.

> **Keputusan desain:** koneksi alat memakai **kabel USB** (serial) dan **ID alat** (nomor seri). **Bluetooth tidak dipakai** (jangkauan pendek, pairing rawan gagal, dan sulit dibuat stabil untuk pelacakan).

---

## 1. Gambaran singkat

```
[Modul GPS NEO-6M] ──TTL──► [Arduino Uno] ──kabel USB──► [Komputer] ──► Backend PawFinder ──► Aplikasi
                              (firmware)    serial 9600
```

Arduino mengirim **satu baris teks per paket** lewat USB. Backend membaca baris itu (langsung dari port USB, atau lewat program `usb-bridge`), memperbarui status hewan, mengevaluasi geofence, dan aplikasi menampilkannya hampir seketika.

Yang **tidak** perlu dilakukan firmware: menghitung geofence, menyimpan riwayat, atau menentukan "online/offline". Semua itu dikerjakan server. Firmware cukup: **sebut identitasnya, kirim data yang ia punya, dan jalankan perintah.**

## 2. Daftar komponen

| Komponen | Keterangan |
|---|---|
| Arduino Uno + kabel USB **data** | Kabel khusus charger tidak membawa data → port tidak terdeteksi |
| Modul GPS NEO-6M (atau NMEA 9600 baud lain) | Perlu langit terbuka; di dalam ruangan biasanya tanpa sinyal |
| Buzzer aktif 5 V | Opsional, untuk tombol "Bunyikan Kalung" |
| Pembagi tegangan (2 resistor) ke A0 | Opsional, untuk persen baterai |
| Sensor suhu LM35 ke A1 | Opsional |
| Papan klon (CH340) | Perlu driver CH340 di Windows |

## 3. Pengkabelan

| Dari | Ke Arduino Uno |
|---|---|
| GPS **TX** | pin **4** (RX perangkat lunak) |
| GPS **RX** | pin **3** (boleh tidak disambung) |
| GPS VCC / GND | 5 V / GND |
| Buzzer (+) / (–) | pin **8** / GND |
| Pembagi tegangan baterai | **A0** (set `BATTERY_SENSE 1`) |
| LM35 | **A1** (set `HAS_LM35 1`) |

Pin dapat diubah di bagian KONFIGURASI sketsa.

## 4. Langkah kerja bertahap (disarankan)

### Tahap 1 — Buktikan rantai USB tanpa sensor apa pun
1. Arduino IDE → buka `firmware/pawfinder_usb_test/pawfinder_usb_test.ino`.
2. Ubah `DEVICE_ID` (mis. `PF-TST-000001`) → pilih board *Arduino Uno* dan port → **Upload**.
3. **Tutup Serial Monitor.**
4. Di komputer: `cd backend && npm install && npm run ports` lalu `npm run start:usb`.
5. Aplikasi → hewan → *Hubungkan GPS* → tab **Kabel USB** → ketuk **Pasangkan** pada alat yang muncul.
6. Hasil yang benar: status **Online**, titik bergerak melingkar kecil, *Koneksi Alat* menunjukkan paket bertambah tiap 2 detik, tombol *Bunyikan Kalung* membuat LED berkedip.

### Tahap 2 — Kalung nyata dengan GPS
1. Rakit sesuai bagian 3. Buka `firmware/pawfinder_collar/pawfinder_collar.ino`, pasang library **TinyGPSPlus**, ubah `DEVICE_ID`, **Upload**.
2. Bawa ke luar ruangan. LED bawaan menyala saat GPS sudah *fix* (1–5 menit pertama kali).
3. Selama belum fix, aplikasi menampilkan **Online · mencari satelit GPS** dan *tidak* menaruh hewan di lokasi palsu.

### Tahap 3 — Uji geofence
Atur radius kecil (mis. 100 m) di menu Geofence, bawa kalung keluar area → notifikasi **"keluar dari Geofence"** muncul; kembali → **"masuk ke Geofence"**.

## 5. Kontrak protokol

Satu baris = satu paket. UTF-8, akhir baris `\n` (atau `\r\n`), panjang < 1024 karakter, **9600 baud 8N1** (ubah dengan `USB_BAUD` di server **dan** `USB_BAUD` di sketsa).

### 5.1 Perkenalan (kirim saat menyala dan saat menerima `WHO`)
```
PF,HELLO,PF-ABC-123456,1.0.0                 ← CSV
{"hello":"PF-ABC-123456","fw":"1.0.0"}       ← JSON
```
Server memakainya sebagai tanda alat hidup dan segera menyinkronkan interval pengiriman.

### 5.2 Data (kirim periodik)
**CSV (disarankan untuk Uno — hemat RAM):**
```
PF,<ID>,<lat>,<lng>,<baterai>,<fix>,<detak>,<suhu>,<satelit>
PF,PF-ABC-123456,-7.715560,110.355470,87,1,,36.5,8
PF,PF-ABC-123456,,,87,0,,,0                    ← GPS belum fix: koordinat dikosongkan
```
Kolom yang tidak ada **dikosongkan**, tetapi koma tetap ditulis (jumlah kolom harus 9; minimal 5 kolom pertama).

**JSON (lebih fleksibel):**
```json
{"serial":"PF-ABC-123456","lat":-7.71556,"lng":110.35547,"fix":1,"bat":87,"sig":"Kuat","hr":96,"temp":38.6,"sat":7}
```
Nama alias yang diterima: `serial|id|sn`, `lat|latitude`, `lng|lon|long|longitude`, `bat|battery`, `hr|heartRate|bpm`, `temp|temperature`, `sig|signal`, `sat|sats|satellites`, `fix|gpsFix|valid`, `hdop`, `spd|speed` (km/jam), `fw|firmware`.

**NMEA mentah** dari modul GPS (`$GPGGA`, `$GPRMC`, `$GNGGA`, `$GNRMC`) juga diterima. NMEA tidak membawa ID, sehingga ID diisi di server: `USB_SERIAL=PF-ABC-123456` (atau `--serial` pada bridge). Checksum (`*47`) diperiksa bila ada.

### 5.3 Aturan nilai

| Field | Aturan |
|---|---|
| ID (`serial`) | Wajib untuk data, format `PF-` + 3 huruf/angka + `-` + **6 angka**, mis. `PF-ABC-123456`. Tiap kalung **unik**. |
| `lat` / `lng` | −90…90 / −180…180, desimal bertitik. **(0,0) dianggap "belum ada sinyal"**, bukan lokasi. |
| `fix` | `1` = koordinat valid; `0` = belum. `fix=0` membatalkan koordinat yang ikut terkirim. |
| baterai | 0–100 (%) |
| detak / suhu | 20–400 bpm / 20–50 °C; di luar itu dibuang |
| `sig` | `Kuat` / `Sedang` / `Lemah` atau 0–4 batang |

Server **tidak pernah crash** karena baris yang salah: baris tak dikenal dihitung ("baris tak dikenali" di layar Koneksi Alat, lengkap dengan contoh barisnya) lalu dilewati.

### 5.4 Baris komentar / debug
Baris berawalan `#` atau `//` diabaikan. Pakai untuk `Serial.println(F("# debug ..."))`.

### 5.5 Perintah dari server ke alat (satu baris, akhiran `\n`)

| Perintah | Arti | Balasan yang diharapkan |
|---|---|---|
| `PING` | Bunyikan buzzer (tombol "Bunyikan Kalung") | `PF,ACK,PING` |
| `INTERVAL <detik>` | Ubah jeda kirim data (1–3600) | `PF,ACK,INTERVAL` |
| `WHO` | Minta perkenalan ulang | `PF,HELLO,<ID>,<versi>` |

Perintah tidak dikenal harus **diabaikan** tanpa error.

### 5.6 Frekuensi kirim
- Lewat jalur USB, server memproses **paling banyak ±1 paket/detik** per alat; kelebihannya dibuang (pengiriman lebih cepat tidak ada gunanya).
- Alat dinyatakan **Offline** bila tidak ada data selama `max(90 detik, 3 × interval)`, atau **langsung** bila kabel USB dicabut.
- Rekomendasi: 1–5 detik saat demo USB (`FORCE_INTERVAL_SEC` di sketsa); ikuti `INTERVAL` dari aplikasi saat memakai baterai.

## 6. Kalung nirkabel nanti (belum diputuskan)

Arduino Uno **tidak punya radio**, jadi kabel USB hanya cocok untuk prototipe/demo di dekat komputer. Untuk kalung yang benar-benar dipakai hewan, tim perlu memilih **satu** jalur data. **Apa pun pilihannya, kontraknya tetap sama** — alat cukup mengirim paket yang sama lewat HTTP:

```
POST  https://SERVER/api/device/telemetry
Header: Content-Type: application/json
        x-device-key: <DEVICE_KEY dari tim Informatika>
Body  : {"serial":"PF-ABC-123456","lat":-7.71556,"lng":110.35547,"battery":87,"sat":8}
Balas : {"ok":true,"commands":[{"cmd":"ping"}],"config":{"intervalSec":30}}
```
Alat membaca `commands` dan `config.intervalSec` dari balasan setiap kali mengirim.

| Opsi | Catatan |
|---|---|
| ESP32 + Wi-Fi + GPS | Paling mudah dan murah; jangkauan = Wi-Fi |
| Arduino/ESP32 + modul GSM (SIM800L/SIM7600) + GPS | Jangkauan luas, butuh kartu SIM & daya lebih besar |
| LoRa + gateway | Hemat daya & jauh, butuh gateway yang meneruskan ke HTTP |

Hal yang perlu disepakati bersama: (1) pilihan jalur data, (2) cara memberi **ID unik** tiap kalung (stiker/QR + tertanam di firmware), (3) siapa memegang `DEVICE_KEY` (rahasia; jangan dipublikasikan), (4) kapasitas baterai vs interval pengiriman.

## 7. Masalah umum

| Gejala | Penyebab & solusi |
|---|---|
| Port tidak terdeteksi | Kabel hanya-charger; driver CH340/FTDI; coba port USB lain |
| Server: "Access denied" / "busy" | Serial Monitor atau program lain memakai port. Tutup |
| Arduino menyala ulang saat server mulai | Normal: membuka port serial me-reset Uno. Firmware mengirim `HELLO` saat boot |
| Aplikasi: "baris tak dikenali" | Baud rate beda, atau format salah. Contoh barisnya tampil di Koneksi Alat |
| "ID alat belum dipasangkan" | Pasang ID itu di aplikasi (tab Kabel USB) |
| Online tetapi tanpa lokasi | GPS belum fix: ke luar ruangan, tunggu 1–5 menit; periksa kabel GPS TX→pin 4 |
| Koordinat meloncat | Antena GPS terhalang; pantulan sinyal. Pergeseran < 3 m tidak dihitung sebagai langkah (agar kalung yang diam di meja tidak menghasilkan langkah palsu) |

## 8. Daftar periksa serah-terima

- [ ] Tahap 1 lulus (rantai USB, tombol Bunyikan, kabel dicabut → Offline, dicolok → Online lagi)
- [ ] Tiap kalung punya ID unik tertulis di badan alat
- [ ] Kalung fix GPS di luar ruangan dan lokasi tampil benar di peta
- [ ] Uji geofence keluar/masuk menghasilkan notifikasi
- [ ] Dalam ruangan: status "Online · mencari satelit", bukan lokasi palsu
- [ ] `DEVICE_KEY` produksi sudah diganti dan tidak ada di repositori
