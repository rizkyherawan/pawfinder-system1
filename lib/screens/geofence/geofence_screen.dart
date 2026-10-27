import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/data_source.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../widgets/buttons.dart';
import '../../widgets/cards.dart';
import '../../widgets/common.dart';
import '../../widgets/inputs.dart';
import '../../widgets/map_view.dart';
import '../../widgets/pair_sheet.dart';
import '../../widgets/paw_map.dart';
import '../../widgets/pet_picker.dart';
import '../tracking/device_detail_screen.dart';

/// Geofencing: peta (skala nyata), koneksi kalung GPS, slider radius, toggle notifikasi, Simpan.
class GeofenceScreen extends StatefulWidget {
  const GeofenceScreen({super.key});

  @override
  State<GeofenceScreen> createState() => _GeofenceScreenState();
}

class _GeofenceScreenState extends State<GeofenceScreen> {
  final _map = PawMapController();
  String? _petId;
  Geofence? _fence; // salinan yang sedang diedit
  Geofence? _saved;
  double _initialRadius = 500; // dipakai hanya untuk zoom awal peta
  bool _loading = false, _saving = false;

  bool get _dirty {
    final a = _fence, b = _saved;
    return a != null && b != null && (a.radius != b.radius || a.notifyExit != b.notifyExit || a.notifyEnter != b.notifyEnter || a.center.lat != b.center.lat || a.center.lng != b.center.lng);
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _load(String petId) async {
    setState(() {
      _petId = petId;
      _loading = true;
      _fence = null;
    });
    try {
      final g = await context.read<AppState>().loadGeofence(petId);
      if (!mounted || _petId != petId) return;
      setState(() {
        _fence = g;
        _saved = g;
        _initialRadius = g.radius;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(context, errorText(e), kind: ToastKind.error);
    }
  }

  Future<void> _save() async {
    final g = _fence;
    if (g == null) return;
    setState(() => _saving = true);
    try {
      final saved = await context.read<AppState>().saveGeofence(g);
      if (!mounted) return;
      setState(() {
        _fence = saved;
        _saved = saved;
        _initialRadius = saved.radius;
        _saving = false;
      });
      showToast(context, 'Pengaturan geofence disimpan', kind: ToastKind.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, errorText(e), kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pet = s.selectedPet;
    final p = context.pf;
    final tx = context.tx;

    if (pet != null && pet.id != _petId && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(pet.id);
      });
    }

    return Column(
      children: [
        PFTopBar(title: 'Geofencing', onBack: () => s.setTab(0)),
        Expanded(
          child: pet == null
              ? Center(child: EmptyState(icon: Icons.location_off_outlined, title: 'Belum ada hewan', message: 'Tambahkan hewan peliharaan untuk mengatur area aman.', actionLabel: 'Ke Beranda', onAction: () => s.setTab(0)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(PF.margin, 4, PF.margin, 28),
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: SizedBox(
                        height: 270,
                        child: Stack(children: [
                          Positioned.fill(
                            child: _fence == null
                                ? Container(color: p.primaryLight, child: const Center(child: PFSpinner()))
                                : PawMap(
                                    key: ValueKey('${pet.id}-${s.settings.mapProvider}-${_saved?.center.lat}-${_saved?.center.lng}'),
                                    controller: _map,
                                    center: _fence!.center,
                                    fence: _fence,
                                    fitRadius: _initialRadius,
                                    onLongPress: (pt) {
                                      setState(() => _fence = _fence!.copyWith(center: pt));
                                      showToast(context, 'Pusat area dipindahkan. Ketuk Simpan untuk menerapkan.');
                                    },
                                    pins: [if (pet.location != null && pet.device.paired) PawPin(pet: pet, point: pet.location!, size: 64, compact: true)],
                                  ),
                          ),
                          Positioned(
                            left: 12,
                            top: 12,
                            right: 80,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: GestureDetector(
                                onTap: s.pets.length > 1 ? () => showPetPicker(context, s) : null,
                                child: MapChip(icon: Icons.home_outlined, label: '${_fence?.name ?? 'Rumah'} · ${pet.name}${s.pets.length > 1 ? '  ▾' : ''}'),
                              ),
                            ),
                          ),
                          Positioned(right: 12, top: 12, child: MapZoomControls(controller: _map, showLocate: false)),
                          Positioned(
                            left: 12,
                            bottom: 10,
                            child: DecoratedBox(
                              decoration: BoxDecoration(color: p.surface.o(0.9), borderRadius: BorderRadius.circular(10)),
                              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Text('Tekan lama peta untuk memindahkan pusat', style: tx.micro.copyWith(fontSize: 10))),
                            ),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _GpsCard(pet: pet),
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(child: Text('Radius Area', style: tx.h3)),
                      Text(fmtRadius(_fence?.radius ?? 500), style: tx.h3.copyWith(color: p.primaryText)),
                    ]),
                    const SizedBox(height: 4),
                    PFSlider(
                      value: _fence?.radius ?? 500,
                      min: 100,
                      max: 2000,
                      divisions: 38,
                      minLabel: '100 m',
                      maxLabel: '2 km',
                      // Selama digeser, lingkaran di peta langsung membesar/mengecil pada skala peta yang sama.
                      onChanged: _fence == null ? (_) {} : (v) => setState(() => _fence = _fence!.copyWith(radius: v.roundToDouble())),
                      onChangeEnd: _fence == null ? null : (v) => _map.ensureCircleVisible(_fence!.center, v),
                    ),
                    const SizedBox(height: 12),
                    PFCard(
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        SwitchTile(
                          title: 'Notifikasi Keluar Area',
                          subtitle: 'Terima peringatan saat ${pet.name} melewati batas area aman.',
                          child: PFSwitch(semanticLabel: 'Notifikasi keluar area', value: _fence?.notifyExit ?? true, onChanged: _fence == null ? null : (v) => setState(() => _fence = _fence!.copyWith(notifyExit: v))),
                        ),
                        Divider(height: 1, color: p.border),
                        SwitchTile(
                          title: 'Notifikasi Masuk Area',
                          subtitle: 'Kabari saat ${pet.name} kembali ke area aman.',
                          child: PFSwitch(semanticLabel: 'Notifikasi masuk area', value: _fence?.notifyEnter ?? true, onChanged: _fence == null ? null : (v) => setState(() => _fence = _fence!.copyWith(notifyEnter: v))),
                        ),
                      ]),
                    ),
                    if (pet.location != null) ...[
                      const SizedBox(height: 6),
                      Center(
                        child: PFButton(
                          label: 'Gunakan lokasi ${pet.name} sebagai pusat',
                          icon: Icons.my_location_rounded,
                          kind: PFButtonKind.text,
                          expand: false,
                          onPressed: _fence == null
                              ? null
                              : () {
                                  setState(() => _fence = _fence!.copyWith(center: pet.location));
                                  showToast(context, 'Pusat area dipindahkan. Ketuk Simpan untuk menerapkan.');
                                },
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    PFButton(label: _dirty ? 'Simpan' : 'Tersimpan', loading: _saving, onPressed: _dirty ? _save : null),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Koneksi kalung GPS di halaman Geofencing: status, pasangkan / putuskan.
class _GpsCard extends StatelessWidget {
  const _GpsCard({required this.pet});
  final Pet pet;

  Future<void> _disconnect(BuildContext context) async {
    final app = context.read<AppState>();
    final ok = await showConfirmDialog(context, title: 'Putuskan GPS?', message: '${pet.name} tidak akan dilacak sampai kalung dipasangkan kembali. Geofence juga berhenti memantau.', confirmLabel: 'Putuskan', danger: true, icon: Icons.link_off_rounded);
    if (!ok || !context.mounted) return;
    try {
      await app.unpairDevice(pet.id);
      if (context.mounted) showToast(context, 'GPS diputuskan');
    } catch (e) {
      if (context.mounted) showToast(context, errorText(e), kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final tx = context.tx;
    final d = pet.device;
    final info = switch (d.connection) {
      'online' => 'Kalung ${d.serial} aktif · baterai ${d.battery ?? '—'}% · sinyal ${d.signal ?? '—'}.',
      'waiting' => 'Kalung ${d.serial} dipasangkan. Menunggu sinyal pertama dari kalung…',
      'offline' => 'Tidak ada sinyal dari kalung ${d.serial}. Pastikan kalung menyala dan berada di area jaringan.',
      _ => 'Geofence baru memantau ${pet.name} setelah kalung GPS terhubung.',
    };
    final accent = d.online ? (p.isDark ? PF.success : p.successFg) : (d.waiting || d.offline ? PF.warning : p.textSecondary);
    return PFCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: accent.o(0.14), borderRadius: BorderRadius.circular(12)), child: Icon(d.paired ? Icons.sensors_rounded : Icons.link_off_rounded, color: accent, size: 22)),
          const SizedBox(width: 12),
          Expanded(child: Text('Koneksi Kalung GPS', style: tx.h3)),
          ConnectionBadge(connection: d.connection),
        ]),
        const SizedBox(height: 10),
        Text(info, style: tx.caption.copyWith(color: p.text)),
        const SizedBox(height: 14),
        Row(children: [
          if (!d.paired)
            Expanded(child: PFButton(label: 'Hubungkan GPS', icon: Icons.link_rounded, height: 48, onPressed: () => showPairSheet(context, pet)))
          else ...[
            Expanded(child: PFButton(label: 'Detail', icon: Icons.memory_rounded, kind: PFButtonKind.secondary, height: 48, pill: false, onPressed: () => pushPage(context, const DeviceDetailScreen()))),
            const SizedBox(width: 10),
            Expanded(child: PFButton(label: 'Putuskan', icon: Icons.link_off_rounded, kind: PFButtonKind.ghost, height: 48, pill: false, onPressed: () => _disconnect(context))),
          ],
        ]),
      ]),
    );
  }
}
