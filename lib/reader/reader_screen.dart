import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../app.dart';
import '../components/adaptive_quran_pages.dart';
import '../components/audio_modal.dart';
import '../components/bookmark_modal.dart';
import '../components/nav_bar_icon.dart';
import '../components/reader_audio_controls.dart';
import '../components/reader_dock.dart';
import '../components/translation_modal.dart';
import '../logic/quran_audio_controller.dart';
import '../logic/storage_manager.dart';
import '../models/bookmark.dart';
import '../models/quran_audio.dart';
import '../pages/page_view.dart';
import '../pages/settings.dart';
import '../progress/daily_reading_card.dart';
import '../progress/journey_tracking.dart';
import '../progress/reading_progress_store.dart';
import '../utils/app_motion.dart';
import '../utils/app_palette.dart';
import '../utils/audio_page_follower.dart';
import '../utils/audio_preferences.dart';
import '../utils/audio_vertical_follower.dart';
import '../utils/ayah_rect_index.dart';
import '../utils/ios_device_idiom.dart';
import '../utils/ios_display_regions.dart';
import '../utils/navigator.dart';
import '../utils/page_ayah_index.dart';
import '../utils/page_mapper.dart';
import '../utils/reader_geometry_probe.dart';
import '../utils/reader_highlight_preferences.dart';
import '../utils/reader_layout.dart';
import '../utils/reader_paging.dart';
import '../utils/recent_surah_history.dart';
import '../utils/surah_mapper.dart' as surah_mapper;
import '../utils/surah_summary_manager.dart';
import '../utils/translation_manager.dart';
import '../utils/translation_preferences.dart';

part 'reader_annotations.dart';
part 'reader_overlays.dart';

class MyPDFViewer extends StatefulWidget {
  const MyPDFViewer({super.key, this.audioController});

  final QuranAudioController? audioController;

  @override
  State<MyPDFViewer> createState() => _MyPDFViewerState();
}

