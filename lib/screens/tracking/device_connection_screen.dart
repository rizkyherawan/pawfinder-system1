import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/data_source.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../../widgets/pair_sheet.dart';
import '../../widgets/pressable.dart';

/// Koneksi Alat: monitor langsung data dari kalung (USB / jaringan), status tautan di server,
/// dan diagnosis otomatis bila data tidak masuk. Diperbarui setiap 1,5 detik selama layar terbuka.
class DeviceConnectionScreen extends StatefulWidget {
  const DeviceConnectionScreen({super.key, required this.petId});
  final String petId;

  @override
  State<DeviceConnectionScreen> createState() => _DeviceConnectionScreenState();
}

class _DeviceConnectionScreenState extends State<DeviceConnectionScreen> {
  DeviceLive? _live;
  UsbStatus? _usb;
  String? _error;
  Timer? _timer;
  bool _busy = false;
  bool _pinging = false;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy || !mounted) return;
    _busy = true;
    final app = context.read<AppState>();
    try {
      final live = await app.loadDeviceLive(widget.petId);
      UsbStatus? usb = _usb;
      // Status USB cukup diperiksa tiap ~4,5 detik.
      if (_ticks % 3 == 0) {
        try {
          usb = await app.loadUsbStatus();
        } catch (_) {
          // informasi tambahan; abaikan bila gagal
        }
      }
      _ticks++;
      if (!mounted) return;
      setState(() {
        _live = live;
        _usb = usb;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      _busy = false;
    }
  }

  Future<void> _ping() async {
    if (_pinging) return;
    setState(() => _pinging = true);
    try {
      final msg = await context.read<AppState>().pingDevice(widget.petId);
      if (mounted) showToast(context, msg, kind: ToastKind.success);
    } catch (e) {
      if (mounted) showToast(context, errorText(e), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _pinging = false);
    }
  }

  /// Langkah perbaikan yang relevan dengan kondisi saat ini (kosong bila semuanya normal).
  List<String> _diagnosis(DeviceLive l, UsbStatus? usb) {
    final out = <String>[];
    if (!l.paired) return ['Kalung belum dipasangkan ke hewan ini. Ketuk "Hubungkan GPS" lalu pilih Nomor Seri (ID) atau Kabel USB.'];
    if (usb != null && usb.enabled && !usb.connected) {
      out.add('Tautan USB di server terputus${usb.lastError == null ? '' : ': ${usb.lastError}'}. Periksa kabel (harus kabel DATA), driver, dan pastikan Arduino IDE / Serial Monitor tidak sedang memakai port yang sama.');
    }
    if (usb != null && usb.enabled && usb.rejectCode == 'UNPAIRED') {
      out.add('Server menerima data dari alat dengan ID yang belum dipasangkan. Pasangkan ID itu lewat "Hubungkan GPS" (tab Kabel USB).');
    }
    if (usb != null && usb.enabled && usb.rejectCode == 'NO_SERIAL') {
      out.add('Data masuk tetapi tanpa ID alat. Kirim field "serial" dari firmware, atau isi USB_SERIAL di backend/.env.');
    }
    if (usb != null && usb.enabled && usb.parseErrors > 0 && usb.lastUnknown != null) {
      out.add('Ada ${usb.parseErrors} baris dari alat yang formatnya tidak dikenali, contoh: "${usb.lastUnknown}". Cocokkan dengan format di README (JSON / CSV / NMEA) dan pastikan baud rate sama dengan firmware (${usb.baud ?? 9600}).');
    }
    switch (l.connection) {
      case 'waiting':
        out.add('Belum ada data pertama dari alat. Pastikan Arduino menyala, kabel USB terpasang, ID alat sama dengan yang dipasangkan (${l.serial ?? '-'}), dan firmware mengirim satu baris data per detik.');
        break;
      case 'offline':
        out.add('Tidak ada data dari alat dalam beberapa saat terakhir. Periksa kabel/daya, lalu tunggu — status kembali Online otomatis begitu data masuk.');
        break;
      case 'online':
        if (l.gpsFix == false) {
          out.add('Alat terhubung, tetapi modul GPS belum mendapat satelit. Bawa ke luar ruangan dengan langit terbuka dan tunggu 1–5 menit (cold start). Lokasi terakhir dipertahankan.');
        }
        if ((l.battery ?? 100) <= 20) out.add('Baterai alat rendah (${l.battery}%). Segera isi daya.');
        break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final pet = context.watch<AppState>().petById(widget.petId);
    final p = context.pf;
    final tx = context.tx;
    final l = _live;

    return Scaffold(
      body: Column(
        children: [
          const PFTopBar(title: 'Koneksi Alat'),
          Expanded(
            child: pet == null
                ? const Center(child: Text('Hewan tidak ditemukan.'))
                : l == null
                    ? Center(
                        child: _error == null
                            ? const PFSpinner()
                            : Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Text(_error!, textAlign: TextAlign.center, style: tx.bodySecondary),
                                  const SizedBox(height: 12),
                                  PFButton(label: 'Coba Lagi', kind: PFButtonKind.secondary, expand: false, onPressed: _load),
                                ]),
                              ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(PF.margin, 8, PF.margin, 28),
                        children: _content(context, pet, l),
                      ),
          ),
        ],
      ),
      backgroundColor: p.background,
    );
  }

  List<Widget> _content(BuildContext context, Pet pet, DeviceLive l) {
    final p = context.pf;
    final tx = context.tx;
    final usb = _usb;
    final tips = _diagnosis(l, usb);
    final viaUsb = l.source == 'usb';
    final sourceText = switch (l.source) {
      'usb' => 'Kabel USB${l.port == null ? '' : ' (${l.port})'}',
      'http' => 'Jaringan (HTTP)',
      'simulator' => 'Simulator (data demo, bukan alat asli)',
      _ => 'Belum ada data',
    };
    final age = l.ageSec;
    final lastText = l.lastPacketAt == null ? 'Belum ada paket diterima' : '${age == null || age < 3 ? 'Baru saja' : '$age detik lalu'} · ${l.packets} paket';
    final fixText = l.gpsFix == null
        ? '—'
        : l.gpsFix!
            ? (l.fixedLocation ? 'Koordinat tetap (tanpa GPS)' : 'Fix · ${l.satellites ?? '-'} satelit')
            : 'Mencari satelit…';
    final hasLoc = l.lat != null && l.lng != null;

    return [
      PFCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: p.primaryLight, shape: BoxShape.circle),
              child: Icon(viaUsb ? Icons.usb : Icons.wifi_tethering_rounded, color: p.primaryText),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('Kalung ${pet.name}', style: tx.h3)),
            ConnectionBadge(connection: l.connection),
          ]),
          const SizedBox(height: 14),
          _Line(label: 'Jalur data', value: sourceText),
          const SizedBox(height: 10),
          _Line(label: 'Data terakhir', value: lastText),
          const SizedBox(height: 10),
          Pressable(
            onTap: l.serial == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: l.serial ?? ''));
                    showToast(context, 'ID alat disalin', kind: ToastKind.success);
                  },
            child: _Line(label: 'ID alat', value: l.serial ?? '—', trailing: l.serial == null ? null : Icon(Icons.copy_rounded, size: 14, color: p.textSecondary)),
          ),
        ]),
      ),
      if (_error != null) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: p.warningBg, borderRadius: BorderRadius.circular(14)),
          child: Text('Gagal memperbarui: $_error. Mencoba lagi otomatis…', style: tx.caption.copyWith(color: p.text)),
        ),
      ],
      const SizedBox(height: 14),
      PFCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Data langsung dari alat', style: tx.h3),
          const SizedBox(height: 14),
          _Line(label: 'Status GPS', value: fixText),
          const SizedBox(height: 10),
          _Line(label: 'Lokasi', value: hasLoc ? '${l.lat!.toStringAsFixed(6)}, ${l.lng!.toStringAsFixed(6)}' : '—'),
          if (l.address != null && l.address!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Line(label: 'Alamat', value: l.address!),
          ],
          if (l.hdop != null) ...[
            const SizedBox(height: 10),
            _Line(label: 'Akurasi (HDOP)', value: fmtDecimal(l.hdop!)),
          ],
          if (l.speedKmh != null) ...[
            const SizedBox(height: 10),
            _Line(label: 'Kecepatan', value: '${fmtDecimal(l.speedKmh!)} km/jam'),
          ],
          const SizedBox(height: 10),
          _Line(label: 'Baterai', value: l.battery == null ? '—' : '${l.battery}%', valueColor: batteryColor(context, l.battery)),
          const SizedBox(height: 10),
          _Line(label: 'Sinyal', value: l.signal ?? '—'),
          const SizedBox(height: 10),
          _Line(label: 'Detak jantung', value: l.heartRate == null ? '—' : '${l.heartRate} bpm'),
          const SizedBox(height: 10),
          _Line(label: 'Suhu tubuh', value: l.temperature == null ? '—' : '${fmtDecimal(l.temperature!)} °C'),
          const SizedBox(height: 10),
          _Line(label: 'Firmware', value: l.firmware.isEmpty ? '—' : l.firmware),
          if (l.pendingCommands > 0) ...[
            const SizedBox(height: 10),
            _Line(label: 'Perintah menunggu', value: '${l.pendingCommands}'),
          ],
        ]),
      ),
      const SizedBox(height: 14),
      PFCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tautan kabel USB di server', style: tx.h3),
          const SizedBox(height: 12),
          if (usb == null)
            Text('Memeriksa…', style: tx.caption)
          else if (!usb.enabled)
            Text(usb.hint ?? 'Tautan USB di server belum aktif. Jalankan backend dengan "npm run start:usb".', style: tx.caption)
          else ...[
            _Line(label: 'Status', value: usb.connected ? 'Tersambung' : (usb.state == 'connecting' ? 'Menyambung…' : 'Terputus')),
            const SizedBox(height: 10),
            _Line(label: 'Port', value: usb.path ?? 'mencari Arduino…'),
            const SizedBox(height: 10),
            _Line(label: 'Baud rate', value: usb.baud == null ? '—' : '${usb.baud}'),
            const SizedBox(height: 10),
            _Line(label: 'Baris diterima', value: fmtInt(usb.lines)),
            const SizedBox(height: 10),
            _Line(label: 'Baris tak dikenali', value: fmtInt(usb.parseErrors), valueColor: usb.parseErrors > 0 ? PF.warning : null),
            if (usb.lastError != null) ...[
              const SizedBox(height: 10),
              Text(usb.lastError!, style: tx.caption.copyWith(color: PF.warning)),
            ],
          ],
        ]),
      ),
      if (tips.isNotEmpty) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: p.warningBg, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.tips_and_updates_outlined, size: 18, color: PF.warning),
              const SizedBox(width: 8),
              Text('Diagnosis', style: tx.captionStrong),
            ]),
            for (final t in tips) ...[
              const SizedBox(height: 8),
              Text('• $t', style: tx.caption.copyWith(color: p.text)),
            ],
          ]),
        ),
      ],
      const SizedBox(height: 20),
      if (!l.paired)
        PFButton(label: 'Hubungkan GPS', icon: Icons.link_rounded, onPressed: () => showPairSheet(context, pet))
      else
        PFButton(label: 'Bunyikan Kalung', icon: Icons.volume_up_outlined, kind: PFButtonKind.secondary, loading: _pinging, onPressed: l.online ? _ping : null),
      if (l.paired && !l.online) ...[
        const SizedBox(height: 6),
        Center(child: Text('Tombol aktif saat alat Online.', style: tx.micro)),
      ],
    ];
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.trailing, this.valueColor});
  final String label, value;
  final Widget? trailing;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final tx = context.tx;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 4, child: Text(label, style: tx.caption)),
      if (trailing != null) ...[trailing!, const SizedBox(width: 6)],
      Expanded(flex: 6, child: Text(value, textAlign: TextAlign.right, style: tx.captionStrong.copyWith(fontSize: 14, color: valueColor))),
    ]);
  }
}
