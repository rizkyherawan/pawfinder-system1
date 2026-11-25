import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../data/data_source.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../widgets/buttons.dart';
import '../../widgets/cards.dart';
import '../../widgets/common.dart';
import '../../widgets/pair_sheet.dart';
import '../../widgets/pet_art.dart';
import '../../widgets/pressable.dart';
import '../history/activity_screen.dart';
import '../history/health_screen.dart';
import '../auth/auth_screen.dart';
import '../profile/pet_edit_screen.dart';
import '../tracking/tracker_screen.dart';
import 'add_pet_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// Pengguna boleh melihat dashboard tanpa akun; untuk menyimpan hewan, masuk/daftar dulu.
  Future<void> _addPet(BuildContext context, AppState app) async {
    if (!app.loggedIn) {
      await pushPage(context, const AuthScreen());
      if (!context.mounted || !app.loggedIn) return;
    }
    if (!context.mounted) return;
    await pushPage(context, const AddPetScreen());
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Column(
      children: [
        _Header(unread: s.unreadCount, onBell: () => s.setTab(3)),
        Expanded(
          child: RefreshIndicator(
            color: PF.primary,
            onRefresh: () async {
              try {
                await s.refresh();
              } catch (e) {
                if (context.mounted) showToast(context, 'Gagal memuat data. Tarik untuk mencoba lagi.', kind: ToastKind.error);
              }
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(PF.margin, 8, PF.margin, 24),
              children: s.loadingPets && s.pets.isEmpty
                  ? _skeleton()
                  : s.pets.isEmpty
                      ? _empty(context, s)
                      : _list(context, s),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _skeleton() => [
        const SizedBox(height: 8),
        const Skeleton(height: 28, width: 180),
        const SizedBox(height: 18),
        for (var i = 0; i < 3; i++) ...[const Skeleton(height: 118, radius: 20), const SizedBox(height: 12)],
      ];

  List<Widget> _empty(BuildContext context, AppState s) {
    final p = context.pf;
    final tx = context.tx;
    return [
      Text('Halo, sahabat Paw! 👋', style: tx.h1),
      const SizedBox(height: 4),
      Text('Mulai perjalanan aman bersama.', style: tx.caption),
      const SizedBox(height: 20),
      Container(
        height: 220,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: p.isDark ? const [Color(0xFF1C3566), Color(0xFF14264F)] : const [Color(0xFFE3EEFD), Color(0xFFCCE0F8)]),
        ),
        child: const Center(child: CollarArt(height: 150)),
      ),
      const SizedBox(height: 22),
      Text('Belum ada hewan peliharaan yang ditambahkan', textAlign: TextAlign.center, style: tx.h2),
      const SizedBox(height: 8),
      Text('Tambahkan sahabat kecilmu untuk mulai memantau lokasi dan aktivitasnya.', textAlign: TextAlign.center, style: tx.bodySecondary.copyWith(fontSize: 14)),
      const SizedBox(height: 22),
      PFButton(label: s.loggedIn ? '+ Tambah Hewan Peliharaan' : 'Masuk / Daftar untuk Menambahkan Hewan', onPressed: () => _addPet(context, s)),
      const SizedBox(height: 16),
      PFCard(
        padding: const EdgeInsets.all(14),
        radius: 18,
        child: Row(children: [
          Icon(Icons.shield_outlined, color: p.primaryText, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text('Hubungkan kalung GPS setelah menambahkan profil hewan peliharaan.', style: tx.caption)),
        ]),
      ),
    ];
  }

  List<Widget> _list(BuildContext context, AppState s) {
    final p = context.pf;
    final tx = context.tx;
    final outside = s.outsidePets;
    final tracked = s.pets.where((e) => e.device.online).toList();
    final String note;
    final Color noteColor;
    final IconData noteIcon;
    if (tracked.isEmpty) {
      note = 'Hubungkan kalung GPS untuk mulai memantau lokasi.';
      noteColor = p.textSecondary;
      noteIcon = Icons.link_off_rounded;
    } else if (outside.isNotEmpty) {
      note = '${outside.map((e) => e.name).join(', ')} berada di luar area aman.';
      noteColor = PF.warning;
      noteIcon = Icons.warning_amber_rounded;
    } else if (!tracked.any((e) => e.location != null)) {
      // Alat hidup tetapi belum ada satu pun lokasi: jangan mengklaim "di area aman".
      note = 'Kalung terhubung, menunggu sinyal satelit GPS (bawa ke luar ruangan).';
      noteColor = PF.warning;
      noteIcon = Icons.satellite_alt_outlined;
    } else {
      note = 'Semua hewan yang terlacak berada di area aman.';
      noteColor = p.textSecondary;
      noteIcon = Icons.location_on_outlined;
    }
    final sel = s.selectedPet;
    return [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Text('Hewan kesayangan', style: tx.h1.copyWith(fontSize: 22))),
        Text('${s.pets.length} hewan', style: tx.caption),
      ]),
      const SizedBox(height: 14),
      for (final pet in s.pets) ...[
        PetCard(
          pet: pet,
          onTap: () {
            s.selectPet(pet.id);
            pushPage(context, const TrackerScreen());
          },
          onMenu: () => _petMenu(context, s, pet),
        ),
        const SizedBox(height: 12),
      ],
      PFButton(label: '+ Tambah Hewan', kind: PFButtonKind.secondary, pill: false, onPressed: () => _addPet(context, s)),
      const SizedBox(height: 16),
      Row(children: [
        Icon(noteIcon, size: 17, color: noteColor),
        const SizedBox(width: 8),
        Expanded(child: Text(note, style: tx.caption.copyWith(color: noteColor, fontWeight: outside.isNotEmpty ? FontWeight.w600 : FontWeight.w400))),
      ]),
      if (sel != null) ...[
        const SizedBox(height: 22),
        Text('Pantau ${sel.name}', style: tx.h3),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _QuickCard(icon: Icons.directions_walk_rounded, title: 'Aktivitas', subtitle: 'Langkah & jarak', onTap: () => pushPage(context, const ActivityScreen()))),
          const SizedBox(width: 12),
          Expanded(child: _QuickCard(icon: Icons.favorite_border_rounded, title: 'Kesehatan', subtitle: 'Catatan & sensor', color: PF.accent, onTap: () => pushPage(context, const HealthScreen()))),
        ]),
      ],
    ];
  }

  /// Menu hewan di Beranda: edit, GPS, aktivitas, kesehatan, dan HAPUS.
  void _petMenu(BuildContext context, AppState s, Pet pet) {
    showPFSheet<void>(
      context,
      title: pet.name,
      builder: (ctx) => TileGroup(children: [
        MenuTile(icon: Icons.edit_outlined, label: 'Edit Profil', subtitle: 'Nama, jenis, tanggal lahir, foto', onTap: () {
          Navigator.of(ctx).pop();
          s.selectPet(pet.id);
          pushPage(context, const PetEditScreen());
        }),
        if (!pet.device.paired)
          MenuTile(icon: Icons.link_rounded, label: 'Hubungkan GPS', subtitle: 'Pasangkan kalung dengan nomor seri', onTap: () {
            Navigator.of(ctx).pop();
            s.selectPet(pet.id);
            showPairSheet(context, pet);
          })
        else
          MenuTile(icon: Icons.link_off_rounded, label: 'Putuskan GPS', subtitle: 'Lepaskan kalung ${pet.device.serial ?? ''}', onTap: () async {
            Navigator.of(ctx).pop();
            final ok = await showConfirmDialog(context, title: 'Putuskan GPS?', message: '${pet.name} tidak akan dilacak sampai kalung dipasangkan kembali.', confirmLabel: 'Putuskan', danger: true, icon: Icons.link_off_rounded);
            if (!ok || !context.mounted) return;
            try {
              await s.unpairDevice(pet.id);
              if (context.mounted) showToast(context, 'GPS diputuskan');
            } catch (e) {
              if (context.mounted) showToast(context, errorText(e), kind: ToastKind.error);
            }
          }),
        MenuTile(icon: Icons.directions_walk_rounded, label: 'Aktivitas', onTap: () {
          Navigator.of(ctx).pop();
          s.selectPet(pet.id);
          pushPage(context, const ActivityScreen());
        }),
        MenuTile(icon: Icons.favorite_border_rounded, label: 'Kesehatan', onTap: () {
          Navigator.of(ctx).pop();
          s.selectPet(pet.id);
          pushPage(context, const HealthScreen());
        }),
        MenuTile(icon: Icons.delete_outline_rounded, label: 'Hapus Hewan', subtitle: 'Hapus profil dan seluruh datanya', danger: true, onTap: () async {
          Navigator.of(ctx).pop();
          final ok = await showConfirmDialog(
            context,
            title: 'Hapus ${pet.name}?',
            message: 'Profil, koneksi GPS, geofence, catatan kesehatan, dan riwayat ${pet.name} akan dihapus permanen.',
            confirmLabel: 'Hapus',
            danger: true,
          );
          if (!ok || !context.mounted) return;
          try {
            await s.deletePet(pet.id);
            if (context.mounted) showToast(context, '${pet.name} berhasil dihapus', kind: ToastKind.success);
          } catch (e) {
            if (context.mounted) showToast(context, errorText(e), kind: ToastKind.error);
          }
        }),
      ]),
    );
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({required this.icon, required this.title, required this.subtitle, required this.onTap, this.color});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final tx = context.tx;
    final c = color ?? p.primaryText;
    return Pressable(
      onTap: onTap,
      child: PFCard(
        padding: const EdgeInsets.all(14),
        radius: 18,
        child: Row(children: [
          IconTile(icon: icon, color: c, background: c.o(0.12), size: 42),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: tx.captionStrong.copyWith(fontSize: 14)), Text(subtitle, style: tx.micro, maxLines: 1, overflow: TextOverflow.ellipsis)])),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.unread, required this.onBell});
  final int unread;
  final VoidCallback onBell;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Padding(
      padding: EdgeInsets.fromLTRB(PF.margin, context.topInset + 10, PF.margin, 10),
      child: Row(children: [
        const PFLogo(size: 36),
        const Spacer(),
        Stack(clipBehavior: Clip.none, children: [
          PFIconButton(icon: Icons.notifications_none_rounded, label: 'Notifikasi', onTap: onBell),
          if (unread > 0) Positioned(right: 11, top: 11, child: Container(width: 10, height: 10, decoration: BoxDecoration(color: PF.danger, shape: BoxShape.circle, border: Border.all(color: p.surface, width: 2)))),
        ]),
      ]),
    );
  }
}
