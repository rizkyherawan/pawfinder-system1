import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/geo.dart';
import '../data/data_source.dart';
import '../data/demo_data_source.dart';
import '../data/local_store.dart';
import '../data/models.dart';
import '../data/remote_data_source.dart';

/// Pusat state aplikasi: sesi, hewan, notifikasi, pengaturan, dan pembaruan live.
class AppState extends ChangeNotifier {
  AppState(this._store);

  final LocalStore _store;

  // ---------- Sesi ----------
  bool ready = false;
  bool splashDone = false;
  bool onboardingDone = false;
  bool demoMode = false;
  AppUser? user;
  String baseUrl = AppConfig.defaultBaseUrl;
  String? _token;
  late DataSource _ds = RemoteDataSource(baseUrl);

  bool get loggedIn => user != null;

  // ---------- Data ----------
  List<Pet> pets = [];
  String? selectedPetId;
  List<AppNotification> notifications = [];
  AppSettings settings = const AppSettings();
  final Map<String, Geofence> _fences = {};
  int tabIndex = 0;
  bool loadingPets = false;

  Timer? _timer;
  Timer? _splashTimer;
  bool _disposed = false;

  Pet? get selectedPet {
    for (final p in pets) {
      if (p.id == selectedPetId) return p;
    }
    return pets.isEmpty ? null : pets.first;
  }

  Pet? petById(String id) {
    for (final p in pets) {
      if (p.id == id) return p;
    }
    return null;
  }

  int get unreadCount => notifications.where((n) => !n.read).length;

  ThemeMode get themeMode => switch (settings.theme) {
        'gelap' => ThemeMode.dark,
        'sistem' => ThemeMode.system,
        _ => ThemeMode.light,
      };

  List<AppNotification> notificationsBy(String category) =>
      category == 'semua' ? notifications : notifications.where((n) => n.category == category).toList();

