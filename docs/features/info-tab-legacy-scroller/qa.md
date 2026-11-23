# Info tab fields run under a legacy scroller: QA

Owner: qa-tester. Date: 2026-11-22. Step 4 of `docs/WORKFLOW.md`.
Tested: `bug/info-tab-legacy-scroller` at 395bdbe (the fix is 9825316), on an Apple M4 Pro, macOS 27.2.1 (26B131), macOS SDK 27.2 (`Scripts/build-app.sh`). Issue #236, Complexity: routine. A bug fix: no PRD; the criteria are `status.md`'s **Bug** section and the issue.

## Verdict
Passes, and the owner signed off on 2026-11-22 (commit 06f3477, no checks left open; see Follow-up). With a legacy scroller the Info tab's controls now stay inside the visible width (`controls 12...271 … fits`; before the fix `12...288 … overflow`, reproduced here on `develop`), nothing changed with overlay scrollers, in the Adjust tab or in #223's per-control verdicts, and the full `swift test` passes. The regression check is the debug script only (PhotoApp has no test target); the one check for a person, the look beside a real legacy scroller (P1), was done by the owner and is closed by the sign-off.

## Acceptance criteria
The Bug section and the issue give four things to check.

| AC | How | Evidence | Result |
| --- | --- | --- | --- |
| B1. The bug shows on `develop`: legacy scroller, Info tab at the default 300 pt pane, `print inspectorwidth` says `overflow` (fields 276 wide, `controls 12...288` in a visible 283) | Script | S1 on the `develop` copy, 3 of 3 plus 1 earlier run | Pass (reproduced) |
| B2. After the fix the Info tab's column follows the visible width, `controls 12...271 … fits` (fields 259 wide, 12 pt padding each side, as the Adjust tab's 8...275) | Script | S1, 6 of 6 runs; S3, 4 of 4 runs | Pass |
| B3. Overlay scrollers, the Adjust tab (in the loupe and, outside it, in the grid) and #223's segmented-control verdicts do not change | Script | S1 and S4 before and after, `diff` of the outputs: only the Info lines differ (legacy); overlay output identical | Pass |
| B4. The test that fails without the fix | Script (no test can reach it) | `status.md` names `print inspectorwidth` as the check: `overflow` before, `fits` after, both shown here (S1, S3). PhotoApp has no test target, so nothing guards it automatically (the code reviewer says the same). | Pass, manual only |
| B5. Nothing else broke: `swift test` | Test | `swift test`: `Test run with 1452 tests in 206 suites passed after 79.885 seconds` | Pass |
| B6. The fields' right edge beside a real legacy scroller looks right | Person | P1 (the script measures frames and cannot draw the panes in the current design) | Pass (owner, 2026-11-22: built the bundle with P1's commands, ran it on `/tmp/qa236lib`, replied "Signed off"; no item-by-item description) |

## Findings
No failures. Two observations for the engineer, neither blocks.

- **Q1 (nit, `status.md`).** The Root cause says "a window resize does not touch it either" (it leaves the document at 300 pt). On the unfixed build here it does: in S3b the Info tab overflowed after the keywords arrived, and a following `windowsize` made the same run report `controls 12...271 … fits`. So a window resize re-solves the document's width; only the clip view's own resize inside the scroll view's layout does not. The fix is unaffected; the account of the cause is stronger than its evidence (the reviewer's C2 says as much). The sentence can be corrected or dropped.
- **Q2 (note).** On the unfixed build the "another photo, Info" step overflowed in the first run and did not in three later runs (`fits`), and the first Info step overflowed in 4 of 4. The bug depends on timing in AppKit's layout; with the fix every run fits (S1 and S3, 10 of 10 runs), so the fix is not the kind of check that needs a flake count; the before side is shown by the runs that overflow.

