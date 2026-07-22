import 'package:flutter/material.dart';
import 'package:mushaf_two_page/logic/storage_manager.dart';
import 'package:mushaf_two_page/progress/progress_page.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/app_review.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  bool isDarkMode = false;
  bool isAppDarkMode = false;
  bool ayahHighlightingEnabled = true;
  String selectedMushaf = 'indopak_tajweed';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadStates();
  }

  Future<void> _loadStates() async {
    final dark = await StorageManager.getDarkMode();
    final appDark = await StorageManager.getAppDarkMode();
    final mushaf = await StorageManager.getMushaf();
    final ayahHighlighting = await StorageManager.getAyahHighlightingEnabled();

    setState(() {
      isDarkMode = dark;
      isAppDarkMode = appDark;
      selectedMushaf = mushaf;
      ayahHighlightingEnabled = ayahHighlighting;
      _loaded = true;
    });
  }

  Future<void> _updateDarkMode(bool value) async {
    await StorageManager.saveDarkMode(value);
    setState(() => isDarkMode = value);
  }

  Future<void> _updateAppDarkMode(bool value) async {
    await StorageManager.saveAppDarkMode(value);
    setState(() => isAppDarkMode = value);
  }

  Future<void> _updateAyahHighlighting(bool value) async {
    await StorageManager.saveAyahHighlightingEnabled(value);
    setState(() => ayahHighlightingEnabled = value);
  }

  Future<void> _updateMushaf(String mushaf) async {
    if (mushaf == selectedMushaf) return;

    final version = _versionForMushaf(mushaf);
    final needsDownload =
        !await StorageManager.isMushafUpToDate(mushaf, version) ||
        !await StorageManager.isMushafAvailable(mushaf);

    if (!mounted) return;

    ValueNotifier<MushafDownloadProgress>? progress;

    if (needsDownload) {
      progress = ValueNotifier(
        const MushafDownloadProgress('Preparing download'),
      );
      _showDownloadingDialog(progress);

      var downloadSucceeded = false;
      try {
        await StorageManager.ensureMushafDownloaded(
          mushaf,
          version,
          onProgress: (value) {
            progress?.value = value;
          },
        );
        downloadSucceeded = true;
      } catch (_) {
      } finally {
        if (mounted) {
          Navigator.pop(context);
        }
        progress.dispose();
      }

      if (!downloadSucceeded) {
        await _showDownloadErrorDialog();
        return;
      }
    }

    if (!mounted) return;

    await StorageManager.saveMushaf(mushaf);

    setState(() {
      selectedMushaf = mushaf;
    });
  }

  int _versionForMushaf(String mushaf) {
    return mushaf == 'indopak_tajweed' ? 1 : 2;
  }

  void _showDownloadingDialog(ValueNotifier<MushafDownloadProgress> progress) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ValueListenableBuilder<MushafDownloadProgress>(
              valueListenable: progress,
              builder: (context, value, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      value.message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    LinearProgressIndicator(
                      value: value.value,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(999),
                      backgroundColor: AppPalette.forDarkMode(
                        isDarkMode,
                      ).accent.withValues(alpha: .12),
                      color: AppPalette.forTheme(
                        mushafDark: isDarkMode,
                        appDark: isAppDarkMode,
                      ).accent,
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDownloadErrorDialog() async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Download failed'),
          content: const Text(
            'Please check your connection and try changing Mushaf again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionTitle(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: .3,
          color: color.withValues(alpha: .8),
        ),
      ),
    );
  }

  Widget _settingsCard(Widget child, AppPalette palette) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border.withValues(alpha: .7)),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSwitch(
    String title,
    bool value,
    AppPalette palette,
    ValueChanged<bool> onChanged, {
    IconData icon = Icons.dark_mode_rounded,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Icon(icon, color: palette.accent),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: palette.surfaceText,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: palette.accent,
          ),
        ],
      ),
    );
  }

  Widget _buildMushafOption({
    required String title,
    required String value,
    required String previewImage,
    required AppPalette palette,
  }) {
    final bool isSelected = selectedMushaf == value;

    return GestureDetector(
      onTap: () => _updateMushaf(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 210,
        margin: const EdgeInsets.only(right: 16),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? palette.accent : palette.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                previewImage,
                height: 170,
                width: double.infinity,
                fit: BoxFit.fill,
              ),
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                if (isSelected)
                  Icon(Icons.check_circle, size: 18, color: palette.accent),

                if (isSelected) const SizedBox(width: 6),

                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: palette.surfaceText,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _navTile({
    required AppPalette palette,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: palette.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: palette.surfaceText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 14, color: palette.surfaceMuted),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: palette.surfaceMuted),
        ],
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String title,
    required String text,
    required Color color,
    required AppPalette palette,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color),
        ),

        const SizedBox(width: 14),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: palette.surfaceText,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                text,
                style: TextStyle(fontSize: 14, color: palette.surfaceMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final palette = AppPalette.forTheme(
      mushafDark: isDarkMode,
      appDark: isAppDarkMode,
    );
    final bg = palette.scaffold;
    final textPrimary = palette.text;

    return Scaffold(
      backgroundColor: bg,

      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: false,
        title: Text(
          'Settings',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: textPrimary),
          onPressed: () => Navigator.pop(context, true),
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                'السلام عليكم ورحمة الله وبركاته',
                style: TextStyle(
                  fontSize: 26,
                  fontFamily: 'Amiri',
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                ),
              ),
            ),

            const SizedBox(height: 24),

            _sectionTitle('PRACTICE', textPrimary),

            _settingsCard(
              _navTile(
                palette: palette,
                icon: Icons.local_fire_department_rounded,
                title: 'Day Streak',
                subtitle: 'Keep your daily Quran reading streak going.',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProgressPage()),
                ),
              ),
              palette,
            ),

            _sectionTitle('HELP', textPrimary),

            _settingsCard(
              Column(
                children: [
                  _infoTile(
                    icon: Icons.bookmark_rounded,
                    title: 'Bookmarks',
                    text:
                        'Save pages while reading and jump back to them later.',
                    color: palette.accent,
                    palette: palette,
                  ),

                  const SizedBox(height: 18),

                  GestureDetector(
                    onTap: () => AppReview.requestFromUser(),
                    child: _infoTile(
                      icon: Icons.star_rounded,
                      title: 'Rate the app',
                      text:
                          'Enjoying the app? Tap here to leave a review — it really helps.',
                      color: const Color(0xFFD9B44A),
                      palette: palette,
                    ),
                  ),
                ],
              ),
              palette,
            ),

            _sectionTitle('APPEARANCE', textPrimary),

            _settingsCard(
              _buildSwitch(
                'Dark Mode',
                isAppDarkMode,
                palette,
                _updateAppDarkMode,
                icon: Icons.nights_stay_rounded,
              ),
              palette,
            ),

            _settingsCard(
              _buildSwitch(
                'Mushaf Dark Mode',
                isDarkMode,
                palette,
                _updateDarkMode,
              ),
              palette,
            ),

            _sectionTitle('QURAN READER', textPrimary),

            _settingsCard(
              _buildSwitch(
                'Ayah highlighting',
                ayahHighlightingEnabled,
                palette,
                _updateAyahHighlighting,
                icon: Icons.highlight_alt_rounded,
              ),
              palette,
            ),

            _sectionTitle('QURAN LAYOUT', textPrimary),

            _settingsCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose the Mushaf layout you prefer.',
                    style: TextStyle(fontSize: 14, color: palette.surfaceMuted),
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    height: 250,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _buildMushafOption(
                          title: 'Indo-Pak Tajweed (13 lines)',
                          value: 'indopak_tajweed',
                          previewImage:
                              'assets/mushaf/indopak_tajweed_preview.png',
                          palette: palette,
                        ),

                        _buildMushafOption(
                          title: 'Madani (15 lines)',
                          value: 'madani',
                          previewImage: 'assets/mushaf/madani_preview.png',
                          palette: palette,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              palette,
            ),
          ],
        ),
      ),
    );
  }
}
