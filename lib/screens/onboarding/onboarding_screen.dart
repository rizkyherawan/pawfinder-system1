import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../../widgets/pet_art.dart';

class _Slide {
  const _Slide(this.eyebrow, this.title, this.body);
  final String eyebrow, title, body;
}

const _slides = [
  _Slide('KENALI PAWFINDER · 01', 'Lacak Lokasi Secara Real-Time', 'Ketahui posisi sahabat kecilmu dari mana saja. Pantau lokasi terkini dan temukan mereka dengan lebih tenang.'),
  _Slide('KENALI PAWFINDER · 02', 'Geofencing & Notifikasi Instan', 'Tentukan area aman di sekitar rumah. Dapatkan notifikasi saat hewan kesayangan keluar atau kembali ke area itu.'),
  _Slide('KENALI PAWFINDER · 03', 'Perangkat GPS Terhubung via IoT', 'Kalung GPS terhubung ke aplikasi melalui IoT. Baterai tahan lama untuk menemani keseharian; daya tahan mengikuti pemakaian dan sinyal.'),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() => context.read<AppState>().completeOnboarding();

  void _next() {
    if (_index >= _slides.length - 1) return _finish();
    _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final tx = context.tx;
    final last = _index == _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(PF.margin, 12, PF.margin, 8),
              child: Row(children: [
                const PFLogo(size: 34),
                const Spacer(),
                PFButton(label: 'Lewati', kind: PFButtonKind.text, expand: false, height: 44, onPressed: _finish),
              ]),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) {
                  final s = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: PF.margin),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(28), child: _scene(i))),
                        const SizedBox(height: 20),
                        Text(s.eyebrow, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: p.primaryText)),
                        const SizedBox(height: 8),
                        Text(s.title, style: tx.display.copyWith(fontSize: 30)),
                        const SizedBox(height: 10),
                        Text(s.body, style: tx.bodySecondary.copyWith(fontSize: 14)),
                        const SizedBox(height: 4),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            PageIndicator(count: _slides.length, index: _index),
            Padding(
              padding: const EdgeInsets.fromLTRB(PF.margin, 18, PF.margin, 16),
              child: PFButton(label: last ? 'Mulai' : 'Lanjut', icon: Icons.arrow_forward_rounded, onPressed: _next),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scene(int i) {
    switch (i) {
      case 0:
        return const _SceneTrack();
      case 1:
        return const _SceneGeofence();
      default:
        return const _SceneDevice();
    }
  }
}

class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return PFCard(
      glass: true,
      radius: 14,
      shadow: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: context.pf.primaryText),
        const SizedBox(width: 8),
        Text(label, style: context.tx.captionStrong.copyWith(fontSize: 12)),
      ]),
    );
  }
}

class _SceneTrack extends StatelessWidget {
  const _SceneTrack();

  @override
  Widget build(BuildContext context) {
    final dark = context.pf.isDark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: dark ? const [Color(0xFF1C3566), Color(0xFF14264F)] : const [Color(0xFFE6EFFC), Color(0xFFCFE0F6)]),
      ),
      child: Stack(
        children: [
          const Positioned(left: 26, top: 40, child: Pin3D(size: 130)),
          const Positioned(right: -6, bottom: 10, child: PetFigure(species: Species.kucing, size: 250)),
          const Positioned(left: 14, bottom: 14, child: _GlassChip(icon: Icons.location_on_outlined, label: 'Lokasi terkini · Sleman')),
        ],
      ),
    );
  }
}

class _SceneGeofence extends StatelessWidget {
  const _SceneGeofence();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: MiniCityPainter()),
        const Align(alignment: Alignment(0, 0.55), child: GeofenceDisc(width: 280)),
        const Align(alignment: Alignment(0, 0.3), child: PetFigure(species: Species.anjing, size: 210)),
        Positioned(
          right: 14,
          top: 14,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: PF.danger, shape: BoxShape.circle, boxShadow: [BoxShadow(color: PF.danger.o(0.4), blurRadius: 12, offset: const Offset(0, 4))]),
            child: const Icon(Icons.notifications_active_outlined, color: Colors.white, size: 22),
          ),
        ),
        const Positioned(left: 14, bottom: 14, child: _GlassChip(icon: Icons.shield_outlined, label: 'Area aman · Rumah')),
      ],
    );
  }
}

class _SceneDevice extends StatelessWidget {
  const _SceneDevice();

  @override
  Widget build(BuildContext context) {
    final dark = context.pf.isDark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: dark ? const [Color(0xFF1C3566), Color(0xFF14264F)] : const [Color(0xFFDCE8F8), Color(0xFFBFD3EE)]),
      ),
      child: Stack(
        children: [
          const Center(child: Padding(padding: EdgeInsets.only(bottom: 30), child: CollarArt(height: 190))),
          const Positioned(left: 14, bottom: 14, child: _GlassChip(icon: Icons.sensors_rounded, label: 'GPS + IoT · Selalu terhubung')),
        ],
      ),
    );
  }
}
