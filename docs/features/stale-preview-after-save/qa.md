# Stale preview after save: QA

Owner: qa-tester. Date: 2026-11-06. Step 4 of `docs/WORKFLOW.md`.
Tested: `bug/stale-preview-after-save` at 013dfea (base `develop` 334312c), on
a Mac16,8 (Apple M4 Pro), macOS 27.2 (26B123), SDK 27.2, Swift 6.4.2. Bundle
built by `Scripts/build-app.sh` (`vtool`: minos 15.0, sdk 27.2).

## Verdict

Passes. The bug reproduces on `develop` with the same scripts: all six
edited photos keep the old thumbnail, and an undo to no edits stores the
edited look under the unedited hash. On this branch it does not reproduce in
any run: every cached thumbnail and preview under the current hash is
byte-identical to a fresh render of the catalog's stack. One item stays
open for the owner: confirming the cost of pipeline version 7 for photos on
offline volumes (P1). It is not a defect.

## Safety record

- Owner's folders before testing (11:19, `stat`): `~/Library/Application
  Support/Gus` (Library: `catalog.sqlite` 11681792 B, Nov 4 05:51;
  `-wal` 992952 B, Nov 5 16:52; `-shm` and `library.lock`, Nov 6 10:23; `LUTs/`)
  and `~/Library/Caches/me.sesser.gus` (`Previews/v6`, `com.apple.e5rt…`),
  1212 entries listed with mtime and size.
- After testing: the same listing is identical (`diff` empty), and
  `find … -newer <start marker>` finds 0 entries in either folder.
  `~/Library/Preferences/me.sesser.gus.plist` is unchanged (Nov 5 16:50).
- Every launch used a copy of the bundle with `CFBundleIdentifier`
  `me.sesser.gus.debugtest`, re-signed ad hoc, through a wrapper that always
  passes `--library-root <scratch>/lib…`. The app was never started with
  `open`, `osascript` or without `--library-root`.
- Afterwards no app process was left (`pgrep -xl Gus`: none). The disk image
  was detached. (`pgrep -fl Gus` is useless here: it matches every process
  with `Projects/Gus` in its path.)

## Acceptance criteria

| AC | How | Evidence | Result |
| --- | --- | --- | --- |
| 1. Root cause stated in `status.md`, clear and matching the code | Read against 334312c | `AdjustmentEditor.swift:555` (`persist`) and `:572`/`:574` (hash published synchronously, before the queued write); `PreviewService.swift:114` (loader reads the catalog), `:179` / `:204` (renders the loaded stack, stores it under the request's key), `:223`/`:231`, `:256`/`:265-267`. All the line numbers match. `persist` (`LibraryModel.swift:1190`) chains the write in a `Task`, so the publish ran first. The script runs below confirm the claim that wrong entries can also sit under the identity hash (S6). | Pass |
| 2. Deterministic test fails before the fix, passes after | Test | `StalePreviewTests` (suite "Previews of a stack not saved yet"): 3 tests pass on the branch. Run against `develop`'s `Sources/` in a scratch copy (S1): 3 tests fail with 20 issues, including the old look served under the new hash (lines 76, 121, 154, 167, 168). | Pass |
| 3a. Edit then relaunch: new-hash files differ from the unedited ones and are brighter; grid shows the edit before and after relaunch, on every photo | Script | S2 (develop: 6 of 6 wrong), S3 + S4 (branch: 6 of 6 right, oracle-equal, relaunch grid right) | Pass |
| 3b. Same with the sharpening map shown, then hidden | Script | S5 | Pass |
| 3c. Undo back to no edits, redo, relaunch | Script | S6 (branch) vs S6-dev (develop: the edited look cached under the identity hash on 6 of 6) | Pass |
| 3d. Several quick successive edits; the grid cell never shows "unavailable" | Script | S7 (editor commits), S6 tail (grid paste / undo / redo / undo / redo). Rapid snapshots: the cell is never blank. The app logged no `previews` notice, so no request was ever refused. | Pass |
| 4a. Pipeline bump: an old `v6` folder is removed at launch, previews regenerate under `v7` | Script | S8 | Pass |
| 4b. Offline-volume cost demonstrated and recorded | Script | S9: the person sees blank cells with the offline badge, and the loupe is blank with an "Offline" caption until the volume is reconnected. Owner confirmation: P1. | Open (P1, owner decision) |
| 5. `swift build` and `swift test` green | Test | `swift build`: Build complete. `swift test`: **554 tests in 97 suites passed, 1 known issue** (pre-existing `LiveSessionTests.swift:258` `withKnownIssue`). 8 suites/tests skipped as usual (`LARGE_RENDER_TESTS`, `CAMERA_RAW_SAMPLE` not set). No `warning:` lines in the test log. | Pass |

`status.md` "For QA" items 1 to 4 are covered by 3a, 3c, 3d and 4a.

## Findings

No failures. No missing test for the PhotoCore invariant.

Observations for the engineer (not regressions, not blocking):

- **O1. A cached thumbnail depends on which path rendered it.** For the
  same key, a thumbnail rendered together with the loupe preview
  (`prepare` on `.preview` adds the thumbnail tier) differs slightly from
  one rendered alone for the grid. Raw thumbnails come out 512×341 one way
  and 512×342 the other, with 1.5 to 4% RMSE and mean levels within 0.5 of
  each other. It happens the same way on `develop` and makes no visible
  difference. It means byte-for-byte checks of thumbnails only hold when
  both sides took the same path. In S3 and S5 the raw thumbnails were
  compared by level for that reason.
- **O2. The app-side ordering has no automated test.** `showSaved` in
  `AdjustmentEditor.apply`, batch undo in `registerEditStacksUndo` and the
  `PhotoCell` silence on `staleEditStack` have no test, because there is no
  PhotoApp test target (`Package.swift` has only `PhotoCoreTests`). The
  PhotoCore guard is what keeps a wrong render out of the cache, and the
  test covers that. The ordering is covered here by S3 to S7 only.

## Scripts

Setup (zsh). `$W` is the worktree; `$S` is
`/private/tmp/claude-501/-Users-randy-Projects-Gus--claude-worktrees-dreamy-williamson-06d436/bb8f1316-b5d3-4935-91c4-e00ccd0ef5ef/scratchpad/qa`.

```
swift build -c release --product photobench
Scripts/build-app.sh
cp -R build/Gus.app $S/
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest $S/Gus.app/Contents/Info.plist
codesign --force --deep --sign - $S/Gus.app
.build/release/photobench generate --output $S/src --jpeg 4 --dng 2 --videos 1
.build/release/photobench import --library-root $S/lib --source $S/src
cp -R $S/lib $S/lib-pristine
```

photobench also wrote 100 HEICs (its default), so the library has 107
items. The photos under test are IMG_00001 to IMG_00004 (JPEG) and
RAW_00005/6 (DNG). Each run started from a copy of `lib-pristine` unless
stated. Every launch went through this wrapper, which always passes
`--library-root`:

```
timeout 240 "$app/Contents/MacOS/Gus" --library-root "$lib" --debug-script "$script" > "$log" 2>&1 < /dev/null
```

The cache report (`$S/tools/cachereport.py`) lists
`<lib>/Previews/v7/{thumb,preview}/<xx>/<contentHash>-<hash16>.jpg` for each
photo, using the catalog's current hash, with the ImageMagick mean level
(gray, 0 to 255) and a `cmp` against the identity file. **Oracle:** after the
app quits, the catalog is copied into a fresh root and
`photobench previews --tier thumbnail` then `--tier preview` render every
version from its stored stack, with no race. The app's file for the current
hash must equal the oracle's byte for byte. The unedited hash is
`6c76a50e5dc3f0cd`, and +1.5 EV is `822f9568f0de6aea`.

### S1. Regression test against the unfixed code

`git archive HEAD` into `$S/before`, then `Sources/` replaced by
`git archive develop Sources`. The only change: the `case staleEditStack`
line was added to `PreviewService.Failure` so the branch's test compiles.
The guard was not added. `swift test --filter "StalePreviewTests|PreviewTests"`:
"23 tests in 6 suites failed … with 20 issues". All 3 `StalePreviewTests`
failed (9 + 5 + 6 issues): no error thrown at lines 55, 58, 61, 108, 111,
147, 161; edit keys cached on disk and in memory (64, 65, 67, 114, 164); the
old level served under the new hash (76 ×3, 121 ×2, 154, 167, 168). The
other `PreviewTests` passed on both. On the branch, `swift test --filter
StalePreviewTests`: 3 tests passed.

### S2. Original repro (c2) on develop, every photo

The develop bundle was built in `$S/before` and copied the same way
(`$S/dev/Gus.app`). One launch per photo, on `lib-dev`:

```
windowsize 1600 1000; wait 1; focus <p>; loupe; wait 5; adjust exposure 1.5; wait 8; snapshot $O/c2-<p>-loupe.png; grid; wait 5; snapshot $O/c2-<p>-grid.png; quit
```

v6 thumbnails under the new hash, against the unedited ones:

| Photo | unedited | new hash | |
| --- | --- | --- | --- |
| IMG_00001 | 124.4 | 124.6 | wrong level |
| IMG_00002 | 113.7 | 114.1 | wrong level |
| IMG_00003 | 87.9 | 87.9 | byte-identical |
| IMG_00004 | 123.9 | 123.9 | byte-identical |
| RAW_00005 | 91.1 | 91.1 | byte-identical |
| RAW_00006 | 148.4 | 148.4 | byte-identical |

The bug reproduced on 6 of 6. The grid snapshot shows IMG_00002 and
IMG_00003 unedited.

### S3. c2 on the branch, every photo

Same script and loop with `$S/Gus.app` on `lib`. Exit 0 each time.

| Photo | thumb unedited → new | preview unedited → new | oracle |
| --- | --- | --- | --- |
| IMG_00001 | 124.4 → 192.0 | 124.2 → 191.5 | both equal |
| IMG_00002 | 113.7 → 178.0 | 113.6 → 177.3 | both equal |
| IMG_00003 | 87.9 → 140.1 | 87.1 → 139.3 | both equal |
| IMG_00004 | 123.9 → 190.2 | 123.5 → 189.7 | both equal |
| RAW_00005 | 91.1 → 141.9 | 90.9 → 141.8 | preview equal; thumb 141.9 vs 142.1 (O1) |
| RAW_00006 | 148.4 → 211.6 | 148.3 → 211.3 | preview equal; thumb 211.6 vs 211.6 (O1) |

None is byte-identical to the unedited file. The loupe and grid snapshots
show the edit, and so does the film strip.

### S4. c3 relaunch on the branch, every photo

```
windowsize 1600 1000; wait 1; focus <p>; wait 5; snapshot $O/c3-<p>-grid-relaunch.png; print selection; quit
```

Every grid snapshot shows the edited photos brightened. Nothing in `Previews/`
was rewritten (the `stat` listings before and after the six relaunches are
identical). A side-by-side of develop c2 | branch c2 | branch c3 for
IMG_00003 is in `$S/out/cmp-IMG_00003.png`.

### S5. With the sharpening map shown, then hidden (one launch, `lib-s`)

For each of the six photos:

```
focus <p>; loupe; wait 4; sharpenmap on; wait 2; adjust amount 80; wait 3; adjust exposure 1.0; wait 3; print sharpenmap; snapshot …-map.png; sharpenmap off; wait 2; grid; wait 3; snapshot …-grid.png;
```

followed by `quit`, then a relaunch (`focus IMG_00003; wait 5; snapshot`).
`print sharpenmap` each time: `asked true onScreen true badge 'Sharpening
Map'`, `frame map of applied values`. Final hash `6bb47eeb6da75710` on all
six. Thumbnails went from unedited to edited: 124.4→169.6, 113.7→155.8,
87.9→120.9, 123.9→168.5, 91.1→124.1, 148.4→193.8, all **oracle-equal**.
The relaunch grid shows the edits.

