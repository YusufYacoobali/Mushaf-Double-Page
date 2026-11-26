import 'package:mushaf_two_page/utils/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/audio_preferences.dart';

class AudioModal extends StatefulWidget {
  final int initialSurah;
  final QuranAudioController? controller;

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
    this.controller,
  });

  static void show(
    BuildContext context, {
    required int initialSurah,
    int? initialFromAyah,
    int? initialToAyah,
  }) {
    showModalBottomSheet(
      sheetAnimationStyle: AppMotion.style(context),
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
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
  static const List<int> _repeatOptions = [1, 3, 5, 10];

  Reciter _reciter = quranReciters.first;
  late int _surah;
  int _fromAyah = 1;
  int _toAyah = 7;
  int? _repeatCount = 10;
  AudioRepeatMode _repeatMode = AudioRepeatMode.range;
  AudioSourceMode _sourceMode = AudioSourceMode.range;
  List<int>? _ayahOptions;
  int? _ayahOptionsSurah;
  bool _preferencesReady = false;
  List<int> _surahQueue = [];

  @override
  void initState() {
    super.initState();
    // The location always follows the page the reader is currently viewing.
    // Saved preferences restore the reciter/repeat choices, not an old surah.
    _surah = widget.initialSurah.clamp(1, 114).toInt();
    final maxAyah = quranAyahCounts[_surah - 1];
    if (widget.initialFromAyah != null && widget.initialToAyah != null) {
      _fromAyah = widget.initialFromAyah!.clamp(1, maxAyah).toInt();
      _toAyah = widget.initialToAyah!.clamp(_fromAyah, maxAyah).toInt();
      _sourceMode = AudioSourceMode.range;
    } else {
      _toAyah = _ayahCount.clamp(1, 7).toInt();
    }
    _restorePreferences();
  }

  QuranAudioController get _controller =>
      widget.controller ?? QuranAudioController.instance;

  int get _ayahCount => quranAyahCounts[_surah - 1];

  Future<void> _restorePreferences() async {
    final saved = await AudioPreferences.load();
    if (!mounted) return;
    if (saved != null) {
      _reciter = quranReciters.firstWhere(
        (reciter) => reciter.id == saved.reciterId,
        orElse: () => quranReciters.first,
      );
      _repeatCount = saved.repeatCount == null
          ? null
          : _repeatOptions.contains(saved.repeatCount)
          ? saved.repeatCount
          : 10;
      _repeatMode = saved.repeatMode;
      _surahQueue = List.of(saved.surahQueue);
      if (saved.surah == _surah && widget.initialFromAyah == null) {
        final maxAyah = quranAyahCounts[_surah - 1];
        _fromAyah = saved.fromAyah.clamp(1, maxAyah).toInt();
        _toAyah = saved.toAyah.clamp(_fromAyah, maxAyah).toInt();
        _sourceMode = saved.sourceMode;
      }
    }
    final active = _controller.plan;
    if (active != null &&
        (_controller.hasActivePlayback || _controller.preparing)) {
      _reciter = active.reciter;
      _surah = active.surah;
      _fromAyah = active.fromAyah;
      _toAyah = active.toAyah;
      _repeatCount = active.repeatCount;
      _repeatMode = active.repeatMode;
      _sourceMode = active.sourceMode;
      if (active.sourceMode == AudioSourceMode.playlist) {
        _surahQueue = List.of(active.surahQueue);
      }
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
        surahQueue: List.of(_surahQueue),
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
      surahQueue: List.unmodifiable(_surahQueue),
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

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.headphones_rounded,
                    color: palette.accent,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Audio',
                      style: TextStyle(
                        color: palette.surfaceText,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded, color: palette.surfaceText),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _compactSelect<Reciter>(
                      palette: palette,
                      icon: Icons.person_outline_rounded,
                      value: _reciter,
                      items: quranReciters,
                      label: (reciter) => reciter.name,
                      menuWidth: (MediaQuery.sizeOf(context).width - 32)
                          .clamp(240.0, 360.0)
                          .toDouble(),
                      onChanged: (reciter) {
                        setState(() => _reciter = reciter);
                        _persistPreferences();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _compactSelect<int>(
                      palette: palette,
                      icon: Icons.menu_book_outlined,
                      value: _surah,
                      items: [for (var i = 1; i <= 114; i++) i],
                      label: (surah) =>
                          '$surah. ${quranSurahs[surah - 1].name}',
                      onChanged: _setSurah,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _compactSelect<AudioSourceMode>(
                      palette: palette,
                      icon: Icons.playlist_play_rounded,
                      value: _sourceMode,
                      items: AudioSourceMode.values,
                      label: (mode) => switch (mode) {
                        AudioSourceMode.range => 'Ayah range',
                        AudioSourceMode.surah => 'Full surah',
                        AudioSourceMode.playlist => 'Surah queue',
                      },
                      onChanged: (mode) {
                        if (mode == AudioSourceMode.playlist) {
                          _showSurahQueue();
                          return;
                        }
                        setState(() => _sourceMode = mode);
                        _persistPreferences();
                        if (mode == AudioSourceMode.range) _warmAyahOptions();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _compactAction(
                      palette: palette,
                      icon: _sourceMode == AudioSourceMode.playlist
                          ? Icons.playlist_play_rounded
                          : Icons.format_list_numbered_rounded,
                      label: _sourceMode == AudioSourceMode.playlist
                          ? '${_surahQueue.length} surahs · Edit'
                          : _sourceMode == AudioSourceMode.surah
                          ? 'All ayahs'
                          : 'Ayah $_fromAyah-$_toAyah',
                      onTap: _sourceMode == AudioSourceMode.playlist
                          ? _showSurahQueue
                          : _showAyahRangePicker,
                      enabled: _sourceMode != AudioSourceMode.surah,
                    ),
                  ),
                ],
              ),
              if (_sourceMode == AudioSourceMode.playlist)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Your queue plays in selection order. Playback starts with the first recording while the next ayahs download.',
                    style: TextStyle(
                      color: palette.surfaceMuted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Divider(height: 1, color: palette.border.withValues(alpha: .8)),
              const SizedBox(height: 10),
              _compactSelect<AudioRepeatMode>(
                palette: palette,
                icon: Icons.repeat_rounded,
                value: _repeatMode,
                items: AudioRepeatMode.values,
                label: (mode) => mode == AudioRepeatMode.range
                    ? (_sourceMode == AudioSourceMode.playlist
                          ? 'Repeat entire queue'
                          : 'Range repeat')
                    : 'Verse repeat',
                onChanged: (mode) {
                  setState(() => _repeatMode = mode);
                  _persistPreferences();
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    for (final count in <int?>[..._repeatOptions, null]) ...[
                      Expanded(child: _repeatChoice(palette, count: count)),
                      if (count != null) const SizedBox(width: 7),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final controller = _controller;
                  return _compactPlayer(palette, controller);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactPlayer(AppPalette palette, QuranAudioController controller) {
    final editedPlan = _plan;
    final isThisPlan = editedPlan.matches(controller.plan);
    final isPlaying = isThisPlan && controller.playing;
    final hasActiveAudio = controller.preparing || controller.hasActivePlayback;
    final canResume = isThisPlan && controller.paused;
    final canRetry =
        isThisPlan && controller.phase == QuranPlaybackPhase.failed;
    final isPreparing =
        isThisPlan && controller.preparing && !controller.paused;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.downloadState.active) ...[
          LinearProgressIndicator(
            value: controller.downloadState.progress,
            minHeight: 4,
            borderRadius: BorderRadius.circular(99),
            backgroundColor: palette.accentSoft,
            color: palette.accent,
          ),
          const SizedBox(height: 7),
        ],
        if (controller.error != null) ...[
          Text(
            controller.error!,
            style: const TextStyle(
              color: Color(0xFF9E1B1B),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: controller.retry,
                child: const Text('Retry'),
              ),
              TextButton(
                onPressed: controller.seekNext,
                child: Text(
                  controller.isIntroduction
                      ? 'Continue without Bismillah'
                      : 'Skip ayah',
                ),
              ),
              TextButton(onPressed: controller.stop, child: const Text('Stop')),
            ],
          ),
          const SizedBox(height: 7),
        ],
        Text(
          '${controller.currentItem?.label ?? ""} · ${controller.statusLabel}',
          style: TextStyle(color: palette.surfaceMuted, fontSize: 12),
        ),
        if (controller.downloadState.message.isNotEmpty)
          Text(
            controller.downloadState.message,
            style: TextStyle(color: palette.surfaceMuted, fontSize: 12),
          ),
        if (controller.introductionNotice != null)
          Text(
            controller.introductionNotice!,
            style: TextStyle(color: palette.surfaceMuted, fontSize: 12),
          ),
        if (controller.offlineDownloading)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: controller.cancelDownload,
              child: const Text('Cancel saving offline'),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: isPreparing
                    ? null
                    : () {
                        if (canRetry) {
                          controller.retry();
                        } else if (isPlaying || canResume) {
                          controller.togglePlayPause();
                        } else {
                          controller.playPlan(editedPlan);
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.onAccent,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: Icon(
                  isPreparing
                      ? Icons.hourglass_empty_rounded
                      : isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
                label: Text(
                  isPreparing
                      ? controller.statusLabel
                      : isPlaying
                      ? 'Pause'
                      : canRetry
                      ? 'Retry'
                      : canResume
                      ? 'Resume'
                      : 'Play',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (hasActiveAudio) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: controller.stop,
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.accent,
                  minimumSize: const Size(102, 54),
                  side: BorderSide(color: palette.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.stop_rounded, size: 20),
                label: const Text(
                  'Stop',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _compactSelect<T>({
    required AppPalette palette,
    required IconData icon,
    required T value,
    required List<T> items,
    required String Function(T value) label,
    required void Function(T value) onChanged,
    double? menuWidth,
  }) {
    return Container(
      height: 52,
      padding: const EdgeInsets.only(left: 10, right: 5),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: palette.accent, size: 20),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                dropdownColor: palette.surfaceRaised,
                borderRadius: BorderRadius.circular(15),
                menuWidth: menuWidth,
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: palette.surfaceText,
                  size: 20,
                ),
                style: TextStyle(
                  color: palette.surfaceText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                items: [
                  for (final item in items)
                    DropdownMenuItem<T>(
                      value: item,
                      child: Text(label(item), overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (selected) {
                  if (selected != null) onChanged(selected);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactAction({
    required AppPalette palette,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    double? width,
    bool enabled = true,
  }) {
    return SizedBox(
      width: width,
      height: 52,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: enabled
                ? palette.surfaceRaised
                : palette.surfaceRaised.withValues(alpha: .55),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: enabled ? palette.accent : palette.surfaceMuted,
                size: 20,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? palette.surfaceText : palette.surfaceMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (enabled)
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: palette.surfaceText,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _repeatChoice(AppPalette palette, {required int? count}) {
    final selected = _repeatCount == count;
    return InkWell(
      onTap: () {
        setState(() => _repeatCount = count);
        _persistPreferences();
      },
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        constraints: const BoxConstraints(minWidth: 46),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? palette.accent : palette.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? palette.accent : palette.border),
        ),
        child: Text(
          count == null ? '∞' : '${count}x',
          style: TextStyle(
            color: selected ? palette.onAccent : palette.surfaceText,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Future<void> _showSurahQueue() async {
    final selected = _surahQueue.isEmpty
        ? <int>[_surah]
        : List<int>.of(_surahQueue);
    final palette = AppPalette.of(context);
    final result = await showModalBottomSheet<List<int>>(
      sheetAnimationStyle: AppMotion.style(context),
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: palette.surface,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) {
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .72,
              child: Column(
                children: [
                  const Text(
                    'Your listening queue',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Select surahs in the order you want to hear them.',
                    ),
                  ),
                  if (selected.isNotEmpty)
                    SizedBox(
                      height: 52,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (var i = 0; i < selected.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: InputChip(
                                label: Text(
                                  '${i + 1}. ${quranSurahs[selected[i] - 1].name}',
                                ),
                                onDeleted: () =>
                                    refresh(() => selected.removeAt(i)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: 114,
                      itemBuilder: (context, i) => CheckboxListTile(
                        title: Text('${i + 1}. ${quranSurahs[i].name}'),
                        subtitle: Text('${quranAyahCounts[i]} ayahs'),
                        value: selected.contains(i + 1),
                        onChanged: (checked) => refresh(() {
                          if (checked == true) {
                            selected.add(i + 1);
                          } else {
                            selected.remove(i + 1);
                          }
                        }),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () => Navigator.pop(context, selected),
                        child: Text('Save queue · ${selected.length} surahs'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _surahQueue = result;
      _sourceMode = AudioSourceMode.playlist;
    });
    _persistPreferences();
  }

  Future<void> _showAyahRangePicker() async {
    _ensureAyahOptions();
    final palette = AppPalette.of(context);
    await showModalBottomSheet<void>(
      sheetAnimationStyle: AppMotion.style(context),
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, refreshSheet) => Container(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Ayah range',
                  style: TextStyle(
                    color: palette.surfaceText,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
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
                            onChanged: (ayah) {
                              _setFromAyah(ayah);
                              refreshSheet(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('To ayah', palette),
                          _ayahDropdown(
                            palette: palette,
                            value: _toAyah,
                            onChanged: (ayah) {
                              _setToAyah(ayah);
                              refreshSheet(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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
}
