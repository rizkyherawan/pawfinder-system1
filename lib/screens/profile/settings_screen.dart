import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../../widgets/buttons.dart';
import '../../widgets/cards.dart';
import '../../widgets/common.dart';
import '../../widgets/inputs.dart';
import '../design/design_system_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static String _themeLabel(String t) => switch (t) {
        'gelap' => 'Gelap',
        'sistem' => 'Ikuti sistem',
        _ => 'Terang',
      };

  // PENGATURAN TEMA
  void _themeSheet(BuildContext context) {
    showPFSheet<void>(
      context,
      title: 'Tampilan Tema',
      builder: (ctx) => Consumer<AppState>(
        builder: (ctx, s, _) {
          const opts = [
            (
              'terang',
              'Terang',
              Icons.light_mode_outlined,
            ),
            (
              'gelap',
              'Gelap',
              Icons.dark_mode_outlined,
            ),
            (
              'sistem',
              'Ikuti sistem',
              Icons.phone_iphone_rounded,
            ),
          ];

          return TileGroup(
            children: [
              for (final o in opts)
                MenuTile(
                  icon: o.$3,
                  label: o.$2,
                  trailing: s.settings.theme == o.$1
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: PF.primary,
                        )
                      : Icon(
                          Icons.circle_outlined,
                          color: ctx.pf.border,
                        ),
                  onTap: () => s.updateSettings(
                    s.settings.copyWith(theme: o.$1),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // PENGATURAN JENIS PETA
  void _mapSheet(BuildContext context) {
    showPFSheet<void>(
      context,
      title: 'Jenis Peta',
      builder: (ctx) => Consumer<AppState>(
        builder: (ctx, s, _) {
          const opts = [
            (
              'google',
              'OpenStreetMap',
              'Peta geografis nyata dengan koneksi internet. Tidak memerlukan API key.',
              Icons.public_rounded,
            ),
            (
              'ilustrasi',
              'Peta ilustratif',
              'Peta simulasi untuk pengujian tampilan, bukan peta geografis nyata.',
              Icons.map_outlined,
            ),
          ];

          return TileGroup(
            children: [
              for (final o in opts)
                MenuTile(
                  icon: o.$4,
                  label: o.$2,
                  subtitle: o.$3,
                  trailing: s.settings.mapProvider == o.$1
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: PF.primary,
                        )
                      : Icon(
                          Icons.circle_outlined,
                          color: ctx.pf.border,
                        ),
                  onTap: () => s.updateSettings(
                    s.settings.copyWith(
                      mapProvider: o.$1,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // DIALOG INFORMASI
  void _info(
    BuildContext context,
    String title,
    String message,
    IconData icon,
  ) {
    showConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: 'Mengerti',
      cancelLabel: 'Tutup',
      icon: icon,
    );
  }

  // PENGATURAN SERVER API
  void _serverSheet(BuildContext context) {
    final s = context.read<AppState>();
    final ctrl = TextEditingController(
      text: s.baseUrl,
    );

    bool testing = false;

    showPFSheet<void>(
      context,
      title: 'Alamat Server',
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.demoMode
                      ? 'Kamu sedang memakai mode demo. Masuk dengan akun untuk menggunakan server.'
                      : 'Alamat backend PawFinder yang digunakan untuk mengakses data akun, GPS, geofence, dan riwayat.',
                  style: ctx.tx.caption,
                ),
                const SizedBox(height: 14),
                PFTextField(
                  controller: ctrl,
                  hint: 'http://10.0.2.2:4000',
                  keyboardType: TextInputType.url,
                  prefixIcon: Icons.dns_outlined,
                ),
                const SizedBox(height: 16),
                PFButton(
                  label: 'Uji Koneksi',
                  kind: PFButtonKind.secondary,
                  loading: testing,
                  onPressed: () async {
                    if (testing) return;

                    setState(() => testing = true);

                    final input = ctrl.text.trim();

                    final url = input.startsWith('http://') ||
                            input.startsWith('https://')
                        ? input
                        : 'http://$input';

                    try {
                      final err = await s.testConnection(url);

                      if (!ctx.mounted) return;

                      showToast(
                        ctx,
                        err ?? 'Terhubung ke server PawFinder',
                        kind: err == null ? ToastKind.success : ToastKind.error,
                      );
                    } catch (_) {
                      if (!ctx.mounted) return;

                      showToast(
                        ctx,
                        'Tidak dapat terhubung ke server',
                        kind: ToastKind.error,
                      );
                    } finally {
                      if (ctx.mounted) {
                        setState(() => testing = false);
                      }
                    }
                  },
                ),
                const SizedBox(height: 10),
                PFButton(
                  label: 'Simpan',
                  onPressed: () async {
                    await s.setBaseUrl(ctrl.text);

                    if (ctx.mounted) {
                      Navigator.of(ctx).pop();
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(ctrl.dispose);
  }

  // INFORMASI AKUN
  void _accountSheet(BuildContext context) {
    final s = context.read<AppState>();

    final name = s.user?.name.trim() ?? '';

    final initial = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();

    showPFSheet<void>(
      context,
      title: 'Akun',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: PF.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.user?.name ?? '-',
                      style: ctx.tx.h3,
                    ),
                    Text(
                      s.user?.email ?? '-',
                      style: ctx.tx.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (s.loggedIn)
            PFButton(
              label: 'Keluar',
              icon: Icons.logout_rounded,
              kind: PFButtonKind.danger,
              onPressed: () async {
                Navigator.of(ctx).pop();

                backToRoot(context);

                await s.logout();
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final set = s.settings;
    final tx = context.tx;
    final p = context.pf;

    final isOSM = set.mapProvider == 'google';

    return Scaffold(
      body: Column(
        children: [
          const PFTopBar(
            title: 'Pengaturan Aplikasi',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                PF.margin,
                0,
                PF.margin,
                28,
              ),
              children: [
                // NOTIFIKASI DAN GEOFENCING
                const SectionLabel(
                  'Geofencing & Riwayat',
                ),

                PFCard(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                  ),
                  child: Column(
                    children: [
                      SwitchTile(
                        title: 'Notifikasi Push',
                        subtitle: 'Peringatan lokasi dan perangkat',
                        child: PFSwitch(
                          semanticLabel: 'Notifikasi Push',
                          value: set.push,
                          onChanged: (v) => s.updateSettings(
                            set.copyWith(push: v),
                          ),
                        ),
                      ),
                      SwitchTile(
                        title: 'Suara Notifikasi',
                        subtitle: 'Bunyi saat ada notifikasi baru',
                        child: PFSwitch(
                          semanticLabel: 'Suara Notifikasi',
                          value: set.sound,
                          onChanged: (v) => s.updateSettings(
                            set.copyWith(sound: v),
                          ),
                        ),
                      ),
                      SwitchTile(
                        title: 'Mode Hemat Daya',
                        subtitle:
                            'Kurangi frekuensi pembaruan lokasi pada aplikasi',
                        child: PFSwitch(
                          semanticLabel: 'Mode Hemat Daya',
                          value: set.powerSave,
                          onChanged: (v) {
                            s.updateSettings(
                              set.copyWith(
                                powerSave: v,
                              ),
                            );

                            showToast(
                              context,
                              v
                                  ? 'Mode hemat daya aktif'
                                  : 'Mode hemat daya nonaktif',
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // TAMPILAN DAN PETA
                const SectionLabel(
                  'Tampilan & Peta',
                ),

                TileGroup(
                  children: [
                    MenuTile(
                      icon: p.isDark
                          ? Icons.dark_mode_outlined
                          : Icons.light_mode_outlined,
                      label: 'Tampilan Tema',
                      subtitle: 'Terang, Gelap, atau Ikuti Sistem',
                      value: _themeLabel(set.theme),
                      onTap: () => _themeSheet(context),
                    ),
                    MenuTile(
                      icon: Icons.map_outlined,
                      label: 'Jenis Peta',
                      subtitle: isOSM
                          ? 'Peta geografis nyata tanpa API key'
                          : 'Peta simulasi untuk pengujian',
                      value: isOSM ? 'OpenStreetMap' : 'Ilustratif',
                      onTap: () => _mapSheet(context),
                    ),
                    MenuTile(
                      icon: Icons.location_on_outlined,
                      label: 'Informasi Lokasi',
                      subtitle: 'Sumber koordinat pelacakan hewan',
                      onTap: () => _info(
                        context,
                        'Informasi Lokasi',
                        'PawFinder menggunakan koordinat dari kalung GPS hewan. Lokasi ponsel tidak digunakan sebagai pengganti lokasi hewan. Aplikasi navigasi eksternal dapat meminta izin lokasi ponsel.',
                        Icons.location_on_outlined,
                      ),
                    ),
                  ],
                ),

                // KONEKSI PERANGKAT
                const SectionLabel(
                  'Koneksi & Perangkat',
                ),

                TileGroup(
                  children: [
                    MenuTile(
                      icon: Icons.sensors_rounded,
                      label: 'Koneksi Alat GPS',
                      subtitle: 'Internet 4G dan nomor seri perangkat',
                      value: '4G / ID',
                      onTap: () => _info(
                        context,
                        'Koneksi Alat GPS',
                        'PawFinder dirancang untuk menerima koordinat dari kalung GPS melalui jaringan internet 4G. Perangkat mengirim data ke backend menggunakan nomor seri yang sudah dipasangkan dengan akun. Koneksi 4G fisik masih perlu diuji menggunakan perangkat sebenarnya.',
                        Icons.sensors_rounded,
                      ),
                    ),
                    MenuTile(
                      icon: Icons.usb_rounded,
                      label: 'Pengujian Perangkat',
                      subtitle: 'USB dan simulator GPS',
                      onTap: () => _info(
                        context,
                        'Pengujian Perangkat',
                        'Koneksi USB dan simulator digunakan sebagai alternatif pengujian pengiriman koordinat, status perangkat, baterai, dan geofencing sebelum perangkat GPS fisik siap digunakan.',
                        Icons.usb_rounded,
                      ),
                    ),
                    MenuTile(
                      icon: Icons.dns_outlined,
                      label: 'Server API',
                      subtitle: s.baseUrl,
                      value: s.demoMode ? 'Demo' : 'API',
                      onTap: () => _serverSheet(context),
                    ),
                  ],
                ),

                // PENGATURAN AKUN
                const SectionLabel('Akun'),

                TileGroup(
                  children: [
                    MenuTile(
                      icon: Icons.person_outline_rounded,
                      label: 'Akun',
                      subtitle:
                          '${s.user?.name ?? '-'} · ${s.user?.email ?? '-'}',
                      onTap: () => _accountSheet(context),
                    ),
                    MenuTile(
                      icon: Icons.palette_outlined,
                      label: 'Design System',
                      subtitle: 'Palet, tipografi, dan komponen',
                      onTap: () => pushPage(
                        context,
                        const DesignSystemScreen(),
                      ),
                    ),
                  ],
                ),

                // INFORMASI APLIKASI
                const SizedBox(height: 22),

                Center(
                  child: Text(
                    'PawFinder versi ${AppConfig.version}',
                    style: tx.micro.copyWith(
                      color: p.textSecondary,
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                Center(
                  child: Text(
                    'Pet Tracking & Safety System',
                    style: tx.micro,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
