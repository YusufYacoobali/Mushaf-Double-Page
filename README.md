# Quran Dual Page

Quran Dual Page is a Flutter Quran reader for Android and iOS, with single-page
and facing-page Mushaf layouts, recitation audio, translations and reading tools.
The app is live and actively maintained.

## Features

- Indo-Pak Tajweed and Madani Mushafs, with page zoom and light/dark appearance.
- Single pages in ordinary phone/tablet portrait, facing pages where the layout
  supports them, and display-region handling for foldable devices.
- RTL page-turn animation. Single-page turns use a printed front and blank
  reverse; two-page turns carry the corresponding page content.
- EveryAyah recitation with ranges, surah queues, repeats, background/media
  controls, offline audio saving and ayah highlighting.
- Automatic page navigation as recitation advances. Scrollable two-page views
  bring the current page's ayah into view; fitted single-page views stay fixed.
- Page and ayah bookmarks, selected-ayah actions, translations, tafsir and surah
  summaries.
- Reading progress and Quran Journey, reminders and a Tasbeeh counter.
- Offline reading and playback after the required content has been downloaded.

## Tech stack

- Flutter and Dart.
- Local preferences, files and SQLite content databases.
- Firebase Storage for Mushaf downloads and EveryAyah for recitation recordings.
- A local `quran_pcm_audio` plugin for continuous mobile playback, with the
  vendored `just_audio` backend available as fallback.

## Goal

Provide a simple, accessible reading experience that feels close to reading
from a physical Mushaf, with layouts suited to the current device and window.

## Development and documentation

The current work in this branch is `v7`. For the local Flutter checks:

```sh
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

The [release-check workflow](.github/workflows/flutter-release-checks.yml) runs
analysis, Flutter tests and QA-script checks on pushes to `v7`. Native audio and
simulator checks have separate commands/workflows; Flutter test results alone do
not establish their outcome.

- [Audio-following behaviour](docs/audio-vertical-following.md): current
  whole-ayah visibility, single-page policy and page-boundary limitations.
- [Continuous EveryAyah playback](docs/continuous-everyayah-engine.md): audio
  ownership, fallback and native validation commands.
- [iOS playback during UI interaction](docs/ios-pcm-ui-contention.md): native
  thread ownership and verification notes.
- [Future refactoring backlog](docs/refactoring-backlog.md): prioritised
  maintenance work, with behaviour-preservation requirements.

Versioned validation reports, dated investigations and recorded test totals in
`docs/` describe their original delivery. Read their branch/date and validation
scope before treating them as current behaviour or current test results.
