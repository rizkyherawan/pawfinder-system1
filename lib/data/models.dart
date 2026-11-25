import '../core/geo.dart';
import '../core/utils.dart';

double _d(dynamic v, [double def = 0]) {
  if (v == null) return def;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? def;
}

int _i(dynamic v, [int def = 0]) {
  if (v == null) return def;
  if (v is num) return v.round();
  return int.tryParse(v.toString()) ?? def;
}

int? _iOrNull(dynamic v) => v == null ? null : _i(v);
double? _dOrNull(dynamic v) => v == null ? null : _d(v);
String? _sOrNull(dynamic v) => v?.toString();
DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

String isoDate(DateTime d) => dateKey(d);

enum Species { anjing, kucing, kelinci }

extension SpeciesX on Species {
  String get label => switch (this) { Species.anjing => 'Anjing', Species.kucing => 'Kucing', Species.kelinci => 'Kelinci' };
  String get emoji => switch (this) { Species.anjing => '🐶', Species.kucing => '🐱', Species.kelinci => '🐰' };
}

Species speciesFrom(String? s) => Species.values.firstWhere((e) => e.name == (s ?? '').toLowerCase(), orElse: () => Species.anjing);

class AppUser {
  const AppUser({required this.id, required this.name, required this.email});
  final String id, name, email;

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(id: '${j['id']}', name: '${j['name']}', email: '${j['email']}');
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email};
}

class AppSettings {
  const AppSettings({this.push = true, this.sound = true, this.powerSave = false, this.theme = 'terang', this.mapProvider = 'google'});
  final bool push, sound, powerSave;
  final String theme; // terang | gelap | sistem
  final String mapProvider; // google | ilustrasi (disimpan lokal)

  AppSettings copyWith({bool? push, bool? sound, bool? powerSave, String? theme, String? mapProvider}) => AppSettings(
        push: push ?? this.push,
        sound: sound ?? this.sound,
        powerSave: powerSave ?? this.powerSave,
        theme: theme ?? this.theme,
        mapProvider: mapProvider ?? this.mapProvider,
      );

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        push: j['push'] != false,
        sound: j['sound'] != false,
        powerSave: j['powerSave'] == true,
        theme: ['terang', 'gelap', 'sistem'].contains(j['theme']) ? j['theme'] as String : 'terang',
        mapProvider: j['mapProvider'] == 'ilustrasi' ? 'ilustrasi' : 'google',
      );
  Map<String, dynamic> toJson() => {'push': push, 'sound': sound, 'powerSave': powerSave, 'theme': theme, 'mapProvider': mapProvider};
}

/// Status koneksi kalung GPS.
/// unpaired = belum dipasangkan · waiting = dipasangkan, menunggu sinyal pertama ·
/// online = mengirim data · offline = berhenti mengirim data.
class DeviceInfo {
  const DeviceInfo({
    this.serial,
    this.firmware = '1.2.0',
    this.battery,
    this.signal,
    this.paired = false,
    this.connection = 'unpaired',
    this.lastSeen,
    this.intervalSec = 30,
    this.gpsFix,
    this.satellites,
    this.source,
  });

  final String? serial, signal;
  final String firmware, connection;
  final int? battery;
  final int intervalSec;
  final bool paired;
  final DateTime? lastSeen;

  /// true = lokasi GPS valid pada paket terakhir · false = alat hidup tetapi belum mendapat satelit · null = belum ada paket.
  final bool? gpsFix;
  final int? satellites;

  /// Jalur data: 'usb' (kabel), 'http' (jaringan), 'simulator' (data demo dari server), atau null.
  final String? source;

  /// Alat terhubung, tetapi belum ada lokasi (mis. di dalam ruangan).
  bool get searchingSatellites => online && gpsFix == false;
  String get sourceLabel => switch (source) { 'usb' => 'Kabel USB', 'http' => 'Jaringan (HTTP)', 'simulator' => 'Simulator (data demo)', _ => 'Belum ada data' };

  bool get online => connection == 'online';
  bool get waiting => connection == 'waiting';
  bool get offline => connection == 'offline';

