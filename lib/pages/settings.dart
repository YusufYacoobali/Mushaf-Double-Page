import 'package:flutter/material.dart';
import 'package:mushaf_two_page/logic/storage_manager.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  bool isOptimizedPortrait = true;
  bool isOptimizedLandscape = true;
  // Prevents UI rendering before async values load
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // Load saved switch values from storage on screen start
    _loadSwitchStates();
  }

  /// Reads saved preferences from StorageManager
  /// and updates local state once loaded
  Future<void> _loadSwitchStates() async {
    final portrait = await StorageManager.getOptimizedPortrait();
    final landscape = await StorageManager.getOptimizedLandscape();

    setState(() {
      isOptimizedPortrait = portrait;
      isOptimizedLandscape = landscape;
      _loaded = true;
    });
  }

  /// Handles switch changes and persists them
  /// `type` determines which setting is being updated
  Future<void> _updateSwitch(String type, bool value) async {
    if (type == 'portrait') {
      await StorageManager.saveOptimizedPortrait(value);
      setState(() => isOptimizedPortrait = value);
    } else {
      await StorageManager.saveOptimizedLandscape(value);
      setState(() => isOptimizedLandscape = value);
    }
  }

  /// Reusable switch row widget (now feels like a row, not just text)
  Widget _buildSwitch(String title, bool value, String type) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _updateSwitch(type, !value),
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
              onChanged: (v) => _updateSwitch(type, v),
              activeColor: const Color.fromARGB(255, 2, 92, 50),
            ),
          ],
        ),
      ),
    );
  }

  /// Card-style container (noticeably different)
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
        backgroundColor: const Color.fromARGB(255, 235, 243, 236), // soft green
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
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        child: SingleChildScrollView(
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

              /// Settings card
              _buildCard(
                Column(
                  children: [
                    _buildSwitch(
                      'Optimized Portrait Quran',
                      isOptimizedPortrait,
                      'portrait',
                    ),
                    const Divider(height: 1),
                    _buildSwitch(
                      'Optimized Landscape Quran',
                      isOptimizedLandscape,
                      'landscape',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
