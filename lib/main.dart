import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'logic/quran_audio_handler.dart';
import 'utils/deferred_reminders.dart';
import 'utils/reminder_notifications.dart';
import 'utils/retired_audio_cache.dart';

export 'app.dart' show MyApp, MyAppState;
export 'reader/reader_screen.dart' show MyPDFViewer;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(removeRetiredAudioCache());
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _initBackgroundAudio();
  // Never await optional notification setup before Flutter's first frame.
  // On iOS 27 its plugin initialization can wait indefinitely for a scene or
  // permissions; previously this trapped the app on the launch storyboard.
  runApp(const MyApp());
  scheduleDeferredReminders(ReminderNotifications.initialize);
}

Future<void> _initBackgroundAudio() async {
  try {
    await QuranAudioHandler.initialize();
  } on MissingPluginException {
    // Plugin not yet registered — requires a fresh build after adding audio deps.
  }
}