  String get statusLabel => switch (connection) { 'online' => 'Online', 'waiting' => 'Menghubungkan', 'offline' => 'Offline', _ => 'Belum terhubung' };
  String get linkText => switch (connection) { 'online' => 'GPS terhubung', 'waiting' => 'Menunggu sinyal', 'offline' => 'GPS terputus', _ => 'GPS belum terhubung' };

  factory DeviceInfo.fromJson(Map<String, dynamic> j) => DeviceInfo(
        serial: _sOrNull(j['serial']),
        firmware: '${j['firmware'] ?? '1.2.0'}',
        battery: _iOrNull(j['battery']),
        signal: _sOrNull(j['signal']),
        paired: j['paired'] == true,
        connection: '${j['connection'] ?? 'unpaired'}',
        lastSeen: _dt(j['lastSeen']),
        intervalSec: _i(j['intervalSec'], 30),
        gpsFix: j['gpsFix'] is bool ? j['gpsFix'] as bool : null,
        satellites: _iOrNull(j['satellites']),
        source: _sOrNull(j['source']),
      );

  DeviceInfo copyWith({int? battery, String? signal, String? connection, bool? paired, String? serial, DateTime? lastSeen, int? intervalSec, bool? gpsFix, int? satellites, String? source, bool clearSerial = false, bool clearLink = false}) => DeviceInfo(
        serial: clearSerial ? null : (serial ?? this.serial),
        firmware: firmware,
        battery: battery ?? this.battery,
        signal: signal ?? this.signal,
        paired: paired ?? this.paired,
        connection: connection ?? this.connection,
        lastSeen: lastSeen ?? this.lastSeen,
        intervalSec: intervalSec ?? this.intervalSec,
        gpsFix: clearLink ? null : (gpsFix ?? this.gpsFix),
        satellites: clearLink ? null : (satellites ?? this.satellites),
        source: clearLink ? null : (source ?? this.source),
      );
}

class Pet {
  const Pet({
    required this.id,
    required this.name,
    required this.species,
    required this.gender,
    required this.device,
    this.birthDate,
    this.avatarColor = 0,
    this.photoVersion = 0,
    this.location,
    this.address = '',
    this.locationUpdatedAt,
    this.insideGeofence,
    this.geofenceName = 'Rumah',
  });

  final String id, name, gender, address, geofenceName;
  final Species species;
  final DateTime? birthDate;
  final int avatarColor, photoVersion;
  final DeviceInfo device;
  final GeoPoint? location;
  final DateTime? locationUpdatedAt;
  final bool? insideGeofence;

  bool get isMale => gender == 'jantan';
  String get genderLabel => isMale ? 'Jantan' : 'Betina';
  String get ageText => ageShort(birthDate);
  String get subtitle => '${species.label} · $ageText';
  bool get hasPhoto => photoVersion > 0;

  /// Hanya hewan dengan GPS online yang punya status "di dalam/di luar area aman".
  bool get isInside => device.online && insideGeofence == true;
  bool get isOutside => device.online && insideGeofence == false;

  factory Pet.fromJson(Map<String, dynamic> j) {
    final loc = j['location'] is Map ? Map<String, dynamic>.from(j['location'] as Map) : null;
    return Pet(
      id: '${j['id']}',
      name: '${j['name']}',
      species: speciesFrom(j['species']?.toString()),
      gender: '${j['gender'] ?? 'jantan'}',
      birthDate: _dt(j['birthDate']),
      avatarColor: _i(j['avatarColor']),
      photoVersion: _i(j['photoVersion']),
      device: DeviceInfo.fromJson(j['device'] is Map ? Map<String, dynamic>.from(j['device'] as Map) : {}),
      location: loc == null ? null : GeoPoint(_d(loc['lat']), _d(loc['lng'])),
      address: loc == null ? '' : '${loc['address'] ?? ''}',
      locationUpdatedAt: loc == null ? null : _dt(loc['updatedAt']),
      insideGeofence: j['insideGeofence'] as bool?,
      geofenceName: '${j['geofenceName'] ?? 'Rumah'}',
    );
  }

