import 'package:flutter/material.dart';

import 'logic/quran_audio_controller.dart';
import 'logic/storage_manager.dart';
import 'models/quran_audio.dart';
import 'pages/loading.dart';
import 'progress/app_time_tracker.dart';
import 'utils/app_palette.dart';
import 'utils/app_review.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<MyAppState>();

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _darkMode = false;
  bool _appDarkMode = false;
  bool _loaded = false;

  bool get darkMode => _darkMode;
  bool get appDarkMode => _appDarkMode;

  @override
  void initState() {
    super.initState();
    AppTimeTracker.instance.start();
    AppReview.schedulePromptAfterOpen(
      () => _navigatorKey.currentContext,
      canShowPrompt: () =>
          _loaded &&
          AppReview.navigatorObserver.currentPageName == '/reader' &&
          _navigatorKey.currentState?.canPop() == false &&
          !QuranAudioController.instance.preparing &&
          QuranAudioController.instance.phase !=
              QuranPlaybackPhase.recovering &&
          QuranAudioController.instance.phase != QuranPlaybackPhase.buffering &&
          !QuranAudioController.instance.offlineDownloading &&
          QuranAudioController.instance.error == null,
    );
    _loadTheme();
  }

  @override
  void dispose() {
    AppReview.cancelScheduledPrompt();
    AppTimeTracker.instance.dispose();
    super.dispose();
  }

  Future<void> _loadTheme() async {
    _darkMode = await StorageManager.getDarkMode();
    _appDarkMode = await StorageManager.getAppDarkMode();
    setState(() => _loaded = true);
  }

  Future<void> reloadTheme() async {
    final dark = await StorageManager.getDarkMode();
    final appDark = await StorageManager.getAppDarkMode();
    setState(() {
      _darkMode = dark;
      _appDarkMode = appDark;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox();

    return MaterialApp(
      navigatorKey: _navigatorKey,
      navigatorObservers: [AppReview.navigatorObserver],
      debugShowCheckedModeBanner: false,
      theme: AppPalette.forTheme(
        mushafDark: _darkMode,
        appDark: _appDarkMode,
      ).toThemeData(),
      home: const LoadingScreen(),
    );
  }
}
