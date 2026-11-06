import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/pages/settings.dart';
import 'package:mushaf_two_page/logic/storage_manager.dart';
import 'package:mushaf_two_page/pages/tasbeeh.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/tasbeeh_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter')
      ..addFont(
        rootBundle.load('assets/fonts/Inter-VariableFont_opsz,wght.ttf'),
      );
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await inter.load();
    await icons.load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  test(
    'restoration gate, rapid taps, undo, reset, separate counts and exact reopening',
    () async {
      final store = TasbeehStore();
      store.increment();
      expect(store.count, BigInt.zero);
      await store.restore();
      for (var i = 0; i < 1000; i++) {
        store.increment();
      }
      expect(store.count, BigInt.from(1000));
      store.undo();
      store.select('alhamdulillah');
      store.increment();
      store.preferences(sound: true, vibration: false);
      store.setTarget(BigInt.from(33));
      store.addCustom('My dhikr');
      store.increment();
      await store.flush();
      final reopened = TasbeehStore();
      await reopened.restore();
      expect(reopened.selected.label, 'My dhikr');
      expect(reopened.count, BigInt.one);
      reopened.select('alhamdulillah');
      expect(reopened.count, BigInt.one);
      expect(reopened.target, BigInt.from(33));
      expect(reopened.sound, isTrue);
      expect(reopened.vibration, isFalse);
      reopened.select('subhanallah');
      expect(reopened.count, BigInt.from(999));
      reopened.reset();
      reopened.undo();
      expect(reopened.display, '00000');
      await reopened.flush();
      store.dispose();
      reopened.dispose();
    },
  );
  test(
    'serialized slow saves coalesce to newest snapshot without losing taps',
    () async {
      final gate = Completer<void>();
      final writes = <String>[];
      var active = 0, maximum = 0;
      final store = TasbeehStore(
        writeSnapshot: (snapshot) async {
          active++;
          maximum = active > maximum ? active : maximum;
          if (writes.isEmpty) await gate.future;
          writes.add(snapshot);
          active--;
          return true;
        },
      );
      await store.restore();
      store.increment();
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < 99; i++) {
        store.increment();
      }
      gate.complete();
      await store.flush();
      expect(maximum, 1);
      expect(writes.length, 2);
      expect((jsonDecode(writes.last)['counts'] as Map)['subhanallah'], '100');
      store.dispose();
    },
  );
  test(
    'target multiple gives feedback but never resets; arbitrary large counts persist',
    () async {
      SharedPreferences.setMockInitialValues({
        TasbeehStore.storageKey: jsonEncode({
          'version': 1,
          'selected': 'subhanallah',
          'counts': {'subhanallah': '99999'},
        }),
      });
      final store = TasbeehStore();
      await store.restore();
      store.setTarget(BigInt.from(100));
      expect(store.increment(), isTrue);
      expect(store.display, '100000');
      expect(store.increment(), isFalse);
      expect(store.count, BigInt.from(100001));
      await store.flush();
      final reopened = TasbeehStore();
      await reopened.restore();
      expect(reopened.display, '100001');
      store.dispose();
      reopened.dispose();
    },
  );
  testWidgets(
    'completed taps count once; cancel does not count; Undo and Reset confirmation',
    (tester) async {
      final store = TasbeehStore();
      await store.restore();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppPalette.emerald.toThemeData(),
          home: TasbeehPage(store: store),
        ),
      );
      await tester.pumpAndSettle();
      final count = find.bySemanticsLabel('Count dhikr');
      for (var i = 0; i < 24; i++) {
        await tester.tap(count);
      }
      await tester.pumpAndSettle();
      expect(store.display, '00024');
      final gesture = await tester.startGesture(tester.getCenter(count));
      await gesture.moveBy(const Offset(300, 0));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(store.display, '00024');
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(store.display, '00023');
      await tester.tap(find.byTooltip('Reset'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.display, '00023');
      await tester.tap(find.byTooltip('Reset'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset').last);
      await tester.pumpAndSettle();
      expect(store.display, '00000');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await store.flush();
      store.dispose();
    },
  );
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1024, 1366),
  ]) {
    for (final dark in [false, true]) {
      testWidgets(
        'Tasbeeh fits $size dark=$dark at large accessibility scale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final store = TasbeehStore();
          await store.restore();
          await tester.pumpWidget(
            MaterialApp(
              theme: (dark ? AppPalette.blackDark : AppPalette.emerald)
                  .toThemeData(),
              builder: (ctx, child) => MediaQuery(
                data: MediaQuery.of(ctx).copyWith(
                  textScaler: const TextScaler.linear(1.6),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: TasbeehPage(store: store),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('Tasbeeh settings'));
          await tester.pumpAndSettle();
          expect(find.text('Vibration'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await store.flush();
          store.dispose();
        },
      );
    }
  }
  testWidgets(
    'Settings → Tasbeeh → Settings → reader retains the exact reader state',
    (tester) async {
      const readerPage = 237;
      await StorageManager.saveCurrentPage(readerPage);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppPalette.emerald.toThemeData(),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(builder: (_) => const Settings()),
                ),
                child: Text('Reader page $readerPage'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Reader page 237'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Tasbeeh'));
      await tester.tap(find.text('Tasbeeh'));
      await tester.pumpAndSettle();
      expect(find.byType(TasbeehPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(Settings), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pumpAndSettle();
      expect(find.text('Reader page 237'), findsOneWidget);
      expect(await StorageManager.getCurrentPage(), readerPage);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('capture counter at 00024', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = TasbeehStore();
    await store.restore();
    for (var i = 0; i < 24; i++) {
      store.increment();
    }
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppPalette.emerald.toThemeData(),
        initialRoute: '/tasbeeh',
        routes: {
          '/': (_) => const Scaffold(),
          '/tasbeeh': (_) => RepaintBoundary(
            key: key,
            child: TasbeehPage(store: store),
          ),
        },
      ),
    );
    await tester.pumpAndSettle();
    final path = Platform.environment['TASBEEH_SCREENSHOT'];
    if (path != null) {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(path).writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
    }
    expect(find.bySemanticsLabel('Tasbeeh count'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await store.flush();
    store.dispose();
  });
}
