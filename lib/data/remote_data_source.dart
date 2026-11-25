import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/utils.dart';
import 'data_source.dart';
import 'models.dart';

/// Terhubung ke backend PawFinder (REST API + JWT).
class RemoteDataSource implements DataSource {
  RemoteDataSource(String baseUrl, [this.token]) : baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  final String baseUrl;
  final String? token;
  static const _timeout = Duration(seconds: 12);

  Uri _uri(String path) {
    try {
      return Uri.parse('$baseUrl$path');
    } on FormatException {
      throw ApiException('Alamat server tidak valid: $baseUrl');
    }
  }

  Future<Map<String, dynamic>> _send(String method, String path, {Object? body}) async {
    final uri = _uri(path);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final payload = jsonEncode(body ?? <String, dynamic>{});
    late http.Response res;
    try {
      switch (method) {
        case 'POST':
          res = await http.post(uri, headers: headers, body: payload).timeout(_timeout);
          break;
        case 'PUT':
          res = await http.put(uri, headers: headers, body: payload).timeout(_timeout);
          break;
        case 'PATCH':
          res = await http.patch(uri, headers: headers, body: payload).timeout(_timeout);
          break;
        case 'DELETE':
          res = await http.delete(uri, headers: headers).timeout(_timeout);
          break;
        default:
          res = await http.get(uri, headers: headers).timeout(_timeout);
      }
    } on TimeoutException {
      throw ApiException('Server tidak merespons. Periksa koneksi atau alamat server.', network: true);
    } catch (_) {
      throw ApiException('Tidak dapat terhubung ke server ($baseUrl). Pastikan backend berjalan.', network: true);
    }

    var data = <String, dynamic>{};
    var jsonObject = false;
    if (res.bodyBytes.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
          jsonObject = true;
        }
      } catch (_) {}
    }
    if (res.statusCode >= 400) {
      throw ApiException('${data['error'] ?? 'Terjadi kesalahan (${res.statusCode})'}', status: res.statusCode, field: data['field']?.toString());
    }
    if (res.bodyBytes.isNotEmpty && !jsonObject) {
      // Berhasil (2xx) tetapi bukan JSON: alamat server kemungkinan menunjuk ke program lain, bukan backend PawFinder.
      throw ApiException('Respons server tidak dikenali. Pastikan alamat menunjuk ke backend PawFinder.', status: res.statusCode);
    }
    return data;
  }

  List<Map<String, dynamic>> _maps(dynamic v) => ((v as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  // ---------- Auth ----------
  Future<bool> ping() async {
    await _send('GET', '/api/ping');
    return true;
  }

  Future<AuthResult> login(String email, String password) async {
    final d = await _send('POST', '/api/auth/login', body: {'email': email.trim(), 'password': password});
    return AuthResult('${d['token']}', AppUser.fromJson(Map<String, dynamic>.from(d['user'] as Map)));
  }

  Future<AuthResult> register(String name, String email, String password) async {
    final d = await _send('POST', '/api/auth/register', body: {'name': name.trim(), 'email': email.trim(), 'password': password});
    return AuthResult('${d['token']}', AppUser.fromJson(Map<String, dynamic>.from(d['user'] as Map)));
  }

  /// Memperbarui profil akun yang sedang masuk. Backend saat ini menerima perubahan nama.
  Future<AppUser> updateProfile(String name) async {
    final d = await _send('PUT', '/api/auth/me', body: {'name': name.trim()});
    return AppUser.fromJson(Map<String, dynamic>.from(d['user'] as Map));
  }

  // ---------- Hewan ----------
  Pet _pet(Map<String, dynamic> d) => Pet.fromJson(Map<String, dynamic>.from(d['pet'] as Map));

  @override
  Future<List<Pet>> getPets() async => _maps((await _send('GET', '/api/pets'))['pets']).map(Pet.fromJson).toList();

  @override
  Future<Pet> createPet({required String name, required Species species, required String gender, DateTime? birthDate, int avatarColor = 0}) async =>
      _pet(await _send('POST', '/api/pets', body: {
        'name': name.trim(),
        'species': species.name,
        'gender': gender,
        'birthDate': birthDate == null ? null : isoDate(birthDate),
        'avatarColor': avatarColor,
      }));

  @override
  Future<Pet> updatePet(Pet pet) async => _pet(await _send('PUT', '/api/pets/${pet.id}', body: {
        'name': pet.name.trim(),
        'species': pet.species.name,
        'gender': pet.gender,
        'birthDate': pet.birthDate == null ? null : isoDate(pet.birthDate!),
        'avatarColor': pet.avatarColor,
      }));

  @override
  Future<void> deletePet(String id) async => _send('DELETE', '/api/pets/$id');

  // ---------- Foto ----------
  @override
  Future<Pet> setPhoto(String petId, Uint8List bytes) async => _pet(await _send('PUT', '/api/pets/$petId/photo', body: {'data': base64Encode(bytes)}));

  @override
  Future<Pet> removePhoto(String petId) async => _pet(await _send('DELETE', '/api/pets/$petId/photo'));

  @override
  Future<Uint8List?> getPhoto(String petId) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/pets/$petId/photo'), headers: {if (token != null) 'Authorization': 'Bearer $token'}).timeout(_timeout);
      return res.statusCode == 200 ? res.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  // ---------- Koneksi kalung GPS ----------
  @override
  Future<Pet> pairDevice(String petId, String serial) async => _pet(await _send('POST', '/api/pets/$petId/device/pair', body: {'serial': serial.trim()}));

  @override
  Future<Pet> unpairDevice(String petId) async => _pet(await _send('POST', '/api/pets/$petId/device/unpair'));

  @override
  Future<void> setDeviceInterval(String petId, int sec) async => _send('PUT', '/api/pets/$petId/device', body: {'intervalSec': sec});

  @override
  Future<String> pingDevice(String petId) async => '${(await _send('POST', '/api/pets/$petId/device/ping'))['message'] ?? 'Kalung dibunyikan'}';

  @override
  Future<DeviceLive> getDeviceLive(String petId) async =>
      DeviceLive.fromJson(Map<String, dynamic>.from((await _send('GET', '/api/pets/$petId/device/live'))['live'] as Map));

  @override
  Future<List<DiscoveredDevice>> getDiscoveredDevices() async => _maps((await _send('GET', '/api/devices/discovered'))['devices']).map(DiscoveredDevice.fromJson).toList();

  @override
  Future<UsbStatus> getUsbStatus() async => UsbStatus.fromJson(Map<String, dynamic>.from((await _send('GET', '/api/usb/status'))['usb'] as Map));

  // ---------- Geofence ----------
  @override
  Future<Geofence> getGeofence(String petId) async => Geofence.fromJson(Map<String, dynamic>.from((await _send('GET', '/api/pets/$petId/geofence'))['geofence'] as Map));

  @override
  Future<Geofence> saveGeofence(Geofence g) async {
    final d = await _send('PUT', '/api/pets/${g.petId}/geofence', body: {
      'radius': g.radius,
      'notifyExit': g.notifyExit,
      'notifyEnter': g.notifyEnter,
      'center': g.center.toJson(),
    });
    return Geofence.fromJson(Map<String, dynamic>.from(d['geofence'] as Map));
  }

  // ---------- Riwayat, aktivitas, kesehatan ----------
  @override
  Future<List<TimelineEvent>> getHistory(DateTime date, {String? petId, String category = 'semua'}) async {
    final q = '?date=${dateKey(date)}&category=$category${petId == null ? '' : '&petId=$petId'}';
    return _maps((await _send('GET', '/api/history$q'))['events']).map(TimelineEvent.fromJson).toList();
  }

  @override
  Future<ActivitySummary> getActivity(String petId) async =>
      ActivitySummary.fromJson(Map<String, dynamic>.from((await _send('GET', '/api/pets/$petId/activity'))['activity'] as Map));

  @override
  Future<HealthSummary> getHealth(String petId) async => HealthSummary.fromJson(Map<String, dynamic>.from((await _send('GET', '/api/pets/$petId/health'))['health'] as Map));

  @override
  Future<void> addHealthRecord(String petId, {required String type, String title = '', double? value, required DateTime date, String note = ''}) async =>
      _send('POST', '/api/pets/$petId/health-records', body: {'type': type, 'title': title, 'value': value, 'date': isoDate(date), 'note': note});

  @override
  Future<void> deleteHealthRecord(String petId, String recordId) async => _send('DELETE', '/api/pets/$petId/health-records/$recordId');

  // ---------- Notifikasi ----------
  @override
  Future<List<AppNotification>> getNotifications() async => _maps((await _send('GET', '/api/notifications'))['notifications']).map(AppNotification.fromJson).toList();

  @override
  Future<void> markAllRead() async => _send('POST', '/api/notifications/read-all');

  @override
  Future<void> markRead(String id) async => _send('PATCH', '/api/notifications/$id/read');

  @override
  Future<void> deleteNotification(String id) async => _send('DELETE', '/api/notifications/$id');

  @override
  Future<void> clearNotifications() async => _send('DELETE', '/api/notifications');

  // ---------- Pengaturan ----------
  @override
  Future<AppSettings> getSettings() async => AppSettings.fromJson(Map<String, dynamic>.from((await _send('GET', '/api/settings'))['settings'] as Map));

  @override
  Future<AppSettings> saveSettings(AppSettings s) async =>
      AppSettings.fromJson(Map<String, dynamic>.from((await _send('PUT', '/api/settings', body: s.toJson()))['settings'] as Map));
}
