import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/data_source.dart';
import '../../state/app_state.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../../widgets/inputs.dart';

/// Form profil pemilik akun. Data hewan dikelola secara terpisah dari profil ini.
class EditAccountScreen extends StatefulWidget {
  const EditAccountScreen({super.key});

  @override
  State<EditAccountScreen> createState() => _EditAccountScreenState();
}

class _EditAccountScreenState extends State<EditAccountScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  bool _saving = false;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppState>().user;
    _name.text = user?.name ?? '';
    _email.text = user?.email ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) {
      setState(() => _nameError = 'Nama wajib diisi');
      return;
    }
    if (name.length < 2) {
      setState(() => _nameError = 'Nama minimal 2 karakter');
      return;
    }
    if (name.length > 60) {
      setState(() => _nameError = 'Nama maksimal 60 karakter');
      return;
    }

    setState(() {
      _saving = true;
      _nameError = null;
    });
    try {
      await context.read<AppState>().updateProfile(name: name);
      if (!mounted) return;
      showToast(context, 'Profil akun berhasil diperbarui', kind: ToastKind.success);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final message = errorText(e);
      setState(() {
        if (message.toLowerCase().contains('nama')) {
          _nameError = message;
        } else {
          _nameError = null;
        }
      });
      showToast(context, message, kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final tx = context.tx;
    final user = context.watch<AppState>().user;
    final displayName = user?.name.trim() ?? '';
    // runes (bukan substring) agar emoji / huruf bertanda tidak terpotong menjadi karakter rusak
    final initial = displayName.isEmpty ? 'P' : String.fromCharCode(displayName.runes.first).toUpperCase();

    return Scaffold(
      body: Column(
        children: [
          const PFTopBar(title: 'Edit Profil'),
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.primaryLight,
                      shape: BoxShape.circle,
                      border: Border.all(color: PF.primary.o(0.22), width: 2),
                    ),
                    child: Text(initial, style: tx.display.copyWith(fontSize: 34, color: p.primaryText, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Profil pemilik akun', textAlign: TextAlign.center, style: tx.h2),
                const SizedBox(height: 5),
                Text('Perubahan di halaman ini hanya mengubah data akun, bukan profil hewan peliharaan.', textAlign: TextAlign.center, style: tx.caption),
                const SizedBox(height: 24),
                PFCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PFTextField(
                        label: 'Nama lengkap',
                        hint: 'Nama pemilik akun',
                        controller: _name,
                        errorText: _nameError,
                        prefixIcon: Icons.person_outline_rounded,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) {
                          if (_nameError != null) setState(() => _nameError = null);
                        },
                        onSubmitted: (_) => _save(),
                      ),
                      const SizedBox(height: 16),
                      PFTextField(
                        label: 'Email akun',
                        hint: 'Email untuk masuk',
                        controller: _email,
                        prefixIcon: Icons.mail_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                        enabled: false,
                      ),
                      const SizedBox(height: 8),
                      Text('Email digunakan sebagai identitas masuk dan tidak dapat diubah dari halaman ini.', style: tx.micro),
                      const SizedBox(height: 22),
                      PFButton(label: 'Simpan Perubahan', icon: Icons.check_rounded, loading: _saving, onPressed: _save),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
