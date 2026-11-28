import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bylwapp/app.dart';
import 'package:bylwapp/ble/bylw_log.dart';
import 'package:bylwapp/ble/flutter_blue_session.dart';
import 'package:bylwapp/ble/ring/ring_parser.dart';
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
  if (!await settings.getRingClockCorrected()) {
    final measurements = await repository.correctRingHistoryClock();
    final events = await _correctJournalRingClock(journal);
    await settings.setRingClockCorrected();
    bylwLog('clock fix measurements=$measurements journal=$events');
  }
  final prefs = CollectorPrefs(
    deviceToken: await settings.getDeviceToken(),
    collectorId: await settings.getCollectorId(),
  );
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
      autoRegister: true,
    ),
  );
}

Future<int> _correctJournalRingClock(JournalStore journal) async {
  final rows = await journal.all();
  var changed = 0;
  for (final row in rows) {
    final event = row.event;
    if (event.sensorKind != 'ring' || event.values['stream'] != 'history') {
      continue;
    }
    final wall = event.wallTimeUtc;
    if (wall == null) continue;
    final stored = DateTime.tryParse(wall)?.toUtc();
    if (stored == null) continue;
    final fixed = correctedRingInstant(stored);
    if (fixed.toUtc() == stored) continue;
    await journal.replace(event.withClock(fixed), pending: false);
    changed++;
  }
  return changed;
}
