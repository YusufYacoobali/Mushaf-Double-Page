# Future maintenance backlog

Status: proposed follow-up work only. None of the refactors below is implemented
by this documentation update. The current app has useful component, layout,
repository and playback boundaries; improve the remaining concentrated
responsibilities through small, behaviour-preserving changes.

## Constraints for every future change

Preserve current phone, tablet and foldable layouts; page sizing and animation;
audio continuity; highlighting and page-navigation timing; preference keys;
cache paths and formats; and public entrypoints. Keep the existing state approach
unless a concrete requirement warrants changing it. Avoid unrelated fixes,
framework migrations and arbitrary file-size targets in extraction work.

## Priority 1: separate reader orchestration from app startup

[main.dart](../lib/main.dart) currently hosts startup, theme state and the reader's
selection, bookmarks, progress, audio-following and overlay coordination.

Future work: move the reader screen and its cohesive coordination responsibilities
into dedicated files, retaining existing public entrypoints and lifecycle
ownership. Reuse the existing paging, layout, dock and follower components rather
than introducing a second source of reader state. Extract one responsibility at
a time, keeping navigation commits and persistence in their current order.

Acceptance: the existing [adaptive reader](../test/adaptive_reader_test.dart),
[turn navigation](../test/reader_turn_navigation_test.dart),
[audio page following](../test/audio_page_follower_test.dart) and device geometry
tests continue to cover the same observable behaviour. Rotation, fold changes
and manual page turns must preserve the focused page and playback.

## Priority 2: give translation content typed data and smaller UI units

[translation_modal.dart](../lib/components/translation_modal.dart) combines
content loading, preference handling, pagination, settings, summaries and ayah
rendering. Its mixed dynamic lists and maps make these responsibilities harder
to follow.

Future work: introduce explicit header/ayah content types, extract the content
assembly and loading state, and separate settings, summary and ayah-row widgets.
Share content assembly between page and surah modes where their rules coincide;
retain the differences in how each mode selects verses.

Acceptance: preserve selected sources, ordering, page-boundary ayah handling,
focused-ayah positioning, bookmarks and copy/share output. Use the existing
[page index](../test/page_ayah_index_test.dart) and
[translation surface](../test/ayah_translation_safe_area_test.dart) checks;
add focused behavioural coverage only for an extraction boundary they do not
already exercise.

## Priority 3: reduce ancillary work in the audio controller

[QuranAudioController](../lib/logic/quran_audio_controller.dart) already delegates
recording retrieval and playback to separate abstractions. Future work should
first extract offline-download job state/retries and listening-progress
integration, preserving the controller's public API and authoritative playback
cursor. Keep backend fallback and cancellation rules explicit.

Acceptance: retain the existing
[download](../test/automatic_audio_download_test.dart),
[play-intent](../test/audio_play_intent_test.dart),
[continuous backend](../test/continuous_pcm_backend_test.dart) and
[journey](../test/journey_test.dart) behaviour. An extraction must not restart
audio, alter repeat/queue ordering or change download priority.

## Lower-priority follow-up

- Separate reader preferences/bookmarks from Mushaf download, extraction and
  installation in [StorageManager](../lib/logic/storage_manager.dart), preserving
  stored data and rollback behaviour.
- Gradually group feature-owned files when those features are next touched;
  avoid a broad folder move solely for appearance.
- Consolidate current native visual-QA instructions and link historical reports
  as evidence. Preserve the established device scenarios and workflow behaviour;
  documentation consolidation does not imply changing CI.

For each future extraction, review its scope first, run the affected existing
checks, then the established project validation gates before merging. Record
completed work separately so this backlog does not become a claim of delivery.
