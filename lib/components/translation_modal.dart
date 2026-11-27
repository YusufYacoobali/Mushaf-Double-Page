import 'package:flutter/material.dart';

import '../utils/app_motion.dart';
import '../utils/app_palette.dart';
import '../utils/page_ayah_index.dart';
import '../utils/surah_mapper.dart';
import '../utils/tafseer_manager.dart';
import '../utils/translation_manager.dart';
import '../utils/translation_preferences.dart';
import 'adaptive_surface.dart';
import 'translation/surah_summary_sheet.dart';
import 'translation/translation_ayah_row.dart';
import 'translation/translation_content.dart';
import 'translation/translation_settings_sheet.dart';

class TranslationModal extends StatefulWidget {
  final int logicalPage;
  final String mushaf;

  /// Physical pages shown together in the reader (2 in landscape spreads, else
  /// 1). The modal aggregates translation for the whole view.
  final int pagesPerView;

  /// Currently bookmarked ayahs as `'surah:ayah'` keys, and a callback to
  /// toggle one (add == true to add, false to remove).
  final Set<String> bookmarkedAyahs;
  final void Function(int surah, int ayah, int page, bool add)?
  onToggleAyahBookmark;

  /// Optional ayah opened from a reader-page selection. Its card is emphasised
  /// and scrolled into view once the page data has loaded.
  final int? focusSurah;
  final int? focusAyah;

  const TranslationModal({
    super.key,
    required this.logicalPage,
    required this.mushaf,
    this.pagesPerView = 1,
    this.bookmarkedAyahs = const {},
    this.onToggleAyahBookmark,
    this.focusSurah,
    this.focusAyah,
  }) : assert(
         (focusSurah == null) == (focusAyah == null),
         'focusSurah and focusAyah must be supplied together',
       );

  static void show(
    BuildContext context, {
    required int logicalPage,
    required String mushaf,
    int pagesPerView = 1,
    Set<String> bookmarkedAyahs = const {},
    void Function(int surah, int ayah, int page, bool add)?
    onToggleAyahBookmark,
    int? focusSurah,
    int? focusAyah,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TranslationModal(
          logicalPage: logicalPage,
          mushaf: mushaf,
          pagesPerView: pagesPerView,
          bookmarkedAyahs: bookmarkedAyahs,
          onToggleAyahBookmark: onToggleAyahBookmark,
          focusSurah: focusSurah,
          focusAyah: focusAyah,
        ),
      ),
    );
  }

  @override
  State<TranslationModal> createState() => _TranslationModalState();
}

class _TranslationModalState extends State<TranslationModal> {
  TranslationPreferencesData _preferences = const TranslationPreferencesData(
    translations: ['Saheeh International'],
    tafseers: ['Tafseer Ibn Kathir'],
    showArabic: true,
    fontSize: 'Medium',
    arabicScript: 'uthmani',
  );
  bool _loading = true;
  List<TranslationEntry> _items = [];
  final Set<int> _collapsedSurahs = {};
  final Set<String> _collapsedTrans = {};
  final Set<String> _collapsedTafseers = {};
  final Set<String> _bookmarkedAyahs = {}; // 'surah:ayah' keys
  final _scrollController = ScrollController();
  final _focusedAyahKey = GlobalKey();
  final _translationsSeen = <String>{};

  // Page mode (Indo-Pak): show exactly the ayahs printed on the current view.
  // The view is one page in portrait, or a two-page spread in landscape, with
  // [_logicalPage] as its first (lowest-numbered) page.
  late bool _pageMode;
  late String _mushaf;
  late int _logicalPage;
  late int _pagesPerView;

  // Surah mode (fallback for mushafs without a layout map): paginate one surah.
  int _currentPage = 0;
  static const int _pageSize = 20;
  late SurahRange _activeSurah;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<TranslationAyah> get _allAyahs =>
      _items.whereType<TranslationAyah>().toList();

