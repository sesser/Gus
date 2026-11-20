# Tone Curve channel control width: QA

Owner: qa-tester. Date: 2026-11-19. Step 4 of `docs/WORKFLOW.md` (bug fix, #223).
Tested: `bug/tone-curve-channel-control-width` at 9baa63c (the fix is 6a6e6d7;
the two commits after it are the design and code reviews, docs only), on an
Apple M4 Pro, macOS 27.2.1 (26B131), SDK 27.2 (`Scripts/build-app.sh`).

## Verdict

Passes. Every check that a test or the debug script can make passes: at the
narrowest inspector (computed, since no script can set the pane's width) the
Tone Curve and Color Grading controls go from `overflow` to `compressed` with
every label whole, at the default width nothing moved, and every segment still
switches. What only a person can see, the narrowest pane by eye, is open (P1 to
P4).

## Bug (from `status.md` and issue #223, with its corrected numbers)

At the inspector's narrowest pane (280 pt) the Tone Curve channel control
(244 pt of need, not the issue's 276) and Color Grading's range control
(256.5 pt) are wider than the column (239 pt with a legacy scroller, 256 pt with
an overlay one), so SwiftUI widens the whole Adjust column and clips both
edges. Fix: `fillsWidth: true` on both.

## Acceptance criteria

The bug has no PRD; its criteria are the Bug section's expected behavior and
the code review's "test that fails without the fix".

| AC | How | Evidence | Result |
|---|---|---|---|
| B1. Tone Curve's channel control no longer widens the column at the narrowest pane | Script | S2 and S3: develop-minus-flag build `keepsWidth ... overflow` (legacy, need 244 over room 239); branch `fillsWidth ... compressed` | Pass (computed, not seen; P1 sees it) |
| B2. Color Grading's range control the same | Script | S2 and S3: before `overflow` (256.5 over 239); after `compressed`; with overlay scrollers 256.5 over 256 is `fits` in both (0.5 pt tolerance) | Pass (computed; P1) |
| B3. Every label of both controls whole at the narrowest width (239 pt legacy, 256 pt overlay) | Script (drawings) | S2: `segmented-1.png` (RGB/Red/Green/Blue, 59.8 pt a segment, "Green" 36.5 pt of text) and `segmented-3.png` (Shadows/Midtones/Highlights, 79.7 pt, "Highlights" 61.1 pt), looked at, all four and all three whole, no label touching a divider or the capsule edge; same at 256 pt | Pass (drawn off-window; P1, P3 look at the real ones) |
| B4. At the default width nothing changed: every control the same width and place | Script | S3 and S4: `buttons` on branch and on a copy of `origin/develop`: Spots mode, Tone Curve, Black & White Filter, Color Grading 259 pt at the same x and y, Lens Source 173 pt at x 1204 in both; `inspectorwidth`: `10...271` in 283 (legacy), `10...288` in 300 (overlay), widest 259 / 276, identical in the three builds | Pass |
| B5. Every segment still switches: Tone Curve's four channels and Color Grading's three ranges | Script | S5 and S6: a click on each segment (`hits NSSegmentedControl`), then an edit that makes SwiftUI refresh the control, then `buttons`: selected 0, 1, 2, 3, 0 for the channels and 0, 2, 1 for the ranges; identical on the develop copy | Pass |
| B6. Spots Heal / Clone and Lens Source (Auto / Manual) unaffected | Script | S2: `fits`, 239 / 153 pt of room against 118 / 136 pt of need, drawings whole (`segmented-0.png`, `-4.png`); same widths as develop (B4) | Pass |
| B7. Only PhotoApp and the docs change | Diff | `git diff origin/develop --name-only -- Sources Tests Scripts Package.swift`: `Model/DebugScript.swift`, `Views/AdjustControls.swift`, `Views/AdjustView.swift`, `Views/CurveEditor.swift`, `Views/MainView.swift`; the rest are the three files in `docs/features/tone-curve-channel-control-width/`. No PhotoCore, test, script or package change; no migration, no pipeline bump | Pass |
| B8. Nothing existing breaks | Test | Full `swift test`: 1240 tests in 176 suites passed (70.2 s), no issue, the #229 flake did not show. Log kept at `/private/tmp/claude-501/-Users-randy-Projects-Gus/e0e0f80d-a682-4069-aabb-35e62561cf82/scratchpad/qa223/swift-test.log` | Pass |
| B9. A test that fails without the fix | none possible | No test target imports PhotoApp (code review and `status.md` agree; `PhotoCoreTests` depends on PhotoCore and PhotoFixtures), so the regression check is `print inspectorwidth`, run on the tree with and without the flag (S2, S3). That is a check someone must remember to run, not a test (see Q1) | Pass, with Q1 |
| B10. The Adjust column is inside the pane at 280 pt, by eye, with both scroller styles | Person | P1, P2 | Open |

## Findings

None to send back to the engineer. Notes, none blocking:

- **Q1 (note, not a finding).** The narrowest-width verdict is arithmetic from
  the layout at the pane's current width (pane less 280, a legacy scroller
  counted); nothing in the scripts can drag the divider, so the clipping itself
  is never seen, here or by the engineer. The two measurements that stand on
  something other than that arithmetic are the code reviewer's bare AppKit
  controls (a segment is the widest label plus a fixed padding) and the
  before/after verdict flip with one flag removed. P1 and P2 close it.
- **Q2 (the Info tab, already known).** `print inspectorwidth` on the Info tab
  (run on the branch only, S2's script) prints `controls 12...288 ... overflow`
  with a legacy scroller at 300 pt (283 visible) and `fits` with overlay
  scrollers. Not this bug and no segmented control involved; `status.md`
  proposes it as a follow-up, which the issue comment names #236.
- **Q3 (Black & White at 239 pt, the designer's J1).** In `segmented-2.png`
  (drawn with the live selection, none) all five names are whole, but "Orange"
  touches the divider to its left, "Yellow" is within a point of the next, and the
  five segments are visibly unequal in width. Not changed by this branch; M3 is P3.

## Scripts

Setup common to all runs. A fresh scratch library, never the owner's:
`swift run -c release photobench generate --output <scratch>/lib-src --jpeg 4 --dng 2 --heic 1`,
then `photobench import --library-root <scratch>/lib-master --source <scratch>/lib-src`
(7 files); each run on a fresh copy of `lib-master`, always with
`--library-root`. Three copies of the bundle, each with its own identifier
(`plutil -replace CFBundleIdentifier ...`, `codesign --force --deep --sign -`):

- `after`: `Scripts/build-app.sh` on this branch at 9baa63c.
- `before`: `git archive HEAD` in a scratch folder with the two `fillsWidth: true`
  removed from `AdjustView.swift` (the diff of two lines), built there. It has the
  new `inspectorwidth`, so it shows the verdict without the fix.
- `develop`: `git archive origin/develop` in a scratch folder, built there (no
  flag, the old `inspectorwidth`, which prints only the first line below).

Per run, in the copy's own preferences domain
(`me.sesser.gus.debugtest.qa223<name>`, deleted afterwards): headings Tone, Lens,
Black & White, Color Grading and Spots open, the others closed
(`defaults write <domain> adjust.section.<name> -bool true|false`), and the scroller
style, `AppleShowScrollBars` `Always` (legacy) or `WhenScrolling` (overlay).
Launch: `<copy>/Contents/MacOS/Gus --library-root <run folder>/lib --debug-script "<script>"`.

**S1. Orient** (after, legacy): `scroll 0|400|800|bottom` then `buttons` to find
every segmented control and where it is. At scroll 400 the Tone Curve control is
at y 316 and Color Grading's at 987 (579 at scroll 800, after an edit moves it
8 pt up).

**S2. Narrowest width, legacy and overlay scrollers**, with `<folder>` an empty
scratch folder (run for `after` and `before`; `develop` prints only the first line):

```
wait 2; focus RAW_00005; loupe; wait 2; inspector on; wait 1; tab adjust; wait 2; print inspectorwidth <folder>; scroll bottom; wait 1; print inspectorwidth; quit
```

Result, "needs" is the control's intrinsic width, "room" the width it has at
280 pt:

| Control (segments) | Needs | Room legacy | Before | After | Room overlay | Before | After |
|---|---|---|---|---|---|---|---|
| Tone Curve RGB/Red/Green/Blue (4) | 244.0 | 239.0 (59.8 a segment) | **overflow** | compressed | 256.0 (64.0) | fits | fits |
| Color Grading Shadows/Midtones/Highlights (3) | 256.5 | 239.0 (79.7) | **overflow** | compressed | 256.0 (85.3) | fits (0.5 over, tolerance) | fits |
| Spots Heal/Clone (2) | 118.0 | 239.0 | fits | fits | 256.0 | fits | fits |
| Lens Auto/Manual, twice (2) | 136.0 | 153.0 | fits | fits | 170.0 | fits | fits |
| Black & White Yellow/Orange/Red/Green/Blue (5), unchanged | 345.0 | 239.0 | compressed | compressed | 256.0 | compressed | compressed |

The lines the script printed (after, legacy; the `before` build printed
`keepsWidth ... overflow` for the first two and the same for the rest):

```
inspectorwidth pane 300 scroller legacy visible 283 controls 10...271 widest NSSegmentedControl 259 fits
segmented RGB/Red/Green/Blue width 259.0 needs 244.0 x 12.0 fillsWidth narrowest room 239.0 segment 59.8 label 36.5 compressed
segmented Shadows/Midtones/Highlights width 259.0 needs 256.5 x 12.0 fillsWidth narrowest room 239.0 segment 79.7 label 61.1 compressed
```

Drawings, looked at: `segmented-0.png` Heal / Clone, `-1` Tone Curve, `-2` Black &
White, `-3` Color Grading, `-4` and `-5` Lens, at 239 pt, in
`/private/tmp/claude-501/-Users-randy-Projects-Gus/e0e0f80d-a682-4069-aabb-35e62561cf82/scratchpad/qa223/draw/after-legacy/`
(and `after-overlay` at 256 pt; `before-legacy` and `before-overlay` hold the
same drawings, which depend only on the room). All labels of Tone Curve, Color
Grading, Heal / Clone and Auto / Manual whole with air each side. Black & White:
names whole, "Yellow" and "Orange" tight and "Orange" touching the divider at its
left (Q3).

**S3. Default width, controls' places** (after and develop, legacy): the same
script as S5 up to its first `buttons`; the segmented lines of both builds are
identical: `'Spot mode' at 1161,47 width 259`, `'' at 1161,316 width 259`
(Tone Curve), `'Filter' at 1161,748 width 259`, `'' at 1161,987 width 259` (Color
Grading), `'Distortion source' at 1204,1426 width 173`.

**S4.** `inspectorwidth` at 300 pt, develop, legacy then overlay:
`visible 283 controls 10...271 widest NSSegmentedControl 259 fits` and
`visible 300 controls 10...288 widest NSSegmentedControl 276 fits`; the branch's
first lines are the same.

**S5. Tone Curve channels** (run on `after` and on `develop`, legacy; every
click is a mouse down and up through the event queue, `hits NSSegmentedControl`;
the adjust after each click makes SwiftUI refresh the control, so a selection
AppKit kept for itself would revert):

```
wait 2; focus RAW_00005; loupe; wait 2; inspector on; wait 1; tab adjust; wait 2; scroll 400; wait 1; print SEGSTART; buttons; click 1064 316; wait 1; adjust curve red 0,0 0.5,0.6 1,1; wait 1; print TONE-click-RGB; buttons; click 1129 316; wait 1; adjust curve green 0,0 0.5,0.6 1,1; wait 1; print TONE-click-Red; buttons; click 1193 316; wait 1; adjust curve blue 0,0 0.5,0.6 1,1; wait 1; print TONE-click-Green; buttons; click 1258 316; wait 1; adjust curve rgb 0,0 0.5,0.55 1,1; wait 1; print TONE-click-Blue; buttons; click 1064 316; wait 1; adjust curve rgb 0,0 0.5,0.5 1,1; wait 1; print TONE-click-RGB-again; buttons; quit
```

After the first edit the control moves to y 308, the clicks still hit it (a
segment is 65 pt wide). Selected segment after each click, `after`: RGB 0, Red 1,
Green 2, Blue 3, RGB 0; `develop` the same. (The same file's first run also
clicked Color Grading at a position that had moved off the window: `hits` nothing,
which is why S6 exists.)

**S6. Color Grading ranges** (`after` and `develop`, legacy):

```
wait 2; focus RAW_00005; loupe; wait 2; inspector on; wait 1; tab adjust; wait 2; scroll 800; wait 1; adjust grade midtones 0.1 0.2; wait 1; print GRADE-start; buttons; click 1075 579; wait 1; adjust grade shadows 0.1 0.2; wait 1; print GRADE-click-Shadows; buttons; click 1247 579; wait 1; adjust grade highlights 0.1 0.2; wait 1; print GRADE-click-Highlights; buttons; click 1161 579; wait 1; adjust grade midtones 0.2 0.3; wait 1; print GRADE-click-Midtones; buttons; quit
```

Selected: start Midtones 1; after the clicks Shadows 0, Highlights 2, Midtones 1;
the same on `develop`. (The state is a `@State` of the view, so what the control
says is read back from SwiftUI; there is no script that prints the curve's
channel or the wheel's range itself. The curve and the wheel changing is for P1.)

**Safety.** Every launch carried `--library-root` on a folder under the
scratchpad's `qa223`; `photocli` was not used. Before and after the runs, a read-only
listing of every file under `~/Library/Application Support/Gus` (418 files; no
`~/Library/Caches/Gus` exists) by modification time and size was identical
(`diff` empty) and nothing there is newer than my start (16:29). My copies'
preference domains were removed. No instance of mine was left running (the
`qa221` copy that `ps` shows belongs to another session's run on its own scratch
library).

## For a person

No VoiceOver, macOS 15 or macOS 26 items (owner's ruling). Build the bundle and
run it on a scratch library: `Scripts/build-app.sh` and the bundle's executable
with `--library-root <folder from photobench>`. The inspector's narrowest width
is 280 pt: drag its left edge until it stops. Open a photo in the loupe, the
inspector on its Adjust tab, with the Tone, Color Grading, Black & White, Lens and
Spots headings open. Covers the designer's M1 to M5 (`review.md`) and
`status.md`'s P1.

- **P1 (M1). Narrowest pane, legacy scroller** (a mouse attached, or System
  Settings ▸ Appearance ▸ Show scroll bars: Always). The whole column is inside the
  pane: the first letters of the slider labels, the value fields, the headings'
  check boxes and reset arrows are not clipped on either side, and the column
  does not shift sideways as you scroll to Tone Curve and to Color Grading.
  RGB / Red / Green / Blue and Shadows / Midtones / Highlights read in full, with
  visible air on each side of the name in the selected segment. Click every
  segment of both and see the curve's channel and the wheel's range change.
- **P2 (M2). Narrowest pane, overlay scroller** (Show scroll bars: When
  scrolling, or no mouse). The same with 17 pt more room: nothing clipped, labels
  roomier. Then the default 300 pt pane and a wide one (about 420 pt): the
  segmented controls fill the column and line up with the sliders' edges as
  before, nothing else has moved. (The default-width half is already shown by S3
  and S4; the eye adds the wide pane.)
- **P3 (M3). Black & White beside them, at the narrowest pane with a legacy
  scroller.** All five names whole. Look at "Yellow" and "Orange" selected: tight
  but readable? Are the five segments visibly equal in width? (`segmented-2.png`
  shows "Orange" touching the divider on its left and unequal widths, Q3.) A
  clash is a Design question (design review J1), not a fail of this branch.
- **P4 (M4, M5). Light, Dark, Increase Contrast, and Spots and Lens.** In System
  Settings ▸ Appearance (the library window is dark only; check what shows) and
  Accessibility ▸ Display ▸ Increase contrast, at the narrowest pane: selected and
  unselected segments of the three controls are distinct, labels readable, divider
  lines visible. Heal / Clone and Lens Source's Auto / Manual look and behave as
  before at the narrowest and default panes.

## Follow-up

Reruns after fixes and the owner's sign-off are recorded here.

**Owner's sign-off, 2026-11-19.** Commit signed off: `a025dcb6c8faef16bc44d6b31bd8b52be71aaa6b`
(`bug/tone-curve-channel-control-width`). The owner built the bundle, ran it on a
scratch library and checked P1 to P4 by eye (narrowest pane with the legacy and the
overlay scroller, Black & White beside them, appearance and Increase Contrast with
Spots and Lens): all pass. No checks are left open. As ruled, VoiceOver, macOS 15
and macOS 26 were not asked of the owner and are covered by CI only.

| P | Covers | Result |
| --- | --- | --- |
| P1 | M1 | Pass (owner, by eye) |
| P2 | M2 | Pass (owner, by eye) |
| P3 | M3 | Pass (owner, by eye) |
| P4 | M4, M5 | Pass (owner, by eye) |

Findings: none were open at sign-off beyond what the Findings section already
records. This entry was written by qa-tester; the main session commits it.
