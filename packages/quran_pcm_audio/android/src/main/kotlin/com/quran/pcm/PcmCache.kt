package com.quran.pcm

/** Tiny recordings can repeat without another decode or another PCM allocation.
 * Long recordings only use the rolling FIFO; never retain them in this cache. */
internal class PcmCache(private val capacity: Int = 88200) {
    private val entries = LinkedHashMap<String, List<ShortArray>>(8, 0.75f, true)
    var frames = 0
        private set
    operator fun get(path: String): List<ShortArray>? = entries[path]
    fun put(path: String, chunks: List<ShortArray>) {
        val size = chunks.sumOf { it.size / 2 }
        if (size > capacity) return
        entries.remove(path)?.let { frames -= it.sumOf { chunk -> chunk.size / 2 } }
        while (entries.isNotEmpty() && (frames + size > capacity || entries.size >= 8)) {
            val oldest = entries.entries.iterator()
            frames -= oldest.next().value.sumOf { it.size / 2 }
            oldest.remove()
        }
        entries[path] = chunks.toList()
        frames += size
    }
}
