import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/progress/reading_progress_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('records a page read and starts a streak', () async {
    SharedPreferences.setMockInitialValues({});
    await ReadingProgressStore.recordPageRead(
      10,
      mushaf: 'm',
      firstContent: 4,
      lastContent: 850,
    );
    final prog = await ReadingProgressStore.load(
      mushaf: 'm',
      firstContent: 4,
      lastContent: 850,
    );
    expect(prog.streak, 1);
    expect(prog.readPages, 1);
    expect(prog.khatmCount, 0);
  });

  test('same-day repeated reads do not inflate the streak', () async {
    SharedPreferences.setMockInitialValues({});
    await ReadingProgressStore.recordPageRead(
      10,
      mushaf: 'm',
      firstContent: 4,
      lastContent: 850,
    );
    await ReadingProgressStore.recordPageRead(
      11,
      mushaf: 'm',
      firstContent: 4,
      lastContent: 850,
    );
    final prog = await ReadingProgressStore.load(
      mushaf: 'm',
      firstContent: 4,
      lastContent: 850,
    );
    expect(prog.streak, 1);
    expect(prog.readPages, 2);
  });

  test('finishing all content pages counts a khatm and resets', () async {
    SharedPreferences.setMockInitialValues({});
    for (var p = 4; p <= 6; p++) {
      await ReadingProgressStore.recordPageRead(
        p,
        mushaf: 'm',
        firstContent: 4,
        lastContent: 6,
      );
    }
    final prog = await ReadingProgressStore.load(
      mushaf: 'm',
      firstContent: 4,
      lastContent: 6,
    );
    expect(prog.khatmCount, 1);
    expect(prog.readPages, 0); // reset for the next khatm
  });

  test('pages outside the content range are ignored for khatm', () async {
    SharedPreferences.setMockInitialValues({});
    await ReadingProgressStore.recordPageRead(
      1, // cover page
      mushaf: 'm',
      firstContent: 4,
      lastContent: 850,
    );
    final prog = await ReadingProgressStore.load(
      mushaf: 'm',
      firstContent: 4,
      lastContent: 850,
    );
    expect(prog.readPages, 0);
    expect(prog.streak, 1); // still counts as activity
  });
}
