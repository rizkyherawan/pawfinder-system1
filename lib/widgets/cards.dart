import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../data/models.dart';
import 'common.dart';
import 'pet_face.dart';
import 'buttons.dart';
import 'pressable.dart';

/// Gaya ikon per tipe kejadian: (ikon, warna ikon, warna latar). Dipakai bersama oleh Riwayat dan Notifikasi.
(IconData, Color, Color) eventStyle(BuildContext context, String type) {
  final p = context.pf;
  final green = p.isDark ? PF.success : p.successFg;
  switch (type) {
    case 'exit':
      return (Icons.gpp_maybe_outlined, PF.danger, p.dangerBg);
    case 'enter':
      return (Icons.verified_user_outlined, green, p.successBg);
    case 'battery':
      return (Icons.battery_alert_rounded, PF.warning, p.warningBg);
    case 'pet_added':
      return (Icons.pets_rounded, p.primaryText, p.primaryLight);
    case 'pet_updated':
      return (Icons.edit_outlined, p.primaryText, p.primaryLight);
    case 'pet_deleted':
      return (Icons.delete_outline_rounded, PF.danger, p.dangerBg);
    case 'gps_paired':
      return (Icons.link_rounded, p.primaryText, p.primaryLight);
    case 'gps_connected':
      return (Icons.sensors_rounded, green, p.successBg);
    case 'gps_offline':
      return (Icons.signal_wifi_off_rounded, PF.danger, p.dangerBg);
    case 'gps_unpaired':
      return (Icons.link_off_rounded, p.textSecondary, p.primaryLight);
    case 'geofence_updated':
      return (Icons.adjust_rounded, p.primaryText, p.primaryLight);
    case 'health_record':
      return (Icons.favorite_border_rounded, PF.accent, p.accentBg);
    default:
      return (Icons.notifications_none_rounded, p.textSecondary, p.primaryLight);
  }
}

class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, required this.color, required this.background, this.size = 44});
  final IconData icon;
  final Color color, background;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(size * 0.3)),
        child: Icon(icon, size: size * 0.5, color: color),
      );
}

/// Kartu hewan: foto/avatar, nama, jenis, umur, status koneksi GPS, baterai, dan menu (edit/hapus).
class PetCard extends StatelessWidget {
  const PetCard({super.key, required this.pet, required this.onTap, this.onMenu});
  final Pet pet;
  final VoidCallback onTap;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final tx = context.tx;
    final p = context.pf;
    final d = pet.device;
    return Semantics(
      button: true,
      label: '${pet.name}, ${pet.subtitle}, ${d.statusLabel}',
      child: PFCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
        child: Column(
          children: [
            Row(children: [
              PetFace(pet: pet, size: 58),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(pet.name, style: tx.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(pet.subtitle, style: tx.caption),
                ]),
              ),
              if (onMenu != null)
                PFIconButton(icon: Icons.more_vert_rounded, label: 'Menu ${pet.name}', border: false, background: Colors.transparent, color: p.textSecondary, onTap: onMenu)
              else
                Padding(padding: const EdgeInsets.only(right: 8), child: Icon(Icons.chevron_right_rounded, color: p.textSecondary)),
            ]),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                ConnectionBadge(connection: d.connection),
                BatteryBadge(percent: d.battery),
                Text(d.linkText, style: tx.micro),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kartu notifikasi: ikon berwarna per tipe, judul, lokasi/waktu, chevron.
class NotificationCard extends StatelessWidget {
  const NotificationCard({super.key, required this.item, required this.onTap});
  final AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tx = context.tx;
    final p = context.pf;
    final (icon, fg, bg) = eventStyle(context, item.type);
    return PFCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      radius: 18,
      child: Row(children: [
        IconTile(icon: icon, color: fg, background: bg),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(item.title, style: tx.captionStrong.copyWith(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (!item.read) ...[const SizedBox(width: 6), Container(width: 7, height: 7, decoration: const BoxDecoration(color: PF.primary, shape: BoxShape.circle))],
            ]),
            const SizedBox(height: 3),
            Text(item.subtitle, style: tx.micro.copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('${fmtTime(item.time)} WIB', style: tx.micro.copyWith(fontSize: 12)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: p.textSecondary, size: 22),
      ]),
    );
  }
}

/// Kartu statistik kecil (Jarak, Waktu Aktif, Kalori).
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.icon, required this.value, required this.label, this.color});
  final IconData icon;
  final String value, label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tx = context.tx;
    return PFCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      radius: 18,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 22, color: color ?? context.pf.primaryText),
        const SizedBox(height: 12),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: tx.h3.copyWith(fontWeight: FontWeight.w700))),
        const SizedBox(height: 2),
        Text(label, style: tx.caption),
      ]),
    );
  }
}

/// Baris menu dengan ikon, label, dan chevron.
class MenuTile extends StatelessWidget {
  const MenuTile({super.key, required this.icon, required this.label, this.subtitle, this.onTap, this.danger = false, this.trailing, this.value});
  final IconData icon;
  final String label;
  final String? subtitle, value;
  final VoidCallback? onTap;
  final bool danger;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final tx = context.tx;
    final color = danger ? PF.danger : p.primaryText;
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          IconTile(icon: icon, color: color, background: danger ? p.dangerBg : p.primaryLight, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: tx.body.copyWith(color: danger ? PF.danger : p.text, fontWeight: FontWeight.w500)),
              if (subtitle != null) Text(subtitle!, style: tx.micro.copyWith(fontSize: 12)),
            ]),
          ),
          if (value != null) Padding(padding: const EdgeInsets.only(right: 4), child: Text(value!, style: tx.caption)),
          trailing ?? Icon(Icons.chevron_right_rounded, color: p.textSecondary),
        ]),
      ),
    );
  }
}

/// Kartu yang mengelompokkan beberapa tile dengan pemisah tipis.
class TileGroup extends StatelessWidget {
  const TileGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i != children.length - 1) items.add(Divider(height: 1, thickness: 1, indent: 68, color: p.border.o(0.7)));
    }
    return PFCard(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: items));
  }
}

/// Baris pengaturan dengan toggle.
class SwitchTile extends StatelessWidget {
  const SwitchTile({super.key, required this.title, required this.subtitle, required this.child});
  final String title, subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tx = context.tx;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: tx.body), const SizedBox(height: 2), Text(subtitle, style: tx.micro.copyWith(fontSize: 12))])),
        child,
      ]),
    );
  }
}

/// Timeline kronologis (Riwayat Aktivitas).
class TimelineList extends StatelessWidget {
  const TimelineList({super.key, required this.events});
  final List<TimelineEvent> events;

  @override
  Widget build(BuildContext context) {
    final tx = context.tx;
    final p = context.pf;
    return Column(
      children: List.generate(events.length, (i) {
        final e = events[i];
        final (icon, fg, bg) = eventStyle(context, e.type);
        final last = i == events.length - 1;
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 44,
              child: Column(children: [
                IconTile(icon: icon, color: fg, background: bg, size: 44),
                if (!last) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 4), color: p.border)),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: last ? 0 : 20, top: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.title, style: tx.captionStrong.copyWith(fontSize: 14)),
                      const SizedBox(height: 3),
                      Text(e.subtitle, style: tx.micro.copyWith(fontSize: 12)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Text(fmtTime(e.time), style: tx.micro.copyWith(fontSize: 12)),
                ]),
              ),
            ),
          ]),
        );
      }),
    );
  }
}
