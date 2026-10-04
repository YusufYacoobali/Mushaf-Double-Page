import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mushaf_two_page/utils/reader_highlight_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const first = SavedReaderHighlight(
    mushaf: 'madani',
    page: 4,
    surah: 1,
    ayah: 3,
  );
  const second = SavedReaderHighlight(
    mushaf: 'madani',
    page: 5,
    surah: 2,
    ayah: 2,
  );

  test('selected ayah survives a fresh preferences session', () async {
    await ReaderHighlightPreferences.save(first);
    final prefs = await SharedPreferences.getInstance();
    final persisted = prefs.getString(ReaderHighlightPreferences.storageKey)!;
    SharedPreferences.setMockInitialValues({
      ReaderHighlightPreferences.storageKey: persisted,
    });
    final restored = await ReaderHighlightPreferences.load('madani');
    expect(restored?.identity, first.identity);
  });
  test('rapid selections preserve the newest ayah', () async {
    await Future.wait([
      ReaderHighlightPreferences.save(first),
      ReaderHighlightPreferences.save(second),
    ]);
    expect(
      (await ReaderHighlightPreferences.load('madani'))?.identity,
      second.identity,
    );
  });
  test('dismissal stays dismissed after reopening', () async {
    await Future.wait([
      ReaderHighlightPreferences.save(first),
      ReaderHighlightPreferences.save(null),
    ]);
    expect(await ReaderHighlightPreferences.load('madani'), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(ReaderHighlightPreferences.storageKey), isFalse);
  });
  test(
    'highlight from another Mushaf is never applied to the current layout',
    () async {
      await ReaderHighlightPreferences.save(first);
      expect(await ReaderHighlightPreferences.load('indopak_tajweed'), isNull);
      expect(
        (await ReaderHighlightPreferences.load('madani'))?.identity,
        first.identity,
      );
    },
  );
  test('invalid or malformed saved references are ignored', () async {
    for (final raw in [
      '{bad json',
      jsonEncode({'mushaf': 'madani', 'page': 4, 'surah': 115, 'ayah': 1}),
      jsonEncode({'mushaf': 'madani', 'page': 4, 'surah': 1, 'ayah': 8}),
      jsonEncode({'mushaf': 'madani', 'page': -1, 'surah': 1, 'ayah': 1}),
      jsonEncode({'mushaf': 'madani', 'page': '4', 'surah': 1, 'ayah': 1}),
    ]) {
      SharedPreferences.setMockInitialValues({
        ReaderHighlightPreferences.storageKey: raw,
      });
      expect(await ReaderHighlightPreferences.load('madani'), isNull);
    }
  });
}
