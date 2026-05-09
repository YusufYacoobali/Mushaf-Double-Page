import 'package:flutter/material.dart';
import 'package:mushaf_two_page/main.dart';
import '../logic/storage_manager.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  bool _downloadFailed = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_prepareApp);
  }

  Future<void> _prepareApp() async {
    try {
      final mushaf = await StorageManager.getMushaf();
      debugPrint('[LOADING] Current mushaf $mushaf ');

      await StorageManager.ensureMushafDownloaded(
        mushaf,
        mushaf == "indopak_tajweed" ? 1 : 2,
      );

      if (!mounted) return;

      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MyPDFViewer()));
    } catch (e) {
      if (mounted) {
        setState(() => _downloadFailed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2A6767),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Center(
            child: Column(
              children: [
                const Spacer(flex: 3),

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
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),

                const Spacer(flex: 2),

                const CircularProgressIndicator(color: Color(0xFFD6D85F)),

                if (_downloadFailed) ...[
                  const SizedBox(height: 32),

                  Text(
                    'Download failed',
                    style: TextStyle(
                      color: Colors.redAccent.withValues(alpha: 0.9),
                      fontSize: 13,
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextButton(
                    onPressed: () {
                      setState(() {
                        _downloadFailed = false;
                      });
                      _prepareApp();
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('Retry'),
                  ),
                ],

                const Spacer(flex: 3),

                const Text(
                  'Can take a few minutes!',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
