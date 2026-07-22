import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/audio_preferences.dart';

class AudioModal extends StatefulWidget {
  final int initialSurah;

  /// Ayah range to pre-select (the ayahs on the current page). When provided,
  /// the modal opens in Range mode with these values. Ignored if audio is
  /// already playing (the active plan is shown instead).
  final int? initialFromAyah;
  final int? initialToAyah;

  const AudioModal({
    super.key,
    required this.initialSurah,
    this.initialFromAyah,
    this.initialToAyah,
  });

  static void show(
    BuildContext context, {
    required int initialSurah,
    int? initialFromAyah,
    int? initialToAyah,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AudioModal(
        initialSurah: initialSurah,
        initialFromAyah: initialFromAyah,
        initialToAyah: initialToAyah,
      ),
    );
  }

  @override
  State<AudioModal> createState() => _AudioModalState();
}

class _AudioModalState extends State<AudioModal> {
  Reciter _reciter = quranReciters.first;
  late int _surah;
  int _fromAyah = 1;
  int _toAyah = 7;
  int? _repeatCount = 20;
  AudioRepeatMode _repeatMode = AudioRepeatMode.range;
  AudioSourceMode _sourceMode = AudioSourceMode.range;
  QuranAudioErrorKind _lastHandledErrorKind = QuranAudioErrorKind.none;
  List<int>? _ayahOptions;
  int? _ayahOptionsSurah;
  bool _preferencesReady = false;

  @override
  void initState() {
    super.initState();
    final activePlan = _currentEditablePlan();
    if (activePlan == null) {
      _surah = widget.initialSurah.clamp(1, 114).toInt();
      final maxAyah = quranAyahCounts[_surah - 1];
      if (widget.initialFromAyah != null && widget.initialToAyah != null) {
        // Pre-select the current page's ayah range.
        _fromAyah = widget.initialFromAyah!.clamp(1, maxAyah).toInt();
        _toAyah = widget.initialToAyah!.clamp(_fromAyah, maxAyah).toInt();
        _sourceMode = AudioSourceMode.range;
      } else {
        _toAyah = _ayahCount.clamp(1, 7).toInt();
      }
    } else {
      _applyPlan(activePlan);
      _preferencesReady = true;
    }
    if (activePlan == null) {
      _restorePreferences();
    } else {
      _persistPreferences();
      _warmAyahOptions();
    }
  }

  int get _ayahCount => quranAyahCounts[_surah - 1];
  String get _surahName => quranSurahs[_surah - 1].name;

  AudioPlaybackPlan? _currentEditablePlan() {
    final controller = QuranAudioController.instance;
    final plan = controller.plan;
    if (plan == null) return null;

    return switch (controller.processingState) {
      ProcessingState.idle || ProcessingState.completed => null,
      ProcessingState.loading ||
      ProcessingState.buffering ||
      ProcessingState.ready => plan,
    };
  }

  void _applyPlan(AudioPlaybackPlan plan) {
    _reciter = quranReciters.firstWhere(
      (reciter) => reciter.id == plan.reciter.id,
      orElse: () => quranReciters.first,
    );
    _surah = plan.surah.clamp(1, 114).toInt();
    final maxAyah = quranAyahCounts[_surah - 1];
    _fromAyah = plan.effectiveFromAyah.clamp(1, maxAyah).toInt();
    _toAyah = plan.effectiveToAyah.clamp(_fromAyah, maxAyah).toInt();
    _repeatCount = plan.repeatCount;
    _repeatMode = plan.repeatMode;
    _sourceMode = plan.sourceMode;
  }

  Future<void> _restorePreferences() async {
    final saved = await AudioPreferences.load();
    if (!mounted) return;
    if (saved != null) {
      _reciter = quranReciters.firstWhere(
        (reciter) => reciter.id == saved.reciterId,
        orElse: () => quranReciters.first,
      );
      _surah = saved.surah.clamp(1, 114).toInt();
      final maxAyah = quranAyahCounts[_surah - 1];
      _fromAyah = saved.fromAyah.clamp(1, maxAyah).toInt();
      _toAyah = saved.toAyah.clamp(_fromAyah, maxAyah).toInt();
      _repeatCount = saved.repeatCount;
      _repeatMode = saved.repeatMode;
      _sourceMode = saved.sourceMode;
    }
    setState(() => _preferencesReady = true);
    _warmAyahOptions();
  }

