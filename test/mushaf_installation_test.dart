import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/logic/storage_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory documents;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('mushaf-install');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => documents.path,
    );
    SharedPreferences.setMockInitialValues({
      'madani_version3': 2,
      'CurrentPage1': 45,
      'bookmarks1': ['{"pageNumber":45,"mushaf":"madani"}'],
    });
  });
  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await documents.delete(recursive: true);
  });

  test(
    'opens an existing edition and restores its files if a replacement fails',
    () async {
      final installed = await Directory('${documents.path}/madani').create();
      final first = await File(
        '${installed.path}/1.webp',
      ).writeAsString('existing');
      await File('${installed.path}/624.webp').create();
      final messages = <String>[];
      await StorageManager.ensureMushafDownloaded(
        'madani',
        2,
        onProgress: (p) => messages.add(p.message),
      );
      expect(messages, ['Checking local Mushaf']);
      final missing = Directory('${documents.path}/madani_pending');
      await expectLater(
        StorageManager.installMushafDirectory(missing, 'madani'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await first.readAsString(), 'existing');
      expect(await StorageManager.isMushafAvailable('madani'), isTrue);
      expect(await StorageManager.getCurrentPage(), 45);
      expect(
        (await StorageManager.getBookmarks('madani')).single.pageNumber,
        45,
      );
    },
  );

  test(
    'stages numbered pages, checks completeness and installs the staged edition',
    () async {
      final archive = Archive();
      final zip = File('${documents.path}/quran_madani.zip');
      final count = StorageManager.expectedMushafPageCount('madani');
      for (var page = 1; page < count; page++) {
        archive.addFile(ArchiveFile.bytes('pages/$page.webp', [1]));
      }
      await zip.writeAsBytes(ZipEncoder().encode(archive));
      await expectLater(
        StorageManager.unzipMushaf(zip, 'madani'),
        throwsStateError,
      );
      expect(await StorageManager.isMushafAvailable('madani'), isFalse);
      archive.addFile(ArchiveFile.bytes('pages/$count.webp', [2]));
      await zip.writeAsBytes(ZipEncoder().encode(archive));
      final stage = await StorageManager.unzipMushaf(zip, 'madani');
      expect(stage.path, '${documents.path}/madani_pending');
      await StorageManager.validateMushafDirectory(stage, count);
      await StorageManager.installMushafDirectory(stage, 'madani');
      expect(await File('${documents.path}/madani/$count.webp').readAsBytes(), [
        2,
      ]);
      expect(await StorageManager.isMushafAvailable('madani'), isTrue);
    },
  );
}
