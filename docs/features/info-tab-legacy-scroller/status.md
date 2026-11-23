Issue: #236 · Complexity: routine

# Info tab fields run under a legacy scroller: implementation status

Owner: swift-macos-engineer. Bug fix (no PRD or design, `docs/WORKFLOW.md`).
Branch `bug/info-tab-legacy-scroller`. Status: **Done**.

## Bug

**Steps to reproduce.** Legacy scrollers (a mouse attached, or System Settings
▸ Appearance ▸ Show scroll bars: Always). Open a photo in the loupe with the
inspector at its default 300 pt, Info tab. Scripted, against a scratch library
from `photobench` (`--library-root` always):

```
wait 2; focus RAW_00005; loupe; wait 2; inspector on; wait 1; tab info; wait 2; print inspectorwidth; quit
```

**Expected.** The Info tab's column follows the visible width, as the Adjust
tab's does: controls inside the clip view's 283 pt (12 pt padding each side).

**Actual.** The text fields (Keywords entry, Metadata fields) are 276 pt wide,
laid out for the 300 pt pane, and run 5 pt under the vertical scroller:
`pane 300 scroller legacy visible 283 controls 12...288 widest NSTextField 276 overflow`.
Overlay scrollers: `fits` (no scroller takes room).

**Root cause.** `AppKitScrollView` pins its hosting view (the document view) to
the clip view's leading and trailing edges with Auto Layout. The Info tab's
content arrives after its first layout (`InfoInspector`'s `.task` loads the
details, keywords and metadata), so the document is first laid out at 300 pt
with no scroller. Once the content is tall enough, the legacy scroller appears
and `NSScrollView` shrinks the clip view to 283 pt. That resize happens inside
the scroll view's own layout pass, and the document's trailing constraint is not
re-solved: the document stays 300 pt wide and SwiftUI keeps laying the content
out at 300 pt. How that happens is a hypothesis that fits the experiments, not
something shown: the clip view's resize inside the scroll view's layout pass
seems to leave it with no pending layout, so Auto Layout does not re-solve the
constraint until something else marks it. What was seen: the constraints
themselves are right (forcing `clip.needsLayout = true` and a layout pass in the
debug script moved the document to 283 at once; setting only
`document.needsLayout` did not), and on the unfixed build a later window resize
did re-solve the width (QA saw `fits` after a `windowsize` that followed the
overflow), so the width stays wrong only until something else lays the clip
view out. The Adjust tab is tall from its first layout, so it never hits this.

**Fix.** `FlippedClipView.setFrameSize` (the clip view `AppKitScrollView` always
uses) marks itself for layout on the next run-loop turn when its width changed
(`Sources/PhotoApp/Views/AppKitScrollView.swift`). Marking it synchronously
inside the resize did not work (still `overflow`); the deferred mark does. Why
the synchronous mark fails is not established; a plausible reason is that the
flag is cleared at the end of the layout pass in progress, which the deferred
mark, made on a later turn, survives.

