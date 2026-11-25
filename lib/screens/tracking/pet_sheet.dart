import 'package:flutter/material.dart';

import '../../core/geo.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../../widgets/pet_face.dart';

/// Bottom sheet detail hewan di atas peta (slide-up saat muncul).
/// Isinya mengikuti status koneksi GPS: belum terhubung, menunggu sinyal, offline, atau online.
class PetSheet extends StatelessWidget {
  const PetSheet({
    super.key,
    required this.pet,
    required this.locationLabel,
    required this.locationIcon,
    required this.onLocation,
    required this.onConnect,
    this.onBatteryTap,
    this.fence,
  });

  final Pet pet;
  final String locationLabel;
  final IconData locationIcon;
  final VoidCallback onLocation, onConnect;
  final VoidCallback? onBatteryTap;
  final Geofence? fence;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final tx = context.tx;
    final d = pet.device;
    final hasLoc = pet.location != null;

    Widget status;
    Widget action;
    switch (d.connection) {
      case 'online':
        if (!hasLoc) {
          // Alat hidup dan mengirim data, tetapi belum ada lokasi (mis. GPS di dalam ruangan): jangan mengaku "di dalam area aman".
          status = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            PFBadge(label: 'Terhubung · mencari satelit GPS', color: PF.warning, background: p.warningBg, icon: Icons.satellite_alt_outlined),
            const SizedBox(height: 10),
            Text('Kalung aktif (${d.sourceLabel}), tetapi belum mendapat lokasi dari satelit. Bawa ke luar ruangan dengan langit terbuka; lokasi tampil otomatis.', style: tx.caption.copyWith(color: p.text)),
          ]);
          action = PFButton(label: 'Periksa Koneksi Alat', kind: PFButtonKind.secondary, onPressed: onConnect);
          break;
        }
        final dist = (hasLoc && fence != null) ? distanceMeters(fence!.center, pet.location!) : null;
        status = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          pet.isOutside
              ? const PFBadge(label: 'Di luar area aman', color: PF.danger, background: Color(0x1FEF4444), icon: Icons.gpp_maybe_outlined)
              : PFBadge(label: 'Di dalam area aman (${pet.geofenceName})', color: p.successFg, background: p.successBg, icon: Icons.verified_user_outlined),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.place_outlined, size: 16, color: p.textSecondary),
            const SizedBox(width: 6),
            Expanded(child: Text(pet.address.isEmpty ? 'Alamat belum tersedia' : pet.address, style: tx.caption.copyWith(color: p.text), maxLines: 2, overflow: TextOverflow.ellipsis)),
          ]),
          if (dist != null) ...[
            const SizedBox(height: 4),
            Padding(padding: const EdgeInsets.only(left: 22), child: Text('Berjarak ${fmtRadius(dist)} dari ${fence!.name}', style: tx.micro)),
          ],
          if (d.searchingSatellites) ...[
            const SizedBox(height: 4),
            Padding(padding: const EdgeInsets.only(left: 22), child: Text('GPS sedang mencari satelit; ini posisi terakhir yang diterima.', style: tx.micro.copyWith(color: PF.warning))),
          ],
        ]);
        action = PFButton(label: locationLabel, icon: locationIcon, onPressed: onLocation);
        break;
      case 'waiting':
        status = Row(children: [
          const PFSpinner(size: 18),
          const SizedBox(width: 12),
          Expanded(child: Text('Menunggu sinyal pertama dari kalung ${d.serial ?? ''}. Status akan hijau setelah kalung mengirim lokasi.', style: tx.caption.copyWith(color: p.text))),
        ]);
        action = PFButton(label: 'Menunggu sinyal…', loading: true, onPressed: null);
        break;
      case 'offline':
        status = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PFBadge(label: 'Sinyal GPS terputus', color: PF.warning, background: p.warningBg, icon: Icons.signal_wifi_off_rounded),
          const SizedBox(height: 10),
          Text(hasLoc ? 'Lokasi terakhir (${updatedAgo(pet.locationUpdatedAt)}): ${pet.address}' : 'Belum ada lokasi yang tercatat.', style: tx.caption.copyWith(color: p.text), maxLines: 2, overflow: TextOverflow.ellipsis),
        ]);
        action = hasLoc ? PFButton(label: 'Lihat Lokasi Terakhir', icon: Icons.history_toggle_off_rounded, kind: PFButtonKind.secondary, onPressed: onLocation) : PFButton(label: 'Periksa Koneksi GPS', kind: PFButtonKind.secondary, onPressed: onConnect);
        break;
      default:
        status = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PFBadge(label: 'GPS belum terhubung', color: p.textSecondary, background: p.primaryLight, icon: Icons.link_off_rounded),
          const SizedBox(height: 10),
          Text('Hubungkan kalung GPS agar lokasi ${pet.name} tampil di peta dan geofence mulai aktif.', style: tx.caption.copyWith(color: p.text)),
        ]);
        action = PFButton(label: 'Hubungkan GPS', icon: Icons.link_rounded, onPressed: onConnect);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 1, end: 0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Transform.translate(offset: Offset(0, 320 * t), child: Opacity(opacity: 1 - t * 0.6, child: child)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: p.shadow, blurRadius: 30, offset: const Offset(0, -4))]),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: p.border, borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 14),
            Row(children: [
              PetFace(pet: pet, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(pet.name, style: tx.h3.copyWith(fontSize: 18)),
                  Text(pet.subtitle, style: tx.caption),
                ]),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onBatteryTap,
                child: Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4), child: BatteryBadge(percent: d.battery)),
              ),
            ]),
            const SizedBox(height: 12),
            status,
            const SizedBox(height: 14),
            action,
          ],
        ),
      ),
    );
  }
}