## Scripts
Every run: a copy of the `Scripts/build-app.sh` bundle with its own bundle identifier (`me.sesser.gus.debugtest.qa236after`, and `…qa236before` built from `develop` at a2a5973 in a scratch worktree), re-signed ad hoc, a `photobench generate --jpeg 4 --dng 2 --heic 1` library imported with `photobench import` and copied fresh for each run, every launch with `--library-root <scratch copy>`. The scroller style was forced per run with `defaults write <that identifier> AppleShowScrollBars Always|WhenScrolling` (the copy's own domain; deleted after each run). Launched as `<copy>/Contents/MacOS/Gus --library-root <lib> --debug-script "<script>"` (a process from a shell has no key window; none of these checks needs one). `Always` is the legacy scroller, `WhenScrolling` the overlay one. Default pane 300 pt in all runs. Only the first line of each `inspectorwidth` result is quoted; the per-control `segmented` lines follow the Adjust ones.

### S1. Info, Adjust, Adjust at the bottom, Info again, another photo (the engineer's, with RAW_00006 for the last)
```
wait 2; focus RAW_00005; loupe; wait 2; inspector on; wait 1; tab info; wait 2; print inspectorwidth; tab adjust; wait 2; print inspectorwidth; scroll bottom; wait 1; print inspectorwidth; tab info; wait 2; print inspectorwidth; focus RAW_00006; wait 2; print inspectorwidth; quit
```
| Scroller | Step | `develop` | Fix |
|---|---|---|---|
| legacy | Info | `visible 283 controls 12...288 widest NSTextField 276 overflow` | `visible 283 controls 12...271 widest NSTextField 259 fits` |
| legacy | Adjust | `visible 283 controls 8...275 widest NSSegmentedControl 259 fits` | same |
| legacy | Adjust, bottom | same | same |
| legacy | Info again | `controls 12...288 … overflow` | `controls 12...271 … fits` |
| legacy | other photo, Info | `controls 12...288 … overflow` (first run); `12...271 … fits` (three later runs) | `controls 12...271 … fits` |
| overlay | Info | `visible 300 controls 12...288 widest NSTextField 276 fits` | same |
| overlay | Adjust | `visible 300 controls 8...292 widest NSSegmentedControl 276 fits` | same |

Runs: `develop` legacy 4 (Info overflow in 4 of 4), fix legacy 6 (fits in 6 of 6), each overlay once (identical, `diff` empty). #223's verdicts, unchanged by the fix: legacy Tone Curve `width 259.0 needs 244.0 … narrowest room 239.0 … compressed`, Color Grading `width 259.0 needs 256.5 … compressed`, Lens Source `width 173.0 … fits`; overlay `width 276.0 … fits` (both), `width 190.0 … fits`. In legacy the `diff` of the `develop` and fix outputs is the Info lines only (the first, and the Info-again and other-photo lines when those overflowed).

### S2. The window's height sweep over the scroller's threshold, Info tab (content not changing, the scroller coming and going)
```
wait 2; focus RAW_00005; loupe; wait 2; inspector on; wait 1; tab info; wait 2; windowsize 1400 1200; wait 1; print inspectorwidth; windowsize 1400 900; wait 1; print inspectorwidth; windowsize 1400 800; wait 1; print inspectorwidth; windowsize 1400 700; … 600; … 500; … 400; windowsize 1400 500; … 600; … 700; … 800; … 900; … 1200 (each followed by wait 1; print inspectorwidth); quit
```
(the full text is the same pattern: heights 1200, 900, 800, 700, 600, 500, 400, 500, 600, 700, 800, 900, 1200.) Fix, legacy: 1200 and 900 `visible 300 controls 12...288 … 276 fits` (no scroller needed), 800 down to 400 and back up to 800 `visible 283 controls 12...271 … 259 fits`, then 900 and 1200 `visible 300 controls 12...288 … fits`. The scroller appeared and went away with the column following each time, no hang (exit 0). The unfixed build gave the same rows, so this sweep does not discriminate (a window resize re-solves the layout, see Q1); it shows the fix does not break the scroller going away.

### S3. Content arriving after the first layout (the bug's own mechanism), Info tab, scroller appearing because content grows
```
wait 2; focus RAW_00005; loupe; wait 2; windowsize 1400 900; inspector on; wait 1; tab info; wait 2; print inspectorwidth; addkeywords alpha-one-long-keyword, bravo-two-long-keyword, charlie-three-long-keyword, delta-four-long-keyword, echo-five-long-keyword, foxtrot-six-long-keyword, golf-seven-long-keyword, hotel-eight-long-keyword; wait 2; print inspectorwidth; quit
```
`develop`, legacy: first print `visible 300 controls 12...288 … 276 fits` (no scroller), after the keywords `visible 283 controls 12...288 … 276 overflow`: the scroller appeared and the document did not follow. Fix, legacy: `visible 283 controls 12...271 … 259 fits` on both prints (in the fix runs the window height at that moment already gave a scroller before the keywords; run 3 more times, after: `fits`, no overflow in 4 of 4). A second variant (window 1400 1100, 12 keywords, then 1800, then 700) gave `fits` throughout on the fix and `overflow` on the first print only on `develop` (the display clamps the height, so a scroller was already there): the first rows of that run are in the same direction as S1.

### S4. The grid: Adjust tab outside the loupe, Info tab with one photo, with all selected, a JPEG, a HEIC, then the loupe and back
```
wait 2; inspector on; wait 1; focus IMG_00001; tab adjust; wait 2; print inspectorwidth; tab info; wait 2; print inspectorwidth; selectall; wait 2; print inspectorwidth; tab adjust; wait 2; print inspectorwidth; deselectall; wait 2; print inspectorwidth; tab info; wait 2; print inspectorwidth; focus IMG_00007; wait 2; print inspectorwidth; loupe; wait 2; print inspectorwidth; tab adjust; wait 2; print inspectorwidth; grid; wait 2; print inspectorwidth; quit
```
Legacy, `develop`: the grid's Adjust tab `visible 300 controls 13...200 widest Button 100 fits` (no scroller there); Info rows `visible 283 controls 12...288 … 276 overflow` for the first Info visit, with all selected `12...271 … fits` (it fits when it lays out again), `overflow` again for the JPEG/HEIC visits. Fix, legacy: every Info row `controls 12...271 … 259 fits`, the grid's Adjust rows unchanged, the loupe's Adjust `controls 8...275 … fits`. Overlay: identical before and after (`visible 300`, Info `12...288 … 276 fits`, loupe Adjust `8...292 … 276 fits`).

### S5. The Adjust tab through the height sweep, loupe, legacy
```
wait 2; focus RAW_00005; loupe; wait 2; inspector on; wait 1; tab adjust; wait 2; <windowsize 1400 H; wait 1; print inspectorwidth> for H in 1200 900 800 700 600 500 400 500 700 800 900 1200; quit
```
Fix and `develop`: all 12 rows `visible 283 controls 8...275 widest NSSegmentedControl 259 fits` (the Adjust tab is always taller than the pane, so its scroller never goes). Identical before and after.

### S6. A photo with little metadata and the Keywords heading folded, Info tab, the scroller coming and going
```
wait 2; focus IMG_00001; loupe; wait 2; inspector on; wait 1; tab info; wait 2; <windowsize 1400 H; wait 1; print inspectorwidth> for H in 1200 900 800 700 600 500 400 500 700 800 900 1200; quit
```
With `info.section.keywords` = false in the copy's own defaults domain. Fix and `develop` alike: 1200, 900, 800 `visible 300 controls 12...288 … 276 fits`; 700 down to 400 and back to 700 `visible 283 controls 12...271 … 259 fits`; 800, 900, 1200 `visible 300 … fits`. The scroller appeared and went at the threshold with no flip-flop (the reviewer's loop concern: none seen, every run exited 0).