  Pet copyWith({
    String? name,
    Species? species,
    String? gender,
    DateTime? birthDate,
    bool clearBirth = false,
    int? avatarColor,
    int? photoVersion,
    DeviceInfo? device,
    GeoPoint? location,
    bool clearLocation = false,
    String? address,
    DateTime? locationUpdatedAt,
    bool? insideGeofence,
    bool clearInside = false,
  }) =>
      Pet(
        id: id,
        name: name ?? this.name,
        species: species ?? this.species,
        gender: gender ?? this.gender,
        birthDate: clearBirth ? null : (birthDate ?? this.birthDate),
        avatarColor: avatarColor ?? this.avatarColor,
        photoVersion: photoVersion ?? this.photoVersion,
        device: device ?? this.device,
        location: clearLocation ? null : (location ?? this.location),
        address: clearLocation ? '' : (address ?? this.address),
        locationUpdatedAt: clearLocation ? null : (locationUpdatedAt ?? this.locationUpdatedAt),
        insideGeofence: clearInside ? null : (insideGeofence ?? this.insideGeofence),
        geofenceName: geofenceName,
      );
}

class Geofence {
  const Geofence({
    required this.petId,
    required this.center,
    this.name = 'Rumah',
    this.radius = 500,
    this.notifyExit = true,
    this.notifyEnter = true,
  });

  final String petId, name;
  final GeoPoint center;
  final double radius;
  final bool notifyExit, notifyEnter;

  factory Geofence.fromJson(Map<String, dynamic> j) => Geofence(
        petId: '${j['petId']}',
        name: '${j['name'] ?? 'Rumah'}',
        center: GeoPoint.fromJson(Map<String, dynamic>.from(j['center'] as Map)),
        radius: _d(j['radius'], 500),
        notifyExit: j['notifyExit'] != false,
        notifyEnter: j['notifyEnter'] != false,
      );

  Geofence copyWith({GeoPoint? center, double? radius, bool? notifyExit, bool? notifyEnter}) => Geofence(
        petId: petId,
        name: name,
        center: center ?? this.center,
        radius: radius ?? this.radius,
        notifyExit: notifyExit ?? this.notifyExit,
        notifyEnter: notifyEnter ?? this.notifyEnter,
      );
}

/// Kejadian pada Riwayat. Isinya sama persis dengan [AppNotification] (satu log kejadian).
class TimelineEvent {
  const TimelineEvent({required this.id, required this.petId, required this.category, required this.type, required this.title, required this.subtitle, required this.time});
  final String id, petId, category, type, title, subtitle; // petId kosong = kejadian akun (mis. hewan dihapus)
  final DateTime time;

  factory TimelineEvent.fromJson(Map<String, dynamic> j) => TimelineEvent(
        id: '${j['id']}',
        petId: j['petId']?.toString() ?? '',
        category: '${j['category'] ?? 'sistem'}',
        type: '${j['type']}',
        title: '${j['title']}',
        subtitle: '${j['subtitle'] ?? ''}',
        time: _dt(j['time']) ?? DateTime.now(),
      );
}

class AppNotification {
  const AppNotification({required this.id, required this.petId, required this.category, required this.type, required this.title, required this.subtitle, required this.time, this.read = false});
  final String id, petId, category, type, title, subtitle;
  final DateTime time;
  final bool read;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: '${j['id']}',
        petId: j['petId']?.toString() ?? '',
        category: '${j['category'] ?? 'sistem'}',
        type: '${j['type']}',
        title: '${j['title']}',
        subtitle: '${j['subtitle'] ?? ''}',
        time: _dt(j['time']) ?? DateTime.now(),
        read: j['read'] == true,
      );

  AppNotification copyWith({bool? read}) =>
      AppNotification(id: id, petId: petId, category: category, type: type, title: title, subtitle: subtitle, time: time, read: read ?? this.read);
}

class DayStat {
  const DayStat({required this.date, required this.label, required this.minutes});
  final String date, label;
  final int minutes;
  factory DayStat.fromJson(Map<String, dynamic> j) => DayStat(date: '${j['date']}', label: '${j['label']}', minutes: _i(j['minutes']));
}