  void _persistPreferences() {
    AudioPreferences.save(
      AudioPreferencesData(
        reciterId: _reciter.id,
        surah: _surah,
        fromAyah: _fromAyah,
        toAyah: _toAyah,
        repeatCount: _repeatCount,
        repeatMode: _repeatMode,
        sourceMode: _sourceMode,
      ),
    ).ignore();
  }

  AudioPlaybackPlan get _plan {
    return AudioPlaybackPlan(
      reciter: _reciter,
      surah: _surah,
      fromAyah: _fromAyah,
      toAyah: _toAyah,
      repeatCount: _repeatCount,
      repeatMode: _repeatMode,
      sourceMode: _sourceMode,
    );
  }

  void _setSurah(int surah) {
    setState(() {
      _surah = surah;
      _fromAyah = 1;
      _toAyah = quranAyahCounts[surah - 1].clamp(1, 7).toInt();
      _ayahOptions = null;
      _ayahOptionsSurah = null;
    });
    _persistPreferences();
    _warmAyahOptions();
  }

  void _setFromAyah(int ayah) {
    setState(() {
      _fromAyah = ayah;
      if (_toAyah < _fromAyah) {
        _toAyah = _fromAyah;
      }
    });
    _persistPreferences();
  }

  void _setToAyah(int ayah) {
    setState(() {
      _toAyah = ayah;
      if (_fromAyah > _toAyah) {
        _fromAyah = _toAyah;
      }
    });
    _persistPreferences();
  }

