package com.ryanheise.just_audio;

import android.content.Context;
import android.os.Bundle;
import android.os.Handler;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.Timeline;
import androidx.media3.exoplayer.DefaultRenderersFactory;
import androidx.media3.exoplayer.ExoPlaybackException;
import androidx.media3.exoplayer.Renderer;
import androidx.media3.exoplayer.audio.AudioRendererEventListener;
import androidx.media3.exoplayer.audio.AudioSink;
import androidx.media3.exoplayer.audio.ForwardingAudioSink;
import androidx.media3.exoplayer.audio.MediaCodecAudioRenderer;
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector;
import androidx.media3.exoplayer.source.MediaSource.MediaPeriodId;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

/** Match the polarity option to the stream actually leaving the decoder.
 * ExoPlayer can already be reading the next item while the previous one drains. */
final class StereoRenderersFactory extends DefaultRenderersFactory {
    static final String OPTION = "invertRightChannel";

    StereoRenderersFactory(Context context) { super(context); }

    @Override
    protected void buildAudioRenderers(Context context, int extensionMode, MediaCodecSelector selector,
            boolean fallback, AudioSink original, Handler handler, AudioRendererEventListener listener,
            ArrayList<Renderer> renderers) {
        StereoSink sink = new StereoSink(original);
        renderers.add(new MediaCodecAudioRenderer(context, getCodecAdapterFactory(), selector, fallback,
                handler, listener, sink) {
            @Override
            protected void onStreamChanged(Format[] formats, long startUs, long offsetUs, MediaPeriodId id)
                    throws ExoPlaybackException {
                Timeline timeline = getTimeline();
                int index = timeline.getIndexOfPeriod(id.periodUid);
                Bundle extras = null;
                if (index != C.INDEX_UNSET) {
                    int window = timeline.getPeriod(index, new Timeline.Period()).windowIndex;
                    MediaItem item = timeline.getWindow(window, new Timeline.Window()).mediaItem;
                    extras = item.requestMetadata.extras;
                }
                sink.pending.put(offsetUs, extras != null && extras.getBoolean(OPTION));
                super.onStreamChanged(formats, startUs, offsetUs, id);
            }

            @Override
            protected void onDisabled() {
                super.onDisabled();
                sink.pending.clear();
                sink.invert = false;
            }

            @Override
            protected void onPositionReset(long positionUs, boolean joining) throws ExoPlaybackException {
                super.onPositionReset(positionUs, joining);
                sink.pending.clear();
            }
        });
    }

    private static final class StereoSink extends ForwardingAudioSink {
        final Map<Long, Boolean> pending = new HashMap<>();
        boolean invert;
        private int encoding;
        private ByteBuffer scratch = ByteBuffer.allocateDirect(0);
        private ByteBuffer input;

        StereoSink(AudioSink sink) { super(sink); }

        @Override
        public void setOutputStreamOffsetUs(long offsetUs) {
            Boolean next = pending.remove(offsetUs);
            if (next != null) invert = next;
            super.setOutputStreamOffsetUs(offsetUs);
        }

        @Override
        public void configure(Format format, int bufferSize, int[] channelMap) throws ConfigurationException {
            encoding = MimeTypes.AUDIO_RAW.equals(format.sampleMimeType) && format.channelCount == 2
                    ? format.pcmEncoding : C.ENCODING_INVALID;
            super.configure(format, bufferSize, channelMap);
        }

        @Override
        public boolean handleBuffer(ByteBuffer buffer, long timeUs, int encodedSamples)
                throws InitializationException, WriteException {
            if (!invert || (encoding != C.ENCODING_PCM_16BIT && encoding != C.ENCODING_PCM_FLOAT)) {
                return super.handleBuffer(buffer, timeUs, encodedSamples);
            }
            if (input != buffer) {
                // Codec output can be read-only. Keep the same corrected buffer across partial writes.
                if (scratch.capacity() < buffer.remaining()) scratch = ByteBuffer.allocateDirect(buffer.remaining());
                scratch.clear();
                scratch.order(ByteOrder.nativeOrder());
                scratch.put(buffer.duplicate()).flip();
                if (encoding == C.ENCODING_PCM_FLOAT) {
                    for (int i = 4; i + 4 <= scratch.limit(); i += 8) scratch.putFloat(i, -scratch.getFloat(i));
                } else {
                    for (int i = 2; i + 2 <= scratch.limit(); i += 4) {
                        scratch.putShort(i, (short)Math.min(Short.MAX_VALUE, -scratch.getShort(i)));
                    }
                }
                input = buffer;
            }
            boolean consumed = super.handleBuffer(scratch, timeUs, encodedSamples);
            buffer.position(buffer.limit() - scratch.remaining());
            if (consumed) input = null;
            return consumed;
        }

        @Override public void flush() { input = null; super.flush(); }
        @Override public void reset() { input = null; super.reset(); }
    }
}
