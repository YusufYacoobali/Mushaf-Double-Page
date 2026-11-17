# iOS 27 Duo startup blank screen — isolated cause

Prior run 44129635338 launched a live Runner process but stayed on its
LaunchImage with zero downloaded Quran pages.

A CI-only instrumented startup build (GitHub Actions run 44136088352)
recorded these stages on 17 November 2026:
- MUSHAF_BOOT firebase-start / firebase-done
- MUSHAF_BOOT audio-start / audio-handler-initialize-done / audio-done
- MUSHAF_BOOT reminders-start
- No reminders-done or runApp-start appeared in the captured window.

The app therefore awaited ReminderNotifications.initialize() before runApp()
and never rendered a first Flutter frame. Its iOS setup uses
DarwinInitializationSettings() which can trigger a notification permission
request, or otherwise stall platform initialization before a scene is ready.

Fix: await required Firebase/audio setup as before, then call runApp() and
schedule optional notification initialization after the first rendered frame.
The notification scheduling implementation itself is not modified.
The next full simulator test must demonstrate visible real Quran pages, with
folded 70%/100%, unfolded 60%/100% screenshots; a successful build alone is
not enough.