  void _warmAyahOptions() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureAyahOptions());
  }

  void _ensureAyahOptions() {
    if (!mounted) return;
    if (_ayahOptionsSurah == _surah && _ayahOptions != null) return;

    final options = [for (var ayah = 1; ayah <= _ayahCount; ayah++) ayah];
    setState(() {
      _ayahOptions = options;
      _ayahOptionsSurah = _surah;
    });
  }

  Future<void> _showConnectionNeededDialog() async {
    if (!mounted) return;

    final palette = AppPalette.of(context);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text(
          'Connection needed',
          style: TextStyle(
            color: palette.surfaceText,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'This audio has not been downloaded yet. Connect to the internet once, then it will play offline next time.',
          style: TextStyle(color: palette.surfaceMuted),
        ),
        actions: [
          TextButton(
            onPressed: () {
              QuranAudioController.instance.clearError();
              Navigator.pop(context);
            },
            child: Text('OK', style: TextStyle(color: palette.accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    if (!_preferencesReady) {
      return SizedBox(
        height: 220,
        child: Center(
          child: CircularProgressIndicator(
            color: palette.accent,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .68,
      minChildSize: .42,
      maxChildSize: .92,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: palette.scaffold,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: palette.accentSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.headphones_rounded,
                      color: palette.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Audio',
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: palette.text),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _panel(
                palette,
                children: [
                  _label('Reciter', palette),
                  _select<Reciter>(
                    palette: palette,
                    value: _reciter,
                    items: quranReciters,
                    label: (reciter) => reciter.name,
                    onChanged: (reciter) {
                      setState(() => _reciter = reciter);
                      _persistPreferences();
                    },
                  ),
                  const SizedBox(height: 14),
                  _label('Surah', palette),
                  _select<int>(
                    palette: palette,
                    value: _surah,
                    items: [for (var i = 1; i <= 114; i++) i],
                    label: (surah) => '$surah. ${quranSurahs[surah - 1].name}',
                    onChanged: _setSurah,
                  ),
                  const SizedBox(height: 14),
                  _label('Play', palette),
                  Row(
                    children: [
                      Expanded(
                        child: _sourceChip(
                          palette,
                          mode: AudioSourceMode.range,
                          title: 'Range',
                          subtitle: 'Choose ayahs',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _sourceChip(
                          palette,
                          mode: AudioSourceMode.surah,
                          title: 'Full surah',
                          subtitle: 'All ayahs',
                        ),
                      ),
                    ],
                  ),
                  if (_sourceMode == AudioSourceMode.range) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('From ayah', palette),
                              _ayahDropdown(
                                palette: palette,
                                value: _fromAyah,
                                onChanged: _setFromAyah,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('To ayah', palette),
                              _ayahDropdown(
                                palette: palette,
                                value: _toAyah,
                                onChanged: _setToAyah,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              _panel(
                palette,
                children: [
                  _label('Repeat style', palette),
                  Row(
                    children: [
                      Expanded(
                        child: _modeChip(
                          palette,
                          mode: AudioRepeatMode.range,
                          title: 'Range repeat',
                          subtitle: '1-5, 1-5',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _modeChip(
                          palette,
                          mode: AudioRepeatMode.ayah,
                          title: 'Verse repeat',
                          subtitle: '1,1, 2,2',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _label('Repeat count', palette),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final count in const [1, 2, 3, 5, 10, 20])
                        ChoiceChip(
                          label: Text('${count}x'),
                          selected: _repeatCount == count,
                          onSelected: (_) {
                            setState(() => _repeatCount = count);
                            _persistPreferences();
                          },
                          selectedColor: palette.accent,
                          labelStyle: TextStyle(
                            color: _repeatCount == count
                                ? Colors.white
                                : palette.surfaceText,
                            fontWeight: FontWeight.w700,
                          ),
                          backgroundColor: palette.surfaceRaised,
                          side: BorderSide(color: palette.border),
                        ),
                      ChoiceChip(
                        label: const Text('\u221e'),
                        selected: _repeatCount == null,
                        onSelected: (_) {
                          setState(() => _repeatCount = null);
                          _persistPreferences();
                        },
                        selectedColor: palette.accent,
                        labelStyle: TextStyle(
                          color: _repeatCount == null
                              ? Colors.white
                              : palette.surfaceText,
                          fontWeight: FontWeight.w800,
                        ),
                        backgroundColor: palette.surfaceRaised,
                        side: BorderSide(color: palette.border),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AnimatedBuilder(
                animation: QuranAudioController.instance,
                builder: (context, _) {
                  final controller = QuranAudioController.instance;
                  if (controller.errorKind ==
                          QuranAudioErrorKind.connectionRequired &&
                      _lastHandledErrorKind != controller.errorKind) {
                    _lastHandledErrorKind = controller.errorKind;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _showConnectionNeededDialog();
                    });
                  } else if (controller.errorKind == QuranAudioErrorKind.none) {
                    _lastHandledErrorKind = QuranAudioErrorKind.none;
                  }

                  return _playerPanel(palette, QuranAudioController.instance);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _playerPanel(AppPalette palette, QuranAudioController controller) {
    final download = controller.downloadState;
    final mediaItem = controller.currentMediaItem;
    final ayah = controller.currentAyah;
    final repeat = controller.currentRepeat;
    final currentIndex = controller.currentIndex;
    final editedPlan = _plan;
    final isThisPlan = editedPlan.matches(controller.plan);
    final isDownloading = download.active && isThisPlan;
    final canResumeCurrentPlan =
        isThisPlan &&
        controller.hasPlan &&
        !controller.playing &&
        controller.processingState != ProcessingState.idle &&
        controller.processingState != ProcessingState.completed;

    return _panel(
      palette,
      children: [
        Text(
          '$_surahName ${editedPlan.rangeLabel}',
          style: TextStyle(
            color: palette.surfaceText,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${editedPlan.infiniteRepeat ? 'Repeats forever' : '${editedPlan.totalPlaybackItems} plays'} \u2022 ${_reciter.name}',
          style: TextStyle(color: palette.surfaceMuted, fontSize: 13),
        ),
        if (download.active) ...[
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: download.progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(99),
            backgroundColor: palette.accent.withValues(alpha: .12),
            color: palette.accent,
          ),
          const SizedBox(height: 8),
          Text(
            download.message,
            style: TextStyle(color: palette.surfaceMuted, fontSize: 12),
          ),
        ],
        if (controller.error != null) ...[
          const SizedBox(height: 12),
          Text(
            controller.error!,
            style: const TextStyle(
              color: Color(0xFF9E1B1B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (mediaItem != null && ayah != null && isThisPlan) ...[
          const SizedBox(height: 12),
          Text(
            'Playing $_surahName:$ayah'
            '${repeat == null ? '' : ' \u2022 repeat $repeat/${editedPlan.repeatLabel}'}'
            '${currentIndex == null ? '' : ' \u2022 ${currentIndex + 1}/${controller.totalItems}'}',
            style: TextStyle(
              color: palette.accent,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            _roundButton(
              palette,
              icon: Icons.skip_previous_rounded,
              onPressed: controller.hasPlan ? controller.seekPrevious : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: isDownloading
                    ? null
                    : () {
                        if (canResumeCurrentPlan) {
                          controller.togglePlayPause();
                          return;
                        }

                        controller.playPlan(editedPlan);
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: Icon(
                  isDownloading
                      ? Icons.hourglass_top_rounded
                      : Icons.play_arrow_rounded,
                ),
                label: Text(
                  isDownloading
                      ? 'Preparing'
                      : canResumeCurrentPlan
                      ? 'Resume'
                      : 'Play',
                ),
              ),
            ),
            const SizedBox(width: 8),
            _roundButton(
              palette,
              icon: Icons.skip_next_rounded,
              onPressed: controller.hasPlan ? controller.seekNext : null,
            ),
            const SizedBox(width: 8),
            _roundButton(
              palette,
              icon: Icons.stop_rounded,
              onPressed: controller.hasPlan ? controller.stop : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _panel(AppPalette palette, {required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border.withValues(alpha: .75)),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: .38),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _label(String text, AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        text,
        style: TextStyle(
          color: palette.surfaceMuted,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: .3,
        ),
      ),
    );
  }

  Widget _select<T>({
    required AppPalette palette,
    required T value,
    required List<T> items,
    required String Function(T value) label,
    required void Function(T value) onChanged,
    bool enabled = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: enabled
            ? palette.surfaceRaised
            : palette.surfaceRaised.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: palette.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(13),
          iconEnabledColor: palette.accent,
          style: TextStyle(
            color: palette.surfaceText,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          items: [
            for (final item in items)
              DropdownMenuItem<T>(
                value: item,
                child: Text(label(item), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) {
            if (!enabled) return;
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }

  Widget _ayahDropdown({
    required AppPalette palette,
    required int value,
    required void Function(int value) onChanged,
  }) {
    final items = _ayahOptionsSurah == _surah ? _ayahOptions : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: palette.border),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _ensureAyahOptions,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: items == null ? null : value,
            hint: Text(value.toString()),
            disabledHint: Text(value.toString()),
            isExpanded: true,
            dropdownColor: palette.surfaceRaised,
            borderRadius: BorderRadius.circular(13),
            iconEnabledColor: palette.accent,
            iconDisabledColor: palette.accent,
            style: TextStyle(
              color: palette.surfaceText,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            items: items == null
                ? null
                : [
                    for (final ayah in items)
                      DropdownMenuItem<int>(
                        value: ayah,
                        child: Text(ayah.toString()),
                      ),
                  ],
            onChanged: items == null
                ? null
                : (ayah) {
                    if (ayah != null) onChanged(ayah);
                  },
          ),
        ),
      ),
    );
  }

  Widget _modeChip(
    AppPalette palette, {
    required AudioRepeatMode mode,
    required String title,
    required String subtitle,
  }) {
    final selected = _repeatMode == mode;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        setState(() => _repeatMode = mode);
        _persistPreferences();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? palette.accentSoft : palette.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? palette.accent : palette.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: selected ? palette.accent : palette.surfaceText,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(color: palette.surfaceMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceChip(
    AppPalette palette, {
    required AudioSourceMode mode,
    required String title,
    required String subtitle,
  }) {
    final selected = _sourceMode == mode;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        setState(() => _sourceMode = mode);
        _persistPreferences();
        if (mode == AudioSourceMode.range) _warmAyahOptions();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? palette.accentSoft : palette.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? palette.accent : palette.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: selected ? palette.accent : palette.surfaceText,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(color: palette.surfaceMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundButton(
    AppPalette palette, {
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: palette.accentSoft,
        disabledBackgroundColor: palette.border.withValues(alpha: .35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      color: palette.accent,
      icon: Icon(icon),
    );
  }
}
