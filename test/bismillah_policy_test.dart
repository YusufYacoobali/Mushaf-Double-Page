import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/audio_modal.dart';
import 'package:mushaf_two_page/logic/audio_repository.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:mushaf_two_page/utils/audio_preferences.dart';
import 'package:mushaf_two_page/utils/bismillah_sources.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_test_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  BismillahResolution mixed(Reciter r, int s) => s == 113
      ? const BismillahResolution(
          BismillahPolicyKind.unverified,
          evidence: 'Synthetic unresolved opening',
        )
      : s == 114
      ? const BismillahResolution(
          BismillahPolicyKind.embeddedInOpeningAyah,
          evidence: 'Synthetic embedded opening',
        )
      : fixtureIntroduction(r, s);
  test(
    'enabled production descriptors match the committed content evidence for the same collection',
    () {
      final audit =
          jsonDecode(
                File('docs/bismillah-content-audit.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final clips = (audit['clips'] as List).cast<Map<String, dynamic>>();
      var enabled = 0;
      for (final reciter in quranReciters) {
        for (var surah = 2; surah <= 114; surah++) {
          final policy = BismillahSources.resolve(reciter, surah);
          if (policy.kind != BismillahPolicyKind.separateVerifiedRecording &&
              policy.kind != BismillahPolicyKind.embeddedInOpeningAyah) {
            continue;
          }
          enabled++;
          final opening = clips.singleWhere(
            (c) =>
                c['folder'] == reciter.folder &&
                c['file'] == '${surah.toString().padLeft(3, '0')}001.mp3',
          );
          expect(policy.openingSha256, opening['sha256']);
          expect(opening['mirrorHashMatches'], isTrue);
          if (policy.source == null) continue;
          for (final source in [
            policy.source!,
            ...policy.source!.alternatives,
          ]) {
            final clip = clips.singleWhere(
              (c) =>
                  c['folder'] == reciter.folder &&
                  c['file'] == source.cacheFilename,
            );
            expect(source.sha256, clip['sha256']);
            expect(clip['mirrorHashMatches'], isTrue);
            expect(
              source.url,
              'https://everyayah.com/data/${reciter.folder}/${source.cacheFilename}',
            );
            expect(source.id, startsWith('${reciter.id}/'));
          }
        }
      }
      expect(enabled, 32);
      // This checks artifact consistency, not the accuracy of automatic ASR.
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
    'one preflight covers unresolved playlist openings and every repeat',
    () async {
      final player = FakePlayer(), repo = ControlledRepository();
      var prompts = 0;
      final c = QuranAudioController.forTesting(
        player: player,
        repository: repo,
        resolveIntroduction: mixed,
      );
      c.requestOpeningConsent = (r, s) async {
        prompts++;
        expect(s, [113]);
        return const OpeningConsent(continueOriginal: true);
      };
      await c.playPlan(plan(queue: [112, 113, 114], count: 2));
      await flush();
      final heard = <String>[];
      for (var i = 0; i < 2 * (1 + 4 + 5 + 6); i++) {
        heard.add(c.currentItem!.key);
        player.advance();
        await flush();
      }
      expect(prompts, 1);
      expect(c.phase, QuranPlaybackPhase.completed);
      expect(heard.where((s) => s == '112:bismillah').length, 2);
      expect(heard, isNot(contains('113:bismillah')));
      expect(heard, isNot(contains('114:bismillah')));
      expect(repo.requested.where((s) => s.contains('113:bismillah')), isEmpty);
      expect(c.error, isNull);
      await c.stop();
      c.dispose();
    },
  );
  test(
    'remembered consent is per reciter and persists through fresh controllers',
    () async {
      var prompts = 0;
      Future<void> run(Reciter reciter) async {
        final c = QuranAudioController.forTesting(
          player: FakePlayer(),
          repository: ControlledRepository(),
          resolveIntroduction: mixed,
          readConsent: AudioPreferences.openingConsent,
          writeConsent: AudioPreferences.rememberOpeningConsent,
        );
        c.requestOpeningConsent = (r, s) async {
          prompts++;
          return const OpeningConsent(continueOriginal: true, remember: true);
        };
        await c.playPlan(plan(surah: 113, from: 1, to: 2, reciter: reciter));
        await c.stop();
        c.dispose();
      }

      await run(quranReciters.first);
      await run(quranReciters.first);
      expect(prompts, 1);
      await run(quranReciters[1]);
      expect(prompts, 2);
    },
  );
  test(
    'Cancel and Stop during pending consent cannot start or remember late audio',
    () async {
      final player = FakePlayer(), repo = ControlledRepository();
      final choice = Completer<OpeningConsent>();
      final c = QuranAudioController.forTesting(
        player: player,
        repository: repo,
        resolveIntroduction: mixed,
        writeConsent: (_, _) async => fail('Late consent must not be saved'),
      );
      c.requestOpeningConsent = (_, _) => choice.future;
      final pending = c.playPlan(plan(surah: 113, from: 1));
      await flush();
      expect(c.awaitingOpeningConsent, isTrue);
      expect(player.starts, 0);
      expect(repo.requested, isEmpty);
      await c.stop();
      choice.complete(
        const OpeningConsent(continueOriginal: true, remember: true),
      );
      await pending;
      expect(c.phase, QuranPlaybackPhase.idle);
      expect(player.starts, 0);
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
  testWidgets(
    'unverified coverage shows Continue/Cancel and the original-recording disclaimer',
    (tester) async {
      OpeningConsent? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await AudioModal.confirmUnverifiedOpenings(
                    ctx,
                    quranReciters.first,
                    [2, 3],
                  );
                },
                child: const Text('Open consent'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open consent'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('does not guarantee Bismillah'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsNothing);
      await tester.tap(find.text('Remember for this reciter'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(result!.continueOriginal, isTrue);
      expect(result!.remember, isTrue);
    },
  );
}