### S6. Undo to no edits, redo; grid paste with undo/redo (`lib-u`)

`lib-u` is a copy of the S3 library (six photos at +1.5 EV). Their unedited
renditions (6 thumbnails and 6 previews) were moved out of the cache to
`$S/ident-ref`, so going back to no edits has to render. This is the case
where develop published the hash before the write. One launch:

```
windowsize 1600 1000; wait 1;
[for each of the six] focus <p>; loupe; wait 4; adjust exposure 0; wait 0.3; undo; wait 0.3; redo; wait 2; grid; wait 3; snapshot …;
focus IMG_00009; loupe; wait 4; adjust exposure 1.5; wait 2; copyadjust; undo; wait 2; grid; wait 3; snapshot …;
focus IMG_00010; pasteadjust; undo; redo; undo; redo; [snapshot b<i>.png; wait 0.1 ×10] wait 3; snapshot bend.png; print undo; quit
```

`print undo`: `undo 'Paste Adjustments'`. Result:
- The six photos and IMG_00009 are back to the identity hash. Their
  unedited thumbnails (124.6, 114.1, 87.9, 123.7, 90.9, 148.4) and previews
  are the original levels and oracle-equal, except O1-sized differences on
  two thumbs. Against the files rendered before any edit, levels are within
  0.5.
