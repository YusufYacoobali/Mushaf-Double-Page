import 'dart:async';

import 'package:flutter/widgets.dart';

/// Start optional notification setup only after Flutter has rendered a frame.
/// This Future must never delay app startup or prevent the Quran from opening.
void scheduleDeferredReminders(Future<void> Function() initialize) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(initialize());
  });
}
