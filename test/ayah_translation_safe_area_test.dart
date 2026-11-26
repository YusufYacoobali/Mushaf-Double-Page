import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mushaf_two_page/main.dart';
import 'package:mushaf_two_page/logic/storage_manager.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/reader_highlight_preferences.dart';
import 'package:mushaf_two_page/utils/translation_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const samples = [
    (Size(320, 568), FakeViewPadding(bottom: 48)),
    (Size(390, 844), FakeViewPadding(bottom: 24)),
    (Size(844, 390), FakeViewPadding(right: 48, bottom: 24)),
  ];
  testWidgets(
    'toolbar ayah translation stays above Android navigation bars through resizing',
    (tester) async {
      var size = samples.first.$1;
      var insets = samples.first.$2;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      tester.view.padding = insets;
      tester.view.viewPadding = insets;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('ayah_translation_safe_area'),
      ))!;
      await tester.runAsync(() async {
        final pages = Directory('${dir.path}/indopak_tajweed');
        await pages.create();
        final image = await File('assets/icon/audio_artwork.png').readAsBytes();
        for (var page = 0; page <= 10; page++) {
          await File('${pages.path}/$page.webp').writeAsBytes(image);
        }
      });
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => dir.path,
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        await tester.runAsync(() => dir.delete(recursive: true));
      });
      SharedPreferences.setMockInitialValues({
        'trans_selected': TranslationManager.sources.keys.toList(),
      });
      await tester.runAsync(
        () => Future.wait(
          TranslationManager.sources.keys.map(TranslationManager.loadSource),
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
      await StorageManager.saveCurrentPage(4);
      await ReaderHighlightPreferences.save(
        const SavedReaderHighlight(
          mushaf: 'indopak_tajweed',
          page: 4,
          surah: 1,
          ayah: 1,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppPalette.emerald.toThemeData().copyWith(
            platform: TargetPlatform.android,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.noScaling),
            child: child!,
          ),
          home: const MyPDFViewer(),
        ),
      );
      // Initialization includes asset and document-directory I/O.
      for (
        var i = 0;
        i < 300 && find.byTooltip('Translate ayah').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        });
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byTooltip('Translate ayah'), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Translate ayah'));
      await tester.pumpAndSettle();
      final card = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byWidgetPredicate(
          (w) => w is Material && w.borderRadius == BorderRadius.circular(20),
        ),
      );
      expect(card, findsOneWidget);
      final lastText = TranslationManager.getSurah(
        1,
        source: 'Fateh Jalandhry (Urdu)',
      )[1]!;
      for (final sample in samples) {
        size = sample.$1;
        insets = sample.$2;
        tester.view.physicalSize = size;
        tester.view.padding = insets;
        tester.view.viewPadding = insets;
        await tester.pumpAndSettle();
        final rect = tester.getRect(card);
        expect(rect.bottom, closeTo(size.height - insets.bottom - 8, .01));
        expect(rect.right, lessThanOrEqualTo(size.width - insets.right));
        await tester.ensureVisible(find.text(lastText));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.text(lastText)).bottom,
          lessThanOrEqualTo(size.height - insets.bottom),
        );
        expect(find.text(lastText).hitTestable(), findsOneWidget);
      }
      await tester.ensureVisible(find.byIcon(Icons.close_rounded));
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
