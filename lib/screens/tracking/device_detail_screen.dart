import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/data_source.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../../widgets/inputs.dart';
import '../../widgets/pair_sheet.dart';
import '../../widgets/pet_art.dart';
import '../../widgets/pet_face.dart';
import '../../widgets/pressable.dart';

/// Batang sinyal GPS (0-4 batang).
class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.signal});
  final String? signal;

  @override
  Widget build(BuildContext context) {
    final level = switch (signal) { 'Kuat' => 4, 'Sedang' => 2, 'Lemah' => 1, _ => 0 };
    final p = context.pf;
    return SizedBox(
      width: 22,
      height: 18,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(4, (i) => Container(width: 4, height: 5.0 + i * 4, decoration: BoxDecoration(color: i < level ? p.primaryText : p.border, borderRadius: BorderRadius.circular(1.5)))),
      ),
    );
  }
}

class DeviceDetailScreen extends StatelessWidget {
  const DeviceDetailScreen({super.key});

  void _settings(BuildContext context, Pet pet) {
    final app = context.read<AppState>();
    const options = [10, 30, 60, 300];
    const labels = ['10 dtk', '30 dtk', '1 mnt', '5 mnt'];
    showPFSheet<void>(
      context,
      title: 'Pengaturan Perangkat',
      builder: (ctx) => Consumer<AppState>(builder: (ctx, s, _) {
        final cur = s.petById(pet.id)?.device.intervalSec ?? 30;
        final idx = options.indexOf(cur).clamp(0, 3).toInt();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Interval pembaruan GPS', style: ctx.tx.bodyStrong),
          const SizedBox(height: 4),
          Text('Interval lebih pendek memberi lokasi lebih akurat, tetapi baterai kalung lebih cepat habis.', style: ctx.tx.caption),
          const SizedBox(height: 14),
          PFSegmented(
            items: labels,
            index: idx,
            onChanged: (i) async {
              try {
                await app.setDeviceInterval(pet.id, options[i]);
              } catch (e) {
                if (ctx.mounted) showToast(ctx, errorText(e), kind: ToastKind.error);
              }
            },
          ),
          if (pet.device.online) ...[
            const SizedBox(height: 20),
            PFButton(
              label: 'Bunyikan Kalung',
              icon: Icons.volume_up_outlined,
              kind: PFButtonKind.secondary,
              onPressed: () async {
                try {
                  final msg = await app.pingDevice(pet.id);
                  if (ctx.mounted) showToast(ctx, msg, kind: ToastKind.success);
                } catch (e) {
                  if (ctx.mounted) showToast(ctx, errorText(e), kind: ToastKind.error);
                }
              },
            ),
          ],
        ]);
      }),
    );
  }

  Future<void> _unpair(BuildContext context, Pet pet) async {
    final app = context.read<AppState>();
    final ok = await showConfirmDialog(
      context,
      title: 'Putuskan GPS?',
      message: '${pet.name} tidak akan dilacak sampai kalung dipasangkan kembali. Geofence juga berhenti memantau.',
      confirmLabel: 'Putuskan',
      danger: true,
      icon: Icons.link_off_rounded,
    );
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
    final s = context.watch<AppState>();
    final pet = s.selectedPet;
    final p = context.pf;
    final tx = context.tx;
    if (pet == null) return const Scaffold(body: Column(children: [PFTopBar(title: 'Detail Perangkat'), Expanded(child: Center(child: Text('Belum ada hewan.')))]));
    final d = pet.device;
    final street = pet.address.split(',').take(2).join(',').trim();
    final subtitle = switch (d.connection) {
      'online' => 'Terhubung via IoT · ${updatedAgo(d.lastSeen)}',
      'waiting' => 'Menunggu sinyal pertama dari kalung',
      'offline' => 'Terakhir terlihat ${updatedAgo(d.lastSeen).toLowerCase()}',
      _ => 'Kalung belum dipasangkan',
    };
    return Scaffold(
      body: Column(
        children: [
          const PFTopBar(title: 'Detail Perangkat'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(PF.margin, 8, PF.margin, 24),
              children: [
                Container(
                  height: 190,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: p.isDark ? const [Color(0xFF1C3566), Color(0xFF14264F)] : const [Color(0xFFE3EEFD), Color(0xFFC6DAF5)]),
                  ),
                  child: Stack(alignment: Alignment.center, children: [
                    Opacity(opacity: d.paired ? 1 : 0.55, child: const CollarArt(height: 150)),
                    Positioned(right: 16, top: 16, child: PetFace(pet: pet, size: 52, ring: d.online)),
                  ]),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(child: Text('Kalung GPS ${pet.name}', style: tx.h1.copyWith(fontSize: 22))),
                  ConnectionBadge(connection: d.connection),
                ]),
                const SizedBox(height: 4),
                Text(subtitle, style: tx.caption),
                const SizedBox(height: 18),
                if (!d.paired) ...[
                  PFCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [Icon(Icons.link_off_rounded, color: p.textSecondary), const SizedBox(width: 10), Text('GPS belum terhubung', style: tx.h3)]),
                      const SizedBox(height: 8),
                      Text('Status baru menjadi aktif (hijau) setelah kalung dipasangkan dan benar-benar mengirim sinyal. Siapkan nomor seri yang tertera pada kalung.', style: tx.bodySecondary.copyWith(fontSize: 14)),
                      const SizedBox(height: 16),
                      PFButton(label: 'Hubungkan GPS', icon: Icons.link_rounded, onPressed: () => showPairSheet(context, pet)),
                    ]),
                  ),
                ] else ...[
                  PFCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _Row(icon: Icon(Icons.battery_charging_full_rounded, size: 22, color: p.textSecondary), label: 'Baterai', value: d.battery == null ? '—' : '${d.battery}%', valueColor: batteryColor(context, d.battery)),
                      const SizedBox(height: 14),
                      _Row(icon: SignalBars(signal: d.signal), label: 'Sinyal GPS', value: d.signal ?? '—', valueColor: p.primaryText),
                      const SizedBox(height: 14),
                      Divider(height: 1, color: p.border),
                      const SizedBox(height: 12),
                      Text(pet.location == null ? 'Lokasi terakhir · belum ada' : 'Lokasi terakhir · ${street.isEmpty ? '-' : street}', style: tx.caption),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  PFCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(children: [
                      _KV(label: 'Firmware', value: d.firmware),
                      const SizedBox(height: 14),
                      Pressable(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: d.serial ?? ''));
                          showToast(context, 'Nomor seri disalin', kind: ToastKind.success);
                        },
                        child: _KV(label: 'Serial No.', value: d.serial ?? '—', trailing: Icon(Icons.copy_rounded, size: 14, color: p.textSecondary)),
                      ),
                      const SizedBox(height: 14),
                      _KV(label: 'Interval GPS', value: d.intervalSec >= 60 ? '${d.intervalSec ~/ 60} menit' : '${d.intervalSec} detik'),
                    ]),
                  ),
                  const SizedBox(height: 22),
                  PFButton(label: 'Pengaturan', icon: Icons.tune_rounded, kind: PFButtonKind.secondary, pill: false, onPressed: () => _settings(context, pet)),
                  const SizedBox(height: 6),
                  PFButton(label: 'Putuskan GPS', icon: Icons.link_off_rounded, kind: PFButtonKind.text, onPressed: () => _unpair(context, pet)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value, required this.valueColor});
  final Widget icon;
  final String label, value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final tx = context.tx;
    return Row(children: [
      SizedBox(width: 24, child: Center(child: icon)),
      const SizedBox(width: 12),
      Expanded(child: Text(label, style: tx.body)),
      Text(value, style: tx.bodyStrong.copyWith(color: valueColor)),
    ]);
  }
}

class _KV extends StatelessWidget {
  const _KV({required this.label, required this.value, this.trailing});
  final String label, value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tx = context.tx;
    return Row(children: [
      Expanded(child: Text(label, style: tx.caption)),
      if (trailing != null) ...[trailing!, const SizedBox(width: 6)],
      Text(value, style: tx.captionStrong.copyWith(fontSize: 14)),
    ]);
  }
}
