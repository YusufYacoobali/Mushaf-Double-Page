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
  String selectedMushaf = 'indopak';

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
    if (mushaf == selectedMushaf) return;

    if (mushaf == 'madani') {
      _showDownloadingDialog();
      await StorageManager.ensureMadaniDownloaded();
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
        return const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(
                child: Text('Downloading Mushaf...'),
              ),
            ],
          ),
        );
      },
    );
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

  Widget _buildMushafOption({
    required String title,
    required String value,
    required String previewImage,
  }) {
    final bool isSelected = selectedMushaf == value;

    return GestureDetector(
      onTap: () => _updateMushaf(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 220,
        margin: const EdgeInsets.only(right: 14),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? const Color.fromARGB(255, 2, 92, 50)
                : Colors.grey.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: const Color(0xFFF5F5F5),
                    child: Image.asset(
                      previewImage,
                      height: 170,
                      width: double.infinity,
                      fit: BoxFit.fill,
                    ),
                  ),
                ),

                if (isSelected)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color.fromARGB(255, 2, 92, 50),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(6),
                      child: const Icon(
                        Icons.check,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
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
            /// Mushaf selector
            _buildCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mushaf Choice',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),

                  const SizedBox(height: 6),

                  const Text(
                    'Choose the Qur’an layout you prefer.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),

                  const SizedBox(height: 14),

                  SizedBox(
                    height: 250,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _buildMushafOption(
                          title: 'Indo-Pak Tajweed (13 lines)',
                          value: 'indopak',
                          previewImage: 'assets/mushaf/indopak_tajweed_preview.png',
                        ),
                        _buildMushafOption(
                          title: 'Madani (15 lines)',
                          value: 'madani',
                          previewImage: 'assets/mushaf/madani_preview.jpeg',
                        ),
                      ],
                    ),
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