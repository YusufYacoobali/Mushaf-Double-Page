import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/audio_modal.dart';
import 'package:mushaf_two_page/logic/audio_repository.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/logic/quran_audio_handler.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:mushaf_two_page/utils/audio_preferences.dart';
import 'package:mushaf_two_page/utils/bismillah_sources.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_test_fixtures.dart';

const productionQueues = [
  [112, 113, 114],
  [2, 3, 4],
  [8, 9, 10],
  [1, 2],
];

// Independent product specification, rather than deriving expected output by
// advancing the production cursor or consulting the introduction resolver.
List<String> expectedSequence(AudioPlaybackPlan p) {
  final sequence = <String>[];
  final verses = [
    for (final surah in p.effectiveSurahs)
      for (
        var ayah = p.sourceMode == AudioSourceMode.range ? p.fromAyah : 1;
        ayah <=
            (p.sourceMode == AudioSourceMode.range
                ? p.toAyah
                : quranAyahCounts[surah - 1]);
        ayah++
      )
        (surah, ayah),
  ];
  for (
    var cycle = 1;
    cycle <= (p.repeatMode == AudioRepeatMode.range ? p.visibleRepeatCount : 1);
    cycle++
  ) {
    for (final verse in verses) {
      if (verse.$2 == 1 && verse.$1 != 1 && verse.$1 != 9) {
        sequence.add('${verse.$1}:bismillah/$cycle/1');
      }
      for (
        var repeat = 1;
        repeat <=
            (p.repeatMode == AudioRepeatMode.ayah ? p.visibleRepeatCount : 1);
        repeat++
      ) {
        sequence.add('${verse.$1}:${verse.$2}/$cycle/$repeat');
      }
    }
  }
  return sequence;
}

