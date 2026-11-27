The original transition fixtures are unmodified EveryAyah recordings from four production reciter collections.

`tool/audio_gap_samples.json` records source archive URLs, original folders and
filenames, hashes and upstream checksum state. The read-only PCM diagnostic in
`tool/audio_gap_diagnostic.py` uses these fixtures along with the production
Bismillah fixtures. See `docs/v5-gapless-validation.md` for measurements and limits.

The Al-Juhany 112:2 fixture exercises stereo polarity in the Android decoder.
Its source folder and checksum are recorded in [the Al-Juhany audit](../../../docs/v9-juhany-stereo.json).