- IMG_00010 is at +1.5 EV: thumb 104.0 → 165.1, oracle-equal.
- IMG_00010's cell over the snapshots measured, as mean/sd: b0 to b1
  178.8/15.4 (unedited, writes pending), then b2 to bend 207.0/26.2
  (edited). It was never a flat placeholder.
- A relaunch shows IMG_00002 to RAW_00005 original and IMG_00010 edited.

**S6-dev:** the same six-photo undo/redo part on the develop bundle, with
`lib-dev` (from S2) minus its identity files. Every **identity** thumbnail
came out at the **edited** level: 192.0, 178.0, 140.1, 190.2, 142.1, 211.6
(the originals are 124 to 148). The undo race is real and is fixed.

### S7. Quick successive edits (`lib-q`)

```
windowsize 1600 1000; wait 1; focus IMG_00003; loupe; wait 5; adjust exposure 0.5; adjust exposure 1.0; adjust exposure 1.5; adjust exposure 2.0; grid; [snapshot q<i>.png; wait 0.1 ×25] wait 4; snapshot qend.png;
focus IMG_00004; loupe; wait 4; adjust exposure 0.5; wait 0.05; adjust exposure 1.0; wait 0.05; adjust exposure -1.0; wait 0.05; adjust contrast 30; grid; wait 0.05; snapshot r0.png; wait 0.2; snapshot r1.png; wait 0.5; snapshot r2.png; wait 4; snapshot rend.png; print undo; quit
```

