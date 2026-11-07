# EveryAyah-only audio restoration

The experimental full-surah provider, timing data, scripts, tests, feature flag
and development modal indicator have been removed. EveryAyah is the only
recording provider for all 22 reciters and all existing playback modes.

The EveryAyah controller and modal were compared against their pre-experiment
versions at `a371881`; only the experiment's changes were removed. The branch
was not reset and no whole commits were reverted. Native queue/cache fixes,
automatic preparation/Play, introductions, repetitions, Surah Queue, background
controls, Journey and iPhone/Android reader layout work are preserved.

A best-effort asynchronous startup migration deletes only the retired
`documents/mp3quran` namespace. It does not traverse `documents/audio`, follows
no symlinks into other caches, and cannot block startup or audio preparation.
Filesystem failures are retried on a subsequent launch. Tests cover preserving
EveryAyah bytes, nested/root symlinks and idempotence. No device cache was remotely
erased from this workspace; upgraded installations perform their own cleanup.

The cleanup is committed separately from the native transition investigation.
See `docs/everyayah-transition-latency.md` for subsequent findings and limitations.

Cleanup validation: `flutter analyze --no-pub` found no issues; all **395** Flutter
tests passed, including the three new provider/removal/cache-migration checks.
Both staged and unstaged whitespace checks passed. The sole remaining legacy
provider name in application code is the exact retired directory being removed.
