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
import 'package:mushaf_two_page/components/tasbeeh_counter.dart';
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
      store.addCustom('My dhikr');
      store.increment();
      await store.flush();
      final reopened = TasbeehStore();
      await reopened.restore();
      expect(reopened.selected.label, 'My dhikr');
      expect(reopened.count, BigInt.one);
      reopened.select('alhamdulillah');
      expect(reopened.count, BigInt.one);
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
        saveInterval: Duration.zero,
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
    'arbitrary large counts keep increasing and persist without rollover',
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
      store.increment();
      expect(store.display, '100000');
      store.increment();
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
    'rapid counting checkpoints are bounded and flush saves the latest count immediately',
    (tester) async {
      final writes = <String>[];
      final store = TasbeehStore(
        writeSnapshot: (value) async {
          writes.add(value);
          return true;
        },
      );
      await store.restore();
      var notifications = 0;
      store.addListener(() => notifications++);
      for (var i = 0; i < 100; i++) {
        store.increment();
        await tester.pump(const Duration(milliseconds: 5));
      }
      expect(store.count, BigInt.from(100));
      expect(writes.length, inInclusiveRange(1, 2));
      expect(
        notifications,
        100,
      ); // Successful storage writes do not rebuild the UI.
      store.increment();
      await store.flush();
      expect((jsonDecode(writes.last)['counts'] as Map)['subhanallah'], '101');
      expect(writes.length, lessThanOrEqualTo(3));
      store.dispose();
    },
  );
  testWidgets('failed checkpoints retain the newest count for explicit retry', (
    tester,
  ) async {
    var accept = false;
    final writes = <String>[];
    final store = TasbeehStore(
      writeSnapshot: (value) async {
        writes.add(value);
        return accept;
      },
    );
    await store.restore();
    store.increment();
    await store.flush();
    expect(store.saveError, isNotNull);
    await tester.pump(const Duration(seconds: 1));
    expect(writes, hasLength(1)); // No background hot retry loop.
    store.increment();
    store.increment();
    accept = true;
    await store.flush();
    expect(store.saveError, isNull);
    expect((jsonDecode(writes.last)['counts'] as Map)['subhanallah'], '3');
    store.dispose();
  });
  testWidgets('disposing before a checkpoint drains the pending count', (
    tester,
  ) async {
    final writes = <String>[];
    final store = TasbeehStore(
      writeSnapshot: (value) async {
        writes.add(value);
        return true;
      },
    );
    await store.restore();
    store.increment();
    store.increment();
    expect(writes, isEmpty);
    store.dispose();
    await store.flush();
    expect((jsonDecode(writes.single)['counts'] as Map)['subhanallah'], '2');
    await tester.pump(const Duration(seconds: 1));
    expect(writes, hasLength(1));
  });
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
  testWidgets(
    'screen, display and shell taps count once; controls, sheets and drags do not count',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = TasbeehStore();
      await store.restore();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppPalette.emerald.toThemeData(),
          home: TasbeehPage(store: store),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Tasbeeh count'));
      expect(store.count, BigInt.one);
      final counter = tester.getRect(find.byType(TasbeehCounter));
      await tester.tapAt(
        Offset(
          counter.left + counter.width * .1,
          counter.top + counter.height * .6,
        ),
      );
      expect(store.count, BigInt.from(2));
      await tester.tap(find.text('Tap anywhere to count'));
      expect(store.count, BigInt.from(3));
      await tester.tapAt(const Offset(5, 750));
      expect(store.count, BigInt.from(4));
      await tester.tap(find.text('Tasbeeh'));
      expect(store.count, BigInt.from(5));
      // Label taps belong to the control rather than the surrounding count area.
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(store.count, BigInt.from(4));
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(store.count, BigInt.from(4));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.count, BigInt.from(4));
      await tester.tap(find.byTooltip('Manage dhikr'));
      await tester.pumpAndSettle();
      expect(store.count, BigInt.from(4));
      expect(find.text('Add custom dhikr'), findsOneWidget);
      // Dismissing a modal's barrier must not count through to the screen.
      await tester.tapAt(const Offset(5, 100));
      await tester.pumpAndSettle();
      expect(store.count, BigInt.from(4));
      await tester.tap(find.text('SubhanAllah'));
      await tester.pumpAndSettle();
      expect(store.count, BigInt.from(4));
      await tester.tap(find.text('Alhamdulillah'));
      await tester.pumpAndSettle();
      expect(store.selected.id, 'alhamdulillah');
      expect(store.count, BigInt.zero);
      await tester.tapAt(const Offset(5, 750));
      expect(store.count, BigInt.one);
      await tester.dragFrom(const Offset(5, 300), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(store.count, BigInt.one);
      tester.view.physicalSize = const Size(1024, 1366);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 800));
      expect(store.count, BigInt.from(2));
      store.select('subhanallah');
      expect(store.count, BigInt.from(4));
      await tester.pumpWidget(const SizedBox());
      await store.flush();
      store.dispose();
    },
  );
  testWidgets(
    'legacy options are removed without losing counts; counting is silent and has no completion feedback',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        TasbeehStore.storageKey: jsonEncode({
          'version': 1,
          'selected': 'custom_saved',
          'counts': {'custom_saved': '32', 'subhanallah': '100000'},
          'targets': {'custom_saved': '33'},
          'vibration': true,
          'sound': true,
          'targetFeedback': true,
          'custom': [
            {'id': 'custom_saved', 'label': 'Saved dhikr'},
          ],
        }),
      });
      final store = TasbeehStore();
      await store.restore();
      await store.flush();
      expect(store.count, BigInt.from(32));
      expect(store.selected.label, 'Saved dhikr');
      final snapshot =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  TasbeehStore.storageKey,
                )!,
              )
              as Map;
      expect(
        snapshot.keys,
        unorderedEquals(['version', 'selected', 'counts', 'custom']),
      );
      final feedback = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate' ||
              call.method == 'SystemSound.play') {
            feedback.add(call.method);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppPalette.emerald.toThemeData(),
            home: TasbeehPage(store: store),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Count dhikr'));
        await tester.pumpAndSettle();
        expect(store.count, BigInt.from(33));
        expect(find.byType(SnackBar), findsNothing);
        await tester.tap(find.bySemanticsLabel('Tasbeeh count'));
        await tester.pumpAndSettle();
        expect(store.count, BigInt.from(34));
        final node = tester.getSemantics(find.bySemanticsLabel('Count dhikr'));
        node.owner!.performAction(node.id, ui.SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(store.count, BigInt.from(35));
        expect(feedback, isEmpty);
        expect(find.textContaining('Target'), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await store.flush();
        final reopened = TasbeehStore();
        await reopened.restore();
        expect(reopened.count, BigInt.from(35));
        reopened.select('subhanallah');
        expect(reopened.count, BigInt.from(100000));
        store.dispose();
        reopened.dispose();
      } finally {
        semantics.dispose();
      }
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
          await tester.tap(find.byTooltip('Manage dhikr'));
          await tester.pumpAndSettle();
          expect(find.text('Add custom dhikr'), findsOneWidget);
          expect(find.byType(SwitchListTile), findsNothing);
          expect(find.text('Vibration'), findsNothing);
          expect(find.text('Sound'), findsNothing);
          expect(find.textContaining('Target'), findsNothing);
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
      final countBeforeBack = TasbeehStore.instance.count;
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(TasbeehStore.instance.count, countBeforeBack);
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
