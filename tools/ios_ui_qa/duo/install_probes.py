"""Instrument only the disposable simulator build, before Flutter compilation."""
from pathlib import Path

folder = Path(__file__).parent
native = Path('ios/Runner/SceneDelegate.swift')
reader = Path('lib/reader/reader_screen.dart')


def insert(text, original, replacement):
    assert text.count(original) == 1, original
    return text.replace(original, replacement)


native.write_text(insert(native.read_text(), 'super.sceneDidBecomeActive(scene)',
                         'super.sceneDidBecomeActive(scene)\n    CoverTouchObserver.install(window)') +
                  (folder / 'UIKitTouches.swift').read_text())
source = reader.read_text()
for original, replacement in [
    ("import 'dart:async';", "import 'dart:async';\nimport 'dart:convert';\nimport 'package:flutter/gestures.dart';"),
    ('  bool _ready = false;', '  bool _ready = false;\n  _CoverProbe? _touchProbe;'),
    ('    _restoreHighlight(savedHighlight, maxFilePage);',
     """    if (Platform.environment['READER_TOUCH_QA'] == '1') {
      _touchProbe = _CoverProbe(this, _docDir);
    }
    _restoreHighlight(savedHighlight, maxFilePage);"""),
    ('    _welcomeTimer?.cancel();', '    _touchProbe?.dispose();\n    _welcomeTimer?.cancel();'),
    ('  void _adjustScale(double delta) {',
     "  void _adjustScale(double delta) {\n    _touchProbe?.event({'callback': 'zoom', 'delta': delta});")
]:
    source = insert(source, original, replacement)
reader.write_text(source + (folder / 'reader_probe.dart.inc').read_text())