**The test that fails without the fix.** No unit test can reach it: the code is
in PhotoApp, which no test target imports (the same limit #223 recorded), and
the fault is in AppKit's layout timing, not in any pure logic. The regression
check is `print inspectorwidth` with each scroller style, recorded below:
`overflow` before, `fits` after.

## Measurements

Two copies of the bundle from `Scripts/build-app.sh` (SDK 27.2) with their own
identifiers (`me.sesser.gus.debugtest.fix236before`, built from this branch's
base, and `…fix236after`), ad hoc re-signed, a
`photobench generate --jpeg 4 --dng 2 --heic 1` scratch library imported with
`photobench import`, copied fresh for each run, every launch with
`--library-root`. The scroller style was forced per run with
`defaults write <bundle id> AppleShowScrollBars Always|WhenScrolling` (the copy's
own domain, deleted after). Default pane 300 pt in every run. (A bare
`swift build` executable records the macOS 15 SDK and runs in the earlier
design, with different control sizes and a 15 pt scroller: do not compare
its output with the bundle's.)

Script (Info, then Adjust, Adjust scrolled to the bottom, Info again, another photo):

```
wait 2; focus RAW_00005; loupe; wait 2; inspector on; wait 1; tab info; wait 2; print inspectorwidth; tab adjust; wait 2; print inspectorwidth; scroll bottom; wait 1; print inspectorwidth; tab info; wait 2; print inspectorwidth; focus RAW_00004; wait 2; print inspectorwidth; quit
```

First line of each `inspectorwidth` (the per-control `segmented` lines follow
the Adjust ones and are identical before and after):

| Scroller | Step | Before | After |
|---|---|---|---|
| legacy | Info | `visible 283 controls 12...288 widest NSTextField 276 overflow` | `visible 283 controls 12...271 widest NSTextField 259 fits` |
| legacy | Adjust | `visible 283 controls 8...275 widest NSSegmentedControl 259 fits` | same |
| legacy | Adjust, bottom | same | same |
| legacy | Info again | `controls 12...288 … overflow` | `controls 12...271 … fits` |
| legacy | other photo, Info | `controls 12...288 … overflow` | `controls 12...271 … fits` |
| overlay | Info | `visible 300 controls 12...288 widest NSTextField 276 fits` | same |
| overlay | Adjust | `visible 300 controls 8...292 widest NSSegmentedControl 276 fits` | same |

#223's per-control verdicts are unchanged by the fix, legacy: Tone Curve
`width 259.0 needs 244.0 … room 239.0 … compressed`, Color Grading
`width 259.0 needs 256.5 … compressed`, Lens Source `width 173.0 … fits`;
overlay: `width 276.0 … fits` (both), `width 190.0 … fits`. The Info-tab
legacy run was repeated four more times after the fix, each
`controls 12...271 … fits`; before the fix it was `overflow` in all six runs
made.

## Build and test

- `swift build`: clean, no warnings from this change.
- `swift test`: `Test run with 1452 tests in 206 suites passed after 73.546 seconds.`
- CI toolchain: `DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer swift build --build-tests --scratch-path .build-xcode26.3`
  (Swift 6.2.4): `Build complete! (59.84s)`. One warning, not from this change
  (`Tests/PhotoCoreTests/VirtualCopiesTests.swift:170`, a redundant `#require`).

## Changes

- `Sources/PhotoApp/Views/AppKitScrollView.swift`: `FlippedClipView` marks itself
  for layout on the next run-loop turn when its width changes.
- `docs/features/info-tab-legacy-scroller/status.md`: this file.

No rendering, migration, golden, pipeline-version or stack change.
`docs/USER_GUIDE.md` doesn't describe this layout: no change.

## Not verified

- By eye: the Info tab's fields' right edge against a real legacy scroller (the
  script measures frames and cannot draw the panes in the current design; see
  `CLAUDE.md`). Check: Info tab, Show scroll bars: Always, default width: the
  fields end 12 pt before the scroller, as the Adjust tab's controls do.
- Dragging the inspector's edge and toggling scroll bar styles live in a
  running app: the script cannot set the pane's width. The fix runs on every
  width change of the clip view, so these take the same path.
- macOS 15 and 26: covered by CI only.

## Review findings

- **C1** (code review, nit): several deferred marks can queue in one turn when
  `NSScrollView.tile` resizes the clip view more than once; the mark is
  idempotent. Left unfixed by the main session's choice, pending the owner.
- **C2** (code review) and **Q1** (QA), both nits: the Root cause overstated its
  evidence, and said a window resize does not touch the stale width, which QA
  saw it does on the unfixed build. Corrected above: the mechanism is worded as
  a hypothesis and the window-resize claim is replaced by what was observed.
- **Q2** (QA, note): on the unfixed build the overflow depends on AppKit's layout
  timing (the first Info step overflowed in 4 of 4 runs, the "other photo" step
  in one run and not in three later ones). With the fix every run fits (10 of
  10), so the before side is shown by the runs that overflow. Noted, no change.

## README

Nothing for the README.

## Open questions

None.
