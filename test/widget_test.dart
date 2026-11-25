import 'package:flutter_test/flutter_test.dart';
import 'package:pawfinder/core/constants.dart';
import 'package:pawfinder/core/geo.dart';
import 'package:pawfinder/core/utils.dart';
import 'package:pawfinder/data/data_source.dart';
import 'package:pawfinder/data/demo_data_source.dart';
import 'package:pawfinder/data/models.dart';
import 'package:pawfinder/state/app_state.dart';

void main() {
  group('format & utilitas', () {
    test('fmtInt memakai titik ribuan', () {
      expect(fmtInt(2345), '2.345');
      expect(fmtInt(10000), '10.000');
      expect(fmtInt(12), '12');
    });

    test('fmtDecimal memakai koma', () {
      expect(fmtDecimal(1.2), '1,2');
      expect(fmtRadius(500), '500 m');
      expect(fmtRadius(1500), '1,5 km');
    });

    test('umur hewan', () {
      final now = DateTime(2025, 9, 24);
      expect(ageShort(DateTime(2023, 8, 14), now: now), '2 th');
      expect(ageShort(DateTime(2025, 1, 24), now: now), '8 bln');
      expect(ageLong(DateTime(2024, 9, 24), now: now), '1 tahun');
    });

    test('konversi WIB (UTC+7)', () {
      expect(fmtTime(DateTime.utc(2025, 9, 24, 7, 32)), '14:32');
    });
  });

  group('geo', () {
    test('jarak 0,001 derajat lintang sekitar 111 m', () {
      final d = distanceMeters(const GeoPoint(-7.0, 110.0), const GeoPoint(-7.001, 110.0));
      expect(d, inInclusiveRange(105, 118));
    });

    test('movePoint lalu hitung jarak kembali', () {
      const a = GeoPoint(-7.71556, 110.35547);
      expect(distanceMeters(a, movePoint(a, 1.0, 250)), closeTo(250, 1));
    });
  });

  group('model', () {
    test('hewan tanpa kalung: belum terhubung, tanpa lokasi & baterai', () {
      final pet = Pet.fromJson({
        'id': 'p1',
        'name': 'Contoh',
        'species': 'kelinci',
        'gender': 'jantan',
        'device': {'paired': false, 'connection': 'unpaired', 'serial': null, 'battery': null},
        'location': null,
        'insideGeofence': null,
      });
      expect(pet.device.connection, 'unpaired');
      expect(pet.device.online, false);
      expect(pet.device.battery, isNull);
      expect(pet.location, isNull);
      expect(pet.isInside, false);
      expect(pet.isOutside, false);
    });

    test('hewan dengan GPS online di luar area aman', () {
      final pet = Pet.fromJson({
        'id': 'p2',
        'name': 'Contoh',
        'species': 'anjing',
        'gender': 'betina',
        'device': {'paired': true, 'connection': 'online', 'serial': 'PF-ABC-123456', 'battery': 78},
        'location': {'lat': -7.7155, 'lng': 110.3554, 'address': 'Sleman'},
        'insideGeofence': false,
      });
      expect(pet.device.online, true);
      expect(pet.isOutside, true);
      expect(pet.device.statusLabel, 'Online');
    });

    test('alat online tanpa lokasi (GPS belum fix): bukan "di dalam area aman"', () {
      final pet = Pet.fromJson({
        'id': 'p3',
        'name': 'Contoh',
        'species': 'anjing',
        'gender': 'jantan',
        'device': {'paired': true, 'connection': 'online', 'serial': 'PF-ABC-123456', 'battery': 80, 'gpsFix': false, 'satellites': 0, 'source': 'usb'},
        'location': null,
        'insideGeofence': null,
      });
      expect(pet.device.online, true);
      expect(pet.device.searchingSatellites, true);
      expect(pet.device.source, 'usb');
      expect(pet.device.sourceLabel, 'Kabel USB');
      expect(pet.isInside, false);
      expect(pet.isOutside, false);
    });

    test('DeviceLive, DiscoveredDevice, dan UsbStatus membaca JSON server', () {
      final live = DeviceLive.fromJson({'paired': true, 'serial': 'PF-ABC-123456', 'connection': 'online', 'source': 'usb', 'port': 'COM3', 'packets': 12, 'ageSec': 1, 'gpsFix': true, 'locationMode': 'tetap', 'satellites': 7, 'lat': -7.71556, 'lng': 110.35547, 'battery': 80, 'heartRate': 96, 'temperature': 38.6});
      expect(live.online, true);
      expect(live.fixedLocation, true);
      expect(live.lat, closeTo(-7.71556, 1e-9));
      expect(live.heartRate, 96);
      expect(DeviceLive.fromJson(<String, dynamic>{}).connection, 'unpaired'); // JSON kosong tidak melempar

      final d = DiscoveredDevice.fromJson({'serial': 'PF-NEW-123456', 'source': 'usb', 'battery': 90, 'lastSeenSec': 3});
      expect(d.sourceLabel, 'Kabel USB');

      final usb = UsbStatus.fromJson({'enabled': true, 'state': 'connected', 'path': 'COM3', 'baud': 9600, 'lines': 40, 'parseErrors': 1, 'lastUnknown': {'line': 'abc', 'reason': 'x'}, 'lastReject': {'code': 'UNPAIRED', 'error': 'x'}, 'serials': ['PF-ABC-123456']});
      expect(usb.connected, true);
      expect(usb.rejectCode, 'UNPAIRED');
      expect(usb.lastUnknown, 'abc');
      expect(UsbStatus.fromJson({'enabled': false, 'hint': 'aktifkan'}).connected, false);
    });

    test('ActivitySummary progress', () {
      final a = ActivitySummary.fromJson({'connected': true, 'steps': 2345, 'goal': 10000, 'distanceKm': 1.2, 'activeMinutes': 90, 'calories': 120, 'week': []});
      expect(a.percent, 23);
      expect(a.activeText, '1,5 jam');
    });

    test('HealthSummary membaca ringkasan & catatan', () {
      final h = HealthSummary.fromJson({
        'sensor': {'available': false, 'live': false},
        'summary': {'latestWeightKg': 4.5, 'lastVaccine': {'title': 'Vaksin rabies', 'date': '2025-02-01'}},
        'records': [
          {'id': 'r1', 'petId': 'p1', 'type': 'berat', 'title': 'Berat badan', 'value': 4.5, 'date': '2025-03-01', 'note': ''},
        ],
      });
      expect(h.latestWeightKg, 4.5);
      expect(h.lastVaccineTitle, 'Vaksin rabies');
      expect(h.records.single.headline, 'Berat 4,5 kg');
    });
  });

  group('alamat server', () {
    test('normalizeBaseUrl merapikan dan menolak alamat yang salah', () {
      expect(AppState.normalizeBaseUrl('192.168.1.10:4000'), 'http://192.168.1.10:4000');
      expect(AppState.normalizeBaseUrl('  http://10.0.2.2:4000/  '), 'http://10.0.2.2:4000');
      expect(AppState.normalizeBaseUrl('HTTPS://api.contoh.com'), 'HTTPS://api.contoh.com');
      expect(AppState.normalizeBaseUrl('http://abc def'), isNull);
      expect(AppState.normalizeBaseUrl('http://'), isNull);
      expect(AppState.normalizeBaseUrl('http://host:99999'), isNull);
      expect(AppState.normalizeBaseUrl(''), AppConfig.defaultBaseUrl); // kosong -> alamat bawaan platform
    });
  });

  group('DemoDataSource (mode demo)', () {
    test('mulai kosong; online hanya setelah sinyal pertama; riwayat = notifikasi', () async {
      final ds = DemoDataSource();
      expect(await ds.getPets(), isEmpty);
      expect(await ds.getNotifications(), isEmpty);

      // Aturan yang sama dengan backend: nama dan tanggal lahir wajib diisi.
      await expectLater(ds.createPet(name: 'Contoh', species: Species.kucing, gender: 'betina'), throwsA(isA<ApiException>()));
      await expectLater(ds.createPet(name: '  ', species: Species.kucing, gender: 'betina', birthDate: DateTime(2023, 1, 1)), throwsA(isA<ApiException>()));
      await expectLater(ds.createPet(name: 'Contoh', species: Species.kucing, gender: 'betina', birthDate: DateTime.now().add(const Duration(days: 30))), throwsA(isA<ApiException>()));
      expect(await ds.getPets(), isEmpty); // semua percobaan gagal tidak meninggalkan data

      final pet = await ds.createPet(name: 'Contoh', species: Species.kucing, gender: 'betina', birthDate: DateTime(2023, 1, 1));
      expect(pet.device.connection, 'unpaired');
      expect(pet.location, isNull);

      await expectLater(ds.pairDevice(pet.id, 'salah'), throwsA(isA<ApiException>()));
      final paired = await ds.pairDevice(pet.id, 'pf-cnt-123456');
      expect(paired.device.connection, 'waiting');
      expect(paired.device.online, false);

      var pets = await ds.getPets();
      expect(pets.first.device.connection, 'waiting'); // belum ada sinyal

      await Future<void>.delayed(const Duration(milliseconds: 2200));
      pets = await ds.getPets();
      expect(pets.first.device.online, true);
      expect(pets.first.location, isNotNull);

      final notifs = await ds.getNotifications();
      expect(notifs.map((n) => n.type), containsAll(['pet_added', 'gps_paired', 'gps_connected']));
      final hist = await ds.getHistory(wibNow());
      expect(hist.length, notifs.length);

      await ds.deletePet(pet.id);
      expect(await ds.getPets(), isEmpty);
      expect((await ds.getNotifications()).first.type, 'pet_deleted');
    });
  });
}
