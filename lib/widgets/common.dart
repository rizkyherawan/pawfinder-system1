import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'buttons.dart';
import 'pressable.dart';

// ---------------------------------------------------------------------------
// Logo & glyph pin
// ---------------------------------------------------------------------------

/// Path pin lokasi (teardrop) di dalam [r].
Path pinPath(Rect r) {
  final w = r.width, h = r.height, cx = r.left + w / 2, rad = w / 2;
  final p = Path()..moveTo(cx, r.bottom);
  p.cubicTo(cx - w * 0.16, r.bottom - h * 0.2, r.left, r.top + h * 0.6, r.left, r.top + rad);
  p.arcToPoint(Offset(r.right, r.top + rad), radius: Radius.circular(rad), clockwise: true);
  p.cubicTo(r.right, r.top + h * 0.6, cx + w * 0.16, r.bottom - h * 0.2, cx, r.bottom);
  p.close();
  return p;
}

class _PinGlyphPainter extends CustomPainter {
  _PinGlyphPainter(this.color, this.stroke);
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round;
    final r = Rect.fromLTWH(s.width * 0.2, s.height * 0.1, s.width * 0.6, s.height * 0.8);
    canvas.drawPath(pinPath(r), paint);
    canvas.drawCircle(Offset(s.width / 2, r.top + r.width / 2), s.width * 0.1, paint);
  }

  @override
  bool shouldRepaint(covariant _PinGlyphPainter old) => old.color != color || old.stroke != stroke;
}

/// Pin garis (seperti pada logo PawFinder).
class PinGlyph extends StatelessWidget {
  const PinGlyph({super.key, this.size = 24, this.color = Colors.white, this.stroke});
  final double size;
  final Color color;
  final double? stroke;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _PinGlyphPainter(color, stroke ?? size * 0.075));
}

class PFLogo extends StatelessWidget {
  const PFLogo({super.key, this.size = 36, this.showText = true, this.textStyle});
  final double size;
  final bool showText;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2F7BFF), PF.primaryDark]),
        boxShadow: [BoxShadow(color: PF.primary.o(0.30), blurRadius: size * 0.4, offset: Offset(0, size * 0.18))],
      ),
      child: Center(child: PinGlyph(size: size * 0.78)),
    );
    if (!showText) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: size * 0.3),
        Text('PawFinder', style: textStyle ?? context.tx.h2.copyWith(fontSize: size * 0.56, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Surface, kartu, badge
// ---------------------------------------------------------------------------

class PFCard extends StatelessWidget {
  const PFCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color, this.radius = PF.rCard, this.shadow = true, this.border = false, this.glass = false});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;
  final bool shadow, border, glass;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final br = BorderRadius.circular(radius);
    Widget body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: glass ? p.surface.o(0.7) : (color ?? p.surface),
        borderRadius: br,
        border: border ? Border.all(color: p.border) : null,
        boxShadow: shadow ? softShadow(p) : null,
      ),
      child: child,
    );
    if (glass) {
      body = ClipRRect(borderRadius: br, child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), child: body));
    }
    return onTap == null ? body : Pressable(onTap: onTap, scale: 0.985, child: body);
  }
}

class PFBadge extends StatelessWidget {
  const PFBadge({super.key, required this.label, required this.color, required this.background, this.dot = false, this.icon});
  final String label;
  final Color color, background;
  final bool dot;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(PF.rChip)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 6)],
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 5)],
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color))),
        ],
      ),
    );
  }
}

/// Badge status koneksi GPS: Belum terhubung · Menghubungkan · Online (hijau) · Offline.
class ConnectionBadge extends StatelessWidget {
  const ConnectionBadge({super.key, required this.connection});
  final String connection; // unpaired | waiting | online | offline

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    switch (connection) {
      case 'online':
        return PFBadge(label: 'Online', color: p.successFg, background: p.successBg, dot: true);
      case 'waiting':
        return PFBadge(label: 'Menghubungkan', color: PF.warning, background: p.warningBg, dot: true);
      case 'offline':
        return PFBadge(label: 'Offline', color: p.textSecondary, background: p.primaryLight, dot: true);
      default:
        return PFBadge(label: 'Belum terhubung', color: p.textSecondary, background: p.primaryLight, icon: Icons.link_off_rounded);
    }
  }
}

