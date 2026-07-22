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
  static const List<int> _repeatOptions = [1, 3, 5, 10];

  Reciter _reciter = quranReciters.first;
  late int _surah;
  int _fromAyah = 1;
  int _toAyah = 7;
  int? _repeatCount = 10;
  AudioRepeatMode _repeatMode = AudioRepeatMode.range;
  AudioSourceMode _sourceMode = AudioSourceMode.range;
  QuranAudioErrorKind _lastHandledErrorKind = QuranAudioErrorKind.none;
  List<int>? _ayahOptions;
  int? _ayahOptionsSurah;
  bool _preferencesReady = false;

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
      if (saved.surah == _surah) {
        final maxAyah = quranAyahCounts[_surah - 1];
        _fromAyah = saved.fromAyah.clamp(1, maxAyah).toInt();
        _toAyah = saved.toAyah.clamp(_fromAyah, maxAyah).toInt();
        _sourceMode = saved.sourceMode;
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
                      label: (mode) => mode == AudioSourceMode.range
                          ? 'Ayah range'
                          : 'Full surah',
                      onChanged: (mode) {
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
                      icon: Icons.format_list_numbered_rounded,
                      label: _sourceMode == AudioSourceMode.surah
                          ? 'All ayahs'
                          : 'Ayah $_fromAyah-$_toAyah',
                      onTap: _showAyahRangePicker,
                      enabled: _sourceMode == AudioSourceMode.range,
                    ),
                  ),
                ],
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
                    ? 'Range repeat'
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
    final isDownloading = controller.downloadState.active && isThisPlan;
    final isPlaying = isThisPlan && controller.playing;
    final hasActiveAudio =
        controller.hasPlan &&
        controller.processingState != ProcessingState.idle &&
        controller.processingState != ProcessingState.completed;
    final canResume =
        isThisPlan &&
        controller.hasPlan &&
        !controller.playing &&
        controller.processingState != ProcessingState.idle &&
        controller.processingState != ProcessingState.completed;

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
          const SizedBox(height: 7),
        ],
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: isDownloading
                    ? null
                    : () {
                        if (isPlaying || canResume) {
                          controller.togglePlayPause();
                        } else {
                          controller.playPlan(editedPlan);
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: Icon(
                  isDownloading
                      ? Icons.hourglass_top_rounded
                      : isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
                label: Text(
                  isDownloading
                      ? 'Preparing'
                      : isPlaying
                      ? 'Pause'
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
            color: selected ? Colors.white : palette.surfaceText,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Future<void> _showAyahRangePicker() async {
    _ensureAyahOptions();
    final palette = AppPalette.of(context);
    await showModalBottomSheet<void>(
      context: context,
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
