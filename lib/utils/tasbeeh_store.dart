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
  TasbeehStore({this.writeSnapshot});
  // One store survives route changes, including an unfinished platform save.
  static final instance = TasbeehStore();
  static const storageKey = 'tasbeeh_state_v1';
  final Future<bool> Function(String)? writeSnapshot;
  SharedPreferences? _prefs;
  Future<void>? _restoring;
  Future<void>? _saving;
  String? _pending;
  bool ready = false;
  bool _disposed = false;
  String? saveError;
  String _selected = 'subhanallah';
  final _counts = <String, BigInt>{};
  final _targets = <String, BigInt>{};
  final _custom = <Dhikr>[];
  bool vibration = true, sound = false, targetFeedback = true;

  List<Dhikr> get dhikrs => List.unmodifiable([...builtInDhikr, ..._custom]);
  Dhikr get selected => dhikrs.firstWhere(
    (d) => d.id == _selected,
    orElse: () => builtInDhikr.first,
  );
  BigInt get count => _counts[_selected] ?? BigInt.zero;
  BigInt? get target => _targets[_selected];
  String get display => count.toString().padLeft(5, '0');

  Future<void> restore() => _restoring ??= _restore();
  Future<void> _restore() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(storageKey);
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if (json['version'] == 1) {
          _selected = json['selected'] as String? ?? _selected;
          vibration = json['vibration'] as bool? ?? true;
          sound = json['sound'] as bool? ?? false;
          targetFeedback = json['targetFeedback'] as bool? ?? true;
          for (final entry in (json['counts'] as Map? ?? {}).entries) {
            final value = BigInt.tryParse('${entry.value}');
            if (value != null && value >= BigInt.zero) {
              _counts['${entry.key}'] = value;
            }
          }
          for (final entry in (json['targets'] as Map? ?? {}).entries) {
            final value = BigInt.tryParse('${entry.value}');
            if (value != null && value > BigInt.zero) {
              _targets['${entry.key}'] = value;
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
        }
      } catch (_) {
        saveError = 'Saved Tasbeeh data could not be read.';
      }
    }
    ready = true;
    if (!_disposed) notifyListeners();
  }

  /// Returns true at each target multiple; reaching it never resets the count.
  bool increment() {
    if (!ready) return false;
    _counts[_selected] = count + BigInt.one;
    final reached = target != null && count % target! == BigInt.zero;
    _changed();
    return reached;
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

  void setTarget(BigInt? value) {
    if (!ready || (value != null && value <= BigInt.zero)) return;
    if (value == null) {
      _targets.remove(_selected);
    } else {
      _targets[_selected] = value;
    }
    _changed();
  }

  void preferences({bool? vibration, bool? sound, bool? targetFeedback}) {
    if (!ready) return;
    this.vibration = vibration ?? this.vibration;
    this.sound = sound ?? this.sound;
    this.targetFeedback = targetFeedback ?? this.targetFeedback;
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
    _targets.remove(id);
    if (_selected == id) _selected = builtInDhikr.first.id;
    _changed();
  }

  void _changed() {
    _pending = jsonEncode({
      'version': 1,
      'selected': _selected,
      'counts': _counts.map((k, v) => MapEntry(k, '$v')),
      'targets': _targets.map((k, v) => MapEntry(k, '$v')),
      'vibration': vibration,
      'sound': sound,
      'targetFeedback': targetFeedback,
      'custom': _custom.map((d) => {'id': d.id, 'label': d.label}).toList(),
    });
    notifyListeners();
    _saving ??= _drain();
  }

  Future<void> _drain() async {
    // Yield once so _saving is assigned even with an immediate test writer.
    await Future<void>.value();
    try {
      while (_pending != null) {
        final snapshot = _pending!;
        _pending = null;
        final saved =
            await (writeSnapshot?.call(snapshot) ??
                _prefs!.setString(storageKey, snapshot));
        if (!saved) throw StateError('Local storage rejected the save');
        saveError = null;
      }
    } catch (_) {
      saveError = 'Progress could not be saved. Please try again.';
      // Keep the newest snapshot queued for flush/retry.
      _pending ??= jsonEncode({
        'version': 1,
        'selected': _selected,
        'counts': _counts.map((k, v) => MapEntry(k, '$v')),
        'targets': _targets.map((k, v) => MapEntry(k, '$v')),
        'vibration': vibration,
        'sound': sound,
        'targetFeedback': targetFeedback,
        'custom': _custom.map((d) => {'id': d.id, 'label': d.label}).toList(),
      });
    } finally {
      _saving = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> flush() async {
    if (_saving == null && _pending != null) _saving = _drain();
    await _saving;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
