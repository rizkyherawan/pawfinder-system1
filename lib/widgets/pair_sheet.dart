import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/data_source.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'buttons.dart';
import 'common.dart';
import 'inputs.dart';

/// Memformat input nomor seri menjadi huruf besar "PF-XXX-000000".
class _SerialFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue value) {
    var raw = value.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (raw.startsWith('PF')) raw = raw.substring(2);
    final b = StringBuffer('PF');
    if (raw.isNotEmpty) b.write('-${raw.substring(0, math.min(3, raw.length))}');
    if (raw.length > 3) b.write('-${raw.substring(3, math.min(9, raw.length))}');
    final text = b.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// Sheet koneksi kalung GPS: pilih jalur (nomor seri / kabel USB) -> menunggu sinyal -> terhubung (hijau).
Future<void> showPairSheet(BuildContext context, Pet pet) {
  return showPFSheet<void>(context, title: 'Hubungkan Kalung GPS', builder: (_) => _PairBody(petId: pet.id));
}

class _PairBody extends StatefulWidget {
  const _PairBody({required this.petId});
  final String petId;

  @override
  State<_PairBody> createState() => _PairBodyState();
}

class _PairBodyState extends State<_PairBody> {
  static final _serialRe = RegExp(r'^PF-[A-Z0-9]{3}-\d{6}$');
  final _serial = TextEditingController(text: 'PF');
  int _method = 0; // 0 = nomor seri (ID alat), 1 = kabel USB
  bool _loading = false;
  bool _sent = false; // pairing berhasil, menunggu sinyal
  String? _error;
  int _waited = 0;
  Timer? _tick, _poll;
  bool _closing = false;
  List<DiscoveredDevice> _found = const [];
  UsbStatus? _usb;

  @override
  void initState() {
    super.initState();
    _refreshLink();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refreshLink());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _poll?.cancel();
    _serial.dispose();
    super.dispose();
  }

  /// Memeriksa alat yang baru terdeteksi dan status tautan USB di server (hanya informasi tambahan).
  Future<void> _refreshLink() async {
    if (_sent || !mounted) return;
    final app = context.read<AppState>();
    try {
      final found = await app.loadDiscoveredDevices();
      final usb = await app.loadUsbStatus();
      if (!mounted) return;
      setState(() {
        _found = found;
        _usb = usb;
      });
    } catch (_) {
      // Diam: daftar ini pelengkap, pairing dengan nomor seri tetap berjalan.
    }
  }

  String? _validate(String text) {
    final t = text.trim().toUpperCase();
    if (t.isEmpty || t == 'PF' || t == 'PF-') return 'Nomor seri wajib diisi';
    if (!_serialRe.hasMatch(t)) return 'Format nomor seri tidak valid. Contoh: PF-ABC-123456';
    return null;
  }

  Future<void> _pair(Pet pet, [String? serial]) async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    final text = serial ?? _serial.text;
    final problem = _validate(text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AppState>().pairDevice(pet.id, text.trim().toUpperCase());
      if (!mounted) return;
      setState(() {
        _loading = false;
        _sent = true;
      });
      _poll?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _waited++);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  void _fillExample(Pet pet) {
    final letters = pet.name.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '').padRight(3, 'X').substring(0, 3);
    final n = (100000 + math.Random().nextInt(899999));
    _serial.text = 'PF-$letters-$n';
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pet = app.petById(widget.petId);
    final tx = context.tx;
    final p = context.pf;
    if (pet == null) return const SizedBox.shrink();

    // Terhubung hanya jika sinyal NYATA sudah diterima (status online dari server).
    if (_sent && pet.device.online && !_closing) {
      _closing = true;
      Future<void>.delayed(const Duration(milliseconds: 1400), () {
        if (mounted) Navigator.of(context).maybePop();
      });
    }

