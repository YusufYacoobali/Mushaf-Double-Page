import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'quran_audio.dart';

/// Stage-A sample timeline, not an alternative recording provider. Registration
/// is available only to the explicit development target; normal playback keeps
/// the existing progressive MP3 path.
class PcmProofOccurrence {
  const PcmProofOccurrence(this.ayah, this.startFrame, this.endFrame, this.id);
  final int? ayah;
  final int startFrame, endFrame;
  final String id;
}

class EveryAyahPcmProof {
  EveryAyahPcmProof({
    required this.path,
    required this.sha256,
    required this.sampleRate,
    required List<PcmProofOccurrence> rows,
  }) : rows = List.unmodifiable(rows) {
    if (sampleRate != 44100 ||
        rows.length != 11 ||
        rows.first.ayah != null ||
        rows.first.startFrame != 0 ||
        rows.map((r) => r.id).toSet().length != rows.length) {
      throw ArgumentError('Invalid ten-ayah proof');
    }
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (r.endFrame <= r.startFrame ||
          (i > 0 && (r.startFrame != rows[i - 1].endFrame || r.ayah != i))) {
        throw ArgumentError('Non-contiguous proof timeline');
      }
    }
  }
  final String path, sha256;
  final int sampleRate;
  final List<PcmProofOccurrence> rows;
  int get frames => rows.last.endFrame;
  Duration time(int frame) =>
      Duration(microseconds: (frame * 1000000 + sampleRate - 1) ~/ sampleRate);
  PcmProofOccurrence? at(Duration position) {
    final frame = position.inMicroseconds * sampleRate ~/ 1000000;
    return rows
        .where((r) => frame >= r.startFrame && frame < r.endFrame)
        .firstOrNull;
  }

  bool supports(AudioPlaybackPlan p) =>
      p.reciter.id == 'yasser_dussary' &&
      p.surah == 55 &&
      p.sourceMode == AudioSourceMode.range &&
      p.fromAyah == 1 &&
      p.toAyah == 10 &&
      p.repeatCount == 1 &&
      p.repeatMode == AudioRepeatMode.range;

  Future<void> verify() async {
    final file = File(path);
    if (!await file.exists() ||
        await file.length() != 44 + frames * 4 ||
        await file.length() > 64 * 1024 * 1024 ||
        (await crypto.sha256.bind(file.openRead()).first).toString() !=
            sha256) {
      throw StateError('PCM proof file failed integrity check');
    }
    final bytes = Uint8List.fromList(await file.openRead(0, 44).first);
    final header = ByteData.sublistView(bytes);
    String text(int start, int end) =>
        String.fromCharCodes(bytes.sublist(start, end));
    if (text(0, 4) != 'RIFF' ||
        text(8, 12) != 'WAVE' ||
        text(12, 16) != 'fmt ' ||
        header.getUint32(16, Endian.little) != 16 ||
        header.getUint16(20, Endian.little) != 1 ||
        header.getUint16(22, Endian.little) != 2 ||
        header.getUint32(24, Endian.little) != sampleRate ||
        header.getUint16(32, Endian.little) != 4 ||
        header.getUint16(34, Endian.little) != 16 ||
        text(36, 40) != 'data' ||
        header.getUint32(40, Endian.little) != frames * 4) {
      throw StateError('PCM proof WAV format mismatch');
    }
  }

  static Future<EveryAyahPcmProof> load(Directory directory) async {
    final m =
        jsonDecode(await File('${directory.path}/manifest.json').readAsString())
            as Map<String, dynamic>;
    if (m['schema'] != 1 ||
        m['reciter'] != 'yasser_dussary' ||
        m['surah'] != 55 ||
        m['fromAyah'] != 1 ||
        m['toAyah'] != 10 ||
        m['channels'] != 2 ||
        m['bitsPerSample'] != 16 ||
        m['allDecodedSamplesComparedEqual'] != true) {
      throw StateError('Unsupported proof manifest');
    }
    final proof = EveryAyahPcmProof(
      path: '${directory.path}/continuous.wav',
      sha256: m['waveSha256'] as String,
      sampleRate: m['sampleRate'] as int,
      rows: [
        for (final r in m['rows'] as List)
          PcmProofOccurrence(
            r['ayah'] as int?,
            r['startFrame'] as int,
            r['endFrame'] as int,
            r['occurrence'] as String,
          ),
      ],
    );
    if (proof.frames != m['frames']) {
      throw StateError('Proof sample count mismatch');
    }
    await proof.verify();
    return proof;
  }
}