String occurrenceLabel(QuranAudioOccurrence o) =>
    '${o.item.key}/${o.rangeCycle}/${o.verseRepetition}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'all 22 canonical production sources match actual MP3 bytes and content evidence',
    () async {
      final audit =
          jsonDecode(
                File('docs/bismillah-content-audit.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final clips = (audit['clips'] as List).cast<Map<String, dynamic>>();
      final fresh = (audit['canonicalVerification']['recordings'] as List)
          .cast<Map<String, dynamic>>();
      expect(audit['unsupportedReciters'], isEmpty);
      final sources = <String>{};
      for (final reciter in quranReciters) {
        final source = BismillahSources.resolve(reciter, 2).source!;
        final clip = clips.singleWhere(
          (c) =>
              c['folder'] == reciter.folder &&
              c['file'] == source.cacheFilename,
        );
        final actual = await File(
          'test/fixtures/bismillah/${reciter.id}.mp3',
        ).readAsBytes();
        expect(AudioRepository.validMp3Bytes(actual), isTrue);
        expect(crypto.sha256.convert(actual).toString(), source.sha256);
        expect(source.sha256, clip['sha256']);
        expect(clip['mirrorHashMatches'], isTrue);
        expect(
          fresh.singleWhere((c) => c['reciter'] == reciter.id)['sha256'],
          source.sha256,
        );
        expect(
          source.url,
          'https://everyayah.com/data/${reciter.folder}/${source.cacheFilename}',
        );
        expect(source.id, '${reciter.id}/${source.cacheFilename}');
        sources.add(source.id);
        for (var surah = 1; surah <= 114; surah++) {
          final policy = BismillahSources.resolve(reciter, surah);
          expect(
            policy.kind,
            surah == 1 || surah == 9
                ? BismillahPolicyKind.notRequired
                : BismillahPolicyKind.separateVerifiedRecording,
          );
          if (surah != 1 && surah != 9) {
            expect(identical(policy.source, source), isTrue);
          }
        }
      }
      expect(sources.length, 22);
      // Ali Jaber 1:1 includes istiadhah; Shaatree's SSS000 is istiadhah alone.
      expect(
        BismillahSources.resolve(
          quranReciters.firstWhere((r) => r.id == 'ali_jaber'),
          2,
        ).source!.cacheFilename,
        '112000.mp3',
      );
      expect(
        BismillahSources.resolve(
          quranReciters.firstWhere((r) => r.id == 'shaatree'),
          2,
        ).source!.cacheFilename,
        '001001.mp3',
      );
    },
  );

  for (final reciter in quranReciters) {
    test('production cursor exact queues and repeat cycles: ${reciter.id}', () {
      final midway = QuranPlaybackCursor(
        plan(reciter: reciter, from: 2, to: 4),
        introductionForSurah: (s) =>
            BismillahSources.resolve(reciter, s).source != null,
      );
      expect(midway.needsIntroduction, isFalse);
      final midwayItems = <String>[];
      do {
        midwayItems.add(midway.item.key);
      } while (midway.advance());
      expect(midwayItems, ['112:2', '112:3', '112:4']);
      for (final queue in productionQueues) {
        for (final mode in AudioRepeatMode.values) {
          final selection = plan(
            reciter: reciter,
            queue: queue,
            count: 3,
            repeat: mode,
          );
          final cursor = QuranPlaybackCursor(
            selection,
            introductionForSurah: (s) =>
                BismillahSources.resolve(reciter, s).source != null,
          );
          cursor.introduction = cursor.needsIntroduction;
          final heard = <String>[];
          do {
            heard.add(
              '${cursor.item.key}/${cursor.rangeCycle}/${cursor.verseRepeat}',
            );
          } while (cursor.advance());
          expect(heard, expectedSequence(selection), reason: '$queue $mode');
        }
      }
    });
  }
  test(
    'production infinite Surah Queue repeats all applicable introductions with bounded native sources',
    () async {
      final player = FakePlayer();
      final c = QuranAudioController.forTesting(
        player: player,
        repository: ControlledRepository(),
      );
      await c.playPlan(plan(queue: [112, 113, 114], count: null));
      await flush();
      for (final expected in expectedSequence(
        plan(queue: [112, 113, 114], count: 3),
      )) {
        expect(occurrenceLabel(c.currentOccurrence!), expected);
        expect(c.nativeQueueLength, lessThanOrEqualTo(6));
        player.advance();
        await flush();
      }
      expect(c.phase, QuranPlaybackPhase.playing);
      expect(c.currentItem!.key, '112:bismillah');
      expect(c.currentRepeat, 4);
      expect(player.sourceLoads, 1);
      await c.stop();
      c.dispose();
    },
  );
  // Exercise native source adoption as well as the cursor, including long queues.
  for (final queue in productionQueues) {
    for (final mode in AudioRepeatMode.values) {
      test('production native queue exact items $queue ${mode.name}', () async {
        final player = FakePlayer(), repo = ControlledRepository();
        final c = QuranAudioController.forTesting(
          player: player,
          repository: repo,
        );
        final selection = plan(queue: queue, count: 2, repeat: mode);
        await c.playPlan(selection);
        await flush();
        final heard = <String>[];
        for (final expected in expectedSequence(selection)) {
          final o = c.currentOccurrence!;
          heard.add(occurrenceLabel(o));
          expect(occurrenceLabel(o), expected);
          if (o.item.isIntroduction) {
            expect(
              o.recordingId,
              BismillahSources.resolve(
                selection.reciter,
                o.item.surah,
              ).source!.id,
            );
            expect(c.currentAyah, isNull);
          } else {
            expect(c.currentAyah, o.item.ayah);
          }
          expect(
            c.nativeQueueLength,
            lessThanOrEqualTo(QuranAudioController.nativeQueueLimit),
          );
          player.advance();
          await flush();
        }
        expect(heard, expectedSequence(selection));
        expect(c.phase, QuranPlaybackPhase.completed);
        expect(player.sourceLoads, 1);
        await c.stop();
        c.dispose();
      });
    }
  }
  test(
    'unavailable/embedded introductions start directly and do not block a mixed queue',
    () async {
      final player = FakePlayer(), repo = ControlledRepository();
      final c = QuranAudioController.forTesting(
        player: player,
        repository: repo,
        resolveIntroduction: (r, s) => s == 113
            ? const BismillahResolution(
                BismillahPolicyKind.unverified,
                evidence: 'Unavailable test source',
              )
            : s == 114
            ? const BismillahResolution(
                BismillahPolicyKind.embeddedInOpeningAyah,
                evidence: 'Already embedded test source',
              )
            : BismillahSources.resolve(r, s),
      );
      await c.playPlan(plan(queue: [112, 113, 114], count: 2));
      await flush();
      final heard = <String>[];
      for (var i = 0; i < 32; i++) {
        heard.add(c.currentItem!.key);
        player.advance();
        await flush();
      }
      expect(c.phase, QuranPlaybackPhase.completed);
      expect(heard.where((s) => s == '112:bismillah').length, 2);
      expect(heard, isNot(contains('113:bismillah')));
      expect(heard, isNot(contains('114:bismillah')));
      expect(c.introductionNotice, contains('unavailable'));
      expect(c.downloadState.message, contains('incomplete'));
      expect(c.error, isNull);
      await c.stop();
      c.dispose();
    },
  );
  test(
    'lock-screen controls preserve production introduction identity and verse numbering',
    () async {
      final player = FakePlayer();
      final c = QuranAudioController.forTesting(
        player: player,
        repository: ControlledRepository(),
      );
      final handler = QuranAudioHandler(c);
      final selection = plan(queue: [112, 113, 114], count: 2);
      await c.playPlan(selection);
      await flush();
      for (final expected in expectedSequence(selection)) {
        final before = c.currentOccurrence!;
        expect(occurrenceLabel(before), expected);
        expect(
          handler.mediaItem.value!.extras!['introduction'],
          before.item.isIntroduction,
        );
        await handler.pause();
        await handler.play();
        expect(c.currentOccurrence!.occurrenceId, before.occurrenceId);
        player.advance();
        await flush();
      }
      expect(c.phase, QuranPlaybackPhase.completed);
      await c.stop();
      c.dispose();
    },
  );
  test(
    'legacy consent preferences are removed while selected reciter survives',
    () async {
      SharedPreferences.setMockInitialValues({
        'audio_original_openings_v1_alafasy': true,
        'audio_selection_configured': true,
        'audio_reciter': 'shaatree',
      });
      expect((await AudioPreferences.load())!.reciterId, 'shaatree');
      expect(
        (await SharedPreferences.getInstance()).getKeys().where(
          (k) => k.startsWith('audio_original_openings_v1_'),
        ),
        isEmpty,
      );
    },
  );
  testWidgets(
    'Play starts directly with no consent or manual-download button',
    (tester) async {
      final player = FakePlayer();
      final c = QuranAudioController.forTesting(
        player: player,
        repository: ControlledRepository(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AudioModal(
              controller: c,
              initialSurah: 113,
              initialFromAyah: 1,
              initialToAyah: 2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Download selection for offline use'), findsNothing);
      await tester.ensureVisible(find.text('Play'));
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(player.starts, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('not been verified'), findsNothing);
      expect(find.text('Remember for this reciter'), findsNothing);
      expect(find.text('Selection available offline'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await c.stop();
      c.dispose();
    },
  );
  test(
    'native introduction decode failure selects the verified alternative without consuming the occurrence',
    () async {
      final player = FakePlayer(), repo = ControlledRepository();
      final c = QuranAudioController.forTesting(
        player: player,
        repository: repo,
        resolveIntroduction: (_, _) => const BismillahResolution(
          BismillahPolicyKind.separateVerifiedRecording,
          evidence: 'Synthetic alternatives',
          source: AudioRecordingSource(
            id: 'primary',
            url: 'https://example.test/a.mp3',
            cacheFilename: 'a.mp3',
            verification: 'Synthetic',
            alternatives: [
              AudioRecordingSource(
                id: 'alternative',
                url: 'https://example.test/b.mp3',
                cacheFilename: 'b.mp3',
                verification: 'Synthetic',
              ),
            ],
          ),
        ),
      );
      await c.playPlan(plan(from: 1, to: 2));
      await flush();
      final id = c.currentOccurrence!.occurrenceId;
      player.fail();
      await flush();
      expect(c.currentOccurrence!.occurrenceId, id);
      expect(c.currentOccurrence!.recordingId, 'alternative');
      expect(repo.invalidated, ['112:bismillah']);
      player.advance();
      await flush();
      expect(c.currentAyah, 1);
      await c.stop();
      c.dispose();
    },
  );
  test(
    'verified same-reciter alternative precedes retry and keeps introduction identity',
    () async {
      final player = FakePlayer(), repo = ControlledRepository();
      repo.remainingFailures['112:bismillah'] = 1;
      repo.failures['112:bismillah'] = const AudioFailure(
        AudioFailureKind.missing,
        '404 primary',
      );
      BismillahResolution resolver(Reciter r, int s) {
        final policy = fixtureIntroduction(r, s);
        if (s != 112) return policy;
        return BismillahResolution(
          BismillahPolicyKind.separateVerifiedRecording,
          evidence: 'Synthetic alternatives',
          source: AudioRecordingSource(
            id: 'primary',
            url: 'https://example.test/a.mp3',
            cacheFilename: 'a.mp3',
            verification: 'Synthetic',
            alternatives: [
              AudioRecordingSource(
                id: 'same-reciter-alternative',
                url: 'https://example.test/b.mp3',
                cacheFilename: 'b.mp3',
                verification: 'Independent synthetic',
              ),
            ],
          ),
        );
      }

      final c = QuranAudioController.forTesting(
        player: player,
        repository: repo,
        resolveIntroduction: resolver,
      );
      await c.playPlan(plan(from: 1));
      await flush();
      expect(c.isIntroduction, isTrue);
      expect(c.currentOccurrence!.recordingId, 'same-reciter-alternative');
      expect(repo.sourceIds.take(2), ['primary', 'same-reciter-alternative']);
      final id = c.currentOccurrence!.occurrenceId;
      player.fail();
      await flush();
      expect(c.currentOccurrence!.occurrenceId, id);
      expect(c.currentAyah, isNull);
      player.advance();
      await flush();
      expect(c.currentAyah, 1);
      await c.stop();
      c.dispose();
    },
  );
  test(
    'planning copies cannot mutate active cursor; introduction repeats only with range',
    () {
      final active = QuranPlaybackCursor(
        plan(from: 1, to: 2, count: 3),
        introductionForSurah: (_) => true,
      );
      active.introduction = true;
      final tail = active.copy();
      tail.advance();
      tail.advance();
      expect(active.introduction, isTrue);
      expect(active.index, 0);
      expect(active.rangeCycle, 1);
      expect(tail.item.ayah, 2);
    },
  );
}
