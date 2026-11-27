import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bylwapp/app.dart';
import 'package:bylwapp/ble/flutter_blue_session.dart';
import 'package:bylwapp/data/sqlite_health_repository.dart';
import 'package:bylwapp/journal/journal_store.dart';
import 'package:bylwapp/reminders/reminder_engine.dart';
import 'package:bylwapp/screens/study_screens.dart';
import 'package:bylwapp/settings/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  final repository = await SqliteHealthRepository.open();
  final settings = await SharedPreferencesSettingsStore.open();
  final journal = await JournalStore.open();
  final prefs = CollectorPrefs();
  final study = StudyBundle(
    journal: journal,
    prefs: prefs,
    engine: ReminderEngine(),
    sessionId: 'sess-app',
  );
  runApp(
    BylwApp(
      repository: repository,
      settings: settings,
      ble: FlutterBlueSession(),
      study: study,
      prefs: prefs,
    ),
  );
}
