# Music observation performance

YuanGUI keeps `MusicFeature` as a non-observable command facade. SwiftUI views
subscribe directly to the smallest music store they render. In particular,
playback progress is isolated in `MusicPlaybackProgress`; library, account, and
import updates must not invalidate progress or transport controls.

There is intentionally no aggregate runtime, service-locator context, or
all-domain coordinator base class. `MusicFeature` directly composes the stores
and coordinators, and is the only place that orchestrates cross-domain flows.
Coordinators receive their own stores and services plus narrow MainActor
delegate/access protocols; they cannot look up concrete sibling coordinators.

Every unstructured async operation is owned by a coordinator. Operations use a
stored task handle or `MusicTaskRegistry`, including tasks that were cancelled
because a newer task replaced them. Shutdown advances the generation, cancels
and awaits every outstanding task, and blocks all post-await state or
persistence commits. The lifecycle tests deliberately suspend providers across
shutdown and then resume them to verify that late results are ignored.

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
publisher isolation, run a 100-update import sequence, exercise suspended
Bilibili and local requests across shutdown, and verify batch de-duplication.
These are behavior tests rather than source-string, symbol-name, or line-count
checks.

## Recorded comparison

Recorded on 2026-07-30 with macOS 26.5, Xcode/Instruments 26.5, and the
`View Body (Legacy)` Instruments instrument. The baseline was tag `v2.7.0`
(`2faaf5b`); the optimized build was the current music isolation worktree.

The opt-in `MusicInstrumentsProfileTests` scenario mounts the production
`MusicPlayerView` (including its real `MusicProgressView`) in an
`NSHostingView`, then publishes 100 individual Bilibili favorite-import
progress changes at 10 ms intervals. Run it with:

```sh
YUANGUI_MUSIC_INSTRUMENTS=1 swift test \
  --filter MusicInstrumentsProfileTests
```

The same test executable was launched by Instruments for both revisions. The
exported `swiftui-body-interval` table reported:

| Revision | `MusicPlayerView` evaluations | `MusicProgressView` evaluations |
| --- | ---: | ---: |
| `v2.7.0` baseline | 103 | 103 |
| optimized | 2 | 1 |

The optimized progress view is evaluated only for its initial mount, while the
full-player shell drops from 103 evaluations to 2 (initial lifecycle work
included). Import progress is confined to the Bilibili import/error leaf
subtree. The trace confirms that the production full-player hierarchy was
mounted in both runs rather than inferring isolation from publisher names or
source text.
