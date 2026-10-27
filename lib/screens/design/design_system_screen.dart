import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../widgets/buttons.dart';
import '../../widgets/cards.dart';
import '../../widgets/common.dart';
import '../../widgets/inputs.dart';
import '../../widgets/pet_art.dart';

/// Galeri Design System: palet, tipografi, ikon, dan semua komponen beserta state-nya.
class DesignSystemScreen extends StatefulWidget {
  const DesignSystemScreen({super.key});

  @override
  State<DesignSystemScreen> createState() => _DesignSystemScreenState();
}

class _DesignSystemScreenState extends State<DesignSystemScreen> {
  int _seg = 0, _gender = 0, _chip = 0, _page = 1;
  bool _toggle = true;
  double _radius = 500;
  final _filled = TextEditingController(text: 'Nama hewan');
  DateTime? _date;

  @override
  void dispose() {
    _filled.dispose();
    super.dispose();
  }

  Widget _title(String t) => Padding(padding: const EdgeInsets.fromLTRB(2, 26, 2, 12), child: Text(t, style: context.tx.h2));

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final tx = context.tx;
    final demoPet = Pet(
      id: 'demo', name: 'Nama Hewan', species: Species.anjing, gender: 'jantan', birthDate: DateTime.now().subtract(const Duration(days: 800)),
      device: const DeviceInfo(serial: 'PF-ABC-123456', battery: 18, paired: true, connection: 'online'),
    );
    final demoNtf = AppNotification(id: 'n', petId: 'demo', category: 'geofence', type: 'exit', title: 'Hewan keluar dari Geofence', subtitle: 'Di luar area Rumah', time: DateTime.now());
    String hex(String light, String dark) => p.isDark ? dark : light;
    final swatches = <(String, Color, String)>[
      ('Primary', PF.primary, '#1E6BFF'), ('Primary Dark', PF.primaryDark, '#0B4FD6'), ('Primary Light', p.primaryLight, hex('#E8F0FF', '#17284F')),
      ('Background', p.background, hex('#F5F9FF', '#0B1226')), ('Surface', p.surface, hex('#FFFFFF', '#131C36')), ('Text Primary', p.text, hex('#0F1B3D', '#EAF0FF')),
      ('Text Secondary', p.textSecondary, hex('#5B6A8A', '#9AA8C7')), ('Border', p.border, hex('#E1E8F5', '#25304F')), ('Success', PF.success, '#22C55E'),
      ('Warning', PF.warning, '#F59E0B'), ('Danger', PF.danger, '#EF4444'), ('Info/Accent', PF.accent, '#8B5CF6'),
    ];
    return Scaffold(
      body: Column(
        children: [
          const PFTopBar(title: 'Design System'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(PF.margin, 0, PF.margin, 40),
              children: [
                Text('Tema mengikuti Mode Terang/Gelap dari Pengaturan. Semua warna & teks berasal dari token PF dan PFText.', style: tx.caption),
                _title('Warna'),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final s in swatches)
                      SizedBox(
                        width: 100,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(height: 54, decoration: BoxDecoration(color: s.$2, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border))),
                          const SizedBox(height: 6),
                          Text(s.$1, style: tx.captionStrong.copyWith(fontSize: 12)),
                          Text(s.$3, style: tx.micro),
                        ]),
                      ),
                  ],
                ),
                _title('Tipografi (Inter)'),
                PFCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Display 32/Bold', style: tx.display),
                    const SizedBox(height: 8),
                    Text('H1 24/Bold', style: tx.h1),
                    const SizedBox(height: 8),
                    Text('H2 20/SemiBold', style: tx.h2),
                    const SizedBox(height: 8),
                    Text('H3 17/SemiBold', style: tx.h3),
                    const SizedBox(height: 8),
                    Text('Body 15/Regular', style: tx.body),
                    const SizedBox(height: 8),
                    Text('Caption 13/Regular', style: tx.caption),
                    const SizedBox(height: 8),
                    Text('Micro 11/Medium', style: tx.micro),
                  ]),
                ),
                _title('Ikon (stroke tipis, 24 pt)'),
                PFCard(
                  child: Wrap(spacing: 18, runSpacing: 16, children: [
                    for (final i in const [Icons.home_outlined, Icons.schedule_rounded, Icons.location_on_outlined, Icons.notifications_none_rounded, Icons.person_outline_rounded, Icons.pets_rounded, Icons.battery_charging_full_rounded, Icons.sensors_rounded, Icons.shield_outlined, Icons.tune_rounded, Icons.route_outlined, Icons.timer_outlined])
                      Icon(i, size: 24, color: p.primaryText),
                  ]),
                ),
                _title('Tombol'),
                PFCard(
                  child: Column(children: [
                    const PFButton(label: 'Primary (tekan untuk Pressed)', onPressed: _noop),
                    const SizedBox(height: 10),
                    const PFButton(label: 'Secondary', kind: PFButtonKind.secondary, onPressed: _noop),
                    const SizedBox(height: 10),
                    const PFButton(label: 'Ghost', kind: PFButtonKind.ghost, onPressed: _noop),
                    const SizedBox(height: 4),
                    const PFButton(label: 'Text link', kind: PFButtonKind.text, onPressed: _noop),
                    const SizedBox(height: 10),
                    const PFButton(label: 'Disabled'),
                    const SizedBox(height: 10),
                    const PFButton(label: 'Loading', loading: true),
                  ]),
                ),
                _title('Input'),
                PFCard(
                  child: Column(children: [
                    const PFTextField(label: 'Default', hint: 'Masukkan nama hewan'),
                    const SizedBox(height: 14),
                    PFTextField(label: 'Filled', controller: _filled),
                    const SizedBox(height: 14),
                    const PFTextField(label: 'Error', hint: 'Nama hewan', errorText: 'Nama hewan wajib diisi'),
                    const SizedBox(height: 14),
                    PFDateField(label: 'Date picker', value: _date, onChanged: (d) => setState(() => _date = d)),
                    const SizedBox(height: 4),
                    Align(alignment: Alignment.centerLeft, child: Text('Focus: ketuk salah satu kolom di atas.', style: tx.micro)),
                  ]),
                ),
                _title('Segmented, Toggle, Slider, Chip'),
                PFCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    PFSegmented(items: const ['Anjing', 'Kucing', 'Kelinci'], index: _seg, onChanged: (i) => setState(() => _seg = i)),
                    const SizedBox(height: 12),
                    PFSegmented(items: const ['Jantan', 'Betina'], index: _gender, onChanged: (i) => setState(() => _gender = i)),
                    const SizedBox(height: 14),
                    Row(children: [Expanded(child: Text('Notifikasi Keluar Area', style: tx.body)), PFSwitch(value: _toggle, onChanged: (v) => setState(() => _toggle = v))]),
                    PFSlider(value: _radius, min: 100, max: 2000, minLabel: '100 m', maxLabel: '2 km', onChanged: (v) => setState(() => _radius = v)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (var i = 0; i < 4; i++) PFChip(label: const ['Semua', 'Geofence', 'Sistem', 'Kesehatan'][i], selected: _chip == i, onTap: () => setState(() => _chip = i)),
                    ]),
                    const SizedBox(height: 16),
                    PageIndicator(count: 3, index: _page),
                    const SizedBox(height: 6),
                    Center(child: PFButton(label: 'Ganti halaman indikator', kind: PFButtonKind.text, expand: false, onPressed: () => setState(() => _page = (_page + 1) % 3))),
                  ]),
                ),
                _title('Kartu'),
                PetCard(pet: demoPet, onTap: () {}),
                const SizedBox(height: 12),
                NotificationCard(item: demoNtf, onTap: () {}),
                const SizedBox(height: 12),
                Row(children: const [
                  Expanded(child: StatCard(icon: Icons.route_outlined, value: '1,2 km', label: 'Jarak')),
                  SizedBox(width: 10),
                  Expanded(child: StatCard(icon: Icons.timer_outlined, value: '1,5 jam', label: 'Waktu Aktif')),
                  SizedBox(width: 10),
                  Expanded(child: StatCard(icon: Icons.local_fire_department_outlined, value: '120 kkal', label: 'Kalori')),
                ]),
                _title('Badge, Baterai, Pin peta'),
                PFCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      const ConnectionBadge(connection: 'online'),
                      const ConnectionBadge(connection: 'waiting'),
                      const ConnectionBadge(connection: 'offline'),
                      const ConnectionBadge(connection: 'unpaired'),
                      const BatteryBadge(percent: 92),
                      const BatteryBadge(percent: 18),
                      const BatteryBadge(percent: 8),
                    ]),
                    const SizedBox(height: 18),
                    Center(
                      child: SizedBox(width: 96, height: 96, child: Stack(alignment: Alignment.center, children: [const PulseRing(size: 96), PetAvatar(species: Species.kelinci, size: 46, ring: true, colorIndex: 2)])),
                    ),
                  ]),
                ),
                _title('Toast & Dialog'),
                PFCard(
                  child: Column(children: [
                    PFButton(label: 'Tampilkan Toast', kind: PFButtonKind.secondary, onPressed: () => showToast(context, 'Pengaturan geofence disimpan', kind: ToastKind.success)),
                    const SizedBox(height: 10),
                    PFButton(label: 'Dialog Konfirmasi', kind: PFButtonKind.ghost, onPressed: () => showConfirmDialog(context, title: 'Hapus hewan?', message: 'Profil hewan akan dihapus permanen.', confirmLabel: 'Hapus', danger: true)),
                    const SizedBox(height: 10),
                    const EmptyState(icon: Icons.pets_rounded, title: 'Empty state', message: 'Contoh tampilan saat belum ada data.'),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _noop() {}