  int get _totalPages => (_allAyahs.length / _pageSize).ceil().clamp(1, 99999);

  /// The list rendered by the builder (headers + ayahs), honouring collapsed
  /// surahs. In page mode `_items` already holds just the current page.
  List<TranslationEntry> get _visibleItems {
    if (_pageMode) {
      return [
        for (final item in _items)
          if (item is! TranslationAyah ||
              !_collapsedSurahs.contains(item.surah))
            item,
      ];
    }
    final ayahs = _allAyahs;
    final start = _currentPage * _pageSize;
    if (start >= ayahs.length) return [];
    return [
      TranslationHeader(_activeSurah),
      if (!_collapsedSurahs.contains(_activeSurah.surah))
        ...ayahs.skip(start).take(_pageSize),
    ];
  }

  @override
  void initState() {
    super.initState();
    _mushaf = widget.mushaf;
    _logicalPage = widget.logicalPage;
    _pagesPerView = widget.pagesPerView;
    _bookmarkedAyahs.addAll(widget.bookmarkedAyahs);
    _pageMode = PageAyahIndex.supportsMushaf(_mushaf);
    final ranges = getSurahRanges(_mushaf);
    final surahs = _pageMode
        ? [
            for (final surah in PageAyahIndex.surahsOnPage(
              _logicalPage,
              mushaf: _mushaf,
            ))
              ranges.firstWhere((range) => range.surah == surah),
          ]
        : surahsFromLogicalPage(_logicalPage, _mushaf);
    _activeSurah = surahs.isNotEmpty
        ? surahs.first
        : ranges.firstWhere((r) => r.surah >= 1, orElse: () => ranges.first);
    _initFromPrefs();
  }

  Future<void> _initFromPrefs() async {
    final preferences = await TranslationPreferences.load();
    final translations = preferences.translations
        .where(TranslationManager.sources.containsKey)
        .toList();
    if (translations.isEmpty) translations.add('Saheeh International');
    final tafseers = preferences.tafseers
        .where(TafseerManager.sources.containsKey)
        .toList();

    _preferences = TranslationPreferencesData(
      translations: translations,
      tafseers: tafseers,
      showArabic: preferences.showArabic,
      fontSize: preferences.fontSize,
      arabicScript: preferences.arabicScript,
    );
    await PageAyahIndex.load();
    _pageMode = PageAyahIndex.supportsMushaf(_mushaf);
    _load();
  }

