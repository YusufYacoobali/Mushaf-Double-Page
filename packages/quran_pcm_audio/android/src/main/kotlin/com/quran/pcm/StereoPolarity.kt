package com.quran.pcm

/** AC energy of a stereo excerpt. Removing DC keeps a biased or silent input
 * from being mistaken for an inverted microphone signal. */
internal class StereoWindow {
    private var frames = 0
    private var leftSum = 0.0
    private var rightSum = 0.0
    private var power = 0.0
    private var sumPower = 0.0

    fun add(samples: ShortArray) {
        val count = samples.size / 2
        for (frame in 0 until count) {
            val left = samples[2 * frame].toDouble()
            val right = samples[2 * frame + 1].toDouble()
            leftSum += left
            rightSum += right
            power += left * left + right * right
            sumPower += (left + right) * (left + right)
        }
        frames += count
    }

    /** Stereo energy and the energy retained by a conventional mono downmix. */
    fun energies(): Pair<Double, Double> {
        if (frames == 0) return 0.0 to 0.0
        val stereo = (power - (leftSum * leftSum + rightSum * rightSum) / frames) / 2
        val sum = leftSum + rightSum
        val mono = (sumPower - sum * sum / frames) / 4
        // Ignore room noise below -40 dBFS RMS.
        return if (stereo < frames * 327.68 * 327.68) 0.0 to 0.0 else stereo to mono
    }
}

internal object StereoPolarity {
    val positions = doubleArrayOf(0.15, 0.50, 0.85)

    fun needsCorrection(window: (Double) -> Pair<Double, Double>): Boolean {
        var strong = 0
        var total = 0.0
        var mix = 0.0
        for (position in positions) {
            val (stereo, mono) = window(position)
            if (stereo <= 0) continue
            if (mono >= stereo * 0.5) return false // centered voice or in-phase stereo
            if (mono <= stereo * 0.0631) strong++ // at least 12 dB of cancellation
            total += stereo
            mix += mono
        }
        return strong >= 2 && mix <= total * 0.0631
    }

    fun restore(samples: ShortArray) {
        for (right in 1 until samples.size step 2) {
            samples[right] = (-samples[right].toInt()).coerceAtMost(Short.MAX_VALUE.toInt()).toShort()
        }
    }
}
