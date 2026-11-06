import '../progress/journey_tracking.dart';
import 'package:mushaf_two_page/utils/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/translation_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/surah_mapper.dart';
import '../utils/translation_manager.dart';
import '../utils/tafseer_manager.dart';
import '../utils/surah_summary_manager.dart';
import '../utils/arabic_text_manager.dart';
import '../utils/page_ayah_index.dart';
import '../utils/quran_arabic_style.dart';

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
  final List<String> _selectedTrans = ['Saheeh International'];
  final List<String> _selectedTafseer = ['Tafseer Ibn Kathir'];
  bool _showArabic = true;
  String _fontSize = 'Medium';
  String _arabicScript = 'uthmani';
  bool _loading = true;
  List<dynamic> _items = [];
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

  List<Map> get _allAyahs => _items.whereType<Map>().toList();

  int get _totalPages => (_allAyahs.length / _pageSize).ceil().clamp(1, 99999);

  /// The list rendered by the builder (headers + ayahs), honouring collapsed
  /// surahs. In page mode `_items` already holds just the current page.
  List<dynamic> get _visibleItems {
    if (!_pageMode) return _pageContent;
    final out = <dynamic>[];
    for (final it in _items) {
      if (it is SurahRange) {
        out.add(it);
      } else if (!_collapsedSurahs.contains((it as Map)['surah'] as int)) {
        out.add(it);
      }
    }
    return out;
  }

  List<dynamic> get _pageContent {
    final ayahs = _allAyahs;
    final start = _currentPage * _pageSize;
    if (start >= ayahs.length) return [];
    final end = (start + _pageSize).clamp(0, ayahs.length);
    final result = <dynamic>[];
    bool headerAdded = false;
    for (final ayah in ayahs.sublist(start, end)) {
      final surahNum = ayah['surah'] as int;
      if (!headerAdded) {
        result.add(_activeSurah);
        headerAdded = true;
      }
      if (!_collapsedSurahs.contains(surahNum)) {
        result.add(ayah);
      }
    }
    return result;
  }

  static const Map<String, ({double arabic, double trans, double tafseer})>
  _fontSizeMap = {
    'Small': (arabic: 18.0, trans: 13.0, tafseer: 13.0),
    'Medium': (arabic: 22.0, trans: 16.0, tafseer: 16.0),
    'Large': (arabic: 26.0, trans: 19.0, tafseer: 19.0),
  };

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
    _selectedTrans
      ..clear()
      ..addAll(translations);
    _selectedTafseer
      ..clear()
      ..addAll(tafseers);
    _showArabic = preferences.showArabic;
    _fontSize = preferences.fontSize;
    _arabicScript = preferences.arabicScript;
    await PageAyahIndex.load();
    _pageMode = PageAyahIndex.supportsMushaf(_mushaf);
    _load();
  }

  Future<void> _savePrefs() async {
    await TranslationPreferences.save(
      TranslationPreferencesData(
        translations: List<String>.from(_selectedTrans),
        tafseers: List<String>.from(_selectedTafseer),
        showArabic: _showArabic,
        fontSize: _fontSize,
        arabicScript: _arabicScript,
      ),
    );
  }

  Future<void> _load({int? restorePage}) async {
    if (!mounted) return;
    setState(() => _loading = true);

    for (final src in _selectedTrans) {
      await TranslationManager.loadSource(src);
    }

    final items = _pageMode
        ? await _buildPageItems()
        : await _buildSurahItems();

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

  /// Build the items for the ayahs printed across the current view. A view can
  /// span the tail of one surah and the start of the next, so we group by surah
  /// and emit a header whenever the surah changes.
  Future<List<dynamic>> _buildPageItems() async {
    final segments = _viewSegments();
    final surahNums = segments.map((s) => s[0]).toSet();

    // Each surah's data is fetched once; the managers cache per surah.
    final transBySurah = <int, Map<String, Map<int, String>>>{};
    final tafseerBySurah = <int, Map<String, Map<int, String>>>{};
    final arabicBySurah = <int, Map<int, String>>{};
    for (final s in surahNums) {
      final t = <String, Map<int, String>>{};
      for (final src in _selectedTrans) {
        t[src] = TranslationManager.getSurah(s, source: src);
      }
      transBySurah[s] = t;
      final tf = <String, Map<int, String>>{};
      for (final src in _selectedTafseer) {
        tf[src] = await TafseerManager.getSurah(s, src);
      }
      tafseerBySurah[s] = tf;
      arabicBySurah[s] = await ArabicTextManager.getSurah(
        s,
        source: _arabicScript,
      );
    }

    final items = <dynamic>[];
    int? lastSurah;
    for (final seg in segments) {
      final s = seg[0];
      if (s != lastSurah) {
        items.add(_rangeForSurah(s));
        lastSurah = s;
      }
      for (int a = seg[1]; a <= seg[2]; a++) {
        final trans = <String, String>{};
        for (final src in _selectedTrans) {
          trans[src] = transBySurah[s]![src]?[a] ?? '';
        }
        final tafseer = <String, String>{};
        for (final src in _selectedTafseer) {
          tafseer[src] = tafseerBySurah[s]![src]?[a] ?? '';
        }
        items.add({
          'surah': s,
          'ayah': a,
          'trans': trans,
          'tafseer': tafseer,
          'arabic': arabicBySurah[s]?[a] ?? '',
        });
      }
    }
    return items;
  }

  /// Build the items for the whole active surah (fallback for mushafs without a
  /// page layout map). The list is chunked into pages of [_pageSize] for display.
  Future<List<dynamic>> _buildSurahItems() async {
    final items = <dynamic>[];
    final surah = _activeSurah;
    items.add(surah);

    final transData = <String, Map<int, String>>{};
    for (final src in _selectedTrans) {
      transData[src] = TranslationManager.getSurah(surah.surah, source: src);
    }
    final tafseerData = <String, Map<int, String>>{};
    for (final src in _selectedTafseer) {
      tafseerData[src] = await TafseerManager.getSurah(surah.surah, src);
    }
    final arabicData = await ArabicTextManager.getSurah(
      surah.surah,
      source: _arabicScript,
    );

    final ayahs = (transData[_selectedTrans.first] ?? {}).keys.toList()..sort();
    for (final ayah in ayahs) {
      final trans = <String, String>{};
      for (final src in _selectedTrans) {
        trans[src] = transData[src]?[ayah] ?? '';
      }
      final tafseer = <String, String>{};
      for (final src in _selectedTafseer) {
        tafseer[src] = tafseerData[src]?[ayah] ?? '';
      }
      items.add({
        'surah': surah.surah,
        'ayah': ayah,
        'trans': trans,
        'tafseer': tafseer,
        'arabic': arabicData[ayah] ?? '',
      });
    }
    return items;
  }

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
      builder: (_) => _SummarySheet(surah: surah, fontSize: _fontSize),
    );
  }

  void _showSettings() {
    final tempTrans = List<String>.from(_selectedTrans);
    final tempTafseer = List<String>.from(_selectedTafseer);
    var tempShowArabic = _showArabic;
    var tempFontSize = _fontSize;
    var tempArabicScript = _arabicScript;

    showModalBottomSheet(
      sheetAnimationStyle: AppMotion.style(context),
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final palette = AppPalette.of(context);
        return StatefulBuilder(
          builder: (ctx, setS) {
            void persistSourceSelections() {
              TranslationPreferences.saveSourceSelections(
                translations: List<String>.from(tempTrans),
                tafseers: List<String>.from(tempTafseer),
              ).ignore();
            }

            void toggleTrans(String src) {
              setS(() {
                if (tempTrans.contains(src)) {
                  if (tempTrans.length > 1) tempTrans.remove(src);
                } else {
                  tempTrans.add(src);
                }
              });
              persistSourceSelections();
            }

            void toggleTafseer(String src) {
              setS(() {
                tempTafseer.contains(src)
                    ? tempTafseer.remove(src)
                    : tempTafseer.add(src);
              });
              persistSourceSelections();
            }

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.88,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: palette.scaffold,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: palette.border,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Text(
                            'Sources',
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              final pageToRestore = _currentPage;
                              Navigator.pop(ctx);
                              setState(() {
                                _selectedTrans
                                  ..clear()
                                  ..addAll(tempTrans);
                                _selectedTafseer
                                  ..clear()
                                  ..addAll(tempTafseer);
                                _showArabic = tempShowArabic;
                                _fontSize = tempFontSize;
                                _arabicScript = tempArabicScript;
                              });
                              _savePrefs();
                              _load(restorePage: pageToRestore);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: palette.accent,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                'Done',
                                style: TextStyle(
                                  color: palette.onAccent,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _SectionLabel(palette: palette, label: 'Display'),
                      const SizedBox(height: 6),
                      _CheckTile(
                        palette: palette,
                        label: 'Show Arabic text',
                        checked: tempShowArabic,
                        onTap: () =>
                            setS(() => tempShowArabic = !tempShowArabic),
                      ),
                      if (tempShowArabic) ...[
                        const SizedBox(height: 12),
                        _SectionLabel(palette: palette, label: 'Arabic Script'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            for (final script in [
                              ('uthmani', 'Uthmani'),
                              ('indopak', 'Indo-Pak'),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: GestureDetector(
                                  onTap: () =>
                                      setS(() => tempArabicScript = script.$1),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 160),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: tempArabicScript == script.$1
                                          ? palette.accent
                                          : palette.surface,
                                      borderRadius: BorderRadius.circular(99),
                                      border: Border.all(
                                        color: tempArabicScript == script.$1
                                            ? palette.accent
                                            : palette.border,
                                      ),
                                    ),
                                    child: Text(
                                      script.$2,
                                      style: TextStyle(
                                        color: tempArabicScript == script.$1
                                            ? palette.onAccent
                                            : palette.text,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      _SectionLabel(palette: palette, label: 'Font Size'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          for (final size in ['Small', 'Medium', 'Large'])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () => setS(() => tempFontSize = size),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: tempFontSize == size
                                        ? palette.accent
                                        : palette.surface,
                                    borderRadius: BorderRadius.circular(99),
                                    border: Border.all(
                                      color: tempFontSize == size
                                          ? palette.accent
                                          : palette.border,
                                    ),
                                  ),
                                  child: Text(
                                    size,
                                    style: TextStyle(
                                      color: tempFontSize == size
                                          ? palette.onAccent
                                          : palette.text,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _SectionLabel(palette: palette, label: 'Translation'),
                      const SizedBox(height: 6),
                      ...TranslationManager.sources.keys.map(
                        (src) => _CheckTile(
                          palette: palette,
                          label: src,
                          checked: tempTrans.contains(src),
                          onTap: () => toggleTrans(src),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionLabel(palette: palette, label: 'Tafseer'),
                      const SizedBox(height: 6),
                      ...TafseerManager.sources.keys.map(
                        (src) => _CheckTile(
                          palette: palette,
                          label: src,
                          checked: tempTafseer.contains(src),
                          onTap: () => toggleTafseer(src),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _copyText(
    BuildContext context,
    AppPalette palette,
    String text,
  ) {
    return Clipboard.setData(ClipboardData(text: text)).then((_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: palette.accent,
          behavior: SnackBarBehavior.floating,
          content: const Text('Copied'),
          duration: const Duration(seconds: 1),
        ),
      );
    });
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
          item is Map &&
          item['surah'] == focusSurah &&
          item['ayah'] == focusAyah,
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

  static final _arabicRunRe = RegExp(r'[؀-ۿﭐ-﷿ﹰ-﻿]{2,}(?:\s+[؀-ۿﭐ-﷿ﹰ-﻿]{2,})*');

  List<Widget> _tafseerParaWidgets(String para, double fontSize, Color color) {
    final widgets = <Widget>[];
    int last = 0;
    for (final m in _arabicRunRe.allMatches(para)) {
      final before = para.substring(last, m.start).trim();
      if (before.isNotEmpty) {
        widgets.add(_tafseerRun(before, fontSize, color, rtl: false));
      }
      final arabic = m.group(0)!.trim();
      if (arabic.isNotEmpty) {
        widgets.add(_tafseerRun(arabic, fontSize, color, rtl: true));
      }
      last = m.end;
    }
    final tail = para.substring(last).trim();
    if (tail.isNotEmpty) {
      widgets.add(_tafseerRun(tail, fontSize, color, rtl: false));
    }
    if (widgets.isEmpty) {
      widgets.add(_tafseerRun(para, fontSize, color, rtl: false));
    }
    return widgets;
  }

  Widget _tafseerRun(
    String text,
    double fontSize,
    Color color, {
    required bool rtl,
  }) {
    return SelectableText(
      text,
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: rtl ? TextAlign.right : TextAlign.left,
      style: TextStyle(
        fontSize: rtl ? fontSize + 2 : fontSize,
        height: 1.5,
        color: color,
        fontFamily: rtl ? 'NotoNaskh' : null,
      ),
    );
  }

  BorderRadius _rowRadius({required bool first, required bool last}) {
    const r = Radius.circular(18);
    return BorderRadius.vertical(
      top: first ? r : Radius.zero,
      bottom: last ? r : Radius.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: palette.scaffold,
      appBar: AppBar(
        backgroundColor: palette.scaffold,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: palette.muted),
        title: GestureDetector(
          onTap: _showSurahPicker,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _headerSurah.name,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    _headerSurah.english,
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                ],
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
                          itemCount: _visibleItems.length,
                          itemBuilder: (context, index) {
                            final items = _visibleItems;
                            final item = items[index];

                            if (item is SurahRange) {
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
                                            item.name,
                                            style: TextStyle(
                                              color: palette.text,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 1),
                                          Text(
                                            item.english,
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
                                      onTap: () => _showSummary(item),
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
                                      onTap: () =>
                                          _toggle(_collapsedSurahs, item.surah),
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
                                          _collapsedSurahs.contains(item.surah)
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

                            final surahNum = item['surah'] as int;
                            final ayahNumber = item['ayah'] as int;
                            final trans = item['trans'] as Map<String, String>;
                            final tafseer =
                                item['tafseer'] as Map<String, String>;
                            final arabic = item['arabic'] as String;
                            final prevIsHeader =
                                index == 0 || items[index - 1] is SurahRange;
                            final nextIsHeader =
                                index == items.length - 1 ||
                                items[index + 1] is SurahRange;

                            final allText = [
                              ...trans.values,
                              if (_selectedTafseer.isNotEmpty)
                                ...tafseer.values,
                            ].join('\n\n');
                            final isBookmarked = _bookmarkedAyahs.contains(
                              '$surahNum:$ayahNumber',
                            );
                            final isFocused =
                                surahNum == widget.focusSurah &&
                                ayahNumber == widget.focusAyah;
                            final rowBorder = isFocused
                                ? palette.accent
                                : palette.border;

                            return Container(
                              key: isFocused ? _focusedAyahKey : null,
                              decoration: BoxDecoration(
                                color: isFocused
                                    ? palette.accentSoft
                                    : palette.surface,
                                borderRadius: _rowRadius(
                                  first: prevIsHeader,
                                  last: nextIsHeader,
                                ),
                                border: Border(
                                  left: BorderSide(
                                    color: rowBorder,
                                    width: isFocused ? 2 : 1,
                                  ),
                                  right: BorderSide(
                                    color: rowBorder,
                                    width: isFocused ? 2 : 1,
                                  ),
                                  top: prevIsHeader
                                      ? BorderSide(color: rowBorder)
                                      : BorderSide.none,
                                  bottom: BorderSide(color: rowBorder),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(10, 6, 4, 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Top row: ayah badge + menu
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: palette.accentSoft,
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            border: Border.all(
                                              color: palette.accent.withValues(
                                                alpha: .18,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            ayahNumber.toString(),
                                            style: TextStyle(
                                              color: palette.accent,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              height: 1,
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () => _toggleAyahBookmark(
                                            surahNum,
                                            ayahNumber,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(4),
                                            child: Icon(
                                              isBookmarked
                                                  ? Icons.bookmark_rounded
                                                  : Icons
                                                        .bookmark_border_rounded,
                                              color: isBookmarked
                                                  ? palette.accent
                                                  : palette.surfaceMuted,
                                              size: 19,
                                            ),
                                          ),
                                        ),
                                        PopupMenuButton<String>(
                                          popUpAnimationStyle: AppMotion.style(
                                            context,
                                          ),
                                          icon: Icon(
                                            Icons.more_vert_rounded,
                                            color: palette.surfaceMuted,
                                            size: 18,
                                          ),
                                          padding: EdgeInsets.zero,
                                          tooltip: 'Actions',
                                          color: palette.surfaceRaised,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          onSelected: (value) {
                                            if (value == 'copy') {
                                              _copyText(
                                                context,
                                                palette,
                                                allText,
                                              );
                                            } else {
                                              SharePlus.instance.share(
                                                ShareParams(text: allText),
                                              );
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            PopupMenuItem(
                                              value: 'copy',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.copy_rounded,
                                                    color: palette.accent,
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  const Text('Copy'),
                                                ],
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'share',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.ios_share_rounded,
                                                    color: palette.accent,
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  const Text('Share'),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),

                                    // Text content (full width)
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Arabic text
                                        if (_showArabic &&
                                            arabic.isNotEmpty) ...[
                                          SizedBox(
                                            width: double.infinity,
                                            child: Text(
                                              arabic,
                                              textDirection: TextDirection.rtl,
                                              textAlign: TextAlign.right,
                                              style: QuranArabicStyle.ayah(
                                                script: _arabicScript,
                                                fontSize: _fontSize,
                                                color: palette.text,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                        ],
                                        // Translation blocks
                                        ..._selectedTrans.asMap().entries.map((
                                          e,
                                        ) {
                                          final src = e.value;
                                          final text = trans[src] ?? '';
                                          final srcKey =
                                              '$surahNum:$ayahNumber:$src';
                                          final srcCollapsed = _collapsedTrans
                                              .contains(srcKey);
                                          return Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (e.key > 0)
                                                Divider(
                                                  height: 16,
                                                  color: palette.border,
                                                ),
                                              GestureDetector(
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                onTap: () => _toggle(
                                                  _collapsedTrans,
                                                  srcKey,
                                                ),
                                                child: Row(
                                                  children: [
                                                    Text(
                                                      src,
                                                      style: TextStyle(
                                                        color: palette.accent,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        letterSpacing: 0.3,
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                    Icon(
                                                      srcCollapsed
                                                          ? Icons
                                                                .keyboard_arrow_down_rounded
                                                          : Icons
                                                                .keyboard_arrow_up_rounded,
                                                      size: 16,
                                                      color: palette.accent,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (!srcCollapsed &&
                                                  text.trim().isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                TranslationExposure(
                                                  verse:
                                                      '$surahNum:$ayahNumber',
                                                  seen: _translationsSeen,
                                                  child: SelectableText(
                                                    text,
                                                    style: TextStyle(
                                                      fontSize:
                                                          _fontSizeMap[_fontSize]!
                                                              .trans,
                                                      height: 1.45,
                                                      color:
                                                          palette.surfaceText,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          );
                                        }),

                                        // Tafseer blocks
                                        if (_selectedTafseer.isNotEmpty &&
                                            _selectedTafseer.any(
                                              (s) =>
                                                  (tafseer[s] ?? '').isNotEmpty,
                                            )) ...[
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.fromLTRB(
                                              8,
                                              6,
                                              6,
                                              6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: palette.scaffold,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border(
                                                left: BorderSide(
                                                  color: palette.accent
                                                      .withValues(alpha: .2),
                                                  width: 2,
                                                ),
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: _selectedTafseer.asMap().entries.map<Widget>((
                                                e,
                                              ) {
                                                final src = e.value;
                                                final text = tafseer[src] ?? '';
                                                if (text.isEmpty) {
                                                  return const SizedBox.shrink();
                                                }
                                                final srcKey =
                                                    '$surahNum:$ayahNumber:$src';
                                                final srcCollapsed =
                                                    _collapsedTafseers.contains(
                                                      srcKey,
                                                    );
                                                return Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    if (e.key > 0)
                                                      Divider(
                                                        height: 16,
                                                        color: palette.border,
                                                      ),
                                                    GestureDetector(
                                                      behavior: HitTestBehavior
                                                          .opaque,
                                                      onTap: () => _toggle(
                                                        _collapsedTafseers,
                                                        srcKey,
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Text(
                                                            src,
                                                            style: TextStyle(
                                                              color:
                                                                  palette.muted,
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              letterSpacing:
                                                                  0.3,
                                                            ),
                                                          ),
                                                          const Spacer(),
                                                          Icon(
                                                            srcCollapsed
                                                                ? Icons
                                                                      .keyboard_arrow_down_rounded
                                                                : Icons
                                                                      .keyboard_arrow_up_rounded,
                                                            size: 16,
                                                            color:
                                                                palette.muted,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    if (!srcCollapsed) ...[
                                                      const SizedBox(height: 4),
                                                      for (final para
                                                          in text
                                                              .split('\n\n')
                                                              .map(
                                                                (p) => p.trim(),
                                                              )
                                                              .where(
                                                                (p) => p
                                                                    .isNotEmpty,
                                                              ))
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                bottom: 36,
                                                              ),
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .stretch,
                                                            children: _tafseerParaWidgets(
                                                              para,
                                                              _fontSizeMap[_fontSize]!
                                                                  .tafseer,
                                                              palette.text
                                                                  .withValues(
                                                                    alpha: .95,
                                                                  ),
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ],
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
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

class _SummarySheet extends StatefulWidget {
  final SurahRange surah;
  final String fontSize;
  const _SummarySheet({required this.surah, required this.fontSize});

  static const Map<String, ({double heading, double body})> _sizes = {
    'Small': (heading: 13.0, body: 13.0),
    'Medium': (heading: 14.0, body: 15.0),
    'Large': (heading: 16.0, body: 17.0),
  };

  @override
  State<_SummarySheet> createState() => _SummarySheetState();
}

class _SummarySheetState extends State<_SummarySheet> {
  bool _urdu = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final summary = SurahSummaryManager.get(widget.surah.surah, urdu: _urdu);
    final sizes = _SummarySheet._sizes[widget.fontSize]!;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: palette.scaffold,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 10),
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              // Header: surah name + language toggle
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.surah.name,
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Summary',
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Language pill toggle
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: palette.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _LangSegment(
                            palette: palette,
                            label: 'English',
                            active: !_urdu,
                            onTap: () => setState(() => _urdu = false),
                          ),
                          _LangSegment(
                            palette: palette,
                            label: 'اردو',
                            active: _urdu,
                            onTap: () => setState(() => _urdu = true),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Divider(height: 1, color: palette.border),

              // Content
              Expanded(
                child: summary == null
                    ? Center(
                        child: Text(
                          'No summary available',
                          style: TextStyle(color: palette.muted),
                        ),
                      )
                    : Scrollbar(
                        controller: scrollController,
                        thumbVisibility: true,
                        radius: const Radius.circular(10),
                        thickness: 6,
                        child: ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          itemCount: summary.sections.length,
                          itemBuilder: (context, i) {
                            final section = summary.sections[i];
                            if (section.isHeading) {
                              return Padding(
                                padding: const EdgeInsets.only(
                                  top: 20,
                                  bottom: 6,
                                ),
                                child: Text(
                                  section.text,
                                  textDirection: _urdu
                                      ? TextDirection.rtl
                                      : TextDirection.ltr,
                                  style: TextStyle(
                                    color: palette.accent,
                                    fontSize: sizes.heading,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              );
                            }
                            final paras = section.text
                                .split('\n\n')
                                .map((p) => p.trim())
                                .where((p) => p.isNotEmpty)
                                .toList();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final para in paras)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 36),
                                    child: Text(
                                      para,
                                      textDirection: _urdu
                                          ? TextDirection.rtl
                                          : TextDirection.ltr,
                                      style: TextStyle(
                                        color: palette.text,
                                        fontSize: sizes.body,
                                        height: 1.6,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LangSegment extends StatelessWidget {
  final AppPalette palette;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _LangSegment({
    required this.palette,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? palette.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? palette.onAccent : palette.muted,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final AppPalette palette;
  final String label;

  const _SectionLabel({required this.palette, required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: palette.muted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  final AppPalette palette;
  final String label;
  final bool checked;
  final VoidCallback onTap;

  const _CheckTile({
    required this.palette,
    required this.label,
    required this.checked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: checked,
                onChanged: (_) => onTap(),
                activeColor: palette.accent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
                side: BorderSide(color: palette.border, width: 1.5),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: palette.text,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