    if (_sent) {
      final online = pet.device.online;
      final accent = online ? (p.isDark ? PF.success : p.successFg) : PF.warning;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 6),
        Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: accent.o(0.14), shape: BoxShape.circle),
            child: online ? Icon(Icons.check_circle_rounded, color: accent, size: 46) : const Center(child: PFSpinner(size: 34)),
          ),
        ),
        const SizedBox(height: 18),
        Text(online ? 'GPS terhubung' : 'Menunggu sinyal dari kalung…', textAlign: TextAlign.center, style: tx.h2.copyWith(color: online ? accent : null)),
        const SizedBox(height: 8),
        Text(
          online ? '${pet.name} kini dilacak secara real-time.' : 'Kalung ${pet.device.serial ?? ''} sudah dipasangkan. Status akan berubah menjadi hijau begitu kalung mengirim data pertamanya.',
          textAlign: TextAlign.center,
          style: tx.bodySecondary.copyWith(fontSize: 14),
        ),
        if (!online && _waited >= 20) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.warningBg, borderRadius: BorderRadius.circular(14)),
            child: Text(
              'Belum ada sinyal. Pastikan kalung menyala dan nomor seri sudah benar. Jika memakai kabel USB: pastikan backend dijalankan dengan USB aktif (npm run start:usb) dan Arduino mengirim data. Kamu boleh menutup sheet ini; status tetap diperbarui otomatis.',
              style: tx.caption.copyWith(color: p.text),
            ),
          ),
        ],
        const SizedBox(height: 20),
        PFButton(label: online ? 'Selesai' : 'Tutup', kind: online ? PFButtonKind.primary : PFButtonKind.secondary, onPressed: () => Navigator.of(context).maybePop()),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PFSegmented(
        items: const ['Nomor Seri (ID)', 'Kabel USB'],
        index: _method,
        onChanged: (i) => setState(() {
          _method = i;
          _error = null;
        }),
      ),
      const SizedBox(height: 16),
      if (_method == 0) ..._idForm(pet, app) else ..._usbForm(pet),
    ]);
  }

  List<Widget> _idForm(Pet pet, AppState app) {
    final tx = context.tx;
    final showExample = kDebugMode || app.demoMode;
    return [
      Text('Masukkan nomor seri yang tertera pada kalung ${pet.name}. Status baru menjadi Online (hijau) setelah kalung benar-benar mengirim sinyal.', style: tx.caption),
      const SizedBox(height: 16),
      PFTextField(
        label: 'Nomor seri kalung*',
        hint: 'PF-ABC-123456',
        controller: _serial,
        errorText: _error,
        prefixIcon: Icons.sensors_rounded,
        textInputAction: TextInputAction.done,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [_SerialFormatter()],
        onSubmitted: (_) => _pair(pet),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      ),
      if (_found.isNotEmpty) ...[
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: PFButton(label: '${_found.length} alat terdeteksi lewat jaringan/USB. Lihat', icon: Icons.usb, kind: PFButtonKind.text, expand: false, onPressed: () => setState(() => _method = 1)),
        ),
      ],
      if (showExample) ...[
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: PFButton(
            label: app.demoMode ? 'Isi nomor seri contoh (uji coba)' : 'Isi nomor seri contoh (butuh server mode simulator)',
            kind: PFButtonKind.text,
            expand: false,
            onPressed: () => _fillExample(pet),
          ),
        ),
      ],
      const SizedBox(height: 8),
      PFButton(label: 'Hubungkan', icon: Icons.link_rounded, loading: _loading, onPressed: () => _pair(pet)),
    ];
  }

  List<Widget> _usbForm(Pet pet) {
    final tx = context.tx;
    final p = context.pf;
    final usb = _usb;
    final connected = usb != null && usb.connected;
    final tone = connected ? (p.isDark ? PF.success : p.successFg) : PF.warning;
    final String statusText;
    if (usb == null) {
      statusText = 'Memeriksa tautan USB di server…';
    } else if (connected) {
      statusText = 'Server terhubung ke Arduino (${usb.path ?? 'USB'}${usb.baud != null ? ' · ${usb.baud} baud' : ''}).';
    } else if (usb.enabled) {
      statusText = usb.lastError ?? 'Server menunggu Arduino dicolok…';
    } else {
      statusText = usb.hint ?? 'Tautan USB di server belum aktif. Jalankan backend dengan "npm run start:usb".';
    }
    return [
      Text('Colok Arduino kalung ${pet.name} ke komputer yang menjalankan server PawFinder memakai kabel USB (kabel data, bukan kabel khusus charger). Alat yang terdeteksi muncul di bawah, lalu ketuk Pasangkan.', style: tx.caption),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: tone.o(0.12), borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(connected ? Icons.usb : Icons.usb_off, size: 18, color: tone),
          const SizedBox(width: 10),
          Expanded(child: Text(statusText, style: tx.caption.copyWith(color: p.text))),
        ]),
      ),
      const SizedBox(height: 14),
      Text('Alat terdeteksi', style: tx.captionStrong),
      const SizedBox(height: 8),
      if (_found.isEmpty)
        Text('Belum ada alat baru yang terdeteksi. Pastikan firmware Arduino mengirim data (lihat README bagian "Koneksi alat"). Daftar diperbarui otomatis.', style: tx.caption)
      else
        for (final d in _found) _foundTile(pet, d),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.error_outline_rounded, size: 16, color: PF.danger),
          const SizedBox(width: 6),
          Expanded(child: Text(_error!, style: tx.caption.copyWith(color: PF.danger))),
        ]),
      ],
    ];
  }

  Widget _foundTile(Pet pet, DiscoveredDevice d) {
    final tx = context.tx;
    final p = context.pf;
    final bat = d.battery == null ? '' : ' · Baterai ${d.battery}%';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.serial, style: tx.bodyStrong),
            Text('${d.sourceLabel}$bat', style: tx.caption),
          ]),
        ),
        PFButton(label: 'Pasangkan', expand: false, height: 40, loading: _loading, onPressed: () => _pair(pet, d.serial)),
      ]),
    );
  }
}
