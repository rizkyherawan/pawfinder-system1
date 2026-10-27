import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'pet_art.dart';

/// Avatar hewan yang memakai foto unggahan pengguna bila ada, atau ilustrasi bila belum ada foto.
class PetFace extends StatefulWidget {
  const PetFace({super.key, required this.pet, this.size = 56, this.ring = false});
  final Pet pet;
  final double size;
  final bool ring;

  @override
  State<PetFace> createState() => _PetFaceState();
}

class _PetFaceState extends State<PetFace> {
  @override
  void initState() {
    super.initState();
    _ensure();
  }

  @override
  void didUpdateWidget(covariant PetFace old) {
    super.didUpdateWidget(old);
    if (old.pet.photoVersion != widget.pet.photoVersion) _ensure();
  }

  void _ensure() {
    if (!widget.pet.hasPhoto) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().ensurePhoto(widget.pet);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pet = widget.pet;
    final Uint8List? bytes = context.select<AppState, Uint8List?>((s) => s.photoBytes(pet));
    if (bytes == null) {
      return PetAvatar(species: pet.species, size: widget.size, colorIndex: pet.avatarColor, ring: widget.ring);
    }
    final p = context.pf;
    return Semantics(
      image: true,
      label: 'Foto ${pet.name}',
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: widget.ring ? Border.all(color: PF.primary, width: widget.size * 0.07) : Border.all(color: p.surface, width: widget.size > 40 ? 2 : 1),
        ),
        child: ClipOval(child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, width: widget.size, height: widget.size)),
      ),
    );
  }
}
