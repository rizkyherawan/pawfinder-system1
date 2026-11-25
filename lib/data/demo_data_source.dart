import 'dart:math' as math;
import 'dart:typed_data';

import '../core/constants.dart';
import '../core/geo.dart';
import '../core/utils.dart';
import 'data_source.dart';
import 'models.dart';

/// Sumber data lokal untuk mode demo (tanpa server).
/// Mulai KOSONG: tidak ada hewan, riwayat, atau notifikasi bawaan. Alurnya meniru backend:
/// hewan baru belum terhubung -> dipasangkan ke kalung -> baru Online setelah "sinyal pertama" masuk.
class DemoDataSource implements DataSource {
  final _rand = math.Random();
  final _home = const GeoPoint(kHomeLat, kHomeLng);
  final List<Pet> _pets = [];
  final Map<String, Geofence> _fences = {};
  final Map<String, double> _heading = {};
  final Map<String, DateTime> _pairedAt = {};
  final Map<String, bool> _everOnline = {};
  final Map<String, Uint8List> _photos = {};
  final Map<String, List<HealthRecord>> _records = {};
  final Map<String, List<num>> _today = {}; // steps, km, menit
  final Map<String, SensorReading> _sensor = {};
  final List<TimelineEvent> _events = [];
  final List<AppNotification> _notifs = [];
  AppSettings _settings = const AppSettings();
  int _seq = 0;

