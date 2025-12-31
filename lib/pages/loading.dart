import 'dart:io';
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

  Future<bool> _checkFilesExist() async {

    final dir = await getApplicationDocumentsDirectory();
    print('[FILES][2] App directory = ${dir.path}');

    final files = [
      'quran_source_double_close.pdf',
      'quran_source_v_l_s.pdf',
      'quran_source_v.pdf',
    ];

    for (final fileName in files) {
      final filePath = '${dir.path}/$fileName';
      final exists = await File(filePath).exists();

      if (!exists) return false;
    }

    return true;
  }

  Future<bool> _downloadAssets() async {
    print('[DOWNLOAD][1] _downloadAssets start');

    final files = [
      {
        'url':
        'https://firebasestorage.googleapis.com/v0/b/quran-pdfs.firebasestorage.app/o/qurans%2Fquran_source_double_close.pdf?alt=media',
        'name': 'quran_source_double_close.pdf',
      },
      {
        'url':
        'https://firebasestorage.googleapis.com/v0/b/quran-pdfs.firebasestorage.app/o/qurans%2Fquran_source_v_l_s.pdf?alt=media',
        'name': 'quran_source_v_l_s.pdf',
      },
      {
        'url':
        'https://firebasestorage.googleapis.com/v0/b/quran-pdfs.firebasestorage.app/o/qurans%2Fquran_source_v.pdf?alt=media',
        'name': 'quran_source_v.pdf',
      },
    ];

    final dir = await getApplicationDocumentsDirectory();
    final client = http.Client();

    try {
      int totalBytes = 0;
      int downloadedBytes = 0;

      // 🔹 HEAD pass to get total size
      for (final file in files) {
        final req = http.Request('HEAD', Uri.parse(file['url']!));
        final res = await client.send(req);
        totalBytes += res.contentLength ?? 0;
      }

      if (mounted) {
        setState(() {
          _totalMB = totalBytes / (1024 * 1024);
        });
      }

      print('[DOWNLOAD] Total bytes = $totalBytes');

      Future<void> downloadFile(Map<String, String> file) async {
        print('[DOWNLOAD] Starting ${file['name']}');

        final request = http.Request('GET', Uri.parse(file['url']!));
        final response = await client.send(request);

        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }

        final filePath = '${dir.path}/${file['name']}';
        final fileSink = File(filePath).openWrite();

        await response.stream.listen(
              (chunk) {
            fileSink.add(chunk);
            downloadedBytes += chunk.length;

            if (mounted && totalBytes > 0) {
              setState(() {
                _progress = downloadedBytes / totalBytes;
                _downloadedMB = downloadedBytes / (1024 * 1024);
              });
            }
          },
          onError: (e) {
            throw e;
          },
          onDone: () async {
            await fileSink.close();
            print('[DOWNLOAD] Finished ${file['name']}');
          },
          cancelOnError: true,
        ).asFuture();
      }

      // 🔥 Parallel downloads
      await Future.wait(files.map(downloadFile));

      print('[DOWNLOAD] All downloads complete');
      return true;
    } catch (e, stack) {
      print('[DOWNLOAD][ERROR]');
      print(e);
      print(stack);
      return false;
    } finally {
      client.close();
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