import 'dart:typed_data';

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status, this.network = false, this.field});
  final String message;
  final int? status;
  final bool network;
  final String? field;
  @override
  String toString() => message;
}

String errorText(Object e) => e is ApiException ? e.message : 'Terjadi kesalahan. Coba lagi.';

class AuthResult {
  const AuthResult(this.token, this.user);
  final String token;
  final AppUser user;
}

/// Kontrak sumber data. Diimplementasikan oleh [RemoteDataSource] (backend)
/// dan [DemoDataSource] (data lokal untuk mode demo tanpa server).
abstract class DataSource {
  // Hewan
  Future<List<Pet>> getPets();
  Future<Pet> createPet({required String name, required Species species, required String gender, DateTime? birthDate, int avatarColor = 0});
  Future<Pet> updatePet(Pet pet);
  Future<void> deletePet(String id);

  // Foto
  Future<Pet> setPhoto(String petId, Uint8List bytes);
  Future<Pet> removePhoto(String petId);
  Future<Uint8List?> getPhoto(String petId);

  // Koneksi kalung GPS
  Future<Pet> pairDevice(String petId, String serial);
  Future<Pet> unpairDevice(String petId);
  Future<void> setDeviceInterval(String petId, int sec);
  Future<String> pingDevice(String petId);

  // Geofence
  Future<Geofence> getGeofence(String petId);
  Future<Geofence> saveGeofence(Geofence g);

  // Riwayat = log kejadian yang sama dengan notifikasi
  Future<List<TimelineEvent>> getHistory(DateTime date, {String? petId, String category = 'semua'});

  // Aktivitas dan Kesehatan adalah dua fitur terpisah
  Future<ActivitySummary> getActivity(String petId);
  Future<HealthSummary> getHealth(String petId);
  Future<void> addHealthRecord(String petId, {required String type, String title = '', double? value, required DateTime date, String note = ''});
  Future<void> deleteHealthRecord(String petId, String recordId);

  // Notifikasi
  Future<List<AppNotification>> getNotifications();
  Future<void> markAllRead();
  Future<void> markRead(String id);
  Future<void> deleteNotification(String id);
  Future<void> clearNotifications();

  // Pengaturan
  Future<AppSettings> getSettings();
  Future<AppSettings> saveSettings(AppSettings s);
}
