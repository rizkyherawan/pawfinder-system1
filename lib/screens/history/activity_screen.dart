import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/data_source.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../widgets/cards.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/pair_sheet.dart';
import '../../widgets/pet_face.dart';
import '../../widgets/pet_picker.dart';
import '../../widgets/pressable.dart';

/// AKTIVITAS (fitur tersendiri): langkah, jarak, waktu aktif, kalori, dan tren 7 hari.
/// Datanya dihitung dari lokasi nyata yang dikirim kalung GPS, bukan data contoh.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  ActivitySummary? _a;
  String? _error;
  String? _loadedFor;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      final s = context.read<AppState>();
      final pet = s.selectedPet;
      if (mounted && pet != null && pet.device.online) _load(s, pet.id, silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load(AppState s, String petId, {bool silent = false}) async {
    if (!silent) setState(() => _error = null);
    try {
      final a = await s.activity(petId);
      if (mounted && s.selectedPet?.id == petId) setState(() => _a = a);
    } catch (e) {
      if (mounted && !silent) setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pet = s.selectedPet;
    final tx = context.tx;
    final p = context.pf;
    if (pet != null && _loadedFor != pet.id) {
      _loadedFor = pet.id;
      _a = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(s, pet.id));
    }
    return Scaffold(
      body: Column(
        children: [
          const PFTopBar(title: 'Aktivitas'),
          Expanded(
            child: pet == null
                ? const Center(child: Text('Belum ada hewan.'))
                : RefreshIndicator(
                    color: PF.primary,
                    onRefresh: () => _load(s, pet.id),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(PF.margin, 4, PF.margin, 28),
                      children: [
                        Pressable(
                          onTap: s.pets.length > 1 ? () => showPetPicker(context, s) : null,
                          child: Row(children: [
                            PetFace(pet: pet, size: 48),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(pet.name, style: tx.h3),
                                Text('${pet.species.label} · ${dayHeader(wibNow())}', style: tx.caption),
                              ]),
                            ),
                            ConnectionBadge(connection: pet.device.connection),
                            if (s.pets.length > 1) Icon(Icons.keyboard_arrow_down_rounded, color: p.textSecondary),
                          ]),
                        ),
                        const SizedBox(height: 16),
                        if (_error != null)
                          EmptyState(icon: Icons.cloud_off_rounded, title: 'Gagal memuat data', message: _error, actionLabel: 'Coba Lagi', onAction: () => _load(s, pet.id))
                        else if (!pet.device.paired)
                          EmptyState(
                            icon: Icons.link_off_rounded,
                            title: 'GPS belum terhubung',
                            message: 'Aktivitas dihitung dari pergerakan nyata ${pet.name}. Hubungkan kalung GPS untuk mulai merekam langkah, jarak, dan waktu aktif.',
                            actionLabel: 'Hubungkan GPS',
                            onAction: () => showPairSheet(context, pet),
                          )
                        else if (_a == null)
                          const Column(children: [Skeleton(height: 120, radius: 20), SizedBox(height: 12), Skeleton(height: 96, radius: 20), SizedBox(height: 12), Skeleton(height: 220, radius: 20)])
                        else
                          ..._content(context, pet, _a!),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context, Pet pet, ActivitySummary a) {
    final tx = context.tx;
    final p = context.pf;
    return [
      if (!pet.device.online)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: PFBadge(label: pet.device.waiting ? 'Menunggu sinyal pertama dari kalung' : 'GPS terputus · data terakhir ditampilkan', color: PF.warning, background: p.warningBg, icon: Icons.info_outline_rounded),
        ),
      PFCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Langkah hari ini', style: tx.caption),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: Text('${fmtInt(a.steps)} langkah', style: tx.display.copyWith(fontSize: 30))),
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${a.percent}%', style: tx.captionStrong.copyWith(color: p.primaryText))),
          ]),
          const SizedBox(height: 12),
          PFProgress(value: a.progress),
          const SizedBox(height: 10),
          Text('Target harian ${fmtInt(a.goal)} langkah', style: tx.micro),
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: StatCard(icon: Icons.route_outlined, value: '${fmtDecimal(a.distanceKm)} km', label: 'Jarak')),
        const SizedBox(width: 10),
        Expanded(child: StatCard(icon: Icons.timer_outlined, value: a.activeText, label: 'Waktu Aktif')),
        const SizedBox(width: 10),
        Expanded(child: StatCard(icon: Icons.local_fire_department_outlined, value: '${a.calories} kkal', label: 'Kalori')),
      ]),
      const SizedBox(height: 12),
      PFCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Aktivitas 7 Hari Terakhir', style: tx.h3),
          const SizedBox(height: 6),
          Row(children: [
            Container(width: 7, height: 7, decoration: const BoxDecoration(color: PF.primary, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('Waktu aktif · menit per hari', style: tx.micro),
          ]),
          const SizedBox(height: 16),
          WeekBarChart(days: a.week),
        ]),
      ),
    ];
  }
}