  String _id(String p) => '${p}_${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  static const _category = {
    'exit': 'geofence', 'enter': 'geofence', 'geofence_updated': 'geofence',
    'battery': 'sistem', 'gps_paired': 'sistem', 'gps_connected': 'sistem', 'gps_offline': 'sistem', 'gps_unpaired': 'sistem',
    'pet_added': 'hewan', 'pet_updated': 'hewan', 'pet_deleted': 'hewan', 'health_record': 'kesehatan',
  };

  /// Satu log kejadian untuk Riwayat dan Notifikasi (isi identik).
  void _log(String type, String title, String subtitle, {String petId = '', bool notify = true}) {
    final t = DateTime.now();
    final cat = _category[type] ?? 'sistem';
    _events.insert(0, TimelineEvent(id: _id('evt'), petId: petId, category: cat, type: type, title: title, subtitle: subtitle, time: t));
    if (notify) _notifs.insert(0, AppNotification(id: _id('ntf'), petId: petId, category: cat, type: type, title: title, subtitle: subtitle, time: t));
  }

  int _idx(String id) {
    final i = _pets.indexWhere((p) => p.id == id);
    if (i < 0) throw ApiException('Hewan tidak ditemukan', status: 404);
    return i;
  }

  /// Satu langkah simulasi: sinyal pertama kalung, gerak hewan, geofence, baterai.
  void _tick() {
    final now = DateTime.now();
    for (var i = 0; i < _pets.length; i++) {
      final p = _pets[i];
      if (!p.device.paired) continue;
      final fence = _fences[p.id];
      final home = fence?.center ?? _home;

      // Sinyal pertama datang ±2 detik setelah dipasangkan -> baru status Online.
      if (p.device.waiting) {
        final at = _pairedAt[p.id] ?? now;
        if (now.difference(at).inMilliseconds < 2000) continue;
        final first = movePoint(home, _rand.nextDouble() * 6.28, 15 + _rand.nextDouble() * 45);
        _pets[i] = p.copyWith(
          location: first,
          address: kHomeAddress,
          locationUpdatedAt: now,
          insideGeofence: true,
          device: p.device.copyWith(connection: 'online', battery: 100, signal: 'Kuat', lastSeen: now, gpsFix: true, satellites: 7, source: 'simulator'),
        );
        final firstTime = _everOnline[p.id] != true;
        _everOnline[p.id] = true;
        _log('gps_connected', firstTime ? 'GPS terhubung' : 'Koneksi GPS tersambung kembali', '${p.name} kini dilacak secara real-time', petId: p.id);
        continue;
      }
      if (!p.device.online || p.location == null) continue;

      final cur = p.location!;
      final wander = 90 + (p.id.hashCode.abs() % 120);
      var h = (_heading[p.id] ?? _rand.nextDouble() * 6.28) + (_rand.nextDouble() - 0.5) * 0.9;
      if (distanceMeters(cur, home) > wander) h = bearingTo(cur, home) + (_rand.nextDouble() - 0.5) * 0.5;
      _heading[p.id] = h;
      final step = 4 + _rand.nextDouble() * 10;
      final next = movePoint(cur, h, step);
      var battery = p.device.battery ?? 100;
      if (_rand.nextDouble() < 0.04) battery = math.max(3, battery - 1);

      var inside = p.insideGeofence ?? true;
      if (fence != null) {
        final nowInside = distanceMeters(fence.center, next) <= fence.radius;
        if (nowInside != inside) {
          inside = nowInside;
          if (inside) {
            _log('enter', '${p.name} masuk ke Geofence', 'Area ${fence.name}', petId: p.id, notify: fence.notifyEnter);
          } else {
            _log('exit', '${p.name} keluar dari Geofence', 'Di luar area ${fence.name}', petId: p.id, notify: fence.notifyExit);
          }
        }
      }
      if (battery <= 20 && (p.device.battery ?? 100) > 20) {
        _log('battery', 'Baterai perangkat rendah', '${p.name} · Baterai $battery% · Segera isi daya', petId: p.id);
      }
      final t = _today.putIfAbsent(p.id, () => [0, 0.0, 0.0]);
      t[0] = t[0].toInt() + (step / 0.6).round();
      t[1] = t[1].toDouble() + step / 1000;
      t[2] = t[2].toDouble() + 0.07;
      _sensor[p.id] = SensorReading(available: true, live: true, heartRate: 88 + _rand.nextInt(16), temperature: 38.3 + _rand.nextInt(5) / 10);
      _pets[i] = p.copyWith(
        location: next,
        address: distanceMeters(next, _home) < 60 ? kHomeAddress : 'Sekitar ${p.geofenceName}',
        locationUpdatedAt: now,
        insideGeofence: inside,
        device: p.device.copyWith(battery: battery, lastSeen: now, connection: 'online', gpsFix: true, satellites: 6 + _rand.nextInt(4)),
      );
    }
  }

  // ---------- Hewan ----------
  @override
  Future<List<Pet>> getPets() async {
    _tick();
    return List<Pet>.unmodifiable(_pets);
  }

  @override
  Future<Pet> createPet({required String name, required Species species, required String gender, DateTime? birthDate, int avatarColor = 0}) async {
    // Aturan yang sama dengan backend, agar perilaku demo dan server tidak berbeda.
    if (name.trim().isEmpty) throw ApiException('Nama hewan wajib diisi', status: 422, field: 'name');
    if (name.trim().length > 30) throw ApiException('Nama hewan maksimal 30 karakter', status: 422, field: 'name');
    if (birthDate == null) throw ApiException('Tanggal lahir wajib diisi', status: 422, field: 'birthDate');
    if (birthDate.isAfter(DateTime.now().add(const Duration(days: 1)))) throw ApiException('Tanggal lahir tidak boleh di masa depan', status: 422, field: 'birthDate');
    final pet = Pet(id: _id('pet'), name: name.trim(), species: species, gender: gender, birthDate: birthDate, avatarColor: avatarColor, device: const DeviceInfo());
    _pets.add(pet);
    _fences[pet.id] = Geofence(petId: pet.id, center: _home, radius: 500);
    _records[pet.id] = [];
    _log('pet_added', 'Hewan baru ditambahkan', '${pet.name} (${species.label}) berhasil didaftarkan · Hubungkan kalung GPS untuk mulai melacak', petId: pet.id);
    return pet;
  }

  @override
  Future<Pet> updatePet(Pet pet) async {
    if (pet.name.trim().isEmpty) throw ApiException('Nama hewan wajib diisi', status: 422, field: 'name');
    if (pet.name.trim().length > 30) throw ApiException('Nama hewan maksimal 30 karakter', status: 422, field: 'name');
    if (pet.birthDate == null) throw ApiException('Tanggal lahir wajib diisi', status: 422, field: 'birthDate');
    final i = _idx(pet.id);
    final old = _pets[i];
    _pets[i] = old.copyWith(name: pet.name, species: pet.species, gender: pet.gender, birthDate: pet.birthDate, clearBirth: pet.birthDate == null, avatarColor: pet.avatarColor);
    _log('pet_updated', 'Profil hewan diperbarui', 'Data ${pet.name} berhasil disimpan', petId: pet.id);
    return _pets[i];
  }

  @override
  Future<void> deletePet(String id) async {
    final pet = _pets[_idx(id)];
    _pets.removeAt(_idx(id));
    _fences.remove(id);
    _photos.remove(id);
    _records.remove(id);
    _today.remove(id);
    _events.removeWhere((e) => e.petId == id);
    _notifs.removeWhere((n) => n.petId == id);
    _log('pet_deleted', 'Data hewan dihapus', '${pet.name} telah dihapus dari akunmu');
  }

  // ---------- Foto ----------
  @override
  Future<Pet> setPhoto(String petId, Uint8List bytes) async {
    final i = _idx(petId);
    _photos[petId] = bytes;
    _pets[i] = _pets[i].copyWith(photoVersion: DateTime.now().millisecondsSinceEpoch);
    _log('pet_updated', 'Foto profil diperbarui', 'Foto ${_pets[i].name} berhasil disimpan', petId: petId);
    return _pets[i];
  }

  @override
  Future<Pet> removePhoto(String petId) async {
    final i = _idx(petId);
    _photos.remove(petId);
    _pets[i] = _pets[i].copyWith(photoVersion: 0);
    return _pets[i];
  }

  @override
  Future<Uint8List?> getPhoto(String petId) async => _photos[petId];

  // ---------- Koneksi kalung GPS ----------
  @override
  Future<Pet> pairDevice(String petId, String serial) async {
    final i = _idx(petId);
    final s = serial.trim().toUpperCase();
    if (!RegExp(r'^PF-[A-Z0-9]{3}-\d{6}$').hasMatch(s)) throw ApiException('Format nomor seri tidak valid. Contoh: PF-ABC-123456', status: 422, field: 'serial');
    if (_pets.any((p) => p.id != petId && p.device.paired && p.device.serial == s)) throw ApiException('Nomor seri ini sudah dipakai oleh hewan lain', status: 409, field: 'serial');
    if (_pets[i].device.paired) throw ApiException('Hewan ini sudah terhubung ke kalung. Putuskan dulu untuk mengganti.', status: 409);
    _pairedAt[petId] = DateTime.now();
    _everOnline[petId] = false;
    _pets[i] = _pets[i].copyWith(device: DeviceInfo(serial: s, paired: true, connection: 'waiting'), clearInside: true);
    _log('gps_paired', 'Kalung GPS dipasangkan', '$s · Menunggu sinyal dari kalung ${_pets[i].name}', petId: petId);
    return _pets[i];
  }

  @override
  Future<Pet> unpairDevice(String petId) async {
    final i = _idx(petId);
    final serial = _pets[i].device.serial ?? '-';
    _pets[i] = _pets[i].copyWith(device: const DeviceInfo(), clearLocation: true, clearInside: true);
    _log('gps_unpaired', 'GPS diputuskan', 'Kalung $serial dilepas dari ${_pets[i].name}', petId: petId);
    return _pets[i];
  }

  @override
  Future<void> setDeviceInterval(String petId, int sec) async {
    final i = _idx(petId);
    _pets[i] = _pets[i].copyWith(device: _pets[i].device.copyWith(intervalSec: sec));
  }

  @override
  Future<String> pingDevice(String petId) async {
    final pet = _pets[_idx(petId)];
    if (!pet.device.paired) throw ApiException('Kalung belum terhubung', status: 409);
    if (!pet.device.online) throw ApiException('Kalung sedang offline, tidak dapat dibunyikan', status: 409);
    return 'Perintah bunyi dikirim ke kalung ${pet.name}';
  }

  @override
  Future<DeviceLive> getDeviceLive(String petId) async {
    final p = _pets[_idx(petId)];
    final s = _sensor[petId];
    final seen = p.device.lastSeen;
    return DeviceLive(
      paired: p.device.paired,
      serial: p.device.serial,
      connection: p.device.connection,
      source: p.device.paired ? 'simulator' : null,
      packets: seen == null ? 0 : 1,
      lastPacketAt: seen,
      ageSec: seen == null ? null : DateTime.now().difference(seen).inSeconds,
      gpsFix: p.device.gpsFix,
      locationMode: p.location == null ? null : 'gps',
      satellites: p.device.satellites,
      lat: p.location?.lat,
      lng: p.location?.lng,
      address: p.address.isEmpty ? null : p.address,
      battery: p.device.battery,
      signal: p.device.signal,
      heartRate: s?.heartRate,
      temperature: s?.temperature,
      firmware: p.device.firmware,
    );
  }

  @override
  Future<List<DiscoveredDevice>> getDiscoveredDevices() async => const [];

  @override
  Future<UsbStatus> getUsbStatus() async => const UsbStatus(enabled: false, hint: 'Mode demo memakai data simulasi di dalam aplikasi. Untuk alat nyata, keluar dari mode demo lalu masuk dengan akun yang terhubung ke server.');

  // ---------- Geofence ----------
  @override
  Future<Geofence> getGeofence(String petId) async => _fences[petId] ?? Geofence(petId: petId, center: _home);

  @override
  Future<Geofence> saveGeofence(Geofence g) async {
    _fences[g.petId] = g;
    final i = _idx(g.petId);
    final loc = _pets[i].location;
    if (loc != null) _pets[i] = _pets[i].copyWith(insideGeofence: distanceMeters(g.center, loc) <= g.radius);
    _log('geofence_updated', 'Geofence diperbarui', '${_pets[i].name} · Radius ${fmtRadius(g.radius)} · Notifikasi keluar area ${g.notifyExit ? 'aktif' : 'nonaktif'}', petId: g.petId);
    return g;
  }

  // ---------- Riwayat ----------
  @override
  Future<List<TimelineEvent>> getHistory(DateTime date, {String? petId, String category = 'semua'}) async {
    return _events.where((e) {
      if (petId != null && e.petId != petId) return false;
      if (category != 'semua' && e.category != category) return false;
      return sameDay(wib(e.time), date);
    }).toList()
      ..sort((a, b) => b.time.compareTo(a.time));
  }

  // ---------- Aktivitas & Kesehatan ----------
  @override
  Future<ActivitySummary> getActivity(String petId) async {
    final pet = _pets[_idx(petId)];
    final t = _today[petId] ?? [0, 0.0, 0.0];
    final steps = t[0].toInt();
    final minutes = t[2].round();
    final w = wibNow();
    const labels = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    final week = <DayStat>[
      for (var i = 6; i >= 0; i--)
        DayStat(date: dateKey(DateTime.utc(w.year, w.month, w.day - i)), label: labels[DateTime.utc(w.year, w.month, w.day - i).weekday - 1], minutes: i == 0 ? minutes : 0),
    ];
    return ActivitySummary(
      connected: pet.device.paired,
      steps: steps,
      goal: AppConfig.dailyStepGoal,
      distanceKm: (t[1].toDouble() * 10).round() / 10,
      activeMinutes: minutes,
      calories: (steps * 0.051).round(),
      week: week,
    );
  }

  @override
  Future<HealthSummary> getHealth(String petId) async {
    _idx(petId);
    final recs = List<HealthRecord>.from(_records[petId] ?? const [])..sort((a, b) => b.date.compareTo(a.date));
    HealthRecord? weight, vaccine;
    for (final r in recs) {
      if (r.type == 'berat') weight ??= r;
      if (r.type == 'vaksin') vaccine ??= r;
    }
    return HealthSummary(
      sensor: _sensor[petId] ?? const SensorReading(),
      records: recs,
      latestWeightKg: weight?.value,
      lastVaccineTitle: vaccine?.title,
      lastVaccineDate: vaccine?.date,
    );
  }

  @override
  Future<void> addHealthRecord(String petId, {required String type, String title = '', double? value, required DateTime date, String note = ''}) async {
    final pet = _pets[_idx(petId)];
    if (type == 'berat') {
      if (value == null || value <= 0 || value > 200) throw ApiException('Berat harus antara 0,1 dan 200 kg', status: 422, field: 'value');
    } else if (title.trim().isEmpty) {
      throw ApiException('Judul catatan wajib diisi', status: 422, field: 'title');
    }
    final rec = HealthRecord(
      id: _id('rec'), petId: petId, type: type, title: type == 'berat' ? 'Berat badan' : title.trim(),
      date: dateKey(date), value: value == null ? null : (value * 10).round() / 10, note: note.trim(),
    );
    (_records[petId] ??= []).add(rec);
    _log('health_record', 'Catatan kesehatan ditambahkan', '${pet.name} · ${type == 'berat' ? 'Berat ${fmtDecimal(rec.value ?? 0)} kg' : rec.title}', petId: petId);
  }

  @override
  Future<void> deleteHealthRecord(String petId, String recordId) async => _records[petId]?.removeWhere((r) => r.id == recordId);

  // ---------- Notifikasi ----------
  @override
  Future<List<AppNotification>> getNotifications() async => List<AppNotification>.unmodifiable(_notifs);

  @override
  Future<void> markAllRead() async {
    for (var i = 0; i < _notifs.length; i++) {
      _notifs[i] = _notifs[i].copyWith(read: true);
    }
  }

  @override
  Future<void> markRead(String id) async {
    final i = _notifs.indexWhere((n) => n.id == id);
    if (i >= 0) _notifs[i] = _notifs[i].copyWith(read: true);
  }

  @override
  Future<void> deleteNotification(String id) async => _notifs.removeWhere((n) => n.id == id);

  @override
  Future<void> clearNotifications() async => _notifs.clear();

  // ---------- Pengaturan ----------
  @override
  Future<AppSettings> getSettings() async => _settings;

  @override
  Future<AppSettings> saveSettings(AppSettings s) async => _settings = s;
}
