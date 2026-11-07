# Local native queue maintenance

The app vendors this package to retain bounded Dart/native source registrations
and its existing queue fixes. See the repository's audio regressions for those
changes; do not replace this tree with an unreviewed upstream copy.

The current Darwin follow-up preserves the identity-matching queued prefix during
loop-off edits that keep the current item. The previous implementation removed
and reinserted every future item, including an unchanged prepared next item.
Only a divergent suffix is now repaired; current-item changes and native loop
modes keep their existing path. Lazy treadmill size and decoder settings are
unchanged. `QueuePrefix.h` is exercised by `tool/native_tests/queue_prefix_test.c`.

This eliminates unnecessary native queue churn; it does not certify audible
output gaplessness. AVFoundation builds and physical before/after capture remain
required. Android Media3 version, offload and decoder behavior are unchanged.