### S7. All three Info headings folded, and the grid's Adjust tab through the sweep, legacy
```
wait 2; inspector on; wait 1; focus IMG_00001; tab info; wait 2; <windowsize 1400 H; wait 1; print inspectorwidth> for H in 900 700 500 400 300 500 700 900; quit
```
(and the same with `tab adjust` for the grid), with `info.section.keywords`, `.metadata` and `.contact` = false for the first. Fix and `develop`: no scroller at any height (`visible 300 controls 13...102 … 74 fits` for the folded Info tab, `13...200 … 100 fits` for the grid's Adjust tab): the content is shorter than the smallest window, so these show no change, not a test of the fix.

### S8. Housekeeping
`swift test`: `Test run with 1452 tests in 206 suites passed after 79.885 seconds`. After the runs: no `Gus` process running (`pgrep -x Gus` finds none); the owner's library folder (`~/Library/Application Support/Gus/Library`) has no file newer than the run's start (newest: `catalog.sqlite-wal`, Nov 20); the copies' defaults domains were deleted; the scratch worktree of `develop` was removed; the checkout is clean (`git status` empty).

## For a person
Only one thing, and the owner needs no VoiceOver, macOS 15 or macOS 26 check (CI only). Status: P1 done by the owner on 2026-11-22 (see Follow-up); nothing is left open.

- **P1 (done 2026-11-22; the look beside a real legacy scroller; covers B6; no M-number, there was no design review).** Build the bundle and run it on a scratch library, never the real one:
  ```
  swift run -c release photobench generate --output /tmp/qa236src --jpeg 4 --dng 2 --heic 1
  swift run -c release photobench import --library-root /tmp/qa236lib --source /tmp/qa236src
  Scripts/build-app.sh
  build/Gus.app/Contents/MacOS/Gus --library-root /tmp/qa236lib
  ```
  Turn on System Settings ▸ Appearance ▸ Show scroll bars: Always (or attach a mouse). Open a photo with Return (the loupe), show the inspector (View menu) at its default width, choose the Info tab. Look for: the Keywords entry and the Metadata fields end a clear gap (about 12 pt) before the vertical scroller, as the Adjust tab's controls do; nothing is cut off or runs under the scroller. Then drag the inspector's left edge wider and narrower (the script cannot) and fold and unfold the Keywords and Metadata headings so the scroller comes and goes: the fields should follow the visible width each time, with no jump or flicker at the end of the animation. Set Show scroll bars back to what it was.

## Follow-up
Not rerun after any change to source or tests: the source last changed at 9825316, and 06f3477 only corrects `status.md`'s root cause for the code review's C2 and my Q1 (docs only, after my pass). Q1 is therefore addressed by that commit; Q2 was a note and needed no fix.

### Owner's sign-off
- **Signed off: 2026-11-22**, commit **06f3477** (source last changed at 9825316).
- How: the owner built the bundle with the commands in P1, ran it on the scratch library `/tmp/qa236lib`, and replied "Signed off". The choice offered was signing off, or signing off with P1 left open. The owner did not describe what they saw item by item, so B6 and P1 are recorded as done on the strength of the sign-off alone.
- Checks left open: none.
- Code review's C1 (nit) is left unfixed.
- `develop` had no new commits to merge into the branch.
