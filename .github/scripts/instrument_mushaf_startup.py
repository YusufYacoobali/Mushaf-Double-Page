#!/usr/bin/env python3
"""Instrument the CI checkout only; do not modify the committed Flutter app."""
from pathlib import Path
p=Path("lib/main.dart")
s=p.read_text()
def change(needle,replacement):
    global s
    occurrences=s.count(needle)
    if occurrences != 1:
        raise SystemExit(f"Expected one match for {needle!r}, got {occurrences}")
    s=s.replace(needle,replacement,1)

change("void main() async {", "void main() async {\n  print('MUSHAF_BOOT main-enter');")
change("  WidgetsFlutterBinding.ensureInitialized();", "  WidgetsFlutterBinding.ensureInitialized();\n  print('MUSHAF_BOOT bindings-ready');")
change("  unawaited(removeRetiredAudioCache());", "  unawaited(removeRetiredAudioCache());\n  print('MUSHAF_BOOT retired-cache-dispatched');")
change("  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);",
       "  print('MUSHAF_BOOT firebase-start');\n  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);\n  print('MUSHAF_BOOT firebase-done');")
change("  await _initBackgroundAudio();",
       "  print('MUSHAF_BOOT audio-start');\n  await _initBackgroundAudio();\n  print('MUSHAF_BOOT audio-done');")
change("  await ReminderNotifications.initialize();",
       "  print('MUSHAF_BOOT reminders-start');\n  await ReminderNotifications.initialize();\n  print('MUSHAF_BOOT reminders-done');")
change("  runApp(const MyApp());","  print('MUSHAF_BOOT runApp-start');\n  runApp(const MyApp());\n  print('MUSHAF_BOOT runApp-returned');")
change("    await QuranAudioHandler.initialize();", "    print('MUSHAF_BOOT audio-handler-initialize-start');\n    await QuranAudioHandler.initialize();\n    print('MUSHAF_BOOT audio-handler-initialize-done');")
p.write_text(s)
print("Instrumented main.dart for CI only")
