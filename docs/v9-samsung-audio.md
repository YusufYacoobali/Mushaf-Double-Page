# Al-Juhany on a Samsung built-in speaker

## Voice cancellation on the speaker

The reported symptom persisted after the media-profile change. On Al-Juhany’s original 112:2, the two channels carry most of the voice with opposite polarity. Adding them cancels the shared voice and leaves more of the room sound. Independent FFmpeg decoding and both Android playback paths reproduce this from the same MP3. The app’s warm-cache 112:2 SHA-256 was `aaf7894410f1cfa9797a796b19b745cb22f616b3d9bdedff5dba8607fdca28a5`. The controller stops the previous output before changing players. The two-ayah capture below follows the selected recordings in order. The reporting Samsung’s acoustic output and its browser’s treatment of the stereo channels have not been captured.

The reader now checks up to three 400 ms excerpts spread through a local stereo MP3 during queue preparation. Each probe discards 80 ms of decoder warm-up. It subtracts the channel means and measures the energy that survives averaging the channels. At least two excerpts and their combined active energy must show at least 12 dB of cancellation. An active excerpt retaining half or more of the stereo energy vetoes the change. Excerpts below −40 dBFS and recordings shorter than 900 ms provide insufficient evidence. The check uses samples from the selected file on Android and iOS. It has no reciter lookup. Only the decision is retained in memory, for up to 16 file versions.

When the check passes, both mobile playback paths reverse the polarity of the right output channel for that recording. This preserves the two separate channels, sample timing, natural pauses and the cached MP3. The only S16 endpoint exception is −32768, whose nearest representable positive value is 32767. Mono, in-phase stereo and inconclusive measurements play as supplied. Independent FFmpeg measurements on the 25 existing audit originals selected 24 and left Al-Juhany’s 1:1 alone.

| Recording | Android continuous frames | Original mono mix vs stereo RMS | Corrected mono mix vs stereo RMS |
| --- | ---: | ---: | ---: |
| Al-Juhany 112:1 | 105,984 | −15.69 dB | −0.12 dB |
| Al-Juhany 112:2 | 87,552 | −15.42 dB | −0.13 dB |
| Al-Juhany 112:3 | 115,200 | −15.36 dB | −0.13 dB |
| Al-Juhany 112:4 | 155,520 | −15.54 dB | −0.12 dB |
| Al-Juhany 2:282 | 5,516,928 | −15.37 dB | −0.13 dB |
| Al-Juhany 1:1 | 144,000 | −0.12 dB | −0.12 dB |
| Alafasy 112:2 | 109,623 | −0.12 dB | −0.12 dB |

On Android 10, all 464,256 Al-Ikhlas frames matched the earlier continuous decode exactly on the left and with opposite polarity on the right. A separate run used the reader controller and its warm MP3 cache to play 112:2–3 through each backend. Continuous output matched the two corrected decodes end to end across all 202,752 frames. Media3 also matched both complete reference recordings from its earlier capture, including its additional 47 endpoint frames per ayah. In this controller run Media3 emitted 529 zero frames at the join and another 529 at the end. The earlier preloaded Media3 playlist emitted that padding at the end only. The captures used different queue preparation conditions. The normal continuous path inserted zero frames at this join.

The focused Flutter suite passed 123 tests. All seven Android PCM unit tests passed. An instrumented Android test compared every sample of Al-Juhany 112:2, his 1:1 control and the Alafasy control against the same native decoder with the correction disabled. Both Android playback paths reached the end of the selection without a handoff. The Android debug reader built and Flutter analysis passed. The Darwin Objective-C playback changes passed an arm64 iOS SDK syntax check. The Swift sources parsed, but the Linux cross-toolchain could not type-check the Apple Dispatch SDK overlay. The iOS test target includes both same-reciter fixtures and checks every Core Audio frame. Running it under Xcode and listening on the reporting Samsung speaker remain outstanding. For the handset check, use the existing cached 112:2 at the same volume as the clear EveryAyah playback.

## Earlier media-profile comparison

The listener reported that the same ayah was clear from EveryAyah on the same Samsung speaker. The app had been explicitly requesting speech playback for every reciter. In the Android comparison, Chromium playing the identical MP3 requested neutral media playback. v9 now uses that media usage and content type for both continuous PCM and just_audio. The iOS session uses the playback category in default mode. Audio focus, pause on duck, queue scheduling, frame recovery, volume and the MP3 files retain their previous behaviour.

**This earlier comparison established the output-setting difference.** The recordings contain a specific reason a speaker mix could affect Al-Juhany much more than another reciter. In 24 of his 25 sampled originals, the left and right waveforms are strongly opposed. Averaging the channels reduces RMS level by 14.78–18.43 dB relative to their stereo energy. Al-Juhany’s 1:1 and the Alafasy 112:2 control each lose only 0.12 dB. The app delivers two channels to Android. The test did not measure acoustic cancellation, Samsung processing or a forced mono mix on the reporting handset.

## Source identity and encoding

All 25 Al-Juhany audit files matched both the SHA-256 of the pinned mirror and its recorded EveryAyah MD5. The direct EveryAyah endpoint returned HTTP 403 from the test environment. Four originals were seeded into an empty app cache for the Android A/B. On the next run the production AudioRepository returned all four existing files from `app_flutter/audio/abdullah_juhany` with the same hashes. The reporting phone’s private cache was unavailable. [Source hashes and pinned mirror](v9-audio-audit.json)

All 25 files declare 576 samples each of LAME encoder delay and padding, including the positive-correlation 1:1 control. For 112:2, Android MediaExtractor reported 576/576 and supplied 77 MPEG audio packets. The Info header counted 78. FFmpeg skipped 1,105 samples at the beginning and applied zero discard at EOF. These are differences at the ends of the recording. They do not account for its opposing channel polarity throughout. The earlier media-profile change made no adjustment to trimming or channel polarity.

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

## Validation of the earlier media-profile change

On the reporting Samsung, play Al-Juhany’s 112:2 through the built-in speaker in v9 at the volume where the haze was audible. Al-Juhany’s 1:1 provides a same-reciter control with the same encoder metadata. Physical Samsung listening and iOS device playback remain outstanding.

The focused Flutter run passed 135 tests covering playback intent, interruption handling, repository validation, continuous recovery, gapless preparation, quarter destinations and navigator sizing/motion. The two new motion tests check intermediate row positions, opacity, chevron rotation, reversal and instant reduced-motion behaviour. Flutter analysis, all ten Python audio-tool tests, all six Android PCM unit tests and the Android debug app build passed.
