import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/app.dart';
import 'src/app_controller.dart';
import 'src/app_settings.dart';
import 'src/export_history.dart';
import 'src/password_vault.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  final history = await ExportHistoryStore.load(
    retentionDays: settings.historyRetentionDays,
  );
  final passwordVault = await PasswordVault.load();
  final controller = AppController(
    settings,
    historyStore: history,
    passwordVault: passwordVault,
  );
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: controller),
        ChangeNotifierProvider.value(value: passwordVault),
      ],
      child: const LangbaiApp(),
    ),
  );
}
