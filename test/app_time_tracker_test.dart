import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mushaf_two_page/progress/app_time_tracker.dart';
import 'package:mushaf_two_page/progress/journey_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'foreground time spans routes and excludes every inactive lifecycle state',
    () async {
      var elapsed = Duration.zero;
      final tracker = AppTimeTracker(elapsed: () => elapsed);
      addTearDown(tracker.dispose);
      tracker.start();
      tracker.didChangeAppLifecycleState(AppLifecycleState.resumed);
      elapsed = const Duration(milliseconds: 5600);
      await tracker.flush();
      expect((await JourneyStore.load()).appSeconds, 5);
      tracker
          .start(); // A rebuild/repeated initialization cannot reset or duplicate time.
      tracker.didChangeAppLifecycleState(AppLifecycleState.inactive);
      elapsed += const Duration(minutes: 10);
      tracker.didChangeAppLifecycleState(AppLifecycleState.hidden);
      elapsed += const Duration(minutes: 10);
      tracker.didChangeAppLifecycleState(AppLifecycleState.paused);
      elapsed += const Duration(minutes: 10);
      tracker.didChangeAppLifecycleState(AppLifecycleState.resumed);
      elapsed += const Duration(milliseconds: 1400);
      await tracker.flush();
      expect((await JourneyStore.load()).appSeconds, 7);
      await tracker.flush();
      expect((await JourneyStore.load()).appSeconds, 7);
      elapsed += const Duration(seconds: 3);
      tracker.dispose();
      expect((await JourneyStore.load()).appSeconds, 10);
    },
  );

  test(
    'new app total never substitutes reading or background listening time',
    () async {
      await JourneyStore.recordTime(reading: 300, listening: 900);
      expect((await JourneyStore.load()).appSeconds, 0);
      var elapsed = Duration.zero;
      final tracker = AppTimeTracker(elapsed: () => elapsed);
      addTearDown(tracker.dispose);
      tracker.start();
      tracker.didChangeAppLifecycleState(AppLifecycleState.resumed);
      elapsed = const Duration(seconds: 20);
      await tracker.flush();
      final stats = await JourneyStore.load();
      expect(stats.appSeconds, 20);
      expect(stats.readingSeconds, 300);
      expect(stats.listeningSeconds, 900);
    },
  );
}
