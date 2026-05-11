import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/surah_mapper.dart';
import '../utils/translation_manager.dart';
import '../utils/tafseer_manager.dart';
import '../utils/surah_summary_manager.dart';
import '../utils/arabic_text_manager.dart';

class TranslationModal extends StatefulWidget {
  final List<SurahRange> surahs;

  const TranslationModal({super.key, required this.surahs});

  static void show(BuildContext context, List<SurahRange> surahs) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TranslationModal(surahs: surahs)),
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
  final _scrollController = ScrollController();
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

  static const Map<String, ({double arabic, double trans, double tafseer})> _fontSizeMap = {
    'Small': (arabic: 18.0, trans: 13.0, tafseer: 13.0),
    'Medium': (arabic: 22.0, trans: 16.0, tafseer: 16.0),
    'Large': (arabic: 26.0, trans: 19.0, tafseer: 19.0),
  };

  @override
  void initState() {
    super.initState();
    _activeSurah = widget.surahs.first;
    _initFromPrefs();
  }

  Future<void> _initFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final trans = prefs.getStringList('trans_selected') ?? ['Saheeh International'];
    final tafseer = prefs.getStringList('tafseer_selected') ?? ['Tafseer Ibn Kathir'];
    final showArabic = prefs.getBool('show_arabic') ?? true;
    final fontSize = prefs.getString('font_size') ?? 'Medium';
    final arabicScript = prefs.getString('arabic_script') ?? 'uthmani';
    _selectedTrans..clear()..addAll(trans);
    _selectedTafseer..clear()..addAll(tafseer);
    _showArabic = showArabic;
    _fontSize = fontSize;
    _arabicScript = arabicScript;
    _load();
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('trans_selected', _selectedTrans);
    await prefs.setStringList('tafseer_selected', _selectedTafseer);
    await prefs.setBool('show_arabic', _showArabic);
    await prefs.setString('font_size', _fontSize);
    await prefs.setString('arabic_script', _arabicScript);
  }

  Future<void> _load({int? restorePage}) async {
    if (!mounted) return;
    setState(() => _loading = true);

    for (final src in _selectedTrans) {
      await TranslationManager.loadSource(src);
    }

    final items = <dynamic>[];

    for (final surah in [_activeSurah]) {
      items.add(surah);

      final transData = <String, Map<int, String>>{};
      for (final src in _selectedTrans) {
        transData[src] = TranslationManager.getSurah(surah.surah, source: src);
      }

      final tafseerData = <String, Map<int, String>>{};
      if (_selectedTafseer.isNotEmpty) {
        for (final src in _selectedTafseer) {
          tafseerData[src] = await TafseerManager.getSurah(surah.surah, src);
        }
      }

      final arabicData = await ArabicTextManager.getSurah(surah.surah, source: _arabicScript);

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
    }

    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
      _currentPage = restorePage != null
          ? restorePage.clamp(0, (_allAyahs.length / _pageSize).ceil() - 1)
          : 0;
    });
  }

  void _showSummary(SurahRange surah) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final palette = AppPalette.of(context);
        return StatefulBuilder(
          builder: (ctx, setS) {
            void toggleTrans(String src) => setS(() {
              if (tempTrans.contains(src)) {
                if (tempTrans.length > 1) tempTrans.remove(src);
              } else {
                tempTrans.add(src);
              }
            });
            void toggleTafseer(String src) => setS(() {
              tempTafseer.contains(src)
                  ? tempTafseer.remove(src)
                  : tempTafseer.add(src);
            });

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
                          child: const Text(
                            'Done',
                            style: TextStyle(
                              color: Colors.white,
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
                    onTap: () => setS(() => tempShowArabic = !tempShowArabic),
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
                              onTap: () => setS(() => tempArabicScript = script.$1),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                                decoration: BoxDecoration(
                                  color: tempArabicScript == script.$1 ? palette.accent : palette.surface,
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(
                                    color: tempArabicScript == script.$1 ? palette.accent : palette.border,
                                  ),
                                ),
                                child: Text(
                                  script.$2,
                                  style: TextStyle(
                                    color: tempArabicScript == script.$1 ? Colors.white : palette.text,
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
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                              decoration: BoxDecoration(
                                color: tempFontSize == size ? palette.accent : palette.surface,
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
                                  color: tempFontSize == size ? Colors.white : palette.text,
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
    final all = indopakSurahRanges.where((s) => s.surah >= 1).toList();
    final palette = AppPalette.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
                  width: 40, height: 5,
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
                    final active = s.surah == _activeSurah.surah;
                    return ListTile(
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => _activeSurah = s);
                        _load();
                      },
                      leading: Container(
                        width: 36, height: 36,
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
                              color: active ? Colors.white : palette.muted,
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
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        s.english,
                        style: TextStyle(color: palette.muted, fontSize: 12),
                      ),
                      trailing: active
                          ? Icon(Icons.check_rounded, color: palette.accent, size: 18)
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
    final ayahCount = _allAyahs.length;
    final onFirst = _currentPage == 0;
    final onLast = (_currentPage + 1) * _pageSize >= ayahCount;
    final displayStart = _currentPage * _pageSize + 1;
    final displayEnd = ((_currentPage + 1) * _pageSize).clamp(0, ayahCount);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: palette.scaffold,
        border: Border(top: BorderSide(color: palette.border.withValues(alpha: .6))),
      ),
      child: Row(
        children: [
          _navBtn(Icons.chevron_left_rounded, !onFirst, () {
            setState(() => _currentPage--);
            _scrollController.jumpTo(0);
          }, palette),
          const Spacer(),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Page ${_currentPage + 1} of $_totalPages',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '$displayStart–$displayEnd of $ayahCount ayahs',
                style: TextStyle(color: palette.muted, fontSize: 11),
              ),
            ],
          ),
          const Spacer(),
          _navBtn(Icons.chevron_right_rounded, !onLast, () {
            final next = _currentPage + 1;
            if (next * _pageSize < ayahCount) {
              setState(() => _currentPage = next);
              _scrollController.jumpTo(0);
            }
          }, palette),
        ],
      ),
    );
  }

  Widget _navBtn(IconData icon, bool enabled, VoidCallback onTap, AppPalette palette) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: enabled ? palette.accent.withValues(alpha: .12) : palette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled ? palette.accent.withValues(alpha: .35) : palette.border,
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

  static final _arabicRunRe =
      RegExp(r'[؀-ۿﭐ-﷿ﹰ-﻿]{2,}(?:\s+[؀-ۿﭐ-﷿ﹰ-﻿]{2,})*');

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

  Widget _tafseerRun(String text, double fontSize, Color color, {required bool rtl}) {
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
                    _activeSurah.name,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    _activeSurah.english,
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down_rounded, color: palette.muted, size: 20),
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
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                color: palette.accent,
                strokeWidth: 2.5,
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    interactive: true,
                    radius: const Radius.circular(10),
                    thickness: 6,
                    child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 22),
                                itemCount: _pageContent.length,
                                itemBuilder: (context, index) {
                                  final items = _pageContent;
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
                                        borderRadius:
                                            BorderRadius.circular(99),
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
                                          borderRadius: BorderRadius.circular(99),
                                          border: Border.all(
                                            color: palette.accent.withValues(alpha: .2),
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
                                      onTap: () => setState(() {
                                        if (_collapsedSurahs.contains(item.surah)) {
                                          _collapsedSurahs.remove(item.surah);
                                        } else {
                                          _collapsedSurahs.add(item.surah);
                                        }
                                      }),
                                      child: Container(
                                        padding: const EdgeInsets.all(5),
                                        decoration: BoxDecoration(
                                          color: palette.surface,
                                          borderRadius: BorderRadius.circular(99),
                                          border: Border.all(color: palette.border),
                                        ),
                                        child: Icon(
                                          _collapsedSurahs.contains(item.surah)
                                              ? Icons.keyboard_arrow_down_rounded
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
                            final trans =
                                item['trans'] as Map<String, String>;
                            final tafseer =
                                item['tafseer'] as Map<String, String>;
                            final arabic = item['arabic'] as String;
                            final prevIsHeader =
                                index == 0 ||
                                items[index - 1] is SurahRange;
                            final nextIsHeader =
                                index == items.length - 1 ||
                                items[index + 1] is SurahRange;

                            final allText = [
                              ...trans.values,
                              if (_selectedTafseer.isNotEmpty) ...tafseer.values,
                            ].join('\n\n');

                            return Container(
                              decoration: BoxDecoration(
                                color: palette.surface,
                                borderRadius: _rowRadius(
                                  first: prevIsHeader,
                                  last: nextIsHeader,
                                ),
                                border: Border(
                                  left: BorderSide(color: palette.border),
                                  right: BorderSide(color: palette.border),
                                  top: prevIsHeader
                                      ? BorderSide(color: palette.border)
                                      : BorderSide.none,
                                  bottom: BorderSide(color: palette.border),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    10, 6, 4, 8),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
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
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            border: Border.all(
                                              color: palette.accent
                                                  .withValues(alpha: .18),
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
                                        PopupMenuButton<String>(
                                          icon: Icon(
                                            Icons.more_vert_rounded,
                                            color: palette.surfaceMuted,
                                            size: 18,
                                          ),
                                          padding: EdgeInsets.zero,
                                          tooltip: 'Actions',
                                          color: palette.surfaceRaised,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                          onSelected: (value) {
                                            if (value == 'copy') {
                                              _copyText(
                                                  context, palette, allText);
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
                                          if (_showArabic && arabic.isNotEmpty) ...[
                                            SizedBox(
                                              width: double.infinity,
                                              child: Text(
                                                arabic,
                                                textDirection: TextDirection.rtl,
                                                textAlign: TextAlign.right,
                                                style: TextStyle(
                                                  fontSize: _fontSizeMap[_fontSize]!.arabic,
                                                  height: 1.8,
                                                  color: palette.text,
                                                  fontFamily: _arabicScript == 'indopak' ? 'IndoPak' : 'Uthmani2',
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                          ],
                                          // Translation blocks
                                          ..._selectedTrans
                                              .asMap()
                                              .entries
                                              .map((e) {
                                            final src = e.value;
                                            final text = trans[src] ?? '';
                                            final srcKey = '$surahNum:$ayahNumber:$src';
                                            final srcCollapsed = _collapsedTrans.contains(srcKey);
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
                                                  behavior: HitTestBehavior.opaque,
                                                  onTap: () => setState(() {
                                                    srcCollapsed
                                                        ? _collapsedTrans.remove(srcKey)
                                                        : _collapsedTrans.add(srcKey);
                                                  }),
                                                  child: Row(
                                                    children: [
                                                      Text(
                                                        src,
                                                        style: TextStyle(
                                                          color: palette.accent,
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w700,
                                                          letterSpacing: 0.3,
                                                        ),
                                                      ),
                                                      const Spacer(),
                                                      Icon(
                                                        srcCollapsed
                                                            ? Icons.keyboard_arrow_down_rounded
                                                            : Icons.keyboard_arrow_up_rounded,
                                                        size: 16,
                                                        color: palette.accent,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (!srcCollapsed) ...[
                                                  const SizedBox(height: 4),
                                                  SelectableText(
                                                    text,
                                                    style: TextStyle(
                                                      fontSize: _fontSizeMap[_fontSize]!.trans,
                                                      height: 1.45,
                                                      color: palette.surfaceText,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            );
                                          }),

                                          // Tafseer blocks
                                          if (_selectedTafseer.isNotEmpty &&
                                              _selectedTafseer
                                                  .any((s) =>
                                                      (tafseer[s] ?? '')
                                                          .isNotEmpty)) ...[
                                            const SizedBox(height: 6),
                                            Container(
                                              padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
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
                                                children: _selectedTafseer
                                                    .asMap()
                                                    .entries
                                                    .map<Widget>((e) {
                                                  final src = e.value;
                                                  final text = tafseer[src] ?? '';
                                                  if (text.isEmpty) return const SizedBox.shrink();
                                                  final srcKey = '$surahNum:$ayahNumber:$src';
                                                  final srcCollapsed = _collapsedTafseers.contains(srcKey);
                                                  return Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      if (e.key > 0)
                                                        Divider(height: 16, color: palette.border),
                                                      GestureDetector(
                                                        behavior: HitTestBehavior.opaque,
                                                        onTap: () => setState(() {
                                                          srcCollapsed
                                                              ? _collapsedTafseers.remove(srcKey)
                                                              : _collapsedTafseers.add(srcKey);
                                                        }),
                                                        child: Row(
                                                          children: [
                                                            Text(
                                                              src,
                                                              style: TextStyle(
                                                                color: palette.muted,
                                                                fontSize: 11,
                                                                fontWeight: FontWeight.w700,
                                                                letterSpacing: 0.3,
                                                              ),
                                                            ),
                                                            const Spacer(),
                                                            Icon(
                                                              srcCollapsed
                                                                  ? Icons.keyboard_arrow_down_rounded
                                                                  : Icons.keyboard_arrow_up_rounded,
                                                              size: 16,
                                                              color: palette.muted,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      if (!srcCollapsed) ...[
                                                        const SizedBox(height: 4),
                                                        for (final para in text.split('\n\n').map((p) => p.trim()).where((p) => p.isNotEmpty))
                                                          Padding(
                                                            padding: const EdgeInsets.only(bottom: 36),
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                                              children: _tafseerParaWidgets(
                                                                para,
                                                                _fontSizeMap[_fontSize]!.tafseer,
                                                                palette.text.withValues(alpha: .95),
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
                  _buildPageNav(palette),
                ],
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
                                padding: const EdgeInsets.only(top: 20, bottom: 6),
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
            color: active ? Colors.white : palette.muted,
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