class _BatteryPainter extends CustomPainter {
  _BatteryPainter(this.percent, this.color, this.outline);
  final int percent;
  final Color color, outline;

  @override
  void paint(Canvas canvas, Size s) {
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(0.8, 0.8, s.width - 4.2, s.height - 1.6), const Radius.circular(3));
    canvas.drawRRect(body, Paint()..color = outline..style = PaintingStyle.stroke..strokeWidth = 1.6);
    final nub = RRect.fromRectAndRadius(Rect.fromLTWH(s.width - 2.4, s.height * 0.32, 2.2, s.height * 0.36), const Radius.circular(1));
    canvas.drawRRect(nub, Paint()..color = outline);
    final fillW = (s.width - 8) * (percent.clamp(0, 100) / 100);
    if (fillW > 0) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(3, 3, fillW, s.height - 6), const Radius.circular(1.5)), Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _BatteryPainter old) => old.percent != percent || old.color != color;
}

Color batteryColor(BuildContext context, int? percent) {
  if (percent == null) return context.pf.textSecondary;
  if (percent <= 10) return PF.danger;
  if (percent <= 20) return PF.warning;
  return context.pf.isDark ? PF.success : context.pf.successFg;
}

class BatteryBadge extends StatelessWidget {
  const BatteryBadge({super.key, required this.percent, this.textStyle});
  final int? percent; // null = belum ada data (kalung belum terhubung)
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final c = batteryColor(context, percent);
    return Semantics(
      label: percent == null ? 'Baterai belum diketahui' : 'Baterai $percent persen',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(size: const Size(22, 12), painter: _BatteryPainter(percent ?? 0, c, c)),
          const SizedBox(width: 6),
          Text(percent == null ? '—' : '$percent%', style: textStyle ?? context.tx.captionStrong.copyWith(color: c)),
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
        child: Text(text.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: context.pf.textSecondary)),
      );
}

class PFProgress extends StatelessWidget {
  const PFProgress({super.key, required this.value, this.height = 8});
  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.clamp(0.0, 1.0).toDouble()),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Container(
        height: height,
        decoration: BoxDecoration(color: p.primaryLight, borderRadius: BorderRadius.circular(height)),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: v == 0 ? 0.0 : math.max(v, 0.02),
          child: Container(decoration: BoxDecoration(color: PF.primary, borderRadius: BorderRadius.circular(height))),
        ),
      ),
    );
  }
}

class PageIndicator extends StatelessWidget {
  const PageIndicator({super.key, required this.count, required this.index});
  final int count, index;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 22 : 6,
          height: 6,
          decoration: BoxDecoration(color: active ? PF.primary : p.border, borderRadius: BorderRadius.circular(6)),
        );
      }),
    );
  }
}

class PFSpinner extends StatelessWidget {
  const PFSpinner({super.key, this.size = 28});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: const CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation<Color>(PF.primary)));
}

/// Placeholder berdenyut saat memuat.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 16, this.width, this.radius = 12});
  final double height;
  final double? width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(color: Color.lerp(p.primaryLight, p.border, _c.value), borderRadius: BorderRadius.circular(widget.radius)),
      ),
    );
  }
}

/// Cincin berdenyut di belakang pin peta.
class PulseRing extends StatefulWidget {
  const PulseRing({super.key, this.size = 80, this.color = PF.primary});
  final double size;
  final Color color;

