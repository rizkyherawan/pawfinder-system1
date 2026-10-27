import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/pet_art.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 3), () {
      if (mounted) context.read<AppState>().markSplashElapsed();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  Animation<double> _in(double a, double b) => CurvedAnimation(parent: _c, curve: Interval(a, b, curve: Curves.easeOutCubic));

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final tx = context.tx;
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: p.isDark ? const [Color(0xFF14264F), Color(0xFF0B1226)] : const [Color(0xFFDCE8FF), Color(0xFFF5F9FF)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(flex: 2),
                FadeTransition(
                  opacity: _in(0, 0.5),
                  child: ScaleTransition(scale: Tween<double>(begin: 0.85, end: 1).animate(_in(0, 0.5)), child: const PFLogo(size: 52)),
                ),
                const SizedBox(height: 10),
                FadeTransition(opacity: _in(0.15, 0.6), child: Text(AppConfig.tagline, style: tx.body.copyWith(color: p.primaryText, fontWeight: FontWeight.w500))),
                const Spacer(),
                FadeTransition(
                  opacity: _in(0.2, 0.8),
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(_in(0.2, 0.8)),
                    child: SizedBox(
                      width: 290,
                      height: 290,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(width: 270, height: 270, decoration: BoxDecoration(color: PF.primary.o(p.isDark ? 0.18 : 0.13), shape: BoxShape.circle)),
                          const Positioned(left: -4, bottom: 10, child: PetFigure(species: Species.anjing, size: 190)),
                          const Positioned(right: 0, bottom: 6, child: PetFigure(species: Species.kucing, size: 136)),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                FadeTransition(
                  opacity: _in(0.5, 1),
                  child: Column(children: [
                    Text('Sahabat kecilmu, selalu dalam jangkauan.', textAlign: TextAlign.center, style: tx.h3.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('Lokasi, aktivitas, dan rasa tenang untuk setiap hari bersama.', textAlign: TextAlign.center, style: tx.caption),
                  ]),
                ),
                const Spacer(),
                const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6, valueColor: AlwaysStoppedAnimation<Color>(PF.primary))),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
