import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Dhikr {
  const Dhikr(
    this.id,
    this.label,
    this.arabic,
    this.meaning, {
    this.custom = false,
  });
  final String id, label, arabic, meaning;
  final bool custom;
}

const builtInDhikr = [
  Dhikr('subhanallah', 'SubhanAllah', 'سُبْحَانَ اللَّهِ', 'Glory be to Allah'),
  Dhikr(
    'alhamdulillah',
    'Alhamdulillah',
    'الْحَمْدُ لِلَّهِ',
    'All praise is for Allah',
  ),
  Dhikr(
    'allahuakbar',
    'Allahu Akbar',
    'اللَّهُ أَكْبَرُ',
    'Allah is the Greatest',
  ),
  Dhikr(
    'astaghfirullah',
    'Astaghfirullah',
    'أَسْتَغْفِرُ اللَّهَ',
    'I seek Allah’s forgiveness',
  ),
  Dhikr(
    'lailahaillallah',
    'La ilaha illallah',
    'لَا إِلَٰهَ إِلَّا اللَّهُ',
    'There is no god but Allah',
  ),
];

/// All values live in one versioned snapshot. Writes are serialized and coalesced
/// so slow platform writes can never publish an older count after a newer one.
class TasbeehStore extends ChangeNotifier {
  TasbeehStore({
    this.writeSnapshot,
    this.saveInterval = const Duration(milliseconds: 250),
  });
  // One store survives route changes, including an unfinished platform save.
  static final instance = TasbeehStore();
  static const storageKey = 'tasbeeh_state_v1';
  final Future<bool> Function(String)? writeSnapshot;
  final Duration saveInterval;
  Timer? _saveTimer;
  SharedPreferences? _prefs;
  Future<void>? _restoring;
  Future<void>? _saving;
  bool _dirty = false;
  bool ready = false;
  bool _disposed = false;
  String? saveError;
  String _selected = 'subhanallah';
  final _counts = <String, BigInt>{};
  final _custom = <Dhikr>[];

  List<Dhikr> get dhikrs => List.unmodifiable([...builtInDhikr, ..._custom]);
  Dhikr get selected => dhikrs.firstWhere(
    (d) => d.id == _selected,
    orElse: () => builtInDhikr.first,
  );
  BigInt get count => _counts[_selected] ?? BigInt.zero;
  String get display => count.toString().padLeft(5, '0');

  Future<void> restore() => _restoring ??= _restore();
  Future<void> _restore() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(storageKey);
    var migrate = false;
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if (json['version'] == 1) {
          _selected = json['selected'] as String? ?? _selected;
          for (final entry in (json['counts'] as Map? ?? {}).entries) {
            final value = BigInt.tryParse('${entry.value}');
            if (value != null && value >= BigInt.zero) {
              _counts['${entry.key}'] = value;
            }
          }
          for (final entry in (json['custom'] as List? ?? [])) {
            if (entry is Map &&
                entry['id'] is String &&
                entry['label'] is String &&
                (entry['label'] as String).trim().isNotEmpty &&
                !dhikrs.any((d) => d.id == entry['id'])) {
              _custom.add(
                Dhikr(entry['id'], entry['label'], '', '', custom: true),
              );
            }
          }
          _selected = selected.id;
          // Remove obsolete options without resetting existing dhikr or counts.
          migrate = const [
            'targets',
            'vibration',
            'sound',
            'targetFeedback',
          ].any(json.containsKey);
        }
      } catch (_) {
        saveError = 'Saved Tasbeeh data could not be read.';
      }
    }
    ready = true;
    if (!_disposed) {
      if (migrate) {
        _changed();
      } else {
        notifyListeners();
      }
    }
  }

  void increment() {
    if (!ready) return;
    _counts[_selected] = count + BigInt.one;
    _changed();
  }

  void undo() {
    if (!ready || count == BigInt.zero) return;
    _counts[_selected] = count - BigInt.one;
    _changed();
  }

  void reset() {
    if (!ready) return;
    _counts[_selected] = BigInt.zero;
    _changed();
  }

  void select(String id) {
    if (!ready || !dhikrs.any((d) => d.id == id)) return;
    _selected = id;
    _changed();
  }

  void addCustom(String label) {
    if (!ready || label.trim().isEmpty) return;
    var id = 'custom_${DateTime.now().microsecondsSinceEpoch}';
    while (dhikrs.any((d) => d.id == id)) {
      id = '${id}_';
    }
    _custom.add(Dhikr(id, label.trim(), '', '', custom: true));
    _selected = id;
    _changed();
  }

  void removeCustom(String id) {
    if (!ready || !_custom.any((d) => d.id == id)) return;
    _custom.removeWhere((d) => d.id == id);
    _counts.remove(id);
    if (_selected == id) _selected = builtInDhikr.first.id;
    _changed();
  }

  void _changed() {
    _dirty = true;
    notifyListeners();
    _scheduleSave();
  }

  String _snapshot() => jsonEncode({
    'version': 1,
    'selected': _selected,
    'counts': _counts.map((k, v) => MapEntry(k, '$v')),
    'custom': _custom.map((d) => {'id': d.id, 'label': d.label}).toList(),
  });

  void _scheduleSave() {
    if (_disposed || _saving != null || _saveTimer != null || !_dirty) return;
    if (saveInterval == Duration.zero) {
      _saving = _drain();
    } else {
      // Do not restart this timer per tap: continuous counting still checkpoints
      // every interval, without a platform write and JSON encoding on every tap.
      _saveTimer = Timer(saveInterval, () {
        _saveTimer = null;
        _saving ??= _drain();
      });
    }
  }

  Future<void> _drain() async {
    // Assign _saving before even an immediate writer.
    await Future<void>.value();
    final previousError = saveError;
    try {
      if (!_dirty) return;
      _dirty = false;
      final snapshot = _snapshot();
      final saved =
          await (writeSnapshot?.call(snapshot) ??
              _prefs!.setString(storageKey, snapshot));
      if (!saved) throw StateError('Local storage rejected the save');
      saveError = null;
    } catch (_) {
      saveError = 'Progress could not be saved. Please try again.';
      _dirty = true; // Retry the newest state, never the failed older snapshot.
    } finally {
      _saving = null;
      if (!_disposed && previousError != saveError) notifyListeners();
      // A failure waits for a new change or explicit retry; no hot retry loop.
      if (_dirty && saveError == null) _scheduleSave();
    }
  }

  Future<void> flush() async {
    do {
      _saveTimer?.cancel();
      _saveTimer = null;
      if (!_dirty && _saving == null) return;
      await (_saving ??= _drain());
      if (saveError != null) return;
    } while (_dirty || _saving != null);
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    _saveTimer = null;
    unawaited(flush());
    super.dispose();
  }
}
