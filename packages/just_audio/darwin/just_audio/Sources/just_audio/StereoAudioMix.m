#import "StereoAudioMix.h"
#import <MediaToolbox/MediaToolbox.h>

static void initialize(MTAudioProcessingTapRef tap, void *info, void **storage) {
    *storage = calloc(1, sizeof(AudioStreamBasicDescription));
}

static void finalize(MTAudioProcessingTapRef tap) {
    free(MTAudioProcessingTapGetStorage(tap));
}

static void prepare(MTAudioProcessingTapRef tap, CMItemCount maxFrames, const AudioStreamBasicDescription *format) {
    AudioStreamBasicDescription *saved = MTAudioProcessingTapGetStorage(tap);
    if (saved) *saved = *format;
}

static void process(MTAudioProcessingTapRef tap, CMItemCount requested, MTAudioProcessingTapFlags flags,
                    AudioBufferList *buffers, CMItemCount *frames, MTAudioProcessingTapFlags *flagsOut) {
    *frames = 0;
    *flagsOut = 0;
    if (MTAudioProcessingTapGetSourceAudio(tap, requested, buffers, flagsOut, NULL, frames) != noErr) return;
    const AudioStreamBasicDescription *format = MTAudioProcessingTapGetStorage(tap);
    if (!format || format->mFormatID != kAudioFormatLinearPCM || format->mChannelsPerFrame != 2 ||
        (format->mFormatFlags & kAudioFormatFlagIsBigEndian) || *frames <= 0) return;
    const BOOL planar = (format->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    if (buffers->mNumberBuffers != (planar ? 2 : 1)) return;
    AudioBuffer right = buffers->mBuffers[planar ? 1 : 0];
    const size_t stride = planar ? 1 : 2, start = planar ? 0 : 1;
    if (!right.mData || right.mNumberChannels != stride) return;
    if ((format->mFormatFlags & kAudioFormatFlagIsFloat) && format->mBitsPerChannel == 32 &&
        format->mBytesPerFrame == stride * sizeof(float)) {
        float *samples = right.mData;
        size_t end = MIN((size_t)*frames * stride, right.mDataByteSize / sizeof(float));
        for (size_t i = start; i < end; i += stride) samples[i] = -samples[i];
    } else if ((format->mFormatFlags & kAudioFormatFlagIsSignedInteger) && format->mBitsPerChannel == 16 &&
               format->mBytesPerFrame == stride * sizeof(int16_t)) {
        int16_t *samples = right.mData;
        size_t end = MIN((size_t)*frames * stride, right.mDataByteSize / sizeof(int16_t));
        for (size_t i = start; i < end; i += stride) samples[i] = (int16_t)MIN(INT16_MAX, -samples[i]);
    }
}

void JAInstallStereoPolarityMix(AVPlayerItem *item) {
    AVAssetTrack *track = [item.asset tracksWithMediaType:AVMediaTypeAudio].firstObject;
    if (!track) return;
    MTAudioProcessingTapCallbacks callbacks = {
        kMTAudioProcessingTapCallbacksVersion_0, NULL, initialize, finalize, prepare, NULL, process
    };
    MTAudioProcessingTapRef tap = NULL;
    if (MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap) != noErr) return;
    AVMutableAudioMixInputParameters *input = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];
    input.audioTapProcessor = tap;
    CFRelease(tap);
    AVMutableAudioMix *mix = [AVMutableAudioMix audioMix];
    mix.inputParameters = @[input];
    item.audioMix = mix;
}
