import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/utils/deferred_reminders.dart';

void main() {
  testWidgets('slow notification plugin cannot block first reader frame', (
    tester,
  ) async {
    final neverCompleteUntilTestEnds = Completer<void>();
    var called = 0;

    scheduleDeferredReminders(() {
      called++;
      return neverCompleteUntilTestEnds.future;
    });
    expect(called, 0);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Quran reader'))),
    );
    expect(find.text('Quran reader'), findsOneWidget);
    expect(called, 1);

    await tester.pump();
    expect(find.text('Quran reader'), findsOneWidget);
    expect(called, 1);

    neverCompleteUntilTestEnds.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
