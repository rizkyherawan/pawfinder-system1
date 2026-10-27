# Memperbaiki import merah di VS Code

1. Ekstrak ZIP ini ke folder baru.
2. Di VS Code pilih **File > Open Folder...**, lalu pilih folder yang di dalamnya langsung terdapat `pubspec.yaml`, `lib`, `web`, dan `android`. Jangan membuka folder induk yang hanya berisi folder proyek lain.
3. Buka Terminal > New Terminal. Pastikan terminal berada di folder yang sama dengan `pubspec.yaml`.
4. Jalankan satu per satu:

```bash
flutter doctor
flutter clean
flutter pub get
flutter run -d chrome
```

`flutter pub get` hanya mengambil dependensi; perintah itu tidak mengganti `lib/main.dart` dengan Flutter Demo. Jika browser masih menampilkan Flutter Demo, hampir pasti perintah `flutter run` dijalankan dari salinan proyek/folder yang berbeda.
