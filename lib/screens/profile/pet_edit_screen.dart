import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/photo_picker.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/data_source.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../widgets/buttons.dart';
import '../../widgets/cards.dart';
import '../../widgets/common.dart';
import '../../widgets/inputs.dart';
import '../../widgets/pet_art.dart';
import '../../widgets/pet_face.dart';
import '../../widgets/pressable.dart';

/// Detail Profil Hewan: edit nama, jenis, kelamin, tanggal lahir, dan FOTO (galeri/kamera dengan izin).
class PetEditScreen extends StatefulWidget {
  const PetEditScreen({super.key});

  @override
  State<PetEditScreen> createState() => _PetEditScreenState();
}

class _PetEditScreenState extends State<PetEditScreen> {
  late final TextEditingController _name;
  late int _species, _gender, _color;
  DateTime? _birth;
  String? _nameErr;
  bool _saving = false, _uploading = false;
  late final String _petId;

  @override
  void initState() {
    super.initState();
    final pet = context.read<AppState>().selectedPet!;
    _petId = pet.id;
    _name = TextEditingController(text: pet.name);
    _species = pet.species.index;
    _gender = pet.isMale ? 0 : 1;
    _color = pet.avatarColor;
    _birth = pet.birthDate;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Pet? get _pet => context.read<AppState>().petById(_petId);

  // ---- foto ----
  void _photoMenu() {
    final pet = _pet;
    if (pet == null) return;
    showPFSheet<void>(
      context,
      title: 'Foto Profil',
      builder: (ctx) => TileGroup(children: [
        MenuTile(icon: Icons.photo_library_outlined, label: 'Pilih dari Galeri', subtitle: 'Perlu izin akses galeri', onTap: () {
          Navigator.of(ctx).pop();
          _pick(PhotoSource.gallery);
        }),
        MenuTile(icon: Icons.photo_camera_outlined, label: 'Ambil Foto', subtitle: 'Perlu izin akses kamera', onTap: () {
          Navigator.of(ctx).pop();
          _pick(PhotoSource.camera);
        }),
        MenuTile(icon: Icons.palette_outlined, label: 'Warna Latar Avatar', subtitle: 'Dipakai bila tidak ada foto', onTap: () {
          Navigator.of(ctx).pop();
          _pickColor();
        }),
        if (pet.hasPhoto)
          MenuTile(icon: Icons.delete_outline_rounded, label: 'Hapus Foto', danger: true, onTap: () {
            Navigator.of(ctx).pop();
            _removePhoto();
          }),
      ]),
    );
  }

  Future<void> _pick(PhotoSource source) async {
    final app = context.read<AppState>();
    final res = await pickPetPhoto(context, source);
    if (!mounted || res.isCancelled) return;
    if (res.error != null) {
      showToast(context, res.error!, kind: ToastKind.error);
      return;
    }
    setState(() => _uploading = true);
    try {
      await app.setPetPhoto(_petId, res.bytes!);
      if (mounted) showToast(context, 'Foto profil diperbarui', kind: ToastKind.success);
    } catch (e) {
      if (mounted) showToast(context, errorText(e), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removePhoto() async {
    final app = context.read<AppState>();
    setState(() => _uploading = true);
    try {
      await app.removePetPhoto(_petId);
      if (mounted) showToast(context, 'Foto dihapus');
    } catch (e) {
      if (mounted) showToast(context, errorText(e), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _pickColor() {
    showPFSheet<void>(
      context,
      title: 'Warna Latar Avatar',
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: PetAvatar(species: Species.values[_species], size: 96, colorIndex: _color)),
          const SizedBox(height: 20),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: List.generate(6, (i) {
              final sel = i == _color;
              return Semantics(
                button: true,
                selected: sel,
                label: 'Warna ${i + 1}',
                child: GestureDetector(
                  onTap: () {
                    setState(() => _color = i);
                    setSheet(() {});
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: avatarBg(ctx, i), shape: BoxShape.circle, border: Border.all(color: sel ? PF.primary : ctx.pf.border, width: sel ? 3 : 1.5)),
                    child: sel ? const Icon(Icons.check_rounded, color: PF.primary) : null,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 22),
          PFButton(label: 'Selesai', onPressed: () => Navigator.of(ctx).pop()),
        ]);
      }),
    );
  }

  // ---- simpan & hapus ----
  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final name = _name.text.trim();
    final pet = _pet;
    if (pet == null) return;
    if (name.isEmpty) {
      setState(() => _nameErr = 'Nama hewan wajib diisi');
      return;
    }
    setState(() {
      _nameErr = null;
      _saving = true;
    });
    final app = context.read<AppState>();
    try {
      await app.updatePet(pet.copyWith(
        name: name,
        species: Species.values[_species],
        gender: _gender == 0 ? 'jantan' : 'betina',
        birthDate: _birth,
        clearBirth: _birth == null,
        avatarColor: _color,
      ));
      if (!mounted) return;
      showToast(context, 'Profil $name diperbarui', kind: ToastKind.success);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, errorText(e), kind: ToastKind.error);
    }
  }

  Future<void> _delete() async {
    final pet = _pet;
    if (pet == null) return;
    final ok = await showConfirmDialog(context, title: 'Hapus ${pet.name}?', message: 'Profil, koneksi GPS, geofence, catatan kesehatan, dan riwayat ${pet.name} akan dihapus permanen.', confirmLabel: 'Hapus', danger: true);
    if (!ok || !mounted) return;
    final app = context.read<AppState>();
    final nav = Navigator.of(context);
    try {
      await app.deletePet(_petId);
      nav.pop();
    } catch (e) {
      if (mounted) showToast(context, errorText(e), kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pet = app.petById(_petId);
    final tx = context.tx;
    final p = context.pf;
    if (pet == null) return const Scaffold(body: Column(children: [PFTopBar(title: 'Detail Profil Hewan'), Expanded(child: Center(child: Text('Data hewan tidak ditemukan.')))]));
    return Scaffold(
      body: Column(
        children: [
          const PFTopBar(title: 'Detail Profil Hewan'),
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(PF.margin, 4, PF.margin, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Pressable(
                      onTap: _uploading ? null : _photoMenu,
                      child: Stack(clipBehavior: Clip.none, children: [
                        pet.hasPhoto ? PetFace(pet: pet, size: 104) : PetAvatar(species: Species.values[_species], size: 104, colorIndex: _color),
                        if (_uploading) Positioned.fill(child: Container(decoration: BoxDecoration(color: Colors.black.o(0.35), shape: BoxShape.circle), child: const Center(child: PFSpinner(size: 26)))),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(color: PF.primary, shape: BoxShape.circle, border: Border.all(color: p.background, width: 3)),
                            child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 18),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  Center(child: PFButton(label: 'Ubah foto', kind: PFButtonKind.text, expand: false, onPressed: _uploading ? null : _photoMenu)),
                  const SizedBox(height: 8),
                  PFTextField(label: 'Nama Hewan*', controller: _name, errorText: _nameErr, maxLength: 30, textCapitalization: TextCapitalization.words, onChanged: (_) {
                    if (_nameErr != null) setState(() => _nameErr = null);
                  }),
                  const SizedBox(height: 18),
                  Text('Jenis Hewan', style: tx.captionStrong),
                  const SizedBox(height: 8),
                  PFSegmented(items: Species.values.map((e) => e.label).toList(), index: _species, onChanged: (i) => setState(() => _species = i)),
                  const SizedBox(height: 18),
                  Text('Jenis Kelamin', style: tx.captionStrong),
                  const SizedBox(height: 8),
                  PFSegmented(items: const ['Jantan', 'Betina'], index: _gender, onChanged: (i) => setState(() => _gender = i)),
                  const SizedBox(height: 18),
                  PFDateField(label: 'Tanggal Lahir (opsional)', value: _birth, onChanged: (d) => setState(() => _birth = d)),
                  if (_birth != null) ...[
                    const SizedBox(height: 8),
                    Text('Usia ${ageLong(_birth)} · per ${fmtDateLong(wibNow())}', style: tx.micro),
                  ],
                  const SizedBox(height: 28),
                  PFButton(label: 'Simpan', loading: _saving, onPressed: _save),
                  const SizedBox(height: 6),
                  PFButton(label: 'Hapus hewan ini', icon: Icons.delete_outline_rounded, kind: PFButtonKind.text, onPressed: _delete),
                  const SizedBox(height: 4),
                  Center(child: Text(pet.device.paired ? 'Nomor seri kalung: ${pet.device.serial}' : 'Kalung GPS belum terhubung', style: tx.micro.copyWith(color: p.textSecondary))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
