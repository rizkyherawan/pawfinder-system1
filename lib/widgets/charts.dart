import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models.dart';

/// Bar chart 7 hari: hari terakhir disorot, ketuk batang untuk melihat nilai.
class WeekBarChart extends StatefulWidget {
  const WeekBarChart({super.key, required this.days, this.height = 170});
  final List<DayStat> days;
  final double height;

  @override
  State<WeekBarChart> createState() => _WeekBarChartState();
}

class _WeekBarChartState extends State<WeekBarChart> {
  int? _sel;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final tx = context.tx;
    final days = widget.days;
    final maxV = math.max(1, days.fold<int>(0, (m, d) => math.max(m, d.minutes)));
    final barArea = widget.height - 44;
    return SizedBox(
      height: widget.height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(days.length, (i) {
          final d = days[i];
          final active = i == days.length - 1 || _sel == i;
          return Expanded(
            child: Semantics(
              label: '${d.label}: ${d.minutes} menit aktif',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _sel = _sel == i ? null : i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: 18,
                      child: _sel == i ? Text('${d.minutes}m', style: tx.micro.copyWith(color: p.primaryText, fontWeight: FontWeight.w700)) : null,
                    ),
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: d.minutes / maxV),
                      duration: Duration(milliseconds: 500 + i * 60),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, __) => Container(
                        width: 24,
                        height: 8 + v * (barArea - 8),
                        decoration: BoxDecoration(color: active ? PF.primary : p.primaryLight, borderRadius: BorderRadius.circular(9)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(d.label, style: tx.micro.copyWith(fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? p.primaryText : p.textSecondary)),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
