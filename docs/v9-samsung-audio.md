# Al-Juhany on a Samsung built-in speaker

The listener reported that the same ayah was clear from EveryAyah on the same Samsung speaker. The app had been explicitly requesting speech playback for every reciter. In the Android comparison, Chromium playing the identical MP3 requested neutral media playback. v9 now uses that media usage and content type for both continuous PCM and just_audio. The iOS session uses the playback category in default mode. Audio focus, pause on duck, queue scheduling, frame recovery, volume and the MP3 files retain their previous behaviour.

**The output-setting difference is confirmed. Its audible effect on the reporting Samsung is pending.** The recordings contain a specific reason a speaker mix could affect Al-Juhany much more than another reciter. In 24 of his 25 sampled originals, the left and right waveforms are strongly opposed. Averaging the channels reduces RMS level by 14.78–18.43 dB relative to their stereo energy. Al-Juhany’s 1:1 and the Alafasy 112:2 control each lose only 0.12 dB. The app delivers two channels to Android. The test did not measure acoustic cancellation, Samsung processing or a forced mono mix on the reporting handset.

## Source identity and encoding

All 25 Al-Juhany audit files matched both the SHA-256 of the pinned mirror and its recorded EveryAyah MD5. The direct EveryAyah endpoint returned HTTP 403 from the test environment. Four originals were seeded into an empty app cache for the Android A/B. On the next run the production AudioRepository returned all four existing files from `app_flutter/audio/abdullah_juhany` with the same hashes. The reporting phone’s private cache was unavailable. [Source hashes and pinned mirror](v9-audio-audit.json)

All 25 files declare 576 samples each of LAME encoder delay and padding, including the positive-correlation 1:1 control. For 112:2, Android MediaExtractor reported 576/576 and supplied 77 MPEG audio packets. The Info header counted 78. FFmpeg skipped 1,105 samples at the beginning and applied zero discard at EOF. These are differences at the ends of the recording. They do not account for its opposing channel polarity throughout. The fix makes no adjustment to trimming or channel polarity.

## Complete-waveform comparison

On Android 10/API 29 x86_64, the two real backends played 112:1–4 in sequence from the same cache paths, at normal speed and gain. The diagnostic build copied the samples accepted by the continuous AudioTrack writer and used a Media3 TeeAudioProcessor on the legacy PCM path. Both reached EOF. FFmpeg independently decoded the originals as 44.1 kHz stereo S16. Each channel was aligned independently at an interior landmark and the full shared interval was compared, including the opening. The endpoint differences are included below.

| Ayah | FFmpeg frames | Continuous frames | Left / right correlation with FFmpeg | Continuous gain delta, left / right |
| --- | ---: | ---: | --- | --- |
| 112:1 | 106,031 | 105,984 | 0.999129 / 0.999051 | −0.00757 / −0.00825 dB |
| 112:2 | 87,599 | 87,552 | 0.999844 / 0.999875 | −0.00138 / −0.00111 dB |
| 112:3 | 115,247 | 115,200 | >0.999999 / >0.999999 | −0.00001 / −0.00002 dB |
| 112:4 | 155,567 | 155,520 | 0.999933 / 0.999885 | −0.00058 / −0.00100 dB |

Continuous PCM and just_audio agreed **sample for sample in both channels on all 464,256 shared frames**. Neither hit a clipping rail in these four recordings. Opening differences against FFmpeg were present in both Android backends. Beyond the first 4,096 frames of each ayah, per-channel error was at most five S16 units throughout the shared interval. The known 47-frame tail difference per ayah remains in continuous PCM. The legacy capture retained those frames and ended with another 529 zero frames. These measurements are upstream of the speaker. [Per-channel peaks, RMS, errors, alignment and unmatched frames](v9-juhany-stereo.json)

Android’s playback log showed `USAGE_MEDIA / CONTENT_TYPE_SPEECH` for both original backends. An HTML audio element playing the same 112:2 MP3 through Android Chromium WebView reported `USAGE_MEDIA / CONTENT_TYPE_UNKNOWN`. After the change, Android reported that same usage and content type for both app backends. A second real playback from the warm cache produced bit-identical output to each backend’s own baseline. The full capture SHA-256 values were `4ee1e9c5f23ad5b8667c0b5382c3090541d0437c5d51c15cb9b7a313ddd4b57f` for continuous and `79eb69d7ff4c1a1ffee56f61d1d36a84e8d653214a75d1bc40075908f79acfe5` for legacy. The diagnostic sample taps are absent from the reader.

The measurements can be repeated on an ordered passage and raw stereo S16LE captures. Omitting the capture arguments reports just the source measurements.

```sh
python3 tool/compare_stereo_playback.py /path/to/11200{1,2,3,4}.mp3 \
  --continuous continuous.s16 --legacy legacy.s16
```

## Acceptance

On the reporting Samsung, play Al-Juhany’s 112:2 through the built-in speaker in v9 at the volume where the haze was audible. Al-Juhany’s 1:1 provides a same-reciter control with the same encoder metadata. Physical Samsung listening and iOS device playback remain outstanding.

The focused Flutter run passed 135 tests covering playback intent, interruption handling, repository validation, continuous recovery, gapless preparation, quarter destinations and navigator sizing/motion. The two new motion tests check intermediate row positions, opacity, chevron rotation, reversal and instant reduced-motion behaviour. Flutter analysis, all ten Python audio-tool tests, all six Android PCM unit tests and the Android debug app build passed.
