import 'dart:async';
import 'dart:math' as math;

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

/// Sheet koneksi kalung GPS: isi nomor seri -> menunggu sinyal -> terhubung (hijau).
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
  final _serial = TextEditingController(text: 'PF');
  bool _loading = false;
  bool _sent = false; // pairing berhasil, menunggu sinyal
  String? _error;
  int _waited = 0;
  Timer? _tick;
  bool _closing = false;

  @override
  void dispose() {
    _tick?.cancel();
    _serial.dispose();
    super.dispose();
  }

  Future<void> _pair(Pet pet) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AppState>().pairDevice(pet.id, _serial.text);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _sent = true;
      });
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
          online ? '${pet.name} kini dilacak secara real-time.' : 'Kalung ${pet.device.serial ?? ''} sudah dipasangkan. Status akan berubah menjadi hijau begitu kalung mengirim lokasi pertamanya.',
          textAlign: TextAlign.center,
          style: tx.bodySecondary.copyWith(fontSize: 14),
        ),
        if (!online && _waited >= 20) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.warningBg, borderRadius: BorderRadius.circular(14)),
            child: Text('Belum ada sinyal. Pastikan kalung menyala, berada di area jaringan, dan nomor seri sudah benar. Kamu boleh menutup sheet ini; status tetap diperbarui otomatis.', style: tx.caption.copyWith(color: p.text)),
          ),
        ],
        const SizedBox(height: 20),
        PFButton(label: online ? 'Selesai' : 'Tutup', kind: online ? PFButtonKind.primary : PFButtonKind.secondary, onPressed: () => Navigator.of(context).maybePop()),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Masukkan nomor seri yang tertera pada kalung ${pet.name}. Status baru menjadi Online (hijau) setelah kalung benar-benar mengirim sinyal.', style: tx.caption),
      const SizedBox(height: 16),
      PFTextField(
        label: 'Nomor seri kalung',
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
      const SizedBox(height: 6),
      Align(alignment: Alignment.centerLeft, child: PFButton(label: 'Isi nomor seri contoh (untuk uji coba)', kind: PFButtonKind.text, expand: false, onPressed: () => _fillExample(pet))),
      const SizedBox(height: 8),
      PFButton(label: 'Hubungkan', icon: Icons.link_rounded, loading: _loading, onPressed: () => _pair(pet)),
    ]);
  }
}
