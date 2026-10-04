import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/logic/storage_manager.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:mushaf_two_page/utils/audio_preferences.dart';
import 'package:mushaf_two_page/utils/translation_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('translation source checkboxes retain their exact selection', () async {
    await TranslationPreferences.saveSourceSelections(
      translations: ['Muhammad M. Pickthall', 'Fateh Jalandhry (Urdu)'],
      tafseers: [],
    );

    final restored = await TranslationPreferences.load();
    expect(restored.translations, [
      'Muhammad M. Pickthall',
      'Fateh Jalandhry (Urdu)',
    ]);
    expect(restored.tafseers, isEmpty);
  });

  test('audio reciter, surah and ayah selection round-trip', () async {
    await AudioPreferences.save(
      const AudioPreferencesData(
        reciterId: 'sudais',
        surah: 36,
        fromAyah: 12,
        toAyah: 27,
        repeatCount: null,
        repeatMode: AudioRepeatMode.ayah,
        sourceMode: AudioSourceMode.range,
      ),
    );

    final restored = await AudioPreferences.load();
    expect(restored, isNotNull);
    expect(restored!.reciterId, 'sudais');
    expect(restored.surah, 36);
    expect(restored.fromAyah, 12);
    expect(restored.toAyah, 27);
    expect(restored.repeatCount, isNull);
    expect(restored.repeatMode, AudioRepeatMode.ayah);
    expect(restored.sourceMode, AudioSourceMode.range);
  });
  test('surah queue keeps the selected listening order', () async {
    await AudioPreferences.save(
      const AudioPreferencesData(
        reciterId: 'abdullah_basfar',
        surah: 112,
        fromAyah: 1,
        toAyah: 4,
        repeatCount: 10,
        repeatMode: AudioRepeatMode.range,
        sourceMode: AudioSourceMode.playlist,
        surahQueue: [114, 112, 1],
      ),
    );
    final restored = await AudioPreferences.load();
    expect(restored!.surahQueue, [114, 112, 1]);
    expect(restored.sourceMode, AudioSourceMode.playlist);
    expect(restored.reciterId, 'abdullah_basfar');
  });
  test(
    'previously saved 120 percent reader scales restore at 100 percent',
    () async {
      SharedPreferences.setMockInitialValues({
        'quran_single_page_scale': 1.2,
        'quran_landscape_page_scale': 1.2,
      });
      expect(await StorageManager.getPageScalePortrait(), 1.0);
      expect(await StorageManager.getPageScaleLandscape(), 1.0);
    },
  );
}