  /// Hewan yang berada di luar geofence (untuk catatan di beranda).
  List<Pet> get outsidePets => pets.where((p) => p.isOutside).toList();

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _splashTimer?.cancel();
    super.dispose();
  }

  // ---------- Inisialisasi ----------
  Future<void> init() async {
    onboardingDone = _store.onboardingDone;
    baseUrl = _store.baseUrl ?? AppConfig.defaultBaseUrl;
    settings = _store.settings;
    demoMode = _store.demo;
    _token = _store.token;
    final saved = _store.user;

    if (demoMode && saved != null) {
      _ds = DemoDataSource();
      user = saved;
      await _loadAll(silent: true);
    } else if (_token != null && saved != null) {
      _ds = RemoteDataSource(baseUrl, _token);
      user = saved;
      try {
        await _loadAll(silent: true);
      } on ApiException catch (e) {
        if (e.status == 401) await logout();
        // Jika jaringan bermasalah, tetap masuk dengan data kosong; akan dicoba lagi saat refresh.
      }
    } else {
      _ds = RemoteDataSource(baseUrl);
    }
    ready = true;
    notifyListeners();
  }

  /// Dipanggil Splash setelah animasinya selesai.
  void markSplashElapsed() {
    splashDone = true;
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    onboardingDone = true;
    await _store.setOnboardingDone(true);
    notifyListeners();
  }

  // ---------- Auth ----------
  Future<void> login(String email, String password) async {
    final remote = RemoteDataSource(baseUrl);
    final res = await remote.login(email, password);
    await _startSession(res.token, res.user, demo: false);
  }

  Future<void> register(String name, String email, String password) async {
    final remote = RemoteDataSource(baseUrl);
    final res = await remote.register(name, email, password);
    await _startSession(res.token, res.user, demo: false);
  }

  Future<void> enterDemo() async {
    await _startSession(null, const AppUser(id: 'demo', name: AppConfig.demoName, email: AppConfig.demoEmail), demo: true);
  }

  Future<void> _startSession(String? token, AppUser u, {required bool demo}) async {
    demoMode = demo;
    _token = token;
    _ds = demo ? DemoDataSource() : RemoteDataSource(baseUrl, token);
    pets = [];
    notifications = [];
    _fences.clear();
    selectedPetId = null;
    // Pertahankan tab yang sedang dibuka (mis. Profil saat pengguna baru masuk).
    await _store.saveSession(token: token, user: u, demo: demo);
    user = u;
    try {
      await _loadAll(silent: true);
    } catch (_) {}
    notifyListeners();
  }

  /// Memperbarui profil pemilik akun, bukan profil hewan.
  /// Untuk akun server, perubahan nama disimpan lewat API; demo disimpan lokal.
  Future<void> updateProfile({required String name}) async {
    final cleanName = name.trim();
    if (cleanName.length < 2) {
      throw ApiException('Nama minimal 2 karakter', status: 422, field: 'name');
    }
    final current = user;
    if (current == null) {
      throw ApiException('Masuk atau daftar terlebih dahulu untuk mengubah profil.');
    }

    AppUser updated;
    if (demoMode) {
      updated = AppUser(id: current.id, name: cleanName, email: current.email);
    } else {
      if (_token == null) {
        throw ApiException('Sesi akun tidak valid. Silakan masuk kembali.');
      }
      updated = await RemoteDataSource(baseUrl, _token).updateProfile(cleanName);
    }
    user = updated;
    await _store.saveSession(token: _token, user: updated, demo: demoMode);
    notifyListeners();
  }

  Future<void> logout() async {
    stopLive();
    await _store.clearSession();
    user = null;
    _token = null;
    demoMode = false;
    pets = [];
    notifications = [];
    _fences.clear();
    selectedPetId = null;
    tabIndex = 0;
    _ds = RemoteDataSource(baseUrl);
    notifyListeners();
  }

  Future<void> setBaseUrl(String url) async {
    var v = url.trim();
    if (v.isEmpty) v = AppConfig.defaultBaseUrl;
    if (!v.startsWith('http')) v = 'http://$v';
    baseUrl = v.replaceAll(RegExp(r'/+$'), '');
    await _store.setBaseUrl(baseUrl);
    if (!demoMode) _ds = RemoteDataSource(baseUrl, _token);
    notifyListeners();
  }

  /// Uji koneksi ke backend. Mengembalikan null jika berhasil, atau pesan galat.
  Future<String?> testConnection([String? url]) async {
    try {
      await RemoteDataSource(url ?? baseUrl).ping();
      return null;
    } catch (e) {
      return errorText(e);
    }
  }

  // ---------- Pemuatan data ----------
  Future<void> _loadAll({bool silent = false}) async {
    if (!silent) {
      loadingPets = true;
      notifyListeners();
    }
    try {
      final results = await Future.wait([_ds.getPets(), _ds.getNotifications(), _ds.getSettings()]);
      pets = results[0] as List<Pet>;
      notifications = results[1] as List<AppNotification>;
      final remoteSettings = results[2] as AppSettings;
      // Tema disimpan lokal agar tidak berkedip saat start.
      settings = remoteSettings.copyWith(theme: _store.settings.theme, mapProvider: _store.settings.mapProvider);
      if (selectedPetId == null || petById(selectedPetId!) == null) selectedPetId = pets.isEmpty ? null : pets.first.id;
    } finally {
      loadingPets = false;
      notifyListeners();
    }
  }

  Future<void> refresh({bool silent = false}) async {
    try {
      await _loadAll(silent: silent);
    } on ApiException catch (e) {
      if (e.status == 401) {
        await logout();
        return;
      }
      if (!silent) rethrow;
    }
  }

  Future<void> reloadNotifications() async {
    try {
      notifications = await _ds.getNotifications();
      notifyListeners();
    } catch (_) {}
  }

  // ---------- Hewan ----------
  void selectPet(String id) {
    if (selectedPetId == id) return;
    selectedPetId = id;
    notifyListeners();
  }

  void _replacePet(Pet pet) {
    pets = pets.map((p) => p.id == pet.id ? pet : p).toList();
    notifyListeners();
  }

  Future<Pet> addPet({required String name, required Species species, required String gender, DateTime? birthDate, int avatarColor = 0}) async {
    final pet = await _ds.createPet(name: name, species: species, gender: gender, birthDate: birthDate, avatarColor: avatarColor);
    pets = [...pets, pet];
    selectedPetId = pet.id;
    notifyListeners();
    await reloadNotifications(); // "Hewan baru ditambahkan" langsung muncul di Notifikasi & Riwayat
    return pet;
  }

  Future<void> updatePet(Pet pet) async {
    _replacePet(await _ds.updatePet(pet));
    await reloadNotifications();
  }

  Future<void> deletePet(String id) async {
    await _ds.deletePet(id);
    pets = pets.where((p) => p.id != id).toList();
    _fences.remove(id);
    _photos.remove(id);
    if (selectedPetId == id) selectedPetId = pets.isEmpty ? null : pets.first.id;
    notifyListeners();
    await reloadNotifications();
  }

  // ---------- Foto hewan ----------
  final Map<String, _PhotoEntry> _photos = {};
  final Set<String> _photoLoading = {};

  /// Foto dari cache (null jika belum ada / belum terunduh).
  Uint8List? photoBytes(Pet pet) {
    final e = _photos[pet.id];
    return (pet.hasPhoto && e != null && e.version == pet.photoVersion) ? e.bytes : null;
  }

  Future<void> ensurePhoto(Pet pet) async {
    if (!pet.hasPhoto || photoBytes(pet) != null || _photoLoading.contains(pet.id)) return;
    _photoLoading.add(pet.id);
    try {
      final b = await _ds.getPhoto(pet.id);
      if (b != null) {
        _photos[pet.id] = _PhotoEntry(pet.photoVersion, b);
        notifyListeners();
      }
    } catch (_) {
      // abaikan: avatar ilustrasi tetap dipakai
    } finally {
      _photoLoading.remove(pet.id);
    }
  }

  Future<void> setPetPhoto(String petId, Uint8List bytes) async {
    final pet = await _ds.setPhoto(petId, bytes);
    _photos[petId] = _PhotoEntry(pet.photoVersion, bytes);
    _replacePet(pet);
    await reloadNotifications();
  }

  Future<void> removePetPhoto(String petId) async {
    final pet = await _ds.removePhoto(petId);
    _photos.remove(petId);
    _replacePet(pet);
  }

  // ---------- Koneksi kalung GPS ----------
  /// Memasangkan kalung. Status baru menjadi Online setelah sinyal pertama dari kalung diterima.
  Future<Pet> pairDevice(String petId, String serial) async {
    final pet = await _ds.pairDevice(petId, serial);
    _replacePet(pet);
    await reloadNotifications();
    _burstRefresh();
    return pet;
  }

  Future<void> unpairDevice(String petId) async {
    _replacePet(await _ds.unpairDevice(petId));
    await reloadNotifications();
  }

  /// Segarkan lebih sering sesaat setelah pairing agar perubahan status cepat terlihat.
  void _burstRefresh() {
    for (final s in const [2, 4, 7, 10, 15]) {
      Future<void>.delayed(Duration(seconds: s), () {
        if (!_disposed && loggedIn) refresh(silent: true);
      });
    }
  }

  Future<String> pingDevice(String petId) => _ds.pingDevice(petId);

  Future<void> setDeviceInterval(String petId, int sec) async {
    await _ds.setDeviceInterval(petId, sec);
    pets = pets.map((p) => p.id == petId ? p.copyWith(device: p.device.copyWith(intervalSec: sec)) : p).toList();
    notifyListeners();
  }

  // ---------- Geofence, riwayat, kesehatan ----------
  Geofence? cachedFence(String petId) => _fences[petId];

  Future<Geofence> loadGeofence(String petId) async {
    final g = await _ds.getGeofence(petId);
    _fences[petId] = g;
    return g;
  }

  final Set<String> _fenceLoading = {};

  /// Memuat geofence ke cache sekali saja (aman dipanggil dari build); memberi tahu listener setelah selesai.
  Future<void> ensureGeofence(String petId) async {
    if (_fences.containsKey(petId) || _fenceLoading.contains(petId)) return;
    _fenceLoading.add(petId);
    try {
      await loadGeofence(petId);
      notifyListeners();
    } catch (_) {
      // Abaikan: peta tetap tampil tanpa lingkaran.
    } finally {
      _fenceLoading.remove(petId);
    }
  }

  Future<Geofence> saveGeofence(Geofence g) async {
    final saved = await _ds.saveGeofence(g);
    _fences[g.petId] = saved;
    await refresh(silent: true);
    return saved;
  }

  /// Riwayat = log kejadian yang sama dengan Notifikasi. [petId] null = semua hewan.
  Future<List<TimelineEvent>> history(DateTime date, {String? petId, String category = 'semua'}) => _ds.getHistory(date, petId: petId, category: category);

  Future<ActivitySummary> activity(String petId) => _ds.getActivity(petId);

  Future<HealthSummary> health(String petId) => _ds.getHealth(petId);

  Future<void> addHealthRecord(String petId, {required String type, String title = '', double? value, required DateTime date, String note = ''}) async {
    await _ds.addHealthRecord(petId, type: type, title: title, value: value, date: date, note: note);
    await reloadNotifications();
  }

  Future<void> deleteHealthRecord(String petId, String recordId) => _ds.deleteHealthRecord(petId, recordId);

  /// Titik tengah peta untuk hewan (lokasi terakhir atau rumah).
  GeoPoint focusOf(Pet? p) => p?.location ?? const GeoPoint(kHomeLat, kHomeLng);

  // ---------- Notifikasi ----------
  Future<void> markRead(String id) async {
    notifications = notifications.map((n) => n.id == id ? n.copyWith(read: true) : n).toList();
    notifyListeners();
    try {
      await _ds.markRead(id);
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    notifications = notifications.map((n) => n.copyWith(read: true)).toList();
    notifyListeners();
    try {
      await _ds.markAllRead();
    } catch (_) {}
  }

  Future<void> deleteNotification(String id) async {
    notifications = notifications.where((n) => n.id != id).toList();
    notifyListeners();
    try {
      await _ds.deleteNotification(id);
    } catch (_) {}
  }

  Future<void> clearNotifications() async {
    notifications = [];
    notifyListeners();
    try {
      await _ds.clearNotifications();
    } catch (_) {}
  }

  // ---------- Pengaturan ----------
  Future<void> updateSettings(AppSettings s) async {
    settings = s;
    await _store.saveSettings(s);
    notifyListeners();
    try {
      await _ds.saveSettings(s);
    } catch (_) {}
    if (_timer != null) startLive(); // sesuaikan interval jika mode hemat daya berubah
  }

  void setTab(int i) {
    if (tabIndex == i) return;
    tabIndex = i;
    notifyListeners();
  }

  // ---------- Pembaruan live ----------
  /// Polling berkala untuk lokasi & notifikasi. Interval lebih panjang saat Mode Hemat Daya.
  void startLive() {
    _timer?.cancel();
    final every = Duration(seconds: settings.powerSave ? 15 : 5);
    _timer = Timer.periodic(every, (_) async {
      if (!loggedIn) return;
      await refresh(silent: true);
    });
  }

  void stopLive() {
    _timer?.cancel();
    _timer = null;
  }
}

class _PhotoEntry {
  const _PhotoEntry(this.version, this.bytes);
  final int version;
  final Uint8List bytes;
}
