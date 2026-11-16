# Dehaze and local tone at the frame's edge: QA

Owner: qa-tester. Date: 2026-11-15. Step 4 of `docs/WORKFLOW.md`.
Tested: `bug/pre-hdr-merge-fixes` at 072518d (the fix is 476d6a9; the branch also carries #65's
23c71f4 and 072518d, QA'd in `docs/features/full-render-main-thread-stall/qa.md`), on a
MacBook Pro (Mac16,8, Apple M4 Pro), macOS 27.2.1 (26B131), macOS 27.2 SDK (the bundle records
`sdk 27.2`, `minos 15.0`). The "before" is `develop` at 1ef945a, built in a scratch clone outside
the checkout.

Issue: #73. A bug fix: the criteria are the **Bug** section of `status.md`, the issue (whose title,
"Dehaze above white", does not describe the cause; `status.md` suggests "Dehaze and local tone at
the frame's edge") and the owner's ruling of 2026-11-15 recorded there.

## Verdict

Passes. The edge darkening and the Dehaze jump reproduce on `develop` and are gone on the branch, in
the app's live path as well as in renders; edits without Dehaze above 0, Shadows or negative
Highlights are byte for byte as before (22 of 22); the goldens passed unchanged in three full
`swift test` runs (1040 tests each, no flakiness). Nothing found for the engineer; one observation
(O1) about a raw's own outermost two pixels, which the fix did not cause.

## Acceptance criteria

| AC | How | Evidence | Result |
|---|---|---|---|
| B1: the haze estimate does not depend on how Core Image evaluates its input (0.094 before, 0 after) | Test | `EstimateEdgeTests.hazeEstimateIsEvaluationIndependent`, four cases. Run on the scratch copy of `develop` with this test file added: the two Shadows 40 cases fail (`difference <= 0x1p-9`); on the branch all four pass | Pass |
| B2: Shadows at 1 never darkens a pixel, the edge included (0.909 of its input at the corner before) | Test | `EstimateEdgeTests.shadowsNeverDarkensTheEdge`; fails on `develop`, passes on the branch. Script 1 shows the same on a real photo | Pass |
| B3: the masks' estimate and global local tone measure alike | Test | `EstimateEdgeTests.maskEstimateIsTheGlobalOne`; fails on `develop`, passes on the branch | Pass |
| B4: values above white do not disturb the haze estimate | Test | `EstimateEdgeTests.hazeEstimateScalesWithExposure` (passes on both, as `status.md` says: a guard, not a regression test) | Pass |
| B5: live session, cached stages against a whole frame, with local dehaze and global Highlights -20 (`aboveWhite`, known issue before) | Test | `LiveSessionTests.aboveWhite(withEstimates: true)`: no known-issue marker on the case any more, and it passed in all three full runs. I did not rerun it on `develop` (the engineer recorded its known issue at the baseline) | Pass |
| B6: preview cache version 10 to 11, a plain bump | Test | `EstimateEdgeTests.pipelineVersionBumped`; fails on `develop`, passes on the branch. `LocalSharpenGroupOffTests` now expects at least 10 | Pass |
| B7: no golden changed | Test | `git diff 1ef945a..HEAD --stat` touches nothing under `Tests/PhotoCoreTests/Goldens`; `GoldenTests` passed in three full runs. `UPDATE_GOLDENS` not run | Pass |
| B8: the edge jump and darkening are gone in a render (Dehaze 60, Shadows 40, 1200 px) | Script | Script 1 (`photocli render`, `develop` against the branch, a JPEG and a synthetic DNG) | Pass |
| B9: the same in the app: moving Shadows from 0 to 1 with Dehaze 60 no longer changes the frame's outer pixels | Script | Script 2 (the bundle's debug script and snapshots, `develop` against the branch) | Pass |
| B10: byte for byte for edits with no Dehaze above 0, Shadows or negative Highlights (owner's ruling) | Script | Script 3: 22 of 22 renders identical (11 edit sets, JPEG and DNG), and a mask with exposure, contrast and clarity | Pass |
| B11: renders that change are the ones the ruling allows (Dehaze above 0, Shadows, negative Highlights) | Script | Script 1 and 3: Dehaze 60 alone differs by at most 0.0046 (about 1 level of 8 bits); Shadows and Highlights differ at the border (up to 0.12 before-to-after) | Pass |
| B12: the owner will see no difference to look at on a real photo | Person | P1 | Open |

## Findings

None for the engineer: no failure and no missing test.

Observations (not failures):

- **O1: a system-decoded raw's outermost two pixels still differ by a few percent from Shadows 0 to
  1.** On the synthetic DNG at 640 to 2560 px, Shadows 1 against no edit gives an output/input
  ratio of 0.960 to 1.034 in the outermost row and 0.989 to 1.016 in the next, against 1.000 to
  1.02 from the third row in (and 1.0000 to 1.0081 everywhere on the JPEG). The unedited render's
  own border is partly transparent there (alpha 0.9948 at (1,1) in the 1600 px render, pixel
  (0,0) already darker than its neighbours), and any local-tone step makes it opaque
  (`settingAlphaOne`). So this is the raw decode's border, which the estimates cannot reach, not
  the estimate. It is two pixels wide at every size and unchanged by the fix (before, it hid under
  a 15% darkening 8 pixels deep). Dehaze alone and Dehaze with Shadows show no such step on the
  DNG (outer 40 px worst 0.0028, inside 0.0035). Worth a line in the PM's follow-ups if the owner
  cares; no action for this fix.
- The engineer's two follow-ups (Vignette's float output varying from run to run, and local tone's
  alpha 0.9996 across large frames) are not part of this fix and I did not test them. Renders of
  the same edit repeated on the same build were byte identical here (the unedited JPEG and DNG).

