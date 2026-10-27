import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'pet_face.dart';

/// Sheet pemilih hewan (dipakai di Pelacak, Geofencing, Profil, dll).
void showPetPicker(BuildContext context, AppState s, {ValueChanged<String>? onPicked}) {
  showPFSheet<void>(
    context,
    title: 'Pilih Hewan',
    builder: (ctx) => Column(children: [
      for (final pet in s.pets)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: PetFace(pet: pet, size: 46),
          title: Text(pet.name, style: ctx.tx.bodyStrong),
          subtitle: Text('${pet.subtitle} · ${pet.device.statusLabel}', style: ctx.tx.caption),
          trailing: pet.id == s.selectedPetId ? const Icon(Icons.check_circle_rounded, color: PF.primary) : null,
          onTap: () {
            s.selectPet(pet.id);
            onPicked?.call(pet.id);
            Navigator.of(ctx).pop();
          },
        ),
    ]),
  );
}