  @override
  State<PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<PulseRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = Curves.easeOut.transform(_c.value);
          return Opacity(
            opacity: (1 - t) * 0.45,
            child: Transform.scale(
              scale: 0.45 + t * 0.55,
              child: Container(width: widget.size, height: widget.size, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Navigasi: top bar & tab bar
// ---------------------------------------------------------------------------

class PFTopBar extends StatelessWidget {
  const PFTopBar({super.key, required this.title, this.onBack, this.showBack = true, this.onMore, this.trailing});

  final String title;
  final VoidCallback? onBack;
  final bool showBack;
  final VoidCallback? onMore;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(PF.margin, context.topInset + 8, PF.margin, 8),
      child: Row(
        children: [
          if (showBack) ...[
            PFIconButton(icon: Icons.chevron_left_rounded, label: 'Kembali', onTap: onBack ?? () => Navigator.of(context).maybePop()),
            const SizedBox(width: 12),
          ],
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tx.h3)),
          if (trailing != null) trailing!,
          if (onMore != null) ...[const SizedBox(width: 8), PFIconButton(icon: Icons.more_horiz_rounded, label: 'Menu lainnya', onTap: onMore)],
        ],
      ),
    );
  }
}

class PFTabBar extends StatelessWidget {
  const PFTabBar({super.key, required this.index, required this.onTap, this.badge = false});

  final int index;
  final ValueChanged<int> onTap;
  final bool badge;