- IMG_00003 ends at ev 2 (catalog). Its thumbnails for each hash are 0.5 →
  103.2, 1.0 → 120.9, 1.5 → 140.1 (the same level as S3's separate render),
  and 2.0 → 160.3 (current, oracle-equal). Each is right for its own stack.
- IMG_00004 ends at ev −1 with contrast 30: thumb 83.8 (current,
  oracle-equal). No file exists for its intermediate hashes.
- Cell measurements, as mean/sd: IMG_00003 goes 170.2 → 202.8 and stays
  there for q02 to qend. IMG_00004 goes r0 170.5 → r1 to rend 167.1. The
  standard deviation is always above 12, so the cell is never blank.
- `log show --predicate 'subsystem == "me.sesser.gus" AND category ==
  "previews"'` over the run: 0 lines. The guard's "not rendered" notice
  never fired, because the publishing order already avoids the race. The
  query does find this subsystem's lines from the test runs. The same query
  over S5 and S6 also gave 0.

### S8. An old v6 folder at launch

`lib-v6` is a copy of `lib-dev` after S2: develop's `Previews/v6`, 43
files, including the wrong entries.

```
windowsize 1600 1000; wait 1; focus IMG_00003; wait 6; snapshot $O/grid.png; quit
```

Afterwards `Previews/` holds only `v7` (20 files). The photos on screen
regenerated with the right edited level: IMG_00002 178.0, IMG_00003 140.1,
IMG_00004 190.2, RAW_00005 142.1, RAW_00006 211.6. IMG_00001 was off screen
and is not rendered yet, as designed.

### S9. Offline volume at the first v7 launch

```
hdiutil create -size 64m -fs APFS -volname QAOFFLINE7 $S/offline.dmg
hdiutil attach -nobrowse $S/offline.dmg
$S/before/.build/release/photobench generate --output /Volumes/QAOFFLINE7/Card --jpeg 3 --heic 0 --dng 0
```

The files were renamed CARD_00001…3, with one local LOCAL_00002 (a distinct
hash). Both were imported into `lib-off` with **develop's** photobench, and
`previews --tier thumbnail|preview` made a v6 cache (8 files).
`hdiutil detach`. Then the branch build:

```
windowsize 1600 1000; wait 1; size 200; wait 4; snapshot …/offline-grid.png; print items; print sidebar; accessibility AXImage; focus CARD_00001; loupe; wait 4; snapshot …/offline-loupe.png; print adjustments; quit
```

- `v6` was deleted. `v7` holds 2 files, both LOCAL_00002's.
- Grid: the three card photos are **empty grey cells with the offline
  (disk) badge** and their names and type badges. The local photo shows its
  thumbnail.
- `accessibility AXImage`: card photos have value `'Offline'`.
- Loupe: a **blank canvas**, an "Offline" caption at the bottom right, and
  blank film-strip cells. `print adjustments`: `state offline`.
- Develop's bundle on an identical copy, also offline, shows the v6
  thumbnails of the card photos with the offline badge
  (`$S/out/offline/offline-grid-dev-crop.png`). That is what the owner
  loses.
- Reattached and relaunched (`accessibility AXImage` values empty): all four
  thumbnails regenerate (5 files in v7). Detached again.

## For a person

There is no `design.md` or `review.md` (bug fix), so no designer M-items.

- **P1 (owner decision, before merge): accept the cost of pipeline version
  7.** At the first launch of this build, every cached thumbnail and preview
  is deleted. Photos whose volume is not mounted then show, until the
  volume is connected again:
  - in the grid, an empty grey cell with the offline badge;
  - in the loupe, a blank canvas captioned "Offline".

  On the previous build those photos showed their cached thumbnails (S9).
  Those cached looks may be wrong: S2 and S6-dev show develop caching the
  wrong look under both the edit's hash and the unedited hash. Once the
  volume is mounted they regenerate on view. To confirm, decide whether
  this is acceptable for a library kept mostly on external drives, and
  record it in `status.md` (code review Q1).
- **P2 (optional, 5 minutes): real use with real files.** In a scratch
  library (a copy of the bundle with its own bundle identifier, launched
  with `--library-root`) with a few real camera raws:
  1. Open one in the loupe, drag the Exposure slider, release, and drag it
     again within a second. Do this three times.
  2. Press Escape back to the grid, quit, and relaunch.

  Look for: the grid thumbnail shows the last value right after returning
  and after relaunch, and it never goes blank. Scripts commit values
  directly, so this is the one path they do not take: a real drag on a key
  window, with interactive frames.

## Follow-up

(Reruns after fixes. No findings to rerun. P1: pending the owner.)