class _MyPDFViewerState extends State<MyPDFViewer>
    with WidgetsBindingObserver, _ReaderAnnotations {
  @override
  String _mushaf = 'indopak_tajweed';

  late Directory _docDir;
  ReaderPaging? _paging;

  bool _ready = false;
  bool _isIPad = false;
  StreamSubscription<dynamic>? _displayRegionSubscription;
  bool _androidCoverDock = false;
  IosDisplayRegions _iosDisplayRegions = IosDisplayRegions.fromEvent(null);
  bool _singlePage = true;
  bool _bottomDock = true;
  @override
  bool _ayahHighlightingEnabled = true;
  bool _readerWhite = false;
  bool _controlsArrowOnly = false;
  bool _audioWasActive = false;
  bool _audioFollowScheduled = false;
  final _audioPageFollower = AudioPageFollower();
  late final AudioVerticalFollower _audioVerticalFollower;
  final _readerDockKey = GlobalKey();
  final _readerDockGeometryKey = GlobalKey();
  bool get _readerVisible =>
      mounted &&
      _ready &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);

  double _pageScalePortrait = 0.8;
  double _pageScaleLandscape = 0.7; // slightly smaller to fit side-by-side

  /// 🔑 single source of truth
  @override
  int _logicalPage = 1;

  bool _isScrollbarVisible = true;
  bool _dockPinned = false;
  Timer? _hideScrollbarTimer;

  late RecentSurahHistory _surahHistory;

  // -------------------------
  // Init
  // -------------------------

  @override
  void initState() {
    super.initState();
    _audioVerticalFollower = AudioVerticalFollower(
      canFollow: () => _readerVisible && _audio.audible,
      obstructions: () {
        if (!_isScrollbarVisible && !_dockPinned) return const [];
        final dock = _readerDockGeometryKey.currentContext?.findRenderObject();
        return dock is RenderBox && dock.hasSize && dock.attached
            ? [
                MatrixUtils.transformRect(
                  dock.getTransformTo(null),
                  Offset.zero & dock.size,
                ),
              ]
            : const [];
      },
    );
    // Android owns status-bar visibility in MainActivity, including app resume.
    if (!Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    WidgetsBinding.instance.addObserver(this);
    _audio.addListener(_audioChanged);
    _init();
  }

  Future<void> _init() async {
    // Resolve the native device family before exposing the reader, avoiding
    // a brief two-page iPad layout or a page-mode change after first paint.
    _isIPad = await IosDeviceIdiom.isIPad();
    if (defaultTargetPlatform == TargetPlatform.iOS && !_isIPad) {
      _displayRegionSubscription =
          const EventChannel(
            'mushaf_two_page/display_regions',
          ).receiveBroadcastStream().listen((event) {
            if (mounted) {
              setState(
                () => _iosDisplayRegions = IosDisplayRegions.fromEvent(event),
              );
            }
          }, onError: (Object _) {});
    }
    if (Platform.isAndroid) {
      _displayRegionSubscription =
          const EventChannel(
            'mushaf_two_page/folded_cover',
          ).receiveBroadcastStream().listen(
            (event) {
              if (mounted && _androidCoverDock != (event == true)) {
                setState(() => _androidCoverDock = event == true);
              }
            },
            onError: (Object _) {
              if (mounted && _androidCoverDock) {
                setState(() => _androidCoverDock = false);
              }
            },
          );
    }
    _docDir = await getApplicationDocumentsDirectory();
    _mushaf = await StorageManager.getMushaf();
    _surahHistory = RecentSurahHistory(_mushaf);
    await _surahHistory.load();
    await _loadBookmarks();

    _readerWhite = await StorageManager.getReaderWhiteBackground();
    _controlsArrowOnly = await StorageManager.getControlsArrowOnly();
    _isScrollbarVisible = !_controlsArrowOnly;
    _pageScalePortrait = await StorageManager.getPageScalePortrait();
    _pageScaleLandscape = await StorageManager.getPageScaleLandscape();
    _ayahHighlightingEnabled =
        await StorageManager.getAyahHighlightingEnabled();

    _logicalPage = await StorageManager.getCurrentPage();

    if (!mounted) return;
    _paging = ReaderPaging(initialPage: _logicalPage, lastPage: maxFilePage)
      ..configure(ReaderPageMode.single);

    if (_isScrollbarVisible) _startHideScrollbarTimer();
    await TranslationManager.load();
    await SurahSummaryManager.load();
    await PageAyahIndex.load();
    _recordSurahVisit();
    await AyahRectIndex.load();
    final savedHighlight = await ReaderHighlightPreferences.load(_mushaf);
    if (!mounted) return;
    _restoreHighlight(savedHighlight, maxFilePage);
    setState(() => _ready = true);
    _audioChanged();
    _persistHighlight();
    _recordProgress();
  }

  @override
  void dispose() {
    _welcomeTimer?.cancel();
    _displayRegionSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _audio.removeListener(_audioChanged);
    _audioVerticalFollower.dispose();
    _hideScrollbarTimer?.cancel();
    _paging?.dispose();
    if (!Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _audioVerticalFollower.invalidate();
    if (state == AppLifecycleState.resumed && _ready) _recordProgress();
    if (state != AppLifecycleState.resumed && _ready) _persistHighlight();
  }

  void _recordSurahVisit({int? surah}) {
    if (_surahHistory.visit(
      _firstVisiblePage,
      pagesPerView: _singlePage ? 1 : 2,
      surah: surah,
    )) {
      unawaited(_surahHistory.save());
    }
  }

  void _jumpToReadingPage(int page, {int? surah}) {
    _audioVerticalFollower.invalidate();
    final logical = page.clamp(1, maxFilePage);
    _forgetAyahSelection();
    // A direct jump commits synchronously, including bookmark highlight resume.
    unawaited(_paging!.goTo(logical));
    _didCommitPage(logical, surah: surah);
  }

  void _didCommitPage(int page, {int? surah, bool recordActivity = true}) {
    if (!mounted) return;
    setState(() {
      _logicalPage = page;
      _recordSurahVisit(surah: surah);
    });
    unawaited(StorageManager.saveCurrentPage(page, maxPage: maxFilePage));
    if (recordActivity) unawaited(_recordProgress());
  }

  void _increaseScale() => _adjustScale(0.05);
  void _decreaseScale() => _adjustScale(-0.05);

  void _adjustScale(double delta) {
    _audioVerticalFollower.invalidate();
    setState(() {
      if (_singlePage) {
        _pageScalePortrait = (_pageScalePortrait + delta).clamp(
          QuranPageView.minPageScalePortrait,
          QuranPageView.maxPageScalePortrait,
        );
        StorageManager.savePageScalePortrait(_pageScalePortrait);
      } else {
        _pageScaleLandscape = (_pageScaleLandscape + delta).clamp(
          QuranPageView.minPageScaleLandscape,
          QuranPageView.maxPageScaleLandscape,
        );
        StorageManager.savePageScaleLandscape(_pageScaleLandscape);
      }
    });
  }

  int get maxFilePage {
    if (_mushaf == 'madani') return PageMapper.madaniLastFilePage;
    return PageMapper.indopakLastFilePage;
  }

  int get totalPages {
    return maxFilePage + 1;
  }

  int get _firstVisiblePage => _paging!.pagesFor(_logicalPage).first;

  String imagePath(int logicalPage) {
    final filePage = logicalPage.clamp(1, maxFilePage);
    return '${_docDir.path}/$_mushaf/$filePage.webp';
  }

  // -------------------------
  // UI helpers
  // -------------------------

  void _startHideScrollbarTimer() {
    _hideScrollbarTimer?.cancel();
    if (_dockPinned) return;
    _hideScrollbarTimer = Timer(const Duration(seconds: 10), () {
      // An explicitly hidden dock stays hidden, but the timer must not remove
      // the playback controls while a recitation is running.
      if (_audio.playing) return;
      if (mounted) setState(() => _isScrollbarVisible = false);
    });
  }

  void _onScreenTap() {
    // Clear the selection independently of whether taps can reveal controls.
    if (_selPage != null) {
      if (_dockPinned) {
        setState(_forgetAyahSelection);
      } else {
        setState(_forgetAyahSelection);
        if (_isScrollbarVisible && !_audioWasActive) _startHideScrollbarTimer();
      }
      return;
    }

    if (_controlsArrowOnly || _dockPinned) return;

    setState(() {
      _isScrollbarVisible = !_isScrollbarVisible;
    });

    if (_isScrollbarVisible) {
      _startHideScrollbarTimer();
    } else {
      _hideScrollbarTimer?.cancel();
    }
  }

  void _audioChanged() {
    if (mounted && _ready) {
      final audio = _audio;
      if (audio.hasActivePlayback) {
        _hideScrollbarTimer?.cancel();
        if (!_audioWasActive && !_controlsArrowOnly) {
          _isScrollbarVisible = true;
        }
      } else if (_audioWasActive && _isScrollbarVisible && _selPage == null) {
        _startHideScrollbarTimer();
      }
      _audioWasActive = audio.hasActivePlayback;
      _persistHighlight();
      setState(() {});
      _scheduleAudioPageFollow();
    }
  }

  void _scheduleAudioPageFollow() {
    if (_audioFollowScheduled) return;
    _audioFollowScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _audioFollowScheduled = false;
      final paging = _paging;
      if (!mounted || !_ready || paging == null) return;
      _audioPageFollower.followReader(
        audio: _audio,
        paging: paging,
        vertical: _audioVerticalFollower,
        visible: _readerVisible,
        animate: !AppMotion.reduced(context),
        mushaf: _mushaf,
        onCommit: (page, changedSpread) =>
            _didCommitPage(page, recordActivity: changedSpread),
      );
    });
  }

  void _highlightAyah(int page, int surah, int ayah) {
    if (!_ayahHighlightingEnabled) return;
    if (!_controlsArrowOnly) _hideScrollbarTimer?.cancel();
    setState(() {
      _selPage = page;
      _selSurah = surah;
      _selAyah = ayah;
      if (!_controlsArrowOnly) _isScrollbarVisible = true;
    });
    _persistHighlight();
  }

  /// A tap on either page layout selects the ayah under the finger; a tap away
  /// from Quran text clears the selection or toggles the reader toolbar.
  void _onPageTap(int page, double nx, double ny) {
    if (_ayahHighlightingEnabled && AyahRectIndex.supportsMushaf(_mushaf)) {
      final hit = AyahRectIndex.hitTest(page, nx, ny, mushaf: _mushaf);
      if (hit != null) {
        if (_selPage != null &&
            _selSurah == hit.surah &&
            _selAyah == hit.ayah) {
          _hideScrollbarTimer?.cancel();
          setState(() {
            _forgetAyahSelection();
            if (!_dockPinned) _isScrollbarVisible = false;
          });
          return;
        }
        _highlightAyah(page, hit.surah, hit.ayah);
        return;
      }
    }
    _onScreenTap();
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const Settings()),
    );

    if (!mounted) return;

    await MyApp.of(context)?.reloadTheme();

    _readerWhite = await StorageManager.getReaderWhiteBackground();
    final ayahHighlighting = await StorageManager.getAyahHighlightingEnabled();
    final arrowOnly = await StorageManager.getControlsArrowOnly();
    if (!mounted) return;
    setState(() {
      if (arrowOnly && !_controlsArrowOnly) {
        _isScrollbarVisible = false;
        _hideScrollbarTimer?.cancel();
      }
      _controlsArrowOnly = arrowOnly;
      _ayahHighlightingEnabled = ayahHighlighting;
      if (!ayahHighlighting) {
        _forgetAyahSelection();
      }
    });

    final mushaf = await StorageManager.getMushaf();
    if (!mounted) return;

    if (mushaf != _mushaf) {
      _audioVerticalFollower.invalidate();
      if (_mushaf == 'indopak_tajweed' && mushaf == 'madani') {
        _logicalPage = PageMapper.indoPakToMadani(_logicalPage);
      }

      if (_mushaf == 'madani' && mushaf == 'indopak_tajweed') {
        _logicalPage = PageMapper.madaniToIndoPak(_logicalPage);
      }

      setState(() {
        _mushaf = mushaf;
        _paging!.lastPage = maxFilePage;
        _paging!.configure(_paging!.mode, force: true, focusPage: _logicalPage);
        _forgetAyahSelection();
      });
      _surahHistory = RecentSurahHistory(_mushaf);
      await _surahHistory.load();
      if (!mounted) return;
      _recordSurahVisit();
      await _loadBookmarks();
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final darkMode = MyApp.of(context)?.darkMode ?? false;
    final palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: _readerWhite ? Colors.white : Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final display = View.of(context).display;
          final layout = ReaderLayout.resolve(
            size: constraints.biggest,
            displaySize: display.size / display.devicePixelRatio,
            padding: MediaQuery.paddingOf(context),
            displayFeatures: [
              ...MediaQuery.displayFeaturesOf(context),
              if (!_isIPad) ..._iosDisplayRegions.forSize(constraints.biggest),
            ],
            pageAspectRatio: QuranPageView.aspectRatioForMushaf(_mushaf),
            preserveLegacyIPadPortrait: _isIPad,
            foldedCover: !_isIPad && _iosDisplayRegions.closed,
            androidCoverDock: _androidCoverDock,
            nativeCoverStrip: _iosDisplayRegions.matches(constraints.biggest)
                ? _iosDisplayRegions.coverStrip
                : null,
            coverObstructions: _iosDisplayRegions.coverObstructions,
            iosPhoneWidePortrait:
                Theme.of(context).platform == TargetPlatform.iOS && !_isIPad,
          );
          final pinned = layout.foldedDockRegion != null;
          if (_dockPinned != pinned) {
            _dockPinned = pinned;
            if (pinned) {
              _hideScrollbarTimer?.cancel();
            } else if (_isScrollbarVisible &&
                _selPage == null &&
                !_audioWasActive) {
              _startHideScrollbarTimer();
            }
          }
          _paging!.configure(layout.pageMode);
          _singlePage = layout.singlePage;
          _bottomDock = layout.bottomDock;
          _logicalPage = _paging!.focusedPage;
          final audioControls = _readerAudioControls(palette);
          final overlay = layout.controlsRegion;
          return ReaderActivity(
            layoutIdentity: layout.pageMode,
            pages: [
              for (final p in _paging!.visiblePages)
                if (PageAyahIndex.surahsOnPage(p, mushaf: _mushaf).isNotEmpty)
                  '$_mushaf:$p',
            ],
            child: ReaderGeometryProbe(
              layout: layout,
              zoom: layout.singlePage
                  ? _pageScalePortrait
                  : _pageScaleLandscape,
              focusedPage: _paging!.focusedPage,
              visiblePages: _paging!.visiblePages,
              edition: _mushaf,
              navigationKey: _readerDockGeometryKey,
              native: _iosDisplayRegions,
              isIPad: _isIPad,
              settled: () => _paging!.settled,
              child: Stack(
                children: [
                  AdaptiveQuranPages(
                    verticalFollower: _audioVerticalFollower,
                    mushaf: _mushaf,
                    paging: _paging!,
                    layout: layout,
                    singleScale: _pageScalePortrait,
                    spreadScale: _pageScaleLandscape,
                    imagePath: imagePath,
                    isDarkMode: darkMode,
                    aspectRatio: QuranPageView.aspectRatioForMushaf(_mushaf),
                    highlightFor: _highlightFor,
                    highlightColor: palette.accent.withValues(alpha: .26),
                    onTap: _onPageTap,
                    onBackgroundTap: _onScreenTap,
                    onFocus: (page) => _didCommitPage(
                      page,
                      surah: PageAyahIndex.surahsOnPage(
                        page,
                        mushaf: _mushaf,
                      ).firstOrNull,
                      recordActivity: false,
                    ),
                    onPageChanged: _didCommitPage,
                  ),
                  Positioned.fromRect(
                    rect: overlay.deflate(16),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 480,
                          maxHeight: overlay.height * .5,
                        ),
                        child: MotionSwitcher(
                          alignment: Alignment.topCenter,
                          offset: const Offset(0, -.12),
                          child: _dailyWelcome == null
                              ? const SizedBox.shrink(
                                  key: ValueKey('no-welcome'),
                                )
                              : DailyReadingCard(
                                  key: const ValueKey('daily-welcome'),
                                  streak: _dailyWelcome!.streak,
                                  compact: true,
                                  onClose: () =>
                                      setState(() => _dailyWelcome = null),
                                ),
                        ),
                      ),
                    ),
                  ),
                  ReaderDockOverlay(
                    layout: layout,
                    child: ReaderDock(
                      key: _readerDockKey,
                      geometryKey: _readerDockGeometryKey,
                      contextControls:
                          audioControls ??
                          (_selPage == null
                              ? null
                              : _buildAyahContextRow(palette)),
                      placement: layout.dockPlacement,
                      expanded: pinned || _isScrollbarVisible,
                      pinned: pinned,
                      onToggle: () {
                        setState(
                          () => _isScrollbarVisible = !_isScrollbarVisible,
                        );
                        if (_isScrollbarVisible) _startHideScrollbarTimer();
                      },
                      palette: palette,
                      zoom: _readerZoom(palette),
                      actions: _readerActions(palette),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
