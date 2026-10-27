import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/constants.dart';
import 'data/local_store.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Penguncian orientasi hanya relevan untuk Android/iOS. Hindari memanggil
  // API orientasi saat aplikasi berjalan di web atau desktop.
  if (AppConfig.isMobile) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  final store = LocalStore();
  await store.init();
  runApp(
    ChangeNotifierProvider<AppState>(
      create: (_) => AppState(store)..init(),
      child: const PawFinderApp(),
    ),
  );
}
