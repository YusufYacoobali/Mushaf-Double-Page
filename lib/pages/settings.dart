import 'package:flutter/material.dart';
import 'package:mushaf_two_page/logic/storage_manager.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {

  static const _darkBg = Color.fromARGB(255, 17, 38, 8);
  static const _lightBg = Color.fromARGB(255, 235, 243, 236);
  static const _accent = Color.fromARGB(255, 2, 92, 50);

  bool isDarkMode = false;
  String selectedMushaf = 'indopak';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadStates();
  }

  Future<void> _loadStates() async {
    final dark = await StorageManager.getDarkMode();
    final mushaf = await StorageManager.getMushaf();

    setState(() {
      isDarkMode = dark;
      selectedMushaf = mushaf;
      _loaded = true;
    });
  }

  Future<void> _updateDarkMode(bool value) async {
    await StorageManager.saveDarkMode(value);

    setState(() {
      isDarkMode = value;
    });
  }

  Future<void> _updateMushaf(String mushaf) async {
    if (mushaf == selectedMushaf) return;

    if (mushaf == 'madani') {
      _showDownloadingDialog();
      await StorageManager.ensureMushafDownloaded("madani", 2);
      Navigator.pop(context);
    }

    await StorageManager.saveMushaf(mushaf);

    setState(() {
      selectedMushaf = mushaf;
    });
  }

  void _showDownloadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Expanded(
                  child: Text(
                    'Downloading Mushaf...',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
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
          color: color.withOpacity(.8),
        ),
      ),
    );
  }

  Widget _settingsCard(Widget child, Color cardColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: child,
    );
  }

  Widget _buildSwitch(String title, bool value, Color textColor) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _updateDarkMode(!value),
      child: Row(
        children: [
          const Icon(Icons.dark_mode_rounded, color: _accent),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: _updateDarkMode,
            activeColor: _accent,
          ),
        ],
      ),
    );
  }

  Widget _buildMushafOption({
    required String title,
    required String value,
    required String previewImage,
    required bool isDark,
    required Color textPrimary,
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
          color: isDark ? const Color(0xFF1E2A1B) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? _accent : Colors.grey.withOpacity(.2),
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
                  const Icon(Icons.check_circle, size: 18, color: _accent),

                if (isSelected) const SizedBox(width: 6),

                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
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

  Widget _infoTile({
    required IconData icon,
    required String title,
    required String text,
    required Color color,
  }) {
    final textPrimary = Colors.black87;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(.12),
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
                  color: textPrimary,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                text,
                style: TextStyle(fontSize: 14, color: textPrimary),
              ),
            ],
          ),
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {

    if (!_loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isDark = isDarkMode;
    final bg = isDark ? _darkBg : _lightBg;
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final cardColor = isDark ? _lightBg : Colors.white;

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

            _sectionTitle('HELP', textPrimary),

            _settingsCard(
              Column(
                children: [

                  _infoTile(
                    icon: Icons.bookmark_rounded,
                    title: 'Bookmarks',
                    text:
                    'Save pages while reading and jump back to them later.',
                    color: _accent,
                  ),

                  const SizedBox(height: 18),

                  _infoTile(
                    icon: Icons.star_rounded,
                    title: 'Support the app',
                    text:
                    'Leaving a positive review helps the project grow.',
                    color: const Color(0xFFD9B44A),
                  ),
                ],
              ),
              cardColor,
            ),

            _sectionTitle('APPEARANCE', textPrimary),

            _settingsCard(
              _buildSwitch('Dark Mode', isDarkMode, Colors.black87),
              cardColor,
            ),

            _sectionTitle('QURAN LAYOUT', textPrimary),

            _settingsCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Text(
                    'Choose the Mushaf layout you prefer.',
                    style: TextStyle(fontSize: 14, color: Colors.black87),
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
                          isDark: isDark,
                          textPrimary: textPrimary,
                        ),

                        _buildMushafOption(
                          title: 'Madani (15 lines)',
                          value: 'madani',
                          previewImage:
                          'assets/mushaf/madani_preview.png',
                          isDark: isDark,
                          textPrimary: textPrimary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              cardColor,
            ),
          ],
        ),
      ),
    );
  }
}