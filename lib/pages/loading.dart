import 'dart:io';
import 'package:dio/dio.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mushaf_two_page/main.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  LoadingScreenState createState() => LoadingScreenState();
}

class LoadingScreenState extends State<LoadingScreen> {
  double _progress = 0.0;
  double _totalMB = 0;
  double _downloadedMB = 0;
  bool _downloadFailed = false;

  @override
  void initState() {
    super.initState();
    print('[LOADING][1] Loading screen initState called');

    // Defer heavy work until after first frame
    Future.microtask(() {
      _checkAndDownloadAssets();
    });
  }

  Future<void> _checkAndDownloadAssets() async {
    print('[LOADING][3] _checkAndDownloadAssets start');

    try {
      final prefs = await SharedPreferences.getInstance();

      final assetsDownloaded =
          prefs.getBool('assetsDownloaded2') ?? false;
      print('[LOADING][5] assetsDownloaded flag = $assetsDownloaded');

      final filesExist = await _checkFilesExist();
      print('[LOADING][7] Files exist = $filesExist');

      if (!assetsDownloaded || !filesExist) {
        print('[LOADING][8] Assets missing, starting download');
        final success = await _downloadAssets();

        if (success) {
          print('[LOADING][9] Download successful, saving flag');
          await prefs.setBool('assetsDownloaded2', true);
        } else {
          print('[LOADING][10] Download failed');
          if (mounted) {
            setState(() => _downloadFailed = true);
          }
          return;
        }
      } else {
        print('[LOADING][8b] Assets already present, skipping download');
      }

      print('[LOADING][11] Scheduling navigation to MyPDFViewer');

      if (!mounted) return;  // Always check
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MyPDFViewer()),
      );
    } catch (e, stack) {
      print('[LOADING][ERROR] Exception in asset check');
      print(e);
      print(stack);

      if (mounted) {
        setState(() => _downloadFailed = true);
      }
    }
  }

  Future<bool> _checkFilesExist({int threshold = 400}) async {
    final dir = await getApplicationDocumentsDirectory();
    final quranDir = Directory('${dir.path}/quran/13line');

    if (!await quranDir.exists()) return false;

    final files = quranDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.webp'));

    int count = 0;
    for (final file in files) {
      count++;
      if (count >= threshold) return true; // early exit
    }

    return false;
  }

  Future<bool> _downloadAssets() async {
    print('[DOWNLOAD] Quran images download start');

    try {
      final storage = FirebaseStorage.instance;
      final ref =
      storage.ref('Quran-images/Quran-13-line-tajweed');

      final dir = await getApplicationDocumentsDirectory();
      final localDir = Directory('${dir.path}/quran/13line');

      if (!await localDir.exists()) {
        await localDir.create(recursive: true);
      }

      final result = await ref.listAll();

      int totalBytes = 0;
      int downloadedBytes = 0;

      // 🔹 First pass: calculate total size
      for (final item in result.items) {
        final meta = await item.getMetadata();
        totalBytes += meta.size ?? 0;
      }

      if (mounted) {
        setState(() {
          _totalMB = totalBytes / (1024 * 1024);
          _downloadedMB = 0;
          _progress = 0;
        });
      }

      print('Found ${result.items.length} pages in Firebase');

      // 🔹 Download files one by one (Firebase native)
      for (final item in result.items) {
        final filePath = '${localDir.path}/${item.name}';
        final file = File(filePath);

        // Skip already downloaded files
        if (await file.exists()) {
          downloadedBytes += await file.length();
          continue;
        }

        final task = item.writeToFile(file);

        task.snapshotEvents.listen((snapshot) {
          if (!mounted || snapshot.totalBytes <= 0) return;

          setState(() {
            _downloadedMB =
                (downloadedBytes + snapshot.bytesTransferred) /
                    (1024 * 1024);
            _progress =
                (downloadedBytes + snapshot.bytesTransferred) /
                    totalBytes;
          });
        });

        await task;
        downloadedBytes += await file.length();
      }

      print('[DOWNLOAD] Quran images download complete');
      return true;
    } catch (e, stack) {
      print('[DOWNLOAD][ERROR]');
      print(e);
      print(stack);
      return false;
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2A6767),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 3),

              // App mark / title
              const Text(
                'Quran',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Preparing your Mushaf',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),

              const Spacer(flex: 2),

              // Progress section
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                      minHeight: 6,
                      backgroundColor: Colors.white.withOpacity(0.15),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFD6D85F), // softer gold
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _progress > 0 ? 'Downloading' : 'Starting…',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        _progress > 0
                            ? '${_downloadedMB.toStringAsFixed(0)} / ${_totalMB.toStringAsFixed(0)} MB'
                            : '',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              if (_downloadFailed) ...[
                const SizedBox(height: 32),
                Text(
                  'Download failed',
                  style: TextStyle(
                    color: Colors.redAccent.withOpacity(0.9),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _progress = 0;
                      _downloadFailed = false;
                    });
                    _checkAndDownloadAssets();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Retry'),
                ),
              ],

              const Spacer(flex: 3),

              // Footnote reassurance
              const Text(
                'Can take a few minutes!',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}