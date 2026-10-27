import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'pressable.dart';

enum PFButtonKind { primary, secondary, ghost, text, danger }

/// Tombol dengan varian Primary, Secondary, Ghost, Text link, Danger
/// dan state Default, Pressed, Disabled, Loading.
class PFButton extends StatefulWidget {
  const PFButton({
    super.key,
    required this.label,
    this.onPressed,
    this.kind = PFButtonKind.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.pill = true,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onPressed;
  final PFButtonKind kind;
  final IconData? icon;
  final bool loading;
  final bool expand;
  final bool pill; // CTA utama berbentuk pill
  final double height;

  @override
  State<PFButton> createState() => _PFButtonState();
}

class _PFButtonState extends State<PFButton> {
  bool _down = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    Color bg, fg;
    Border? border;
    List<BoxShadow>? shadow;
    switch (widget.kind) {
      case PFButtonKind.primary:
        bg = _down ? PF.primaryDark : PF.primary;
        fg = Colors.white;
        shadow = _enabled ? [BoxShadow(color: PF.primary.o(0.30), blurRadius: 18, offset: const Offset(0, 8))] : null;
        break;
      case PFButtonKind.secondary:
        bg = _down ? p.primaryLight.o(0.7) : p.primaryLight;
        fg = p.primaryText;
        break;
      case PFButtonKind.ghost:
        bg = _down ? p.primaryLight : Colors.transparent;
        fg = p.text;
        border = Border.all(color: p.border, width: 1.5);
        break;
      case PFButtonKind.text:
        bg = Colors.transparent;
        fg = p.primaryText;
        break;
      case PFButtonKind.danger:
        bg = _down ? const Color(0xFFD93636) : PF.danger;
        fg = Colors.white;
        break;
    }
    if (widget.onPressed == null && !widget.loading) {
      // Disabled
      bg = widget.kind == PFButtonKind.primary || widget.kind == PFButtonKind.danger ? bg.o(0.4) : bg;
      fg = fg.o(0.5);
      shadow = null;
    }
    final isText = widget.kind == PFButtonKind.text;
    final radius = BorderRadius.circular(widget.pill ? PF.rChip : PF.rButton);

    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4, valueColor: AlwaysStoppedAnimation<Color>(fg)),
          )
        else ...[
          if (widget.icon != null) ...[Icon(widget.icon, size: 20, color: fg), const SizedBox(width: 8)],
          Flexible(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg, decoration: isText ? TextDecoration.none : null),
            ),
          ),
        ],
      ],
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: _enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: _enabled ? () => setState(() => _down = false) : null,
        onTap: _enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _down && !isText ? 0.98 : 1,
          duration: const Duration(milliseconds: 90),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            constraints: BoxConstraints(minHeight: widget.height < 44 ? 44 : widget.height),
            padding: EdgeInsets.symmetric(horizontal: isText ? 8 : 22),
            decoration: BoxDecoration(color: bg, borderRadius: radius, border: border, boxShadow: shadow),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Tombol ikon bulat 44x44 (target sentuh minimum), mis. kembali / menu / zoom.
class PFIconButton extends StatelessWidget {
  const PFIconButton({super.key, required this.icon, this.onTap, this.size = 44, this.label, this.background, this.color, this.border = true, this.shadow = false});

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final String? label;
  final Color? background;
  final Color? color;
  final bool border;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        child: Container(
          width: size < 44 ? 44 : size,
          height: size < 44 ? 44 : size,
          decoration: BoxDecoration(
            color: background ?? p.surface,
            shape: BoxShape.circle,
            border: border ? Border.all(color: p.border) : null,
            boxShadow: shadow ? softShadow(p) : null,
          ),
          child: Icon(icon, size: 22, color: color ?? p.text),
        ),
      ),
    );
  }
}
