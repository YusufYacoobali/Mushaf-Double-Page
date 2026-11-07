#ifndef JUST_AUDIO_QUEUE_PREFIX_H
#define JUST_AUDIO_QUEUE_PREFIX_H
#include <stdbool.h>
#include <stddef.h>

// Retain only the unchanged prefix: preserving an item after a mismatch could
// put the native queue in a different order from the logical playlist.
static inline size_t JAMatchingQueuePrefix(size_t existingCount,
                                          size_t desiredCount,
                                          void *context,
                                          bool (*sameItem)(void *, size_t)) {
    size_t keep = 0;
    while (keep < existingCount && keep < desiredCount && sameItem(context, keep)) {
        ++keep;
    }
    return keep;
}
#endif
