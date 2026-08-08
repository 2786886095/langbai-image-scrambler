import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/app.dart';
import 'src/app_controller.dart';
import 'src/app_settings.dart';
import 'src/export_history.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  final history = await ExportHistoryStore.load(
    retentionDays: settings.historyRetentionDays,
  );
  final controller = AppController(settings, historyStore: history);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: controller),
      ],
      child: const LangbaiApp(),
    ),
  );
}
