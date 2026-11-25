import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/data_source.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../widgets/buttons.dart';
import '../../widgets/cards.dart';
import '../../widgets/common.dart';
import '../../widgets/inputs.dart';
import '../../widgets/pet_face.dart';
import '../../widgets/pet_picker.dart';
import '../../widgets/pressable.dart';

IconData _recordIcon(String type) => switch (type) {
      'berat' => Icons.monitor_weight_outlined,
      'vaksin' => Icons.vaccines_outlined,
      'obat' => Icons.medication_outlined,
      _ => Icons.edit_note_rounded,
    };

/// KESEHATAN (fitur tersendiri): sensor kalung + catatan kesehatan yang dibuat pengguna
/// (berat badan, vaksin, obat, catatan).
class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  HealthSummary? _h;
  String? _error;
  String? _loadedFor;

  Future<void> _load(AppState s, String petId) async {
    setState(() => _error = null);
    try {
      final h = await s.health(petId);
      if (mounted && s.selectedPet?.id == petId) setState(() => _h = h);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  void _addRecord(AppState s, Pet pet) {
    showPFSheet<void>(context, title: 'Tambah Catatan Kesehatan', builder: (ctx) => _RecordForm(pet: pet, onSaved: () => _load(s, pet.id)));
  }

  Future<void> _delete(AppState s, Pet pet, HealthRecord r) async {
    final ok = await showConfirmDialog(context, title: 'Hapus catatan?', message: '"${r.headline}" akan dihapus dari catatan kesehatan ${pet.name}.', confirmLabel: 'Hapus', danger: true);
    if (!ok || !mounted) return;
    try {
      await s.deleteHealthRecord(pet.id, r.id);
      if (mounted) {
        showToast(context, 'Catatan dihapus');
        _load(s, pet.id);
      }
    } catch (e) {
      if (mounted) showToast(context, errorText(e), kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pet = s.selectedPet;
    final tx = context.tx;
    final p = context.pf;
    if (pet != null && _loadedFor != pet.id) {
      _loadedFor = pet.id;
      _h = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(s, pet.id));
    }
    return Scaffold(
      body: Column(
        children: [
          const PFTopBar(title: 'Kesehatan'),
          Expanded(
            child: pet == null
                ? const Center(child: Text('Belum ada hewan.'))
                : RefreshIndicator(
                    color: PF.primary,
                    onRefresh: () => _load(s, pet.id),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(PF.margin, 4, PF.margin, 28),
                      children: [
                        Pressable(
                          onTap: s.pets.length > 1 ? () => showPetPicker(context, s) : null,
                          child: Row(children: [
                            PetFace(pet: pet, size: 48),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(pet.name, style: tx.h3), Text('${pet.species.label} · ${pet.genderLabel} · ${pet.ageText}', style: tx.caption)]),
                            ),
                            if (s.pets.length > 1) Icon(Icons.keyboard_arrow_down_rounded, color: p.textSecondary),
                          ]),
                        ),
                        const SizedBox(height: 16),
                        if (_error != null)
                          EmptyState(icon: Icons.cloud_off_rounded, title: 'Gagal memuat data', message: _error, actionLabel: 'Coba Lagi', onAction: () => _load(s, pet.id))
                        else if (_h == null)
                          const Column(children: [Skeleton(height: 110, radius: 20), SizedBox(height: 12), Skeleton(height: 110, radius: 20), SizedBox(height: 12), Skeleton(height: 160, radius: 20)])
                        else
                          ..._content(context, s, pet, _h!),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context, AppState s, Pet pet, HealthSummary h) {
    final tx = context.tx;
    final p = context.pf;
    final se = h.sensor;
    Widget tile(IconData icon, Color color, Color bg, String value, String label) => Expanded(
          child: PFCard(
            padding: const EdgeInsets.all(16),
            radius: 18,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconTile(icon: icon, color: color, background: bg, size: 40),
              const SizedBox(height: 14),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: tx.h2)),
              const SizedBox(height: 2),
              Text(label, style: tx.caption),
            ]),
          ),
        );
    return [
      Row(children: [
        Expanded(child: Text('Sensor kalung', style: tx.h3)),
        if (se.live) PFBadge(label: 'Langsung', color: p.successFg, background: p.successBg, dot: true) else PFBadge(label: se.available ? 'Data terakhir' : 'Belum ada data', color: p.textSecondary, background: p.primaryLight),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        tile(Icons.favorite_border_rounded, PF.danger, p.dangerBg, se.heartRate == null ? '—' : '${se.heartRate} bpm', 'Detak jantung'),
        const SizedBox(width: 12),
        tile(Icons.thermostat_rounded, PF.warning, p.warningBg, se.temperature == null ? '—' : '${fmtDecimal(se.temperature!)} °C', 'Suhu tubuh'),
      ]),
      if (!se.available) ...[
        const SizedBox(height: 8),
        Text(pet.device.paired ? 'Kalung belum mengirim data sensor suhu/detak jantung.' : 'Hubungkan kalung GPS yang mendukung sensor untuk melihat suhu dan detak jantung.', style: tx.micro),
      ],
      const SizedBox(height: 22),
      Text('Ringkasan', style: tx.h3),
      const SizedBox(height: 12),
      Row(children: [
        tile(Icons.monitor_weight_outlined, p.primaryText, p.primaryLight, h.latestWeightKg == null ? '—' : '${fmtDecimal(h.latestWeightKg!)} kg', 'Berat terakhir'),
        const SizedBox(width: 12),
        tile(Icons.vaccines_outlined, PF.accent, p.accentBg, h.lastVaccineTitle ?? '—', 'Vaksin terakhir'),
      ]),
      const SizedBox(height: 22),
      Row(children: [
        Expanded(child: Text('Catatan kesehatan', style: tx.h3)),
        PFButton(label: 'Tambah', icon: Icons.add_rounded, kind: PFButtonKind.secondary, expand: false, height: 44, onPressed: () => _addRecord(s, pet)),
      ]),
      const SizedBox(height: 12),
      if (h.records.isEmpty)
        EmptyState(icon: Icons.edit_note_rounded, title: 'Belum ada catatan', message: 'Catat berat badan, vaksinasi, obat, atau catatan dokter hewan ${pet.name}.', actionLabel: 'Tambah Catatan', onAction: () => _addRecord(s, pet))
      else
        for (final r in h.records) ...[
          PFCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            radius: 18,
            child: Row(children: [
              IconTile(icon: _recordIcon(r.type), color: PF.accent, background: p.accentBg, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.headline, style: tx.captionStrong.copyWith(fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('${r.date}${r.note.isEmpty ? '' : ' · ${r.note}'}', style: tx.micro.copyWith(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
              PFIconButton(icon: Icons.delete_outline_rounded, label: 'Hapus catatan', border: false, background: Colors.transparent, color: p.textSecondary, onTap: () => _delete(s, pet, r)),
            ]),
          ),
          const SizedBox(height: 10),
        ],
      const SizedBox(height: 8),
      Text('Catatan ini bersifat pribadi dan bukan pengganti pemeriksaan dokter hewan.', style: tx.micro),
    ];
  }
}

class _RecordForm extends StatefulWidget {
  const _RecordForm({required this.pet, required this.onSaved});
  final Pet pet;
  final VoidCallback onSaved;

  @override
  State<_RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<_RecordForm> {
  static const _types = ['berat', 'vaksin', 'obat', 'catatan'];
  int _type = 0;
  final _value = TextEditingController();
  final _title = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  String? _error, _valueErr, _titleErr;
  bool _saving = false;

  @override
  void dispose() {
    _value.dispose();
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final isWeight = _type == 0;
    double? value;
    if (isWeight) {
      final raw = _value.text.trim();
      if (raw.isEmpty) {
        setState(() => _valueErr = 'Berat wajib diisi');
        return;
      }
      value = double.tryParse(raw.replaceAll(',', '.'));
      if (value == null || value <= 0 || value > 200) {
        setState(() => _valueErr = 'Masukkan berat yang valid (0,1 – 200 kg)');
        return;
      }
    } else if (_title.text.trim().isEmpty) {
      setState(() => _titleErr = 'Judul catatan wajib diisi');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _valueErr = null;
      _titleErr = null;
    });
    final app = context.read<AppState>();
    try {
      await app.addHealthRecord(widget.pet.id, type: _types[_type], title: _title.text, value: value, date: _date, note: _note.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = errorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PFSegmented(items: const ['Berat', 'Vaksin', 'Obat', 'Catatan'], index: _type, onChanged: (i) => setState(() {
            _type = i;
            _error = null;
            _valueErr = null;
            _titleErr = null;
          })),
      const SizedBox(height: 16),
      if (_type == 0)
        PFTextField(
          label: 'Berat (kg)',
          hint: 'mis. 4,5',
          controller: _value,
          errorText: _valueErr,
          onChanged: (_) {
            if (_valueErr != null) setState(() => _valueErr = null);
          },
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          prefixIcon: Icons.monitor_weight_outlined,
        )
      else
        PFTextField(label: 'Judul', hint: _type == 1 ? 'mis. Vaksin rabies' : (_type == 2 ? 'mis. Obat cacing' : 'mis. Kontrol dokter hewan'), controller: _title, errorText: _titleErr, onChanged: (_) {
          if (_titleErr != null) setState(() => _titleErr = null);
        }, maxLength: 60, textCapitalization: TextCapitalization.sentences, prefixIcon: Icons.edit_outlined),
      const SizedBox(height: 14),
      PFDateField(label: 'Tanggal', value: _date, hint: 'Pilih tanggal', firstDate: DateTime(DateTime.now().year - 20), onChanged: (d) => setState(() => _date = d)),
      const SizedBox(height: 14),
      PFTextField(label: 'Keterangan (opsional)', hint: 'mis. dosis, nama dokter', controller: _note, maxLength: 300),
      if (_error != null) ...[
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.error_outline_rounded, size: 16, color: PF.danger),
          const SizedBox(width: 6),
          Expanded(child: Text(_error!, style: context.tx.caption.copyWith(color: PF.danger))),
        ]),
      ],
      const SizedBox(height: 18),
      PFButton(label: 'Simpan', loading: _saving, onPressed: _save),
    ]);
  }
}