/// Fitur AKTIVITAS: langkah, jarak, waktu aktif, kalori, dan tren 7 hari.
class ActivitySummary {
  const ActivitySummary({required this.connected, required this.steps, required this.goal, required this.distanceKm, required this.activeMinutes, required this.calories, required this.week});
  final bool connected;
  final int steps, goal, activeMinutes, calories;
  final double distanceKm;
  final List<DayStat> week;

  double get progress => goal == 0 ? 0 : (steps / goal).clamp(0.0, 1.0).toDouble();
  int get percent => (progress * 100).round();
  String get activeText => activeMinutes >= 60 ? '${fmtDecimal(activeMinutes / 60)} jam' : '$activeMinutes mnt';

  factory ActivitySummary.fromJson(Map<String, dynamic> j) => ActivitySummary(
        connected: j['connected'] == true,
        steps: _i(j['steps']),
        goal: _i(j['goal'], 10000),
        distanceKm: _d(j['distanceKm']),
        activeMinutes: _i(j['activeMinutes']),
        calories: _i(j['calories']),
        week: ((j['week'] as List?) ?? const []).map((e) => DayStat.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
}

class SensorReading {
  const SensorReading({this.available = false, this.live = false, this.heartRate, this.temperature});
  final bool available, live;
  final int? heartRate;
  final double? temperature;

  factory SensorReading.fromJson(Map<String, dynamic> j) => SensorReading(
        available: j['available'] == true,
        live: j['live'] == true,
        heartRate: _iOrNull(j['heartRate']),
        temperature: _dOrNull(j['temperature']),
      );
}

class HealthRecord {
  const HealthRecord({required this.id, required this.petId, required this.type, required this.title, required this.date, this.value, this.note = ''});
  final String id, petId, type, title, date, note; // type: berat | vaksin | obat | catatan
  final double? value;

  factory HealthRecord.fromJson(Map<String, dynamic> j) => HealthRecord(
        id: '${j['id']}',
        petId: '${j['petId']}',
        type: '${j['type']}',
        title: '${j['title'] ?? ''}',
        date: '${j['date']}',
        value: _dOrNull(j['value']),
        note: '${j['note'] ?? ''}',
      );

  String get headline => type == 'berat' ? 'Berat ${fmtDecimal(value ?? 0)} kg' : title;
}

/// Fitur KESEHATAN: sensor kalung + catatan kesehatan buatan pengguna.
class HealthSummary {
  const HealthSummary({required this.sensor, required this.records, this.latestWeightKg, this.lastVaccineTitle, this.lastVaccineDate});
  final SensorReading sensor;
  final List<HealthRecord> records;
  final double? latestWeightKg;
  final String? lastVaccineTitle, lastVaccineDate;

  factory HealthSummary.fromJson(Map<String, dynamic> j) {
    final sum = j['summary'] is Map ? Map<String, dynamic>.from(j['summary'] as Map) : <String, dynamic>{};
    final vac = sum['lastVaccine'] is Map ? Map<String, dynamic>.from(sum['lastVaccine'] as Map) : null;
    return HealthSummary(
      sensor: SensorReading.fromJson(j['sensor'] is Map ? Map<String, dynamic>.from(j['sensor'] as Map) : {}),
      records: ((j['records'] as List?) ?? const []).map((e) => HealthRecord.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      latestWeightKg: _dOrNull(sum['latestWeightKg']),
      lastVaccineTitle: vac == null ? null : '${vac['title']}',
      lastVaccineDate: vac == null ? null : '${vac['date']}',
    );
  }
}

/// Data langsung dari alat untuk layar "Koneksi Alat".
class DeviceLive {
  const DeviceLive({
    this.paired = false,
    this.serial,
    this.connection = 'unpaired',
    this.source,
    this.port,
    this.packets = 0,
    this.lastPacketAt,
    this.ageSec,
    this.gpsFix,
    this.locationMode,
    this.satellites,
    this.hdop,
    this.speedKmh,
    this.lat,
    this.lng,
    this.address,
    this.battery,
    this.signal,
    this.heartRate,
    this.temperature,
    this.firmware = '',
    this.pendingCommands = 0,
  });

  final bool paired;
  final String? serial, source, port, locationMode, address, signal;
  final String connection, firmware;
  final int packets, pendingCommands;
  final DateTime? lastPacketAt;
  final int? ageSec, satellites, battery, heartRate;
  final bool? gpsFix;
  final double? hdop, speedKmh, lat, lng, temperature;

  bool get online => connection == 'online';

  /// 'tetap' = koordinat tetap (prototipe tanpa modul GPS), bukan hasil satelit.
  bool get fixedLocation => locationMode == 'tetap';

  factory DeviceLive.fromJson(Map<String, dynamic> j) => DeviceLive(
        paired: j['paired'] == true,
        serial: _sOrNull(j['serial']),
        connection: '${j['connection'] ?? 'unpaired'}',
        source: _sOrNull(j['source']),
        port: _sOrNull(j['port']),
        packets: _i(j['packets']),
        lastPacketAt: _dt(j['lastPacketAt']),
        ageSec: _iOrNull(j['ageSec']),
        gpsFix: j['gpsFix'] is bool ? j['gpsFix'] as bool : null,
        locationMode: _sOrNull(j['locationMode']),
        satellites: _iOrNull(j['satellites']),
        hdop: _dOrNull(j['hdop']),
        speedKmh: _dOrNull(j['speedKmh']),
        lat: _dOrNull(j['lat']),
        lng: _dOrNull(j['lng']),
        address: _sOrNull(j['address']),
        battery: _iOrNull(j['battery']),
        signal: _sOrNull(j['signal']),
        heartRate: _iOrNull(j['heartRate']),
        temperature: _dOrNull(j['temperature']),
        firmware: '${j['firmware'] ?? ''}',
        pendingCommands: _i(j['pendingCommands']),
      );
}

/// Alat yang sudah mengirim paket ke server tetapi belum dipasangkan ke hewan mana pun.
class DiscoveredDevice {
  const DiscoveredDevice({required this.serial, this.source, this.port, this.firmware, this.battery, this.lastSeenSec = 0});
  final String serial;
  final String? source, port, firmware;
  final int? battery;
  final int lastSeenSec;

  String get sourceLabel => source == 'usb' ? 'Kabel USB' : 'Jaringan';

  factory DiscoveredDevice.fromJson(Map<String, dynamic> j) => DiscoveredDevice(
        serial: '${j['serial']}',
        source: _sOrNull(j['source']),
        port: _sOrNull(j['port']),
        firmware: _sOrNull(j['firmware']),
        battery: _iOrNull(j['battery']),
        lastSeenSec: _i(j['lastSeenSec']),
      );
}

/// Status tautan kabel USB di sisi server.
class UsbStatus {
  const UsbStatus({
    this.enabled = false,
    this.state = 'idle',
    this.path,
    this.baud,
    this.lines = 0,
    this.parseErrors = 0,
    this.lastError,
    this.lastLineAgeSec,
    this.serials = const [],
    this.driver,
    this.hint,
    this.lastUnknown,
    this.rejectCode,
  });

  final bool enabled;
  final String state;
  final String? path, lastError, driver, hint, lastUnknown, rejectCode;
  final int? baud, lastLineAgeSec;
  final int lines, parseErrors;
  final List<String> serials;

  bool get connected => enabled && state == 'connected';

  factory UsbStatus.fromJson(Map<String, dynamic> j) {
    final unknown = j['lastUnknown'] is Map ? Map<String, dynamic>.from(j['lastUnknown'] as Map) : null;
    final reject = j['lastReject'] is Map ? Map<String, dynamic>.from(j['lastReject'] as Map) : null;
    return UsbStatus(
      enabled: j['enabled'] == true,
      state: '${j['state'] ?? 'idle'}',
      path: _sOrNull(j['path']),
      baud: _iOrNull(j['baud']),
      lines: _i(j['lines']),
      parseErrors: _i(j['parseErrors']),
      lastError: _sOrNull(j['lastError']),
      lastLineAgeSec: _iOrNull(j['lastLineAgeSec']),
      serials: ((j['serials'] as List?) ?? const []).map((e) => '$e').toList(),
      driver: _sOrNull(j['driver']),
      hint: _sOrNull(j['hint']),
      lastUnknown: unknown == null ? null : _sOrNull(unknown['line']),
      rejectCode: reject == null ? null : _sOrNull(reject['code']),
    );
  }
}
