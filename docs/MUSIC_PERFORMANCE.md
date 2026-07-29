# Music observation performance

YuanGUI keeps `MusicFeature` as a non-observable command facade. SwiftUI views
subscribe directly to the smallest music store they render. In particular,
playback progress is isolated in `MusicPlaybackProgress`; library, account, and
import updates must not invalidate progress or transport controls.

There is intentionally no aggregate `MusicFeatureRuntime`. `MusicFeatureContext`
contains only the seven stores and coordinator wiring. Playback, lyrics,
Bilibili, local import, library, and persistence coordinators own their services,
tasks, caches, queues, and cancellation state. `MusicObservationTests` rejects a
new central runtime and verifies those ownership boundaries from production
sources.

## Repeatable Instruments check

1. Build a Debug app and open **Instruments → SwiftUI** with **View Body
   Updates** enabled.
2. Open the mini player and the full music player.
3. Record 30 seconds of playback. Progress updates may refresh
   `MusicProgressView`; they must not refresh the settings root, library
   sidebar, or `PetRootView`.
4. While recording, import or remove library entries and exercise Bilibili
   account/import UI. These operations may refresh their own subtree; they
   must not refresh `MusicProgressView` or transport controls.
5. Exercise a 100-step favorite-folder import. Only the import sheet/sidebar
   may follow `completedCount`.

The automated companion checks live in `MusicObservationTests`. They verify
publisher isolation, run a 100-update import sequence, prohibit
`ObservedMusicFeature` and `MusicFeatureRuntime`, verify coordinator task
ownership, and keep `MusicFeature.swift` below 500 lines.
