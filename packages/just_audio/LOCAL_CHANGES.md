# Local just_audio 0.10.5 patch

Source: the published [just_audio 0.10.5 package](https://pub.dev/packages/just_audio/versions/0.10.5).
The original license, platform source and package version are retained.

This application uses a continuously replenished, flat root playlist. Upstream
0.10.5 retains every attached source in its Dart registration map, and Android
retains every decoded MediaSource by ID even after root playlist removal. New
occurrences would therefore accumulate during infinite playback despite a small
visible queue.

The local changes are limited to:

- Releasing unreachable Dart source registrations after root removals or complete
  source-list replacement. Reachability includes nested source children.
- Preserving the root's current logical source while broadcasting a prefix
  removal, avoiding a transient index that names the next ayah.
- Pruning Android's decoded source cache to IDs still in the flat root timeline.
- Exposing a test-only registration count for the real Dart playlist regression.

Upstream trailing whitespace in the README and two native source files is also
normalized so the vendored addition passes `git diff --check`.

The app's queue remains at most six items. Each occurrence uses a distinct source
ID, and source objects are released when removed. Replacements/recovery preserve
occurrence identity through their tags. `test/just_audio_queue_registry_test.dart`
exercises the actual Dart player with a controlled platform channel, rather than
only a FakePlayer. Android/iOS builds and device behavior still require device
validation; no device test is implied by that unit test.

Do not remove this patch or switch the dependency back to pub.dev until an
upstream version provides equivalent bounded retention and the regression passes.
