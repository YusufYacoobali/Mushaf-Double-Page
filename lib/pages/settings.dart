import 'package:flutter/material.dart';
import 'package:mushaf_two_page/logic/storage_manager.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  bool isDarkMode = false;

  /// Selected Mushaf
  String selectedMushaf = 'madani';

  /// Prevent UI rendering before async values load
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadStates();
  }

  /// Load saved settings
  Future<void> _loadStates() async {
    final dark = await StorageManager.getDarkMode();
    final mushaf = await StorageManager.getMushaf();

    setState(() {
      isDarkMode = dark;
      selectedMushaf = mushaf;
      _loaded = true;
    });
  }

  /// Update dark mode
  Future<void> _updateDarkMode(bool value) async {
    await StorageManager.saveDarkMode(value);

    setState(() {
      isDarkMode = value;
    });
  }

  /// Update mushaf
  Future<void> _updateMushaf(String mushaf) async {
    await StorageManager.saveMushaf(mushaf);

    setState(() {
      selectedMushaf = mushaf;
    });
  }

  /// Switch row widget
  Widget _buildSwitch(String title, bool value) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _updateDarkMode(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            Switch(
              value: value,
              onChanged: _updateDarkMode,
              activeColor: const Color.fromARGB(255, 2, 92, 50),
            ),
          ],
        ),
      ),
    );
  }

  /// Mushaf selector option
  Widget _buildMushafOption({
    required String title,
    required String value,
    required String previewImage,
  }) {
    final bool isSelected = selectedMushaf == value;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _updateMushaf(value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color.fromARGB(255, 2, 92, 50)
                : Colors.grey.shade300,
            width: 2,
          ),
          color: isSelected
              ? const Color.fromARGB(255, 2, 92, 50).withOpacity(0.06)
              : Colors.white,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                previewImage,
                width: 60,
                height: 80,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: Color.fromARGB(255, 2, 92, 50),
              ),
          ],
        ),
      ),
    );
  }

  /// Card container
  Widget _buildCard(Widget child) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBFB),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 235, 243, 236),
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 235, 243, 236),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        title: const Text(
          'Settings',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1F4F4F),
            letterSpacing: 0.2,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: Color(0xFF1F4F4F),
          ),
          onPressed: () => Navigator.pop(context, true),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            /// Info card
            _buildCard(
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Text(
                      'السلام عليكم ورحمة الله وبركاته',
                      style: TextStyle(
                        fontSize: 26,
                        fontFamily: 'Amiri',
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 2, 92, 50),
                      ),
                    ),
                  ),
                  SizedBox(height: 24),

                  Row(
                    children: [
                      Icon(
                        Icons.bookmark_rounded,
                        size: 28,
                        color: Color.fromARGB(255, 2, 92, 50),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Using bookmarks',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 12),

                  Text(
                    'Save pages while reading and jump back to them later using the bookmarks icon.',
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),

                  SizedBox(height: 20),

                  Row(
                    children: [
                      Icon(Icons.star_rounded, size: 28, color: Color(0xFFD9B44A)),
                      SizedBox(width: 10),
                      Text(
                        'Support the app',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 12),

                  Text(
                    'Leaving a positive review helps us continue improving the app.',
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                ],
              ),
            ),

            /// Appearance
            _buildCard(
              Column(
                children: [
                  _buildSwitch(
                    'Dark Mode',
                    isDarkMode,
                  ),
                ],
              ),
            ),

            /// Mushaf selector
            _buildCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mushaf',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  _buildMushafOption(
                    title: 'Madani (15 lines)',
                    value: 'madani',
                    previewImage: 'assets/mushaf/madani_preview.jpeg',
                  ),

                  _buildMushafOption(
                    title: 'Indo-Pak (15 lines)',
                    value: 'indopak',
                    previewImage: 'assets/mushaf/indopak_tajweed_preview.png',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}