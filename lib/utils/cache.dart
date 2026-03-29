import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';

class QuranPageCache {
  static final Map<String, Image> _cache = {};

  static Image getPage(String path) {
    if (!_cache.containsKey(path)) {
      _cache[path] = Image.file(File(path), fit: BoxFit.contain);
    }
    return _cache[path]!;
  }
}
