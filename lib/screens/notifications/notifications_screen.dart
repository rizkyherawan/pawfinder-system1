import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../widgets/cards.dart';
import '../../widgets/common.dart';
import '../../widgets/inputs.dart';
import '../history/health_screen.dart';
import '../tracking/device_detail_screen.dart';
import '../tracking/location_view_screen.dart';
import '../tracking/tracker_screen.dart';

/// Notifikasi: chip filter, daftar dikelompokkan per hari, geser untuk menghapus.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _cat = 'semua';
  static const _cats = [('semua', 'Semua'), ('geofence', 'Geofence'), ('hewan', 'Hewan'), ('sistem', 'Sistem'), ('kesehatan', 'Kesehatan')];

  void _open(AppState s, AppNotification n) {
    s.markRead(n.id);
    final pet = s.petById(n.petId);
    if (pet == null) return; // mis. hewan sudah dihapus: cukup ditandai dibaca
    s.selectPet(pet.id);
    switch (n.type) {
      case 'exit':
      case 'enter':
      case 'geofence_updated':
        pushPage(context, const LocationViewScreen());
        break;
      case 'battery':
      case 'gps_paired':
      case 'gps_connected':
      case 'gps_offline':
      case 'gps_unpaired':
        pushPage(context, const DeviceDetailScreen());
        break;
      case 'health_record':
        pushPage(context, const HealthScreen());
        break;
      default:
        pushPage(context, const TrackerScreen());
    }
  }

  void _menu(AppState s) {
    showPFSheet<void>(
      context,
      builder: (ctx) => TileGroup(children: [
        MenuTile(icon: Icons.done_all_rounded, label: 'Tandai semua dibaca', onTap: () {
          Navigator.of(ctx).pop();
          s.markAllRead();
          showToast(context, 'Semua notifikasi ditandai dibaca', kind: ToastKind.success);
        }),
        MenuTile(icon: Icons.delete_sweep_outlined, label: 'Hapus semua notifikasi', danger: true, onTap: () async {
          Navigator.of(ctx).pop();
          final ok = await showConfirmDialog(context, title: 'Hapus semua notifikasi?', message: 'Riwayat notifikasi akan dihapus dan tidak dapat dikembalikan.', confirmLabel: 'Hapus', danger: true);
          if (ok) s.clearNotifications();
        }),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final tx = context.tx;
    final list = s.notificationsBy(_cat);
    final now = wibNow();

    // Kelompokkan per hari (WIB).
    final groups = <String, List<AppNotification>>{};
    for (final n in list) {
      final w = wib(n.time);
      groups.putIfAbsent(dayHeader(w, now: now), () => []).add(n);
    }

    return Column(
      children: [
        PFTopBar(title: 'Notifikasi', onBack: () => s.setTab(0), onMore: () => _menu(s)),
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: PF.margin, vertical: 4),
            itemCount: _cats.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => PFChip(label: _cats[i].$2, selected: _cat == _cats[i].$1, onTap: () => setState(() => _cat = _cats[i].$1)),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: PF.primary,
            onRefresh: () => s.refresh(silent: true),
            child: list.isEmpty
                ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                    const SizedBox(height: 60),
                    EmptyState(icon: Icons.notifications_off_outlined, title: 'Belum ada notifikasi', message: _cat == 'semua' ? 'Kejadian seperti menambahkan hewan, memasangkan GPS, atau hewan keluar area aman akan muncul di sini.' : 'Tidak ada notifikasi pada kategori ini.'),
                  ])
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(PF.margin, 8, PF.margin, 28),
                    children: [
                      for (final e in groups.entries) ...[
                        Padding(padding: const EdgeInsets.only(top: 6, bottom: 10, left: 2), child: Text(e.key, style: tx.captionStrong)),
                        for (final n in e.value)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Dismissible(
                              key: ValueKey(n.id),
                              direction: DismissDirection.endToStart,
                              onDismissed: (_) {
                                s.deleteNotification(n.id);
                                showToast(context, 'Notifikasi dihapus');
                              },
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 22),
                                decoration: BoxDecoration(color: PF.danger, borderRadius: BorderRadius.circular(18)),
                                child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                              ),
                              child: NotificationCard(item: n, onTap: () => _open(s, n)),
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