  static const _items = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home_rounded, 'Beranda'),
    (Icons.schedule_rounded, Icons.schedule_rounded, 'Riwayat'),
    (Icons.location_on_outlined, Icons.location_on_rounded, 'Geofence'),
    (Icons.notifications_none_rounded, Icons.notifications_rounded, 'Notifikasi'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Padding(
      // Latar luar transparan agar bilah terlihat benar-benar mengambang.
      padding: EdgeInsets.fromLTRB(14, 7, 14, math.max(context.bottomInset, 12)),
      child: Container(
        height: 70,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: p.border.o(0.8)),
          boxShadow: [
            BoxShadow(color: p.shadow.o(0.12), blurRadius: 26, offset: const Offset(0, 9)),
            BoxShadow(color: PF.primary.o(0.05), blurRadius: 16, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: List.generate(_items.length, (i) {
            final item = _items[i];
            return Expanded(
              child: _FloatingTabItem(
                key: ValueKey('nav-$i'),
                index: i,
                active: index == i,
                badge: i == 3 && badge,
                icon: index == i ? item.$2 : item.$1,
                label: item.$3,
                onTap: () => onTap(i),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _FloatingTabItem extends StatefulWidget {
  const _FloatingTabItem({
    super.key,
    required this.index,
    required this.active,
    required this.badge,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final int index;
  final bool active, badge;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_FloatingTabItem> createState() => _FloatingTabItemState();
}

class _FloatingTabItemState extends State<_FloatingTabItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final active = widget.active;
    return Semantics(
      button: true,
      selected: active,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.92 : (active ? 1.035 : 1),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutBack,
          child: Transform.translate(
            offset: Offset(0, active ? -4 : 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              decoration: BoxDecoration(
                color: active ? p.primaryLight : Colors.transparent,
                borderRadius: BorderRadius.circular(19),
                boxShadow: active
                    ? [BoxShadow(color: PF.primary.o(0.12), blurRadius: 14, offset: const Offset(0, 4))]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 28,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: active ? 38 : 30,
                          height: active ? 30 : 28,
                          decoration: BoxDecoration(
                            color: active ? PF.primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(13),
                            boxShadow: active
                                ? [BoxShadow(color: PF.primary.o(0.26), blurRadius: 10, offset: const Offset(0, 4))]
                                : null,
                          ),
                          child: Icon(widget.icon, size: active ? 20 : 22, color: active ? Colors.white : p.textSecondary),
                        ),
                        if (widget.badge)
                          Positioned(
                            right: -1,
                            top: -2,
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(color: PF.danger, shape: BoxShape.circle, border: Border.all(color: p.surface, width: 1.5)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    style: TextStyle(fontSize: 9.5, height: 1.1, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? p.primaryText : p.textSecondary),
                    child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state, toast, dialog, bottom sheet
// ---------------------------------------------------------------------------

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.message, this.illustration, this.icon, this.actionLabel, this.onAction});
  final String title;
  final String? message, actionLabel;
  final Widget? illustration;
  final IconData? icon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final tx = context.tx;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (illustration != null) illustration!,
          if (illustration == null && icon != null)
            Container(width: 72, height: 72, decoration: BoxDecoration(color: p.primaryLight, shape: BoxShape.circle), child: Icon(icon, size: 32, color: p.primaryText)),
          const SizedBox(height: 18),
          Text(title, textAlign: TextAlign.center, style: tx.h2),
          if (message != null) ...[const SizedBox(height: 8), Text(message!, textAlign: TextAlign.center, style: tx.bodySecondary)],
          if (actionLabel != null) ...[const SizedBox(height: 20), PFButton(label: actionLabel!, onPressed: onAction, expand: false)],
        ],
      ),
    );
  }
}

enum ToastKind { info, success, error }

void showToast(BuildContext context, String message, {ToastKind kind = ToastKind.info}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _ToastView(message: message, kind: kind, onDone: () => entry.remove()));
  overlay.insert(entry);
}

class _ToastView extends StatefulWidget {
  const _ToastView({required this.message, required this.kind, required this.onDone});
  final String message;
  final ToastKind kind;
  final VoidCallback onDone;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await _c.forward();
    await Future<void>.delayed(const Duration(milliseconds: 2600));
    if (!mounted) return;
    await _c.reverse();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (bg, icon) = switch (widget.kind) {
      ToastKind.success => (const Color(0xFF15803D), Icons.check_circle_rounded),
      ToastKind.error => (const Color(0xFFDC2626), Icons.error_rounded),
      ToastKind.info => (const Color(0xFF0F1B3D), Icons.info_rounded),
    };
    return Positioned(
      top: context.topInset + 12,
      left: PF.margin,
      right: PF.margin,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _c,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, -0.4), end: Offset.zero).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8))]),
                child: Row(children: [
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(widget.message, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500, height: 1.3))),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Ya',
  String cancelLabel = 'Batal',
  bool danger = false,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.o(0.45),
    builder: (ctx) {
      final p = ctx.pf;
      final tx = ctx.tx;
      final accent = danger ? PF.danger : PF.primary;
      return Dialog(
        backgroundColor: p.surface,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 60, height: 60, decoration: BoxDecoration(color: accent.o(0.12), shape: BoxShape.circle), child: Icon(icon ?? (danger ? Icons.delete_outline_rounded : Icons.help_outline_rounded), color: accent, size: 28)),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center, style: tx.h2),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: tx.bodySecondary),
              const SizedBox(height: 22),
              Row(children: [
                Expanded(child: PFButton(label: cancelLabel, kind: PFButtonKind.ghost, onPressed: () => Navigator.of(ctx).pop(false))),
                const SizedBox(width: 12),
                Expanded(child: PFButton(label: confirmLabel, kind: danger ? PFButtonKind.danger : PFButtonKind.primary, onPressed: () => Navigator.of(ctx).pop(true))),
              ]),
            ],
          ),
        ),
      );
    },
  );
  return result ?? false;
}

Future<T?> showPFSheet<T>(BuildContext context, {required WidgetBuilder builder, String? title}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.o(0.4),
    builder: (ctx) {
      final p = ctx.pf;
      return Container(
        decoration: BoxDecoration(color: p.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
        padding: EdgeInsets.fromLTRB(PF.margin, 10, PF.margin, MediaQuery.of(ctx).viewInsets.bottom + math.max(ctx.bottomInset, 16) + 8),
        child: SafeArea(
          top: false,
          bottom: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.82),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: p.border, borderRadius: BorderRadius.circular(4)))),
                if (title != null) ...[const SizedBox(height: 16), Text(title, style: ctx.tx.h2)],
                const SizedBox(height: 14),
                Flexible(child: SingleChildScrollView(child: builder(ctx))),
              ],
            ),
          ),
        ),
      );
    },
  );
}
