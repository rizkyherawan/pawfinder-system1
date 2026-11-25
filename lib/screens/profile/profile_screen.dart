import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../widgets/buttons.dart';
import '../../widgets/cards.dart';
import '../../widgets/common.dart';
import '../../widgets/pet_face.dart';
import '../auth/auth_screen.dart';
import '../history/activity_screen.dart';
import '../history/health_screen.dart';
import '../home/add_pet_screen.dart';
import 'edit_account_screen.dart';
import 'help_screen.dart';
import 'pet_edit_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _openAuth(BuildContext context) async {
    await pushPage(context, const AuthScreen());
  }

  Future<void> _addPet(
    BuildContext context,
    AppState app,
  ) async {
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
    final p = context.pf;
    final tx = context.tx;
    final selected = s.selectedPet;
    final name = s.user?.name.trim() ?? '';

    final initial = name.isEmpty ? 'P' : name.substring(0, 1).toUpperCase();

    final themeLabel = switch (s.settings.theme) {
      'gelap' => 'Gelap',
      'sistem' => 'Ikuti sistem',
      _ => 'Terang',
    };

    return Column(
      children: [
        const PFTopBar(
          title: 'Profil',
          showBack: false,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              PF.margin,
              4,
              PF.margin,
              34,
            ),
            children: [
              // PROFIL PEMILIK
              PFCard(
                padding: const EdgeInsets.all(18),
                radius: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: p.primaryLight,
                            shape: BoxShape.circle,
                          ),
                          child: s.loggedIn
                              ? Text(
                                  initial,
                                  style: tx.h1.copyWith(
                                    fontSize: 26,
                                    color: p.primaryText,
                                  ),
                                )
                              : Icon(
                                  Icons.person_outline_rounded,
                                  size: 30,
                                  color: p.primaryText,
                                ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.loggedIn
                                    ? s.user!.name
                                    : 'Selamat datang di PawFinder',
                                style: tx.h2,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                s.loggedIn
                                    ? s.user!.email
                                    : 'Masuk atau buat akun untuk menyimpan data hewanmu.',
                                style: tx.caption,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (s.demoMode) ...[
                                const SizedBox(height: 6),
                                const PFBadge(
                                  label: 'Mode demo',
                                  color: PF.primary,
                                  background: Color(0xFFEAF1FF),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (s.loggedIn)
                          PFIconButton(
                            icon: Icons.edit_outlined,
                            label: 'Edit profil pemilik',
                            background: p.surface,
                            onTap: () => pushPage(
                              context,
                              const EditAccountScreen(),
                            ),
                          ),
                      ],
                    ),
                    if (!s.loggedIn) ...[
                      const SizedBox(height: 18),
                      PFButton(
                        label: 'Masuk / Buat Akun',
                        icon: Icons.login_rounded,
                        onPressed: () => _openAuth(context),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      Text(
                        'Profil pemilik terpisah dari profil hewan peliharaan.',
                        style: tx.micro,
                      ),
                    ],
                  ],
                ),
              ),

              // PENGATURAN APLIKASI
              const SizedBox(height: 14),

              TileGroup(
                children: [
                  MenuTile(
                    icon: Icons.settings_outlined,
                    label: 'Pengaturan',
                    subtitle: 'Tema, notifikasi, peta dan koneksi',
                    onTap: () => pushPage(
                      context,
                      const SettingsScreen(),
                    ),
                  ),
                  MenuTile(
                    icon: p.isDark
                        ? Icons.dark_mode_outlined
                        : Icons.light_mode_outlined,
                    label: 'Tampilan Tema',
                    subtitle: 'Ubah tema aplikasi',
                    value: themeLabel,
                    onTap: () => pushPage(
                      context,
                      const SettingsScreen(),
                    ),
                  ),
                ],
              ),

              // DAFTAR HEWAN PELIHARAAN
              const SectionLabel('Hewan Peliharaan Saya'),

              if (!s.loggedIn)
                PFCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Icon(
                        Icons.pets_rounded,
                        size: 36,
                        color: p.textSecondary,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Masuk untuk mengelola hewan',
                        style: tx.h3,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Setelah masuk, kamu bisa menambahkan beberapa hewan ke satu akun dan mengelola setiap profilnya secara terpisah.',
                        style: tx.caption,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      PFButton(
                        label: 'Masuk / Daftar',
                        onPressed: () => _openAuth(context),
                      ),
                    ],
                  ),
                )
              else if (s.pets.isEmpty)
                PFCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Icon(
                        Icons.pets_outlined,
                        size: 36,
                        color: p.textSecondary,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Belum ada hewan peliharaan',
                        style: tx.h3,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tambahkan anjing, kucing, atau kelinci. Satu akun dapat menyimpan lebih dari satu hewan.',
                        style: tx.caption,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else
                for (final pet in s.pets) ...[
                  _PetAccountCard(
                    pet: pet,
                    selected: pet.id == selected?.id,
                    onSelect: () => s.selectPet(pet.id),
                    onEdit: () {
                      s.selectPet(pet.id);

                      pushPage(
                        context,
                        const PetEditScreen(),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                ],

              if (s.loggedIn) ...[
                const SizedBox(height: 8),
                PFButton(
                  label: 'Tambah Hewan Peliharaan',
                  icon: Icons.add_rounded,
                  kind: PFButtonKind.secondary,
                  onPressed: () => _addPet(context, s),
                ),
              ],

              // FITUR PAWFINDER
              const SectionLabel('Fitur PawFinder'),

              TileGroup(
                children: [
                  MenuTile(
                    icon: Icons.directions_walk_rounded,
                    label: 'Aktivitas Hewan',
                    subtitle: selected == null
                        ? 'Pilih atau tambahkan hewan terlebih dahulu'
                        : 'Langkah, jarak, dan waktu aktif ${selected.name}',
                    onTap: selected == null
                        ? () => _addPet(context, s)
                        : () => pushPage(
                              context,
                              const ActivityScreen(),
                            ),
                  ),
                  MenuTile(
                    icon: Icons.favorite_border_rounded,
                    label: 'Kesehatan Hewan',
                    subtitle: selected == null
                        ? 'Catatan kesehatan setiap hewan'
                        : 'Catatan kesehatan ${selected.name}',
                    onTap: selected == null
                        ? () => _addPet(context, s)
                        : () => pushPage(
                              context,
                              const HealthScreen(),
                            ),
                  ),
                  MenuTile(
                    icon: Icons.location_on_outlined,
                    label: 'Geofencing',
                    onTap: () => s.setTab(2),
                  ),
                  MenuTile(
                    icon: Icons.history_rounded,
                    label: 'Riwayat',
                    onTap: () => s.setTab(1),
                  ),
                  MenuTile(
                    icon: Icons.notifications_none_rounded,
                    label: 'Notifikasi',
                    onTap: () => s.setTab(3),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // BANTUAN DAN LOGOUT
              TileGroup(
                children: [
                  MenuTile(
                    icon: Icons.help_outline_rounded,
                    label: 'Bantuan & FAQ',
                    onTap: () => pushPage(
                      context,
                      const HelpScreen(),
                    ),
                  ),
                  if (s.loggedIn)
                    MenuTile(
                      icon: Icons.logout_rounded,
                      label: 'Keluar dari Akun',
                      danger: true,
                      onTap: () async {
                        final ok = await showConfirmDialog(
                          context,
                          title: 'Keluar dari PawFinder?',
                          message:
                              'Kamu akan kembali ke dashboard. Data akun tetap tersimpan di server.',
                          confirmLabel: 'Keluar',
                          danger: true,
                          icon: Icons.logout_rounded,
                        );

                        if (ok && context.mounted) {
                          await s.logout();
                        }
                      },
                    ),
                ],
              ),

              const SizedBox(height: 18),

              Center(
                child: Text(
                  '${AppConfig.appName} · ${AppConfig.tagline}',
                  style: tx.micro,
                ),
              ),

              Center(
                child: Text(
                  'Versi ${AppConfig.version}',
                  style: tx.micro.copyWith(
                    color: p.textSecondary.o(0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PetAccountCard extends StatelessWidget {
  const _PetAccountCard({
    required this.pet,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
  });

  final Pet pet;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final tx = context.tx;

    return PFCard(
      radius: 20,
      padding: const EdgeInsets.all(13),
      border: selected,
      color: selected ? p.primaryLight.o(0.5) : null,
      child: Row(
        children: [
          PetFace(
            pet: pet,
            size: 58,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onSelect,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pet.name,
                    style: tx.h3,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${pet.species.label} · ${pet.genderLabel} · ${pet.ageText}',
                    style: tx.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 15,
                        color: selected ? PF.primary : p.textSecondary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        selected ? 'Hewan aktif' : 'Pilih hewan',
                        style: tx.micro.copyWith(
                          color: selected ? p.primaryText : p.textSecondary,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          PFIconButton(
            icon: Icons.edit_outlined,
            label: 'Edit ${pet.name}',
            onTap: onEdit,
            size: 42,
          ),
        ],
      ),
    );
  }
}
