#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include "../../packages/just_audio/darwin/just_audio/Sources/just_audio/include/just_audio/QueuePrefix.h"

typedef struct { const int *existing; const int *desired; } Context;
static bool equal(void *context, size_t index) {
    Context *items = context;
    return items->existing[index] == items->desired[index];
}

static void check(const int *old, size_t oldCount, const int *target,
                  size_t targetCount, size_t expectedKeep) {
    Context context = {old, target};
    size_t keep = JAMatchingQueuePrefix(oldCount, targetCount, &context, equal);
    assert(keep == expectedKeep);
    // Model precisely the production suffix removal/append. Every retained
    // item's identity and residency survive; the final order must be exact.
    int queue[16];
    size_t count = oldCount;
    for (size_t i = 0; i < count; ++i) queue[i] = old[i];
    while (count > keep) --count;
    for (size_t i = keep; i < targetCount; ++i) queue[count++] = target[i];
    assert(count == targetCount);
    for (size_t i = 0; i < count; ++i) assert(queue[i] == target[i]);
}

int main(void) {
    int ab[] = {1, 2}, abc[] = {1, 2, 3}, ac[] = {1, 3};
    int a[] = {1}, bc[] = {2, 3};
    check(ab, 2, ab, 2, 2); // append beyond the two-item lazy treadmill: no native edits
    check(abc, 3, ab, 2, 2); // trim suffix without evicting next item
    check(ab, 2, abc, 3, 2); // eager source append retains existing preparation
    check(ab, 2, ac, 2, 1); // next source replaced: repair suffix only
    check(a, 1, ab, 2, 1); // initial lookahead arrives
    check(ab, 2, a, 1, 1); // next source removed
    check(ab, 2, bc, 2, 0); // current changes use the legacy path
    check(NULL, 0, ab, 2, 0);
    check(ab, 2, NULL, 0, 0);
    // Exhaustively validate prefix + order for duplicate/repeat identities too.
    for (size_t oldCount = 0; oldCount <= 4; ++oldCount) {
        for (size_t newCount = 0; newCount <= 4; ++newCount) {
            for (unsigned oldBits = 0; oldBits < (1u << oldCount); ++oldBits) {
                for (unsigned newBits = 0; newBits < (1u << newCount); ++newBits) {
                    int old[4], target[4];
                    for (size_t i = 0; i < oldCount; ++i) old[i] = (oldBits >> i) & 1;
                    for (size_t i = 0; i < newCount; ++i) target[i] = (newBits >> i) & 1;
                    size_t expected = 0;
                    while (expected < oldCount && expected < newCount && old[expected] == target[expected]) ++expected;
                    check(old, oldCount, target, newCount, expected);
                }
            }
        }
    }
    puts("Native queue prefix tests passed (order/residency only; no audio-output claim).");
    return 0;
}
