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
import '../../widgets/pressable.dart';
import 'activity_screen.dart';
import 'health_screen.dart';

const kEventCategories = [('semua', 'Semua'), ('geofence', 'Geofence'), ('hewan', 'Hewan'), ('sistem', 'Sistem'), ('kesehatan', 'Kesehatan')];

/// Riwayat: log kejadian yang SAMA dengan Notifikasi, dikelompokkan per tanggal.
/// Aktivitas dan Kesehatan adalah fitur terpisah (tombol pintasan di bagian atas).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String? _petFilter; // null = semua hewan
  String _cat = 'semua';
  late DateTime _date = _today();
  List<TimelineEvent> _events = const [];
  bool _loading = true;
  String? _error;
  String _loadedKey = '';

  DateTime _today() {
    final w = wibNow();
    return DateTime(w.year, w.month, w.day);
  }

  Future<void> _load(AppState s, String key) async {
    if (!mounted) return;
    setState(() {
      _loading = _events.isEmpty;
      _error = null;
    });
    try {
      final list = await s.history(_date, petId: _petFilter, category: _cat);
      if (!mounted || _loadedKey != key) return;
      setState(() {
        _events = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || _loadedKey != key) return;
      setState(() {
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  Future<void> _pickDate() async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today,
      helpText: 'Pilih tanggal riwayat',
      cancelText: 'Batal',
      confirmText: 'Pilih',
      builder: (ctx, child) => Theme(data: Theme.of(ctx).copyWith(colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: PF.primary)), child: child ?? const SizedBox.shrink()),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pf;
    final tx = context.tx;

    // Hewan yang sudah dihapus tidak boleh tetap menjadi filter.
    if (_petFilter != null && s.petById(_petFilter!) == null) _petFilter = null;
    final key = '$_petFilter|$_cat|${dateKey(_date)}|${s.notifications.length}|${s.pets.length}';
    if (key != _loadedKey) {
      _loadedKey = key;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(s, key));
    }
    final sel = s.selectedPet;

    return Column(
      children: [
        PFTopBar(title: 'Riwayat', onBack: () => s.setTab(0)),
        Expanded(
          child: RefreshIndicator(
            color: PF.primary,
            onRefresh: () async => _load(s, key),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(PF.margin, 4, PF.margin, 28),
              children: [
                if (sel != null) ...[
                  Row(children: [
                    Expanded(child: PFButton(label: 'Aktivitas', icon: Icons.directions_walk_rounded, kind: PFButtonKind.secondary, pill: false, height: 48, onPressed: () => pushPage(context, const ActivityScreen()))),
                    const SizedBox(width: 10),
                    Expanded(child: PFButton(label: 'Kesehatan', icon: Icons.favorite_border_rounded, kind: PFButtonKind.secondary, pill: false, height: 48, onPressed: () => pushPage(context, const HealthScreen()))),
                  ]),
                  const SizedBox(height: 16),
                ],
                if (s.pets.length > 1) ...[
                  SizedBox(
                    height: 46,
                    child: ListView(scrollDirection: Axis.horizontal, children: [
                      PFChip(label: 'Semua hewan', selected: _petFilter == null, onTap: () => setState(() => _petFilter = null)),
                      for (final pet in s.pets) ...[const SizedBox(width: 8), PFChip(label: pet.name, selected: _petFilter == pet.id, onTap: () => setState(() => _petFilter = pet.id))],
                    ]),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  height: 46,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: kEventCategories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => PFChip(label: kEventCategories[i].$2, selected: _cat == kEventCategories[i].$1, onTap: () => setState(() => _cat = kEventCategories[i].$1)),
                  ),
                ),
                const SizedBox(height: 10),
                Pressable(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Expanded(child: Text(dayHeader(_date), style: tx.captionStrong)),
                      Icon(Icons.calendar_month_outlined, size: 20, color: p.primaryText),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                if (_loading)
                  const Column(children: [Skeleton(height: 64), SizedBox(height: 12), Skeleton(height: 64), SizedBox(height: 12), Skeleton(height: 64)])
                else if (_error != null)
                  EmptyState(icon: Icons.cloud_off_rounded, title: 'Gagal memuat', message: _error, actionLabel: 'Coba Lagi', onAction: () => _load(s, key))
                else if (_events.isEmpty)
                  EmptyState(icon: Icons.history_rounded, title: 'Belum ada riwayat', message: s.pets.isEmpty ? 'Riwayat akan muncul setelah kamu menambahkan hewan peliharaan dan mulai memakai fitur PawFinder.' : 'Tidak ada kejadian pada tanggal dan filter ini.')
                else ...[
                  PFCard(padding: const EdgeInsets.all(18), child: TimelineList(events: _events)),
                  const SizedBox(height: 16),
                  Center(child: Text('Isi riwayat sama dengan notifikasi · Semua waktu menggunakan WIB.', textAlign: TextAlign.center, style: tx.micro)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
