# Al-Juhany on a Samsung built-in speaker

The listener confirmed that polarity correction cleared Al-Juhany’s recitation on the Samsung speaker and that his original recordings already sound clear on iOS. The reader uses the same speech audio-session configuration as `main`. Android’s continuous output specifies `USAGE_MEDIA / CONTENT_TYPE_SPEECH`.

## Verification with the restored speech profile

On Android 10/API 29, the reader played cached Al-Juhany 112:2–3 through continuous PCM and separately through the Media3 fallback. Android reported `CONTENT_TYPE_SPEECH` for both. The 202,752 stereo frames accepted by continuous output were **byte-identical** to the confirmed correction under the neutral profile (SHA-256 `eaa45d91b0b2f231fd0b25bfb39b48d929a251df3e7f9b656a7e261367e582f0`). Each complete Media3 ayah also matched its earlier corrected capture. Both joins added zero PCM frames in this run. Media3 emitted 529 zero frames at final EOF.

For 112:2, combining the original channels lost 15.42 dB relative to stereo RMS. With the speech profile and correction it lost 0.13 dB. Alafasy 112:2 bypassed analysis and all 109,623 frames matched its previous output. The cached MP3s kept the same file identities, sizes and modification times.

| Cached MP3 selection | Time for the controller to prepare playback | Stereo check on the first file |
| --- | ---: | --- |
| Al-Juhany 112:2–3, first continuous play | 11,688 ms | 3,580 ms for fresh analysis |
| Al-Juhany 112:2, played again | 354 ms | 15 ms for a cached decision |
| Alafasy 112:2, continuous play | 203 ms | Bypassed |
| Al-Juhany 112:2–3, first Media3 play | 10,413 ms | 9 ms for a cached decision |

These times measure `playPlan` on a software-emulated CPU in a debug build. The emulator reported output underruns, and the two single-ayah runs provided no intermediate controller position before completion. The captures establish exactly which samples reached the output writer. Physical startup latency and listening on the Samsung with the **restored** profile remain unmeasured.

The 167 focused Flutter tests cover cache reuse, joins, repeats, interruptions, long-ayah recovery and fallback. Controller tests exercised all 22 reciter selections on each mobile platform and observed probe calls only for Android Al-Juhany. Flutter analysis, the Android debug build and all seven Android PCM unit tests passed. Two Android instrumented tests also passed. One checked every decoded sample of Al-Juhany’s affected 112:2 and already-clear 1:1. The other checked exact occurrence boundaries and pause/resume over three repetitions on one output. The iOS PCM decoder, Darwin just_audio implementation and iOS test target match their pre-polarity versions, including the zero-frame EOF fix. The Swift sources parsed on Linux. An iOS runtime was unavailable.

## Voice cancellation on the speaker

The reported symptom persisted after the media-profile change. On Al-Juhany’s original 112:2, the two channels carry most of the voice with opposite polarity. Adding them cancels the shared voice and leaves more of the room sound. Independent FFmpeg decoding and both Android playback paths reproduce this from the same MP3. The app’s warm-cache 112:2 SHA-256 was `aaf7894410f1cfa9797a796b19b745cb22f616b3d9bdedff5dba8607fdca28a5`. The controller stops the previous output before changing players. The two-ayah capture below follows the selected recordings in order. The reporting Samsung’s acoustic output and its browser’s treatment of the stereo channels have not been captured.

When Al-Juhany is selected on Android, the reader checks up to three 400 ms excerpts spread through each local stereo MP3 during queue preparation. Each probe discards 80 ms of decoder warm-up. It subtracts the channel means and measures the energy that survives averaging the channels. At least two excerpts and their combined active energy must show at least 12 dB of cancellation. An active excerpt retaining half or more of the stereo energy vetoes the change. Excerpts below −40 dBFS and recordings shorter than 900 ms provide insufficient evidence. All other Android reciters and all iOS selections go straight from file preparation to playback. For eligible files, the repository retains the decision in memory for up to 16 file versions.

When the check passes, Android continuous PCM and the just_audio fallback reverse the polarity of the right output channel for that recording. This preserves the two separate channels, sample timing, natural pauses and the cached MP3. The only S16 endpoint exception is −32768, whose nearest representable positive value is 32767. Mono, in-phase stereo and inconclusive measurements play as supplied. Independent FFmpeg measurements on the 25 existing audit originals selected 24 and left Al-Juhany’s 1:1 alone.

| Recording | Android continuous frames | Original mono mix vs stereo RMS | Corrected mono mix vs stereo RMS |
| --- | ---: | ---: | ---: |
| Al-Juhany 112:1 | 105,984 | −15.69 dB | −0.12 dB |
| Al-Juhany 112:2 | 87,552 | −15.42 dB | −0.13 dB |
| Al-Juhany 112:3 | 115,200 | −15.36 dB | −0.13 dB |
| Al-Juhany 112:4 | 155,520 | −15.54 dB | −0.12 dB |
| Al-Juhany 2:282 | 5,516,928 | −15.37 dB | −0.13 dB |
| Al-Juhany 1:1 | 144,000 | −0.12 dB | −0.12 dB |
| Alafasy 112:2 | 109,623 | −0.12 dB | −0.12 dB |

In the earlier neutral-profile run on Android 10, all 464,256 Al-Ikhlas frames matched the earlier continuous decode exactly on the left and with opposite polarity on the right. A separate run used the reader controller and its warm MP3 cache to play 112:2–3 through each backend. Continuous output matched the two corrected decodes end to end across all 202,752 frames. Media3 also matched both complete reference recordings from its earlier capture, including its additional 47 endpoint frames per ayah. In this controller run Media3 emitted 529 zero frames at the join and another 529 at the end. The earlier preloaded Media3 playlist emitted that padding at the end only. The captures used different queue preparation conditions. The normal continuous path inserted zero frames at this join.

## Earlier media-profile comparison

Chromium requested neutral media playback when playing the same MP3 on Android. An earlier version of v9 temporarily matched that profile for both backends. The listener still heard the haze with that change. In 24 of the 25 sampled originals, averaging the opposing channels reduced RMS level by 14.78–18.43 dB. Al-Juhany’s 1:1 and the Alafasy 112:2 control each lost only 0.12 dB.

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

Android’s playback log showed `USAGE_MEDIA / CONTENT_TYPE_SPEECH` for both original backends. An HTML audio element playing the same 112:2 MP3 through Android Chromium WebView reported `USAGE_MEDIA / CONTENT_TYPE_UNKNOWN`. During the neutral-profile experiment, Android reported the same usage and content type as Chromium for both app backends. A second real playback from the warm cache produced bit-identical output to each backend’s own baseline. The full capture SHA-256 values were `4ee1e9c5f23ad5b8667c0b5382c3090541d0437c5d51c15cb9b7a313ddd4b57f` for continuous and `79eb69d7ff4c1a1ffee56f61d1d36a84e8d653214a75d1bc40075908f79acfe5` for legacy. The diagnostic sample taps are absent from the reader.

To reproduce the original decoder comparison, supply an ordered passage and the uncorrected stereo S16LE captures. Omitting the capture arguments reports just the source measurements.

```sh
python3 tool/compare_stereo_playback.py /path/to/11200{1,2,3,4}.mp3 \
  --continuous continuous.s16 --legacy legacy.s16
```
