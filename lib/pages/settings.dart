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

  @override
  void initState() {
    super.initState();
    _loadSwitchStates();
  }

  Future<void> _loadSwitchStates() async {
    final portrait = await StorageManager.getOptimizedPortrait();
    final landscape = await StorageManager.getOptimizedLandscape();
    setState(() {
      isOptimizedPortrait = portrait;
      isOptimizedLandscape = landscape;
    });
  }

  Future<void> _updateSwitch(String type, bool value) async {
    if (type == 'portrait') {
      await StorageManager.saveOptimizedPortrait(value);
      setState(() => isOptimizedPortrait = value);
    } else {
      await StorageManager.saveOptimizedLandscape(value);
      setState(() => isOptimizedLandscape = value);
    }
  }

  Widget _buildSwitch(String title, bool value, String type) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        Switch(
          value: value,
          onChanged: (v) => _updateSwitch(type, v),
          activeColor: const Color.fromARGB(255, 2, 92, 50),
        ),
      ],
    );
  }

  Widget _buildCard(Widget child) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBFB),
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: const Color(0xFFD6D6D6)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 3,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 22),
        title: const Text('Settings'),
        backgroundColor: const Color.fromARGB(255, 2, 92, 50),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCard(
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Text(
                      'السلام عليكم ورحمة الله وبركاته',
                      style: TextStyle(
                        fontSize: 29,
                        fontFamily: 'Amiri',
                        fontWeight: FontWeight.bold,
                        color: Color.fromARGB(255, 2, 92, 50),
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  Row(
                    children: [
                      Icon(Icons.bookmark, size: 30, color: Color.fromARGB(255, 2, 92, 50)),
                      SizedBox(width: 10),
                      Text(
                        'To Use Bookmarks:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text(
                    '1. While viewing the PDF, tap on the bookmarks icon to save the current page as a bookmark.',
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                  SizedBox(height: 10),
                  Text(
                    '2. To access your bookmarks later, tap on the bookmarks icon again and select the desired bookmark from the list.',
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                  SizedBox(height: 20),
                  Row(
                    children: [
                      Icon(Icons.star, size: 30, color: Color(0xFFD9B44A)),
                      SizedBox(width: 10),
                      Text(
                        'Praise Our App:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Kindly support our efforts by leaving positive reviews on the app store. Your feedback encourages charitable actions.',
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Additionally, feel free to share any suggestions or enhancements you would like us to consider. Your input is invaluable to us.',
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildCard(
              Column(
                children: [
                  _buildSwitch('Optimized Portrait Quran', isOptimizedPortrait, 'portrait'),
                  const SizedBox(height: 20),
                  Divider(color: Colors.grey.shade400),
                  const SizedBox(height: 20),
                  _buildSwitch('Optimized Landscape Quran', isOptimizedLandscape, 'landscape'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