  Future<void> _load({int? restorePage}) async {
    if (!mounted) return;
    setState(() => _loading = true);

    final loader = TranslationContentLoader(_preferences);
    final items = _pageMode
        ? await loader.loadPage(_mushaf, _viewPages)
        : await loader.loadSurah(_activeSurah);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
      if (!_pageMode) {
        _currentPage = restorePage != null
            ? restorePage.clamp(0, (_allAyahs.length / _pageSize).ceil() - 1)
            : 0;
      }
    });
    _positionAfterLoad();
  }

  /// Logical pages making up the current view (1 in portrait, up to 2 in a
  /// landscape spread), dropping any with no ayahs (e.g. a trailing cover page).
  List<int> get _viewPages {
    final pages = <int>[];
    for (var i = 0; i < _pagesPerView; i++) {
      final p = _logicalPage + i;
      if (PageAyahIndex.segmentsForPage(p, mushaf: _mushaf).isNotEmpty) {
        pages.add(p);
      }
    }
    return pages.isEmpty ? [_logicalPage] : pages;
  }

  /// Segments across the whole view, merged per surah so an ayah straddling a
  /// page break appears once.
  List<List<int>> _viewSegments() =>
      PageAyahIndex.segmentsForPages(_viewPages, mushaf: _mushaf);

  SurahRange _rangeForSurah(int surah) {
    final ranges = getSurahRanges(_mushaf);
    return ranges.firstWhere(
      (r) => r.surah == surah,
      orElse: () => ranges.first,
    );
  }

  /// Surah shown in the app-bar title (first surah in the view in page mode).
  SurahRange get _headerSurah {
    if (_pageMode) {
      final segs = _viewSegments();
      if (segs.isNotEmpty) return _rangeForSurah(segs.first[0]);
    }
    return _activeSurah;
  }

  void _showSummary(SurahRange surah) {
    showModalBottomSheet(
      sheetAnimationStyle: AppMotion.style(context),
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          SurahSummarySheet(surah: surah, fontSize: _preferences.fontSize),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      sheetAnimationStyle: AppMotion.style(context),
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TranslationSettingsSheet(
        initial: _preferences,
        onApply: (value) {
          final page = _currentPage;
          setState(() => _preferences = value);
          TranslationPreferences.save(value);
          _load(restorePage: page);
        },
      ),
    );
  }

  void _showSurahPicker() {
    final all = getSurahRanges(_mushaf).where((s) => s.surah >= 1).toList();
    final currentSurahs = _pageMode
        ? _viewSegments().map((s) => s[0]).toSet()
        : {_activeSurah.surah};
    final palette = AppPalette.of(context);
    showModalBottomSheet(
      sheetAnimationStyle: AppMotion.style(context),
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.78,
          decoration: BoxDecoration(
            color: palette.scaffold,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
                  children: [
                    Text(
                      'Select Surah',
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: palette.border),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: all.length,
                  itemBuilder: (_, i) {
                    final s = all[i];
                    final active = currentSurahs.contains(s.surah);
                    return ListTile(
                      onTap: () {
                        Navigator.pop(context);
                        // The top selector is a strict single-surah selector.
                        // Page mode may initially contain several surahs when
                        // they are genuinely printed in the current view, but
                        // choosing here must not inherit neighbouring surahs
                        // from the selected surah's first printed page.
                        setState(() {
                          _pageMode = false;
                          _activeSurah = s;
                          _currentPage = 0;
                          _collapsedSurahs.clear();
                        });
                        _load();
                      },
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: active ? palette.accent : palette.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: active ? palette.accent : palette.border,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '${s.surah}',
                            style: TextStyle(
                              color: active ? palette.onAccent : palette.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        s.name,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 15,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        s.english,
                        style: TextStyle(color: palette.muted, fontSize: 12),
                      ),
                      trailing: active
                          ? Icon(
                              Icons.check_rounded,
                              color: palette.accent,
                              size: 18,
                            )
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPageNav(AppPalette palette) {
    final String title;
    final String subtitle;
    final bool onFirst;
    final bool onLast;
    if (_pageMode) {
      final view = _viewPages;
      final firstPrinted = PageAyahIndex.printedPage(view.first);
      final lastPrinted = PageAyahIndex.printedPage(view.last);
      onFirst = _logicalPage <= PageAyahIndex.firstContentPageFor(_mushaf);
      onLast = view.last >= PageAyahIndex.lastContentPageFor(_mushaf);
      title = firstPrinted == lastPrinted
          ? 'Page $firstPrinted of ${PageAyahIndex.totalPrintedPagesFor(_mushaf)}'
          : 'Pages $firstPrinted–$lastPrinted of ${PageAyahIndex.totalPrintedPagesFor(_mushaf)}';
      subtitle = _pageSubtitle();
    } else {
      final ayahCount = _allAyahs.length;
      onFirst = _currentPage == 0;
      onLast = (_currentPage + 1) * _pageSize >= ayahCount;
      final displayStart = _currentPage * _pageSize + 1;
      final displayEnd = ((_currentPage + 1) * _pageSize).clamp(0, ayahCount);
      title = 'Page ${_currentPage + 1} of $_totalPages';
      subtitle = '$displayStart-$displayEnd of $ayahCount ayahs';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: palette.scaffold,
        border: Border(
          top: BorderSide(color: palette.border.withValues(alpha: .6)),
        ),
      ),
      child: Row(
        children: [
          _navBtn(Icons.chevron_left_rounded, !onLast, _goToNextPage, palette),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          _navBtn(
            Icons.chevron_right_rounded,
            !onFirst,
            _goToPreviousPage,
            palette,
          ),
        ],
      ),
    );
  }

  /// One-line summary of the surah(s) and ayah range in the current view.
  String _pageSubtitle() {
    final segs = _viewSegments();
    return segs
        .map((seg) {
          final name = _rangeForSurah(seg[0]).name;
          final range = seg[1] == seg[2] ? '${seg[1]}' : '${seg[1]}–${seg[2]}';
          return '$name $range';
        })
        .join('   •   ');
  }

  void _goToNextPage() {
    if (_pageMode) {
      if (_viewPages.last >= PageAyahIndex.lastContentPageFor(_mushaf)) return;
      setState(() => _logicalPage += _pagesPerView);
      _load();
      return;
    }
    final ayahCount = _allAyahs.length;
    final next = _currentPage + 1;
    if (next * _pageSize >= ayahCount) return;
    setState(() => _currentPage = next);
    _scrollToTop();
  }

  void _goToPreviousPage() {
    if (_pageMode) {
      if (_logicalPage <= PageAyahIndex.firstContentPageFor(_mushaf)) return;
      setState(
        () => _logicalPage = (_logicalPage - _pagesPerView).clamp(
          PageAyahIndex.firstContentPageFor(_mushaf),
          PageAyahIndex.lastContentPageFor(_mushaf),
        ),
      );
      _load();
      return;
    }
    if (_currentPage == 0) return;
    setState(() => _currentPage--);
    _scrollToTop();
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  int get _focusedItemIndex {
    final focusSurah = widget.focusSurah;
    final focusAyah = widget.focusAyah;
    if (focusSurah == null || focusAyah == null) return -1;
    return _visibleItems.indexWhere(
      (item) =>
          item is TranslationAyah &&
          item.surah == focusSurah &&
          item.ayah == focusAyah,
    );
  }

  void _positionAfterLoad() {
    if (_focusedItemIndex < 0) {
      _scrollToTop();
      return;
    }
    _scrollToFocusedAyah();
  }

  void _scrollToFocusedAyah([int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focusedContext = _focusedAyahKey.currentContext;
      if (focusedContext != null) {
        Scrollable.ensureVisible(
          focusedContext,
          alignment: .08,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
        return;
      }
      if (attempt >= 3 || !_scrollController.hasClients) return;

      final index = _focusedItemIndex;
      final itemCount = _visibleItems.length;
      if (index < 0 || itemCount < 2) return;
      final target =
          _scrollController.position.maxScrollExtent * index / (itemCount - 1);
      _scrollController.jumpTo(
        target.clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        ),
      );
      _scrollToFocusedAyah(attempt + 1);
    });
  }

  Widget _navBtn(
    IconData icon,
    bool enabled,
    VoidCallback onTap,
    AppPalette palette,
  ) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: enabled
              ? palette.accent.withValues(alpha: .12)
              : palette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled
                ? palette.accent.withValues(alpha: .35)
                : palette.border,
          ),
        ),
        child: Icon(
          icon,
          color: enabled ? palette.accent : palette.muted.withValues(alpha: .4),
          size: 22,
        ),
      ),
    );
  }

  void _toggleAyahBookmark(int surah, int ayah) {
    final key = '$surah:$ayah';
    final adding = !_bookmarkedAyahs.contains(key);
    setState(() {
      if (adding) {
        _bookmarkedAyahs.add(key);
      } else {
        _bookmarkedAyahs.remove(key);
      }
    });
    final page = _pageMode
        ? (PageAyahIndex.pageOfAyah(surah, ayah, mushaf: _mushaf) ??
              _logicalPage)
        : pageFromSurah(surah, _mushaf);
    widget.onToggleAyahBookmark?.call(surah, ayah, page, adding);
  }

  // Adds/removes a key from a Set and triggers a rebuild.
  void _toggle<T>(Set<T> set, T key) {
    setState(() {
      if (set.contains(key)) {
        set.remove(key);
      } else {
        set.add(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      AdaptiveSurface(child: Builder(builder: _buildScaffold));

  Widget _buildScaffold(BuildContext context) {
    final palette = AppPalette.of(context);

    final items = _visibleItems;
    return Scaffold(
      backgroundColor: palette.scaffold,
      appBar: AppBar(
        toolbarHeight:
            (MediaQuery.textScalerOf(context).scale(20) +
                    MediaQuery.textScalerOf(context).scale(12) +
                    16)
                .clamp(56.0, 104.0),
        backgroundColor: palette.scaffold,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: palette.muted),
        title: GestureDetector(
          onTap: _showSurahPicker,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _headerSurah.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _headerSurah.english,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: palette.muted,
                size: 20,
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            onPressed: _showSettings,
            icon: Icon(Icons.tune_rounded, color: palette.muted, size: 22),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? Center(
                child: CircularProgressIndicator(
                  color: palette.accent,
                  strokeWidth: 2.5,
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragEnd: (details) {
                        final velocity = details.primaryVelocity ?? 0;
                        if (velocity < -200) {
                          _goToNextPage();
                        } else if (velocity > 200) {
                          _goToPreviousPage();
                        }
                      },
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        interactive: true,
                        radius: const Radius.circular(10),
                        thickness: 6,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 22),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];

                            if (item case TranslationHeader(:final range)) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 4,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: palette.accent,
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            range.name,
                                            style: TextStyle(
                                              color: palette.text,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 1),
                                          Text(
                                            range.english,
                                            style: TextStyle(
                                              color: palette.muted,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => _showSummary(range),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: palette.accentSoft,
                                          borderRadius: BorderRadius.circular(
                                            99,
                                          ),
                                          border: Border.all(
                                            color: palette.accent.withValues(
                                              alpha: .2,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.info_outline_rounded,
                                              size: 13,
                                              color: palette.accent,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Summary',
                                              style: TextStyle(
                                                color: palette.accent,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    GestureDetector(
                                      onTap: () => _toggle(
                                        _collapsedSurahs,
                                        range.surah,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.all(5),
                                        decoration: BoxDecoration(
                                          color: palette.surface,
                                          borderRadius: BorderRadius.circular(
                                            99,
                                          ),
                                          border: Border.all(
                                            color: palette.border,
                                          ),
                                        ),
                                        child: Icon(
                                          _collapsedSurahs.contains(range.surah)
                                              ? Icons
                                                    .keyboard_arrow_down_rounded
                                              : Icons.keyboard_arrow_up_rounded,
                                          size: 16,
                                          color: palette.muted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final ayah = item as TranslationAyah;
                            final isFocused =
                                ayah.surah == widget.focusSurah &&
                                ayah.ayah == widget.focusAyah;
                            return TranslationAyahRow(
                              key: isFocused ? _focusedAyahKey : null,
                              item: ayah,
                              preferences: _preferences,
                              first:
                                  index == 0 ||
                                  items[index - 1] is TranslationHeader,
                              last:
                                  index == items.length - 1 ||
                                  items[index + 1] is TranslationHeader,
                              isFocused: isFocused,
                              isBookmarked: _bookmarkedAyahs.contains(
                                '${ayah.surah}:${ayah.ayah}',
                              ),
                              translationsSeen: _translationsSeen,
                              collapsedTranslations: _collapsedTrans,
                              collapsedTafseers: _collapsedTafseers,
                              onBookmark: () =>
                                  _toggleAyahBookmark(ayah.surah, ayah.ayah),
                              onToggleTranslation: (key) =>
                                  _toggle(_collapsedTrans, key),
                              onToggleTafseer: (key) =>
                                  _toggle(_collapsedTafseers, key),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  _buildPageNav(palette),
                ],
              ),
      ),
    );
  }
}
