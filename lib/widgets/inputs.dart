import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import 'pressable.dart';

/// Kolom input: Default, Focus, Filled, Error.
class PFTextField extends StatefulWidget {
  const PFTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.errorText,
    this.prefixIcon,
    this.suffix,
    this.keyboardType,
    this.obscure = false,
    this.onChanged,
    this.textInputAction,
    this.onSubmitted,
    this.maxLength,
    this.autofillHints,
    this.enabled = true,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
  });

  final String? label, hint, errorText;
  final TextEditingController? controller;
  final IconData? prefixIcon;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final bool obscure, enabled;
  final ValueChanged<String>? onChanged, onSubmitted;
  final TextInputAction? textInputAction;
  final int? maxLength;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<PFTextField> createState() => _PFTextFieldState();
}

class _PFTextFieldState extends State<PFTextField> {
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final tx = context.tx;
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;
    final borderColor = hasError ? PF.danger : (_focused ? PF.primary : p.border);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[Text(widget.label!, style: tx.captionStrong), const SizedBox(height: 8)],
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(PF.rInput),
            border: Border.all(color: borderColor, width: _focused || hasError ? 1.6 : 1.2),
            boxShadow: _focused && !hasError ? [BoxShadow(color: PF.primary.o(0.14), blurRadius: 0, spreadRadius: 3)] : null,
          ),
          child: Row(
            children: [
              if (widget.prefixIcon != null) ...[Icon(widget.prefixIcon, size: 20, color: p.textSecondary), const SizedBox(width: 10)],
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  obscureText: widget.obscure,
                  keyboardType: widget.keyboardType,
                  textInputAction: widget.textInputAction,
                  textCapitalization: widget.textCapitalization,
                  autofillHints: widget.autofillHints,
                  maxLength: widget.maxLength,
                  inputFormatters: widget.inputFormatters,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  cursorColor: PF.primary,
                  style: tx.body,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    counterText: '',
                    hintText: widget.hint,
                    hintStyle: tx.body.copyWith(color: p.textSecondary.o(0.8)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              if (widget.suffix != null) widget.suffix!,
            ],
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.error_outline_rounded, size: 14, color: PF.danger),
            const SizedBox(width: 4),
            Expanded(child: Text(widget.errorText!, style: tx.caption.copyWith(color: PF.danger))),
          ]),
        ],
      ],
    );
  }
}

/// Field tanggal: menampilkan tanggal terpilih atau placeholder, membuka date picker.
class PFDateField extends StatelessWidget {
  const PFDateField({super.key, this.label, this.value, this.hint = 'Pilih tanggal lahir', required this.onChanged, this.firstDate, this.lastDate, this.errorText});

  /// Pesan galat (mis. "Tanggal lahir wajib diisi"); bila ada, bingkai menjadi merah.
  final String? label, hint, errorText;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate, lastDate;

  Future<void> _pick(BuildContext context) async {
    // Tanggal awal HARUS berada di antara firstDate dan lastDate, kalau tidak showDatePicker melempar assertion.
    final today = DateUtils.dateOnly(DateTime.now());
    final first = DateUtils.dateOnly(firstDate ?? DateTime(today.year - 30));
    var last = DateUtils.dateOnly(lastDate ?? today);
    if (last.isBefore(first)) last = first;
    var initial = DateUtils.dateOnly(value ?? DateTime(today.year - 1, today.month, today.day));
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Pilih tanggal',
      cancelText: 'Batal',
      confirmText: 'Pilih',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: PF.primary)),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final tx = context.tx;
    final hasError = errorText != null && errorText!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[Text(label!, style: tx.captionStrong), const SizedBox(height: 8)],
        Pressable(
          onTap: () => _pick(context),
          scale: 0.99,
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(PF.rInput), border: Border.all(color: hasError ? PF.danger : p.border, width: hasError ? 1.6 : 1.2)),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value == null ? (hint ?? '') : fmtDateLong(value!),
                    style: value == null ? tx.body.copyWith(color: p.textSecondary.o(0.8)) : tx.body,
                  ),
                ),
                Icon(Icons.calendar_month_outlined, size: 20, color: p.textSecondary),
              ],
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.error_outline_rounded, size: 14, color: PF.danger),
            const SizedBox(width: 4),
            Expanded(child: Text(errorText!, style: tx.caption.copyWith(color: PF.danger))),
          ]),
        ],
      ],
    );
  }
}

/// Segmented control (Anjing/Kucing/Kelinci, Jantan/Betina, Perjalanan/Aktivitas/Kesehatan).
class PFSegmented extends StatelessWidget {
  const PFSegmented({super.key, required this.items, required this.index, required this.onChanged, this.height = 44});

  final List<String> items;
  final int index;
  final ValueChanged<int> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.primaryLight, borderRadius: BorderRadius.circular(PF.rInput)),
      child: Row(
        children: List.generate(items.length, (i) {
          final active = i == index;
          return Expanded(
            child: Semantics(
              button: true,
              selected: active,
              label: items[i],
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  height: height - 8 < 36 ? 36 : height - 8,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? p.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(PF.rInput - 3),
                    boxShadow: active ? [BoxShadow(color: PF.primary.o(0.14), blurRadius: 8, offset: const Offset(0, 2))] : null,
                  ),
                  child: Text(
                    items[i],
                    style: TextStyle(fontSize: 13.5, fontWeight: active ? FontWeight.w600 : FontWeight.w500, color: active ? p.primaryText : p.textSecondary),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Toggle switch bergaya PawFinder.
class PFSwitch extends StatelessWidget {
  const PFSwitch({super.key, required this.value, required this.onChanged, this.semanticLabel});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Semantics(
      toggled: value,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                onChanged!(!value);
              },
        child: SizedBox(
          width: 56,
          height: 44, // target sentuh 44
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: 52,
              height: 30,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: value ? PF.primary : (p.isDark ? p.border : const Color(0xFFD5DEEF)),
                borderRadius: BorderRadius.circular(999),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Slider (radius geofence) dengan nilai terformat dan label batas.
class PFSlider extends StatelessWidget {
  const PFSlider({super.key, required this.value, required this.min, required this.max, required this.onChanged, this.onChangeEnd, this.minLabel, this.maxLabel, this.divisions});

  final double value, min, max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String? minLabel, maxLabel;
  final int? divisions;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final tx = context.tx;
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: PF.primary,
            inactiveTrackColor: p.primaryLight,
            thumbColor: PF.primary,
            overlayColor: PF.primary.o(0.12),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12, elevation: 3),
            trackShape: const RoundedRectSliderTrackShape(),
          ),
          child: Slider(value: value.clamp(min, max).toDouble(), min: min, max: max, divisions: divisions, onChanged: onChanged, onChangeEnd: onChangeEnd),
        ),
        if (minLabel != null || maxLabel != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(minLabel ?? '', style: tx.micro), Text(maxLabel ?? '', style: tx.micro)]),
          ),
      ],
    );
  }
}

/// Chip filter (Semua, Geofence, Sistem, Kesehatan).
class PFChip extends StatelessWidget {
  const PFChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? PF.primary : p.surface,
            borderRadius: BorderRadius.circular(PF.rChip),
            border: Border.all(color: selected ? PF.primary : p.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 16, color: selected ? Colors.white : p.textSecondary), const SizedBox(width: 6)],
              Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: selected ? Colors.white : p.text)),
            ],
          ),
        ),
      ),
    );
  }
}
