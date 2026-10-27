import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../data/data_source.dart';
import '../../state/app_state.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../../widgets/inputs.dart';
import '../../widgets/pet_art.dart';
import '../../data/models.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  int _mode = 0; // 0 masuk, 1 daftar
  bool _loading = false, _showPass = false;
  String? _nameErr, _emailErr, _passErr, _banner;
  bool _networkIssue = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _validate() {
    final emailOk = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(_email.text.trim());
    setState(() {
      _nameErr = _mode == 1 && _name.text.trim().length < 2 ? 'Nama minimal 2 karakter' : null;
      _emailErr = emailOk ? null : 'Format email tidak valid';
      _passErr = _password.text.length < 6 ? 'Kata sandi minimal 6 karakter' : null;
      _banner = null;
    });
    return _nameErr == null && _emailErr == null && _passErr == null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_validate()) return;
    final app = context.read<AppState>();
    setState(() {
      _loading = true;
      _networkIssue = false;
    });
    try {
      if (_mode == 0) {
        await app.login(_email.text, _password.text);
      } else {
        await app.register(_name.text, _email.text, _password.text);
      }
      if (mounted) Navigator.of(context).maybePop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _networkIssue = e.network;
        if (e.field == 'email') {
          _emailErr = e.message;
        } else if (e.field == 'password') {
          _passErr = e.message;
        } else if (e.field == 'name') {
          _nameErr = e.message;
        } else {
          _banner = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fillDemo() {
    setState(() {
      _mode = 0;
      _email.text = AppConfig.demoEmail;
      _password.text = AppConfig.demoPassword;
      _emailErr = _passErr = _banner = null;
    });
  }

  void _serverSheet() {
    final app = context.read<AppState>();
    final ctrl = TextEditingController(text: app.baseUrl);
    showPFSheet<void>(
      context,
      title: 'Alamat Server',
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        var testing = false;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Isi dengan alamat backend PawFinder. Android emulator: http://10.0.2.2:4000 · HP asli: http://IP-KOMPUTER:4000', style: ctx.tx.caption),
          const SizedBox(height: 14),
          PFTextField(controller: ctrl, hint: 'http://10.0.2.2:4000', keyboardType: TextInputType.url, prefixIcon: Icons.dns_outlined),
          const SizedBox(height: 16),
          StatefulBuilder(builder: (ctx, setBtn) {
            return PFButton(
              label: 'Uji Koneksi',
              kind: PFButtonKind.secondary,
              loading: testing,
              onPressed: () async {
                setBtn(() => testing = true);
                final err = await app.testConnection(ctrl.text.trim().startsWith('http') ? ctrl.text.trim() : 'http://${ctrl.text.trim()}');
                setBtn(() => testing = false);
                if (!ctx.mounted) return;
                showToast(ctx, err ?? 'Terhubung ke server PawFinder', kind: err == null ? ToastKind.success : ToastKind.error);
              },
            );
          }),
          const SizedBox(height: 10),
          PFButton(
            label: 'Simpan',
            onPressed: () async {
              await app.setBaseUrl(ctrl.text);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
          ),
        ]);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final tx = context.tx;
    final app = context.watch<AppState>();
    final register = _mode == 1;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: p.isDark ? const [Color(0xFF14264F), Color(0xFF0B1226)] : const [Color(0xFFDCE8FF), Color(0xFFF5F9FF)]),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(PF.margin, 24, PF.margin, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: PFLogo(size: 48)),
                const SizedBox(height: 8),
                Center(child: Text(AppConfig.tagline, style: tx.body.copyWith(color: p.primaryText))),
                const SizedBox(height: 18),
                SizedBox(
                  height: 120,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: const [
                    PetAvatar(species: Species.anjing, size: 92, colorIndex: 0),
                    SizedBox(width: 10),
                    PetAvatar(species: Species.kucing, size: 76, colorIndex: 1),
                    SizedBox(width: 10),
                    PetAvatar(species: Species.kelinci, size: 62, colorIndex: 2),
                  ]),
                ),
                const SizedBox(height: 22),
                PFCard(
                  padding: const EdgeInsets.all(20),
                  radius: 26,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    PFSegmented(items: const ['Masuk', 'Daftar'], index: _mode, onChanged: (i) => setState(() {
                          _mode = i;
                          _nameErr = _emailErr = _passErr = _banner = null;
                        })),
                    const SizedBox(height: 18),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      child: register
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: PFTextField(label: 'Nama', hint: 'Nama lengkap', controller: _name, errorText: _nameErr, prefixIcon: Icons.person_outline_rounded, textCapitalization: TextCapitalization.words, textInputAction: TextInputAction.next),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    PFTextField(label: 'Email', hint: 'nama@email.com', controller: _email, errorText: _emailErr, prefixIcon: Icons.mail_outline_rounded, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, autofillHints: const [AutofillHints.email]),
                    const SizedBox(height: 14),
                    PFTextField(
                      label: 'Kata sandi',
                      hint: 'Minimal 6 karakter',
                      controller: _password,
                      errorText: _passErr,
                      prefixIcon: Icons.lock_outline_rounded,
                      obscure: !_showPass,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      suffix: GestureDetector(
                        onTap: () => setState(() => _showPass = !_showPass),
                        child: SizedBox(width: 44, height: 44, child: Icon(_showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: p.textSecondary)),
                      ),
                    ),
                    if (_banner != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: p.dangerBg, borderRadius: BorderRadius.circular(14)),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.error_outline_rounded, color: PF.danger, size: 18),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_banner!, style: tx.caption.copyWith(color: PF.danger, fontWeight: FontWeight.w500))),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 18),
                    PFButton(label: register ? 'Buat Akun' : 'Masuk', loading: _loading, onPressed: _submit),
                    if (!register) ...[
                      const SizedBox(height: 8),
                      Center(child: PFButton(label: 'Isi akun demo', kind: PFButtonKind.text, expand: false, onPressed: _fillDemo)),
                    ],
                  ]),
                ),
                const SizedBox(height: 16),
                PFButton(
                  label: 'Coba mode demo (tanpa server)',
                  icon: Icons.play_circle_outline_rounded,
                  kind: _networkIssue ? PFButtonKind.primary : PFButtonKind.secondary,
                  onPressed: () async {
                    await app.enterDemo();
                    if (mounted) Navigator.of(context).maybePop(true);
                  },
                ),
                const SizedBox(height: 10),
                Center(
                  child: GestureDetector(
                    onTap: _serverSheet,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.dns_outlined, size: 16, color: p.textSecondary),
                        const SizedBox(width: 8),
                        Flexible(child: Text('Server: ${app.baseUrl}', style: tx.caption, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 6),
                        Icon(Icons.edit_outlined, size: 14, color: p.primaryText),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