## Scripts

All run from `/private/tmp/claude-501/-Users-randy--claude-spares-spare-BGdTA8/e0e0f80d-a682-4069-aabb-35e62561cf82/scratchpad/qa`
(call it `$Q`). The branch's `photocli` is `/Users/randy/Projects/Gus/.build/release/photocli` (rebuilt
at 072518d); the before's is `$Q/dev73/.build/release/photocli` (clone of the checkout at 1ef945a,
`Scripts/build-app.sh` and `swift build -c release --product photocli`). The scratch library is
`$Q/lib` (made with `photobench generate --dng 4 --dng-size 6000x4000 --jpeg 2 --jpeg-size 3000x2000`,
the HEICs removed, then `photobench import --library-root $Q/lib --source $Q/photos`). The compare
tools are `$Q/tools/imgcmp.swift` (16-bit PNGs: worst difference, share changed, output/input ratio
by distance from the edge) and `$Q/tools/snapdiff.swift` (the snapshots).

### Script 1: the edge on `develop` and on the branch (`$Q/tools/run73.zsh`, output `$Q/r73.out`)

For each of `IMG_00001.JPG` (3000 x 2000) and `RAW_00003.DNG`, and each binary:
`photocli render <file> --long-edge 1200 --set <module.param=value>... --out <png>` for no edit,
`tone.shadows=1`, `presence.dehaze=60`, `presence.dehaze=60 tone.shadows=1`,
`tone.shadows=40 presence.dehaze=60`, `tone.highlights=-20`; then `imgcmp` between renders.

| Measurement | Before (`develop`) | After (branch) |
|---|---|---|
| JPEG, Dehaze 60, Shadows 0 to 1: worst change, outer 40 px / inside | 0.223 / 0.035 | 0.00145 / 0.00145 |
| JPEG, Shadows 1 against no edit: lowest output/input | 0.846 (at the bottom edge) | 0.9995 (inside, in the rounding) |
| JPEG, Highlights -20: lowest output/input, outer 24 px | 0.813 | 0.933 (a real darkening by the slider) |
| DNG, Dehaze 60, Shadows 0 to 1: outer 40 px / inside | 0.175 / 0.027 | 0.0028 / 0.0035 |
| DNG, Shadows 1 against no edit, third row in and deeper | 0.848 at the edge, 0.90 to 0.99 within 8 px | 0.9935 to 1.0176 (the darker values are dark-pixel noise; see O1 for rows 0 and 1) |
| Unedited, repeated: same file hash | yes | yes |

### Script 2: the live path in the bundle (`$Q/tools/s73.txt`, `SNAP` replaced by a folder)

The `develop` bundle and the branch bundle, each copied to `$Q/app/<name>.app` with the identifier
`me.sesser.gus.debugqa` and `NSAppSleepDisabled`, signed ad hoc, launched with
`--library-root $Q/lib` every time:

```
wait 2; inspector off; loupe; wait 1; focus RAW_00003; windowsize 1400 1000; wait 2; adjust reset all; wait 1; adjust dehaze 60; wait 2; snapshot SNAP/a0.png; adjust shadows 1; wait 2; snapshot SNAP/a1.png; adjust shadows 40; wait 2; snapshot SNAP/a2.png; adjust reset all; wait 1; adjust shadows 1; wait 2; snapshot SNAP/b1.png; adjust reset all; wait 2; snapshot SNAP/b0.png; print selection; quit
```

