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

  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  /// Aturan kata sandi untuk PENDAFTARAN (sama dengan backend). Saat masuk cukup tidak boleh kosong.
  static String? passwordPolicy(String p) {
    if (p.length < 8) return 'Kata sandi minimal 8 karakter';
    if (p.length > 128) return 'Kata sandi maksimal 128 karakter';
    if (!RegExp(r'[A-Za-z]').hasMatch(p) || !RegExp(r'\d').hasMatch(p)) return 'Kata sandi harus mengandung huruf dan angka';
    return null;
  }

  bool _validate() {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final pass = _password.text;
    String? nameErr, emailErr, passErr;
    if (_mode == 1) {
      if (name.isEmpty) {
        nameErr = 'Nama wajib diisi';
      } else if (name.length < 2) {
        nameErr = 'Nama minimal 2 karakter';
      } else if (name.length > 60) {
        nameErr = 'Nama maksimal 60 karakter';
      }
    }
    if (email.isEmpty) {
      emailErr = 'Email wajib diisi';
    } else if (email.length > 254 || !_emailRe.hasMatch(email)) {
      emailErr = 'Format email tidak valid';
    }
    if (pass.isEmpty) {
      passErr = 'Kata sandi wajib diisi';
    } else if (_mode == 1) {
      passErr = passwordPolicy(pass);
    }
    setState(() {
      _nameErr = nameErr;
      _emailErr = emailErr;
      _passErr = passErr;
      _banner = null;
    });
    return nameErr == null && emailErr == null && passErr == null;
  }

  Future<void> _submit() async {
    if (_loading) return; // tombol Enter di keyboard tidak boleh mengirim dua kali
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
    } catch (_) {
      if (mounted) setState(() => _banner = 'Terjadi kesalahan tak terduga. Pastikan alamat server benar, lalu coba lagi.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _serverSheet() {
    final app = context.read<AppState>();
    showPFSheet<void>(
      context,
      title: 'Alamat Server',
      builder: (ctx) => _ServerSheet(app: app),
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
                              child: PFTextField(label: 'Nama', hint: 'Nama lengkap', controller: _name, errorText: _nameErr, maxLength: 60, onChanged: (_) {
          if (_nameErr != null) setState(() => _nameErr = null);
        }, prefixIcon: Icons.person_outline_rounded, textCapitalization: TextCapitalization.words, textInputAction: TextInputAction.next),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    PFTextField(label: 'Email', hint: 'nama@email.com', controller: _email, errorText: _emailErr, maxLength: 254, onChanged: (_) {
          if (_emailErr != null) setState(() => _emailErr = null);
        }, prefixIcon: Icons.mail_outline_rounded, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, autofillHints: const [AutofillHints.email]),
                    const SizedBox(height: 14),
                    PFTextField(
                      label: 'Kata sandi',
                      hint: register ? 'Minimal 8 karakter, huruf dan angka' : 'Masukkan kata sandi',
                      controller: _password,
                      errorText: _passErr,
                      maxLength: 128,
                      onChanged: (_) {
          if (_passErr != null) setState(() => _passErr = null);
        },
                      prefixIcon: Icons.lock_outline_rounded,
                      obscure: !_showPass,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      suffix: GestureDetector(
                        onTap: () => setState(() => _showPass = !_showPass),
                        behavior: HitTestBehavior.opaque,
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

/// Sheet alamat server. State (kolom, status uji, galat) disimpan di State sendiri agar tidak hilang
/// saat keyboard muncul/hilang dan sheet dibangun ulang.
class _ServerSheet extends StatefulWidget {
  const _ServerSheet({required this.app});
  final AppState app;

  @override
  State<_ServerSheet> createState() => _ServerSheetState();
}

class _ServerSheetState extends State<_ServerSheet> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.app.baseUrl);
  bool _testing = false;
  String? _err;

  static const _invalid = 'Alamat server tidak valid. Contoh: http://192.168.1.10:4000';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    if (_testing) return;
    if (AppState.normalizeBaseUrl(_ctrl.text) == null) {
      setState(() => _err = _invalid);
      return;
    }
    setState(() {
      _testing = true;
      _err = null;
    });
    final err = await widget.app.testConnection(_ctrl.text);
    if (!mounted) return;
    setState(() => _testing = false);
    showToast(context, err ?? 'Terhubung ke server PawFinder', kind: err == null ? ToastKind.success : ToastKind.error);
  }

  Future<void> _save() async {
    if (AppState.normalizeBaseUrl(_ctrl.text) == null) {
      setState(() => _err = _invalid);
      return;
    }
    try {
      await widget.app.setBaseUrl(_ctrl.text);
    } catch (e) {
      if (mounted) setState(() => _err = errorText(e));
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Isi dengan alamat backend PawFinder. Android emulator: http://10.0.2.2:4000 · HP asli: http://IP-KOMPUTER:4000', style: context.tx.caption),
      const SizedBox(height: 14),
      PFTextField(
        controller: _ctrl,
        hint: 'http://10.0.2.2:4000',
        errorText: _err,
        keyboardType: TextInputType.url,
        prefixIcon: Icons.dns_outlined,
        onChanged: (_) {
          if (_err != null) setState(() => _err = null);
        },
      ),
      const SizedBox(height: 16),
      PFButton(label: 'Uji Koneksi', kind: PFButtonKind.secondary, loading: _testing, onPressed: _test),
      const SizedBox(height: 10),
      PFButton(label: 'Simpan', onPressed: _save),
    ]);
  }
}
