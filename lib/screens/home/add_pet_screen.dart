import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/data_source.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../../widgets/inputs.dart';
import '../../widgets/pair_sheet.dart';
import '../../widgets/pet_art.dart';

class AddPetScreen extends StatefulWidget {
  const AddPetScreen({super.key});

  @override
  State<AddPetScreen> createState() => _AddPetScreenState();
}

class _AddPetScreenState extends State<AddPetScreen> {
  final _name = TextEditingController();
  int _species = 0;
  int _gender = 0;
  DateTime? _birth;
  String? _nameErr, _birthErr;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final name = _name.text.trim();
    final nameErr = name.isEmpty ? 'Nama hewan wajib diisi' : (name.length > 30 ? 'Nama maksimal 30 karakter' : null);
    final birthErr = _birth == null ? 'Tanggal lahir wajib diisi' : null;
    if (nameErr != null || birthErr != null) {
      setState(() {
        _nameErr = nameErr;
        _birthErr = birthErr;
      });
      return;
    }
    setState(() {
      _nameErr = null;
      _birthErr = null;
      _saving = true;
    });
    final app = context.read<AppState>();
    try {
      final pet = await app.addPet(
        name: name,
        species: Species.values[_species],
        gender: _gender == 0 ? 'jantan' : 'betina',
        birthDate: _birth,
        avatarColor: app.pets.length % 6,
      );
      if (!mounted) return;
      showToast(context, '${pet.name} berhasil ditambahkan', kind: ToastKind.success);
      // Hewan baru belum terhubung ke GPS: tawarkan langsung memasangkan kalung.
      final connect = await showConfirmDialog(
        context,
        title: 'Hubungkan kalung GPS sekarang?',
        message: '${pet.name} baru bisa dilacak setelah kalung GPS dipasangkan. Kamu juga bisa melakukannya nanti dari Beranda atau Geofencing.',
        confirmLabel: 'Hubungkan',
        cancelLabel: 'Nanti',
        icon: Icons.link_rounded,
      );
      if (connect && mounted) await showPairSheet(context, pet);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        // Galat dari server yang menunjuk ke satu kolom ditampilkan tepat di bawah kolom itu.
        if (e is ApiException && e.field == 'name') _nameErr = e.message;
        if (e is ApiException && e.field == 'birthDate') _birthErr = e.message;
      });
      final inline = e is ApiException && (e.field == 'name' || e.field == 'birthDate');
      if (!inline) showToast(context, errorText(e), kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final tx = context.tx;
    final species = Species.values[_species];
    return Scaffold(
      body: Column(
        children: [
          const PFTopBar(title: 'Tambah Hewan Peliharaan'),
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(PF.margin, 8, PF.margin, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PFSegmented(items: Species.values.map((e) => e.label).toList(), index: _species, onChanged: (i) => setState(() => _species = i)),
                  const SizedBox(height: 16),
                  Container(
                    height: 180,
                    decoration: BoxDecoration(color: p.primaryLight, borderRadius: BorderRadius.circular(24)),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: ScaleTransition(scale: Tween<double>(begin: 0.9, end: 1).animate(anim), child: child)),
                      child: PetFigure(key: ValueKey(species), species: species, size: 160),
                    ),
                  ),
                  const SizedBox(height: 22),
                  PFTextField(label: 'Nama Hewan*', hint: 'Masukkan nama hewan', controller: _name, errorText: _nameErr, maxLength: 30, textCapitalization: TextCapitalization.words, onChanged: (_) {
                    if (_nameErr != null) setState(() => _nameErr = null);
                  }),
                  const SizedBox(height: 18),
                  Text('Jenis Kelamin', style: tx.captionStrong),
                  const SizedBox(height: 8),
                  PFSegmented(items: const ['Jantan', 'Betina'], index: _gender, onChanged: (i) => setState(() => _gender = i)),
                  const SizedBox(height: 18),
                  PFDateField(
                    label: 'Tanggal Lahir*',
                    value: _birth,
                    errorText: _birthErr,
                    onChanged: (d) => setState(() {
                      _birth = d;
                      _birthErr = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  Text('Tidak tahu tanggal pastinya? Perkirakan saja. Profil membantu kami menampilkan aktivitas yang sesuai untuk hewan kesayanganmu.', style: tx.caption),
                  const SizedBox(height: 26),
                  PFButton(label: 'Simpan', loading: _saving, onPressed: _save),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