I looked at a snapshot: the photo (a synthetic raw) fills the loupe, the glass panes are blank as
`CLAUDE.md` says. `snapdiff a0 a1` (Dehaze 60, Shadows 0 to 1) finds the photo's region by its
changes and counts pixels in its outer 20 px band that changed by more than 2 of 255 levels:

| | `develop` bundle | Branch bundle |
|---|---|---|
| Dehaze 60, Shadows 0 to 1: worst change in the outer 20 px band; pixels over 2 levels | 47 levels; 76,458 px | 7 levels; 181 px |
| Shadows 0 to 1 alone: outer band worst; pixels over 2 levels | 29 levels; 59,930 px | 7 levels; 2,702 px (116 of them 3 px or more in from the edge; the rest are the raw's border, O1) |

### Script 3: byte for byte (`$Q/tools/bytes73.zsh`, output `$Q/bytes73.out`)

`photocli render <file> --long-edge 1200 --set ...` with each binary, then `cmp` of the two PNGs, for
the JPEG and the DNG and these edits: `exposure.ev=0.6`; `tone.contrast=25`; `tone.highlights=40`;
`tone.whites=20 tone.blacks=-15`; `presence.clarity=35 presence.vibrance=20 presence.saturation=-10`;
`presence.dehaze=-40`; `sharpen.amount=60 sharpen.radius=1.2 sharpen.masking=30`;
`colorMixer.redHue=20 colorGrade.shadowsHue=210 colorGrade.shadowsAmount=20`;
`noiseReduction.luminance=30 grain.strength=20`; `crop.angle=3 crop.quarterTurns=1`; and all the
global edits together without Shadows, negative Highlights or Dehaze above 0. Result: **22 of 22
IDENTICAL**. Each differs from the unedited render, so none was a no-op. Masks, on the scratch
library: `photocli mask add --library-root $Q/lib --version 1 --shape radial --params
'{"centerX":0.5,"centerY":0.5,"radiusX":0.4,"radiusY":0.3}' --set exposure=0.4 --set contrast=20
--set clarity=30`, then `photocli render --version 1 --library-root $Q/lib --long-edge 1200` with each
binary: identical. The same mask with `--set shadows=50 --set dehaze=40` on version 2 differs (0.020
at worst, inside the frame), as the ruling allows: the mask's Dehaze goes through the haze estimate.
(The masks are still on versions 1 and 2 of the scratch library.)

### Tests on a copy of `develop`

`$Q/dev73` (a clone at 1ef945a, outside the checkout) with
`Tests/PhotoCoreTests/EstimateEdgeTests.swift` copied in: `swift test --filter EstimateEdgeTests` gave
5 issues in 4 tests, all four failing as listed under B1 to B3 and B6 (log
`$Q/dev73-estimatetests.log`). On the branch: `swift test` run three times (`$Q/test-1.log` to
`test-3.log`): 1040 tests in 155 suites passed after 69.4, 69.7 and 67.6 s, no known issues, no
failed expectation. (The first run overlapped a release build of `photobench`.) `Scripts/build-app.sh all`
succeeded (`$Q/build-all.log`); the bundle records SDK 27.2.

## For a person

- **P1 (optional, a minute).** In a bundle on a scratch library, open a real raw at fit, set Dehaze
  to 60 and drag Shadows slowly from 0 to 40 and back, then the same with Highlights toward -40.
  Look at the photo's border: no dark or bright rim that appears or jumps while the slider moves
  (only the content's own changes). Needs eyes because the scripted measurements are on synthetic
  images and on two-pixel and 20-pixel bands. No M-number: a bug fix has no design review.

Nothing for VoiceOver, macOS 15 or macOS 26 (the owner does not test them).

## Follow-up

Reruns after fixes and the owner's sign-off are recorded here.

Run safety: no instance of the app or `photocli` was left running. The owner's library folder
had **one file newer than my start**: `catalog.sqlite-shm` (18:55). `catalog.sqlite` and
`catalog.sqlite-wal` kept their times (07:09) and sizes, so nothing was written to the catalog;
the cause is my `photocli render <file> --out ...` runs (Scripts 1 and 3), which I started without
`--library-root`: with no library named, `render` opens the standard library read-only to refuse
an output that is a master, and that touches the shared-memory index. The app was only ever
launched with `--library-root`.
