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

/// Pengaturan Aplikasi: notifikasi, tema, izin, koneksi, akun.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static String _themeLabel(String t) => switch (t) { 'gelap' => 'Gelap', 'sistem' => 'Sistem', _ => 'Terang' };

  void _themeSheet(BuildContext context) {
    showPFSheet<void>(
      context,
      title: 'Tampilan Tema',
      builder: (ctx) => Consumer<AppState>(builder: (ctx, s, _) {
        const opts = [('terang', 'Terang', Icons.light_mode_outlined), ('gelap', 'Gelap', Icons.dark_mode_outlined), ('sistem', 'Ikuti sistem', Icons.phone_iphone_rounded)];
        return TileGroup(children: [
          for (final o in opts)
            MenuTile(
              icon: o.$3,
              label: o.$2,
              trailing: s.settings.theme == o.$1 ? const Icon(Icons.check_circle_rounded, color: PF.primary) : Icon(Icons.circle_outlined, color: ctx.pf.border),
              onTap: () => s.updateSettings(s.settings.copyWith(theme: o.$1)),
            ),
        ]);
      }),
    );
  }

  void _mapSheet(BuildContext context) {
    showPFSheet<void>(
      context,
      title: 'Jenis Peta',
      builder: (ctx) => Consumer<AppState>(builder: (ctx, s, _) {
        const opts = [('google', 'Google Maps', 'Peta nyata. Perlu Google Maps API key (lihat README).', Icons.public_rounded), ('ilustrasi', 'Peta ilustratif', 'Tanpa API key. Cocok untuk uji coba.', Icons.map_outlined)];
        return TileGroup(children: [
          for (final o in opts)
            MenuTile(
              icon: o.$4,
              label: o.$2,
              subtitle: o.$3,
              trailing: s.settings.mapProvider == o.$1 ? const Icon(Icons.check_circle_rounded, color: PF.primary) : Icon(Icons.circle_outlined, color: ctx.pf.border),
              onTap: () => s.updateSettings(s.settings.copyWith(mapProvider: o.$1)),
            ),
        ]);
      }),
    );
  }

  void _info(BuildContext context, String title, String message, IconData icon) {
    showConfirmDialog(context, title: title, message: message, confirmLabel: 'Mengerti', cancelLabel: 'Tutup', icon: icon);
  }

  void _serverSheet(BuildContext context) {
    final s = context.read<AppState>();
    final ctrl = TextEditingController(text: s.baseUrl);
    showPFSheet<void>(
      context,
      title: 'Alamat Server',
      builder: (ctx) {
        var testing = false;
        return StatefulBuilder(builder: (ctx, setState) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.demoMode ? 'Kamu sedang memakai mode demo. Keluar lalu masuk dengan akun untuk memakai server.' : 'Alamat backend PawFinder yang dipakai aplikasi.', style: ctx.tx.caption),
            const SizedBox(height: 14),
            PFTextField(controller: ctrl, hint: 'http://10.0.2.2:4000', keyboardType: TextInputType.url, prefixIcon: Icons.dns_outlined),
            const SizedBox(height: 16),
            PFButton(
              label: 'Uji Koneksi',
              kind: PFButtonKind.secondary,
              loading: testing,
              onPressed: () async {
                setState(() => testing = true);
                final url = ctrl.text.trim().startsWith('http') ? ctrl.text.trim() : 'http://${ctrl.text.trim()}';
                final err = await s.testConnection(url);
                setState(() => testing = false);
                if (ctx.mounted) showToast(ctx, err ?? 'Terhubung ke server PawFinder', kind: err == null ? ToastKind.success : ToastKind.error);
              },
            ),
            const SizedBox(height: 10),
            PFButton(
              label: 'Simpan',
              onPressed: () async {
                await s.setBaseUrl(ctrl.text);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
          ]);
        });
      },
    );
  }

  void _accountSheet(BuildContext context) {
    final s = context.read<AppState>();
    showPFSheet<void>(
      context,
      title: 'Akun',
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: PF.primary, shape: BoxShape.circle),
            child: Text((s.user?.name ?? '?')[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.user?.name ?? '-', style: ctx.tx.h3), Text(s.user?.email ?? '-', style: ctx.tx.caption)])),
        ]),
        const SizedBox(height: 22),
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
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final set = s.settings;
    final tx = context.tx;
    final p = context.pf;
    return Scaffold(
      body: Column(
        children: [
          const PFTopBar(title: 'Pengaturan Aplikasi'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(PF.margin, 0, PF.margin, 28),
              children: [
                const SectionLabel('Geofencing & Riwayat'),
                PFCard(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(children: [
                    SwitchTile(title: 'Notifikasi Push', subtitle: 'Peringatan lokasi dan perangkat', child: PFSwitch(semanticLabel: 'Notifikasi Push', value: set.push, onChanged: (v) => s.updateSettings(set.copyWith(push: v)))),
                    SwitchTile(title: 'Suara Notifikasi', subtitle: 'Bunyi saat ada notifikasi baru', child: PFSwitch(semanticLabel: 'Suara Notifikasi', value: set.sound, onChanged: (v) => s.updateSettings(set.copyWith(sound: v)))),
                    SwitchTile(
                      title: 'Mode Hemat Daya',
                      subtitle: 'Kurangi frekuensi pembaruan GPS',
                      child: PFSwitch(
                        semanticLabel: 'Mode Hemat Daya',
                        value: set.powerSave,
                        onChanged: (v) {
                          s.updateSettings(set.copyWith(powerSave: v));
                          showToast(context, v ? 'Mode hemat daya aktif · lokasi diperbarui tiap 15 detik' : 'Mode hemat daya nonaktif');
                        },
                      ),
                    ),
                  ]),
                ),
                const SectionLabel('Tampilan & Koneksi'),
                TileGroup(children: [
                  MenuTile(icon: Icons.light_mode_outlined, label: 'Tampilan Tema', subtitle: 'Terang / Gelap', value: _themeLabel(set.theme), onTap: () => _themeSheet(context)),
                  MenuTile(icon: Icons.location_on_outlined, label: 'Izin Lokasi', subtitle: 'Diperlukan untuk pelacakan', value: 'Selalu', onTap: () => _info(context, 'Izin Lokasi', 'PawFinder memakai lokasi dari kalung GPS hewan, bukan dari ponselmu. Izin lokasi ponsel hanya dipakai untuk fitur navigasi ke lokasi hewan.', Icons.location_on_outlined)),
                  MenuTile(icon: Icons.bluetooth_rounded, label: 'Bluetooth', subtitle: 'Untuk menghubungkan kalung GPS', value: 'Aktif', onTap: () => _info(context, 'Bluetooth', 'Bluetooth dipakai saat pertama kali memasangkan kalung GPS. Setelah itu kalung terhubung ke server lewat jaringan IoT.', Icons.bluetooth_rounded)),
                  MenuTile(icon: Icons.map_outlined, label: 'Jenis Peta', subtitle: !AppConfig.googleMapsSupported ? 'Peta ilustratif (Google Maps hanya di Android/iOS)' : (set.mapProvider == 'google' ? 'Google Maps (butuh API key)' : 'Peta ilustratif (tanpa API key)'), value: AppConfig.googleMapsSupported && set.mapProvider == 'google' ? 'Google' : 'Ilustratif', onTap: () => _mapSheet(context)),
                  MenuTile(icon: Icons.dns_outlined, label: 'Server API', subtitle: s.baseUrl, value: s.demoMode ? 'Demo' : 'Online', onTap: () => _serverSheet(context)),
                ]),
                const SectionLabel('Akun'),
                TileGroup(children: [
                  MenuTile(icon: Icons.person_outline_rounded, label: 'Akun', subtitle: '${s.user?.name ?? '-'} · ${s.user?.email ?? '-'}', onTap: () => _accountSheet(context)),
                  MenuTile(icon: Icons.palette_outlined, label: 'Design System', subtitle: 'Palet, tipografi, dan komponen', onTap: () => pushPage(context, const DesignSystemScreen())),
                ]),
                const SizedBox(height: 22),
                Center(child: Text('PawFinder versi ${AppConfig.version}', style: tx.micro.copyWith(color: p.textSecondary))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
