import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../widgets/common.dart';

import 'constants.dart';

enum PhotoSource { gallery, camera }

class PhotoPickResult {
  const PhotoPickResult.ok(this.bytes) : error = null;
  const PhotoPickResult.fail(this.error) : bytes = null;
  const PhotoPickResult.cancelled() : bytes = null, error = null;
  final Uint8List? bytes;
  final String? error;
  bool get isCancelled => bytes == null && error == null;
}

/// Alur lengkap memilih foto hewan: penjelasan izin -> permintaan izin sistem -> pemilih foto.
/// Foto diperkecil (maks 900 px, JPEG) agar ringan diunggah.
Future<PhotoPickResult> pickPetPhoto(BuildContext context, PhotoSource source) async {
  final isGallery = source == PhotoSource.gallery;

  // Di Chrome/Windows tidak ada izin sistem seperti di HP: langsung buka pemilih berkas.
  if (!AppConfig.isMobile) {
    if (!isGallery) {
      return const PhotoPickResult.fail(
        'Kamera langsung tersedia di Android/iOS. Di web dan desktop, pilih foto dari berkas.',
      );
    }
    return _pickFromFiles();
  }

  // 1) Penjelasan mengapa izin diperlukan (rationale) sebelum dialog izin sistem muncul.
  final proceed = await showConfirmDialog(
    context,
    title: isGallery ? 'Izinkan akses galeri' : 'Izinkan akses kamera',
    message: isGallery
        ? 'PawFinder memerlukan akses ke galeri foto agar kamu dapat memilih foto profil hewan peliharaanmu. Foto hanya dipakai untuk profil hewan.'
        : 'PawFinder memerlukan akses kamera agar kamu dapat memotret hewan peliharaanmu untuk foto profil.',
    confirmLabel: 'Lanjutkan',
    cancelLabel: 'Batal',
    icon: isGallery ? Icons.photo_library_outlined : Icons.photo_camera_outlined,
  );
  if (!proceed) return const PhotoPickResult.cancelled();

  // 2) Izin sistem (Android 13+: READ_MEDIA_IMAGES, iOS: Photos / Camera).
  PermissionStatus status;
  if (isGallery) {
    status = await Permission.photos.request();
    if (!(status.isGranted || status.isLimited)) {
      // Android 12 ke bawah memakai izin penyimpanan.
      final legacy = await Permission.storage.request();
      if (legacy.isGranted) status = legacy;
    }
  } else {
    status = await Permission.camera.request();
  }

  if (!(status.isGranted || status.isLimited)) {
    if (status.isPermanentlyDenied && context.mounted) {
      final open = await showConfirmDialog(
        context,
        title: 'Izin diperlukan',
        message: 'Akses ${isGallery ? 'galeri' : 'kamera'} ditolak. Aktifkan izin di Pengaturan sistem agar PawFinder dapat mengambil foto.',
        confirmLabel: 'Buka Pengaturan',
        cancelLabel: 'Nanti',
        icon: Icons.lock_outline_rounded,
      );
      if (open) await openAppSettings();
    }
    return PhotoPickResult.fail('Izin ${isGallery ? 'galeri' : 'kamera'} belum diberikan');
  }

  // 3) Pemilih foto.
  return _pick(isGallery ? ImageSource.gallery : ImageSource.camera);
}

Future<PhotoPickResult> _pickFromFiles() async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return const PhotoPickResult.cancelled();
    }
    final bytes = result.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      return const PhotoPickResult.fail('Berkas foto tidak dapat dibaca. Pilih foto lain.');
    }
    if (bytes.length > 700 * 1024) {
      return const PhotoPickResult.fail('Ukuran foto terlalu besar (maks 700 KB). Pilih foto lain.');
    }
    return PhotoPickResult.ok(bytes);
  } catch (_) {
    return const PhotoPickResult.fail('Tidak dapat membuka pemilih berkas. Coba lagi.');
  }
}

Future<PhotoPickResult> _pick(ImageSource source) async {
  try {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 900, maxHeight: 900, imageQuality: 82);
    if (file == null) return const PhotoPickResult.cancelled();
    final bytes = await file.readAsBytes();
    if (bytes.length > 700 * 1024) return const PhotoPickResult.fail('Ukuran foto terlalu besar (maks 700 KB). Pilih foto lain.');
    return PhotoPickResult.ok(bytes);
  } catch (_) {
    return const PhotoPickResult.fail('Tidak dapat membuka foto. Coba lagi.');
  }
}
