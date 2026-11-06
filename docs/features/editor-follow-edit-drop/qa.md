# Editor follow edit drop and reload stale hash: QA

Owner: qa-tester. Date: 2026-11-06. Step 4 of `docs/WORKFLOW.md`.
Tested: `bug/editor-follow-edit-drop` at 975cf49 (base `develop` 14dc0c1), on
a Mac16,8, macOS 27.2 (26B123), SDK 27.2, Swift 6.4.2. Bundle built by
`Scripts/build-app.sh` (`vtool`: minos 15.0, sdk 27.2). For comparison, the
same bundle was built from `develop` (14dc0c1) in a scratch tree.

Spec: no `prd.md` or `design.md` (bug fix, owner's ruling). Acceptance comes
from the roadmap rows `editor-follow-edit-drop` and `reload-items-stale-hash`
(`docs/roadmap.md`, Next), the owner's rulings (one change for both bugs; for
each bug a test that fails without the fix and passes with it; the ordering
rule in PhotoCore, `WriteChain`, with `LibraryModel.reloadItems` and
`AdjustmentEditor.follow` as thin users), `status.md` (including "For QA") and
`code-review.md` (ready to merge, no findings).

## Verdict

Passes. All three routes reproduce on `develop` with scripted runs that widen
the race, and none reproduces on the branch:
- an edit dropped after leaving a photo and coming back (S2: 2 of 2 runs);
- an undo lost while the photo loads (S5b);
- the grid showing an old look, and culling values reverting, after a reload
  (S3b: 5 of 14 rounds; S3c: 6 of 6; S4: 7 of 9).

The new tests fail without the rule and pass with it. Nothing is left open
that blocks the merge. One optional check with real files is left for a
person (P1).

## Safety record

- Owner's folders before testing (14:53, `stat` listing of
  `~/Library/Application Support/Gus` and `~/Library/Caches/me.sesser.gus`,
  1212 entries). After testing the listing is identical (`diff` empty), and
  `find … -newer <start marker>` finds 0 entries.
  `~/Library/Preferences/me.sesser.gus.plist` is unchanged (Nov 5 16:50).
- Every launch used a copy of the bundle with `CFBundleIdentifier`
  `me.sesser.gus.debugtest`, re-signed ad hoc, through a wrapper that always
  passes `--library-root` and refuses a library outside the scratch folder.
  The app was never started with `open`, `osascript` or without
  `--library-root`. Its preferences went to
  `~/Library/Preferences/me.sesser.gus.debugtest.plist` (the scratch id used by
  earlier QA runs too), not the owner's.
- Afterwards no app process was left (`pgrep -xl Gus`: none). The scratch
  libraries, bundles and source trees were deleted.

## Acceptance criteria

| AC | How | Evidence | Result |
| --- | --- | --- | --- |
| 1. **editor-follow-edit-drop:** leave a photo and come back before its last save lands, then change something; the earlier edit stays | Test, Script | `WriteChainTests`: `readWaitsForQueuedWrites`, `returningBeforeTheSaveLandsKeepsTheEdit`. S2 and S2r: on `develop`, +1.5 EV was dropped in 2 of 2 runs (stored `tone[contrast=20]` only). On the branch, 0 of 2: the editor waits in `loading`, then stores `exposure 1.5 + contrast 20`. | Pass |
| 2. A test for bug 1 that fails without the fix and passes with it | Test | Scratch copy with `read` bypassing the rule (M1): both bug 1 tests fail (`WriteChainTests.swift:79, 83, 200, 209`). Restored: pass. | Pass |
| 3. **reload-items-stale-hash:** after an edit, a reload that read the row before the edit's write does not put the old hash back; the grid cell shows the new look | Test, Script | `readOvertakenByAWriteReadsAgain`, `reloadDoesNotPutTheOldHashBack`. S3b: on `develop` the editor's photo kept the previous round's hash in 5 of 14 rounds, on the branch in 0 of 14. S3c: on `develop` the grid cell showed the previous look in 6 of 6 rounds, on the branch the new look in 6 of 6 (snapshots looked at). | Pass |
| 4. A test for bug 2 that fails without the fix and passes with it | Test | M1: both bug 2 tests fail (`:112, :113, :253`). M2 (only the wait half of the rule): both still fail, which shows the re-check is needed. Restored: pass. | Pass |
| 5. One change for both bugs | Read | `develop..HEAD`: 04bf094 `WriteChain`, feda2c0 `reloadItems`, 7976b49 `follow`, 975cf49 `status.md`. Both bugs go through `WriteChain.read`. | Pass |
| 6. Ordering rule in PhotoCore and tested there; app code a thin user | Read, Test | `Sources/PhotoCore/Support/WriteChain.swift` (`enqueue`, `afterPendingWrites`, `read`, `settled`); `WriteChainTests` in `PhotoCoreTests`. App: `LibraryModel.persist`/`afterPendingWrites` forward to `writes`, `reloadItems` and `AdjustmentEditor.follow` call `writes.read` once each (`LibraryModel.swift:701`, `AdjustmentEditor.swift:258`). | Pass |
| 7. Culling followed by a reload: rating, flag and label stay | Test, Script | `optimisticChangeSurvivesARead`. S4 (9 rounds: rating, pick/reject/clear, labels): on the branch every round showed the right values and the catalog ended right (rating 1, no flag, no label). On `develop`, 7 of 9 rounds showed old values, and the catalog ended **wrong** (flag `rejected` after `U` cleared it; see Q1). | Pass |
| 8. Undo and redo of an edit after coming back | Script | S1: three edits with leave-and-return between them; undo, undo, redo, redo after coming back walk exactly through the three stacks; stored stack and hash match the editor. S7: after relaunch the photo loads with both edits from S2. | Pass |
| 9. A paste or an undo on a photo while the loupe is still loading it | Script | S5a (paste while `loading`): kept, then contrast on top, then both undone in order. S5b (undo while `loading`): on `develop` the undo was silently reverted and the next change saved the undone +1.5 EV again. On the branch the undo held (stored `contrast 20` only). | Pass |
| 10. Undo steps stay on the ordered write chain | Test, Script | `writesRunInOrder`; S1, S5a, S5b (undo after the change it reverses, every time). | Pass |
| 11. No change to how existing stacks render | Read, Test | Diff touches no renderer, `PreviewCacheKey` or golden; `GoldenTests` pass in the full run. | Pass |
| 12. `swift build` and `swift test` green | Test | `swift build`: Build complete. `swift test`: **562 tests in 98 suites passed, 1 known issue** (pre-existing `LiveSessionTests.swift:258` `withKnownIssue`). Large-render and camera-RAW suites skipped as usual (env vars not set). `swift test --filter WriteChainTests`: 10 of 10 runs passed. | Pass |
| 13. The editor's other load paths are unchanged (RAW header and camera frame now read before the stack; crop; unreadable stack) | Script | S6: RAW leave-and-return with exposure, contrast and a crop, all stored; a stack with schema 99 shows `unreadable(newerVersion(99))`, ignores a change and is not written over. | Pass |

`status.md` "For QA" 1 to 3 are covered by AC1, AC9 (item 1), AC3 (item 2)
and AC7 (item 3). Its real arrow-key version of item 1 is P1.

## Findings

No failures and no missing test for the PhotoCore rule.

- **Q1 (for the engineer, `status.md` record only; not a defect on the
  branch). The culling route was not display only on `develop`.**
  `status.md` Root cause says of culling during a reload: "The catalog was
  right; the screen was wrong until the next reload." S4 on `develop` shows
  otherwise. `applyCulling` (`LibraryModel.swift:1091`) writes rating, flag
  and label together, built from the row on screen (`CullingValues(item)`, `:1042`
  in `perform`). So the next culling key after a stale reload writes the
  stale values back.
  - Steps (`develop`): 30,000-version library; in the grid, `sort …; key x`,
    later `sort …; key u`, then `sort …; key opt+0` (S4).
  - Expected: the catalog ends with no flag.
  - Actual: `flag rejected`.

  The branch fixes this with the rest (the S4 catalog is right). Worth one
  line in `status.md`, and it raises the severity of
  `reload-items-stale-hash` for the record (see Requirements issues).
- **O1 (observation). A long write now holds the editor and reloads.** By
  design, `read` waits for every queued write. Behind a batch undo of
  29,894 photos, the editor showed `loading` for about 3 s (S2r: 12 polls at
  0.25 s), where `develop` showed it ready at once, with the wrong values.
  A reload waits the same way. Batches of normal size take milliseconds. No
  change asked for; P1 lets the owner see it with real files.
- **O2 (already tracked, `qa-test-gaps`).** Nothing automated fails if
  `follow` or `reloadItems` stops calling `writes.read`, because there is no
  PhotoApp test target. S2, S3b, S3c, S4 and S5b are the regression
  evidence for the app side. They reproduce on `develop`, so they are worth
  rerunning when this code changes.

## Scripts

Setup (zsh). `$S` was
`/private/tmp/claude-501/-Users-randy--claude-spares-spare-BvSgNb/01bc42db-08f5-4b01-8597-318d3962c9c5/scratchpad/qa`
(deleted afterwards).

```
Scripts/build-app.sh
cp -R build/Gus.app $S/
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest $S/Gus.app/Contents/Info.plist
codesign --force --deep --sign - $S/Gus.app
git archive develop | tar -x -C $S/dev-src
(cd $S/dev-src && Scripts/build-app.sh)
cp -R $S/dev-src/build/Gus.app $S/dev/
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest $S/dev/Gus.app/Contents/Info.plist
codesign --force --deep --sign - $S/dev/Gus.app
swift build -c release --product photobench
.build/release/photobench generate --output $S/src --jpeg 4 --dng 2 --videos 0
.build/release/photobench import --library-root $S/lib-pristine --source $S/src
cp -R $S/lib-pristine $S/lib-big-pristine
.build/release/photobench synthesize --library-root $S/lib-big-pristine --count 30000
```

`lib-pristine` has 106 photos: IMG_00001 to 00004 (JPEG), RAW_00005/6 (DNG)
and 100 HEICs. `lib-big-pristine` adds 29,894 offline clones named
`….clone-N` (so `search clone` selects only them). Paste doesn't need the
original, so pasting onto the clones and undoing that paste gives a write of
a few seconds that leaves the photos under test alone. **This is how the
scripts widen the race.** Without it, the window is one write's latency
(milliseconds), and a script's `focus` reaches `follow` only at the loupe's
next update. Each run started from a fresh copy of a pristine library.
Every launch went through this wrapper:

```
timeout 240 "$app/Contents/MacOS/Gus" --library-root "$lib" --debug-script "$script" > "$log" 2>&1 < /dev/null
```

Stored values after quit were read with
`photocli query images --library-root $lib --limit 100000` (rating, flag,
label, `renderHash`, stack).

### M1, M2. The tests without the rule

`git archive HEAD` into `$S/mut`. In the copy only:
- M1: first line of `read` made `if true { let value = try await fetch(); try apply(value); return value }`.
  `swift test --filter WriteChainTests`: **6 of 8 failed, 10 issues**
  (`:79, :83` bug 1 in memory; `:200, :209` bug 1 on a catalog; `:112, :113`
  and `:253` bug 2; `:136` culling; `:155, :156` cancellation).
- M2: rule restored, `guard mark == queuedCount else { continue }` replaced
  by `_ = mark`. **3 failed, 4 issues** (`:112, :113, :136, :253`): both
  reload tests and the culling test.
- File restored (`cmp` identical to the branch): 8 of 8 passed.

These are the engineer's and the reviewer's counts.

### S1. Leave and come back, then undo and redo (branch, `lib-pristine`)

```
windowsize 1600 1000; wait 2; focus 0; loupe; wait 3; adjust exposure 1.5; wait 1; focus 1; wait 2; focus 0; wait 3; print adjustments; adjust contrast 20; wait 2; print adjustments; focus 1; wait 0.05; focus 0; wait 0.3; print adjustments; adjust highlights -30; wait 3; print adjustments; focus 1; wait 0.5; focus 0; wait 1; print undo; undo; wait 1; print adjustments; undo; wait 1; print adjustments; redo; wait 1; print adjustments; redo; wait 1; print adjustments; print undo; grid; wait 4; snapshot $O/s1-grid.png; quit
```

Index 0 is IMG_00106 (newest first). Editor after each return:
`ev 1.5` → `+contrast 20` → (fast return, ready by 0.3 s) unchanged →
`+highlights -30` (hash `95dca2c59b2b`). Undo: `0bb2116e036c` (contrast 20),
`822f9568f0de` (ev 1.5). Redo: `0bb2…`, `95dc…`. Stored: IMG_00106
`exposure[ev=1.5] tone[contrast=20 highlights=-30]`, hash `95dca2c59b2b`.

### S2, S2r. Bug 1, widened (both builds, `lib-big-pristine`)

```
windowsize 1600 1000; wait 3; focus IMG_00007; loupe; wait 3; adjust vignette -40; wait 1; copyadjust; grid; wait 1; search clone; wait 4; selectall; print selection; pasteadjust; wait 10; print undo; search ; wait 5; focus IMG_00001; loupe; wait 3; print adjustments; undo; adjust exposure 1.5; focus IMG_00002; wait 0.05; focus IMG_00001; wait 0.2; print adjustments; wait 8; print adjustments; adjust contrast 20; wait 6; print adjustments; quit
```

`undo` queues the slow write (Paste Adjustments on 29,894 clones). The +1.5
EV commit queues behind it, then the photo is left and opened again.

| | 0.2 s after return | 8 s after | stored after `contrast 20` |
| --- | --- | --- | --- |
| branch | `loading` | `ready`, ev 1.5 | `exposure[ev=1.5] tone[contrast=20]` |
| develop | `ready`, identity | `ready`, identity | `tone[contrast=20]`: **edit dropped** |

S2r is the same with `print adjustments; wait 0.25` ×32 after the return.
On the branch: 12 polls `loading`, then `ready` ev 1.5; stored both edits.
On `develop`: `ready` with identity on every poll, while the photo's hash
already said +1.5 (`822f9568f0de`); stored `tone[contrast=20]`. So **2 of 2
on `develop`, 0 of 2 on the branch.**

### S3, S3b, S3c. Bug 2: a commit during a reload's read (both builds, `lib-big-pristine`)

A sort change reloads 30,000 rows at once (`reloadItems(keepFocus: true)`).

S3 (`sort fileName; adjust exposure 1.5` with no delay): did not reproduce
on either build. The write had landed before the read began.

S3b sweeps the delay. After `windowsize 1600 1000; wait 3; focus IMG_00001; loupe; wait 3`, 14 rounds of

```
sort <captureDate|fileName, alternating>; wait <d>; adjust exposure 0.<i>; wait 2; print adjustments
```

with d = 0.01, 0.02, 0.03, 0.05, 0.08, 0.12, 0.2, twice. The printed hash
is the photo's (`editor.item`), and each round's exposure has its own hash.

- `develop`: rounds 2, 4, 8, 9 and 10 still showed the previous round's hash
  2 s later (**5 of 14**).
- Branch: every round showed its own hash (0 of 14).

S3c (snapshots):

```
windowsize 1600 1000; wait 3; size 300; focus IMG_00001; loupe; wait 3; sort fileName; wait 0.02; adjust exposure 2; wait 2; print adjustments; grid; wait 3; print selection; snapshot $O/s3c-BUILD-r1.png; loupe; wait 2; sort captureDate; wait 0.02; adjust exposure -2; wait 2; print adjustments; grid; wait 3; print selection; snapshot $O/s3c-BUILD-r2.png; loupe; wait 2; [rounds 3 to 6 alternate the same way]; quit
```

- `develop`: in all 6 rounds the photo kept the previous hash (round 1: the
  unedited `6c76a50e5dc3`).
- Branch: the new hash every time (`ff9043ecfe8f` at +2, `6340617d360c` at −2).
- Snapshots (IMG_00001 is the focused first cell): round 1 shows the branch
  cell brightened, the `develop` cell unedited. Round 2 shows the branch cell
  darkened, the `develop` cell still bright from round 1.

The stored stack was right on both builds: on its own this route is display
only.

### S4. Culling during a reload's read (both builds, `lib-big-pristine`, grid)

```
windowsize 1600 1000; wait 3; size 300; focus IMG_00001; wait 2; accessibility AXImage; sort fileName; wait 0.02; key 3; wait 2; print selection; accessibility AXImage; sort captureDate; wait 0.02; key p; wait 2; print selection; accessibility AXImage; sort fileName; wait 0.02; key opt+2; wait 2; print selection; accessibility AXImage; sort captureDate; wait 0.05; key 5; wait 2; print selection; accessibility AXImage; sort fileName; wait 0.05; key x; wait 2; print selection; accessibility AXImage; sort captureDate; wait 0.05; key opt+4; wait 2; print selection; accessibility AXImage; sort fileName; wait 0.01; key 1; wait 2; print selection; accessibility AXImage; sort captureDate; wait 0.01; key u; wait 2; print selection; accessibility AXImage; sort fileName; wait 0.01; key opt+0; wait 2; print selection; accessibility AXImage; quit
```

IMG_00001's cell value 2 s after each key:

| Key | branch | develop |
| --- | --- | --- |
| 3 | 3 stars | 3 stars |
| P | 3 stars, Picked | 3 stars |
| ⌥2 | 3 stars, Picked, Orange label | 3 stars, Picked |
| 5 | 5 stars, Picked, Orange label | 5 stars, Orange label |
| X | 5 stars, Rejected, Orange label | 5 stars, Orange label |
| ⌥4 | 5 stars, Rejected, Green label | 5 stars, Rejected, Green label |
| 1 | 1 star, Rejected, Green label | 5 stars, Rejected, Green label |
| U | 1 star, Green label | 1 star, Rejected, Green label |
| ⌥0 | 1 star | 5 stars, Green label |
| stored | rating 1, flag none, label none | rating 1, **flag rejected**, label none |

The branch is right on every row. `develop` is wrong on screen in 7 of 9,
and wrong in the catalog (Q1).

### S5a, S5b. Paste and undo while the loupe loads (both builds, `lib-big-pristine`)

S5a:

```
windowsize 1600 1000; wait 3; focus IMG_00001; loupe; wait 3; adjust exposure 1.5; wait 1; focus IMG_00007; wait 3; adjust vignette -40; wait 1; copyadjust; grid; wait 1; search clone; wait 4; selectall; pasteadjust; wait 10; search ; wait 5; focus IMG_00002; loupe; wait 3; print undo; undo; focus IMG_00001; wait 0.05; pasteadjust; wait 0.1; print adjustments; wait 8; print adjustments; adjust contrast 20; wait 3; print adjustments; print undo; undo; wait 2; print adjustments; undo; wait 2; print adjustments; quit
```

- Branch: `loading` at 0.1 s (the paste was made while it loaded); then
  `vignette -40` (paste replaces); then `contrast 20 + vignette -40`. Undo
  gives `vignette -40`, then `exposure 1.5`, which is what was stored.
- `develop`: the same end state. Its editor was already `ready` (its read
  does not wait), so the paste arrived through `catalogChanged`. For a JPEG
  the gap this route needs on `develop` (between the stack read and `ready`)
  is too short to hit, so S5a only shows the branch is right.

S5b:

```
windowsize 1600 1000; wait 3; focus IMG_00007; loupe; wait 3; adjust vignette -40; wait 1; copyadjust; focus IMG_00001; wait 3; adjust exposure 1.5; wait 1; grid; wait 1; search clone; wait 4; selectall; pasteadjust; wait 10; search ; wait 5; focus IMG_00002; loupe; wait 3; print undo; undo; focus IMG_00001; wait 0.05; print undo; undo; wait 0.1; print adjustments; wait 8; print adjustments; print undo; adjust contrast 20; wait 3; print adjustments; quit
```

The second `undo` is "Debug exposure" on IMG_00001, made while it loads.

- Branch: `loading`, then `ready` with identity. Stored
  `tone[contrast=20]`, which is right.
- `develop`: `ready` with ev 1.5 while the photo's hash is the identity
  `6c76a50e5dc3`. Stored `exposure[ev=1.5] tone[contrast=20]`: the **undo was
  silently reverted**.

(A first S5b ran the edits in the other order, so its undo hit IMG_00007;
it is not counted.)

### S6. RAW path and an unreadable stack (branch, `lib-pristine` copy)

Version 3 (IMG_00003) set to `{"schemaVersion":99,"operations":[]}` with
`sqlite3` in the scratch catalog.

```
windowsize 1600 1000; wait 3; focus RAW_00005; loupe; wait 4; print adjustments; adjust exposure 1; focus RAW_00006; wait 0.05; focus RAW_00005; wait 3; print adjustments; adjust contrast 20; adjust crop begin; adjust crop rect 0.1 0.1 0.8 0.8; adjust crop done; wait 2; focus RAW_00006; wait 0.05; focus RAW_00005; wait 3; print adjustments; snapshot $O/s6-raw-loupe.png; focus IMG_00003; wait 3; print adjustments; adjust exposure 1; wait 1; print adjustments; quit
```

- RAW_00005 comes back `ready` each time, with exposure 1, then crop, exposure
  and contrast. Stored the same (hash `f4f00b2c918c`), and the loupe snapshot
  shows the cropped, brightened photo.
- IMG_00003 shows `unreadable(newerVersion(99))` before and after
  `adjust exposure 1`. Its stored stack is untouched.

### S7. Relaunch (branch, the S2 library)

```
windowsize 1600 1000; wait 4; focus IMG_00001; loupe; wait 3; print adjustments; focus IMG_00003; wait 3; print selection; adjust exposure 0.7; key right left; wait 2; print selection; print adjustments; adjust contrast -25; wait 2; print adjustments; grid; wait 4; snapshot $O/s7-grid.png; quit
```

- IMG_00001 loads with `exposure 1.5 + contrast 20`, the S2 result.
- `key right left` with no key window: focus ended at 568 as before.
  Whether the loupe moved in between is not observable, so this does not
  count as a real arrow-key leave-and-return (P1). IMG_00003 stored
  `exposure 0.7 + contrast -25`.
- The grid snapshot shows only offline clone cells (IMG_00003 is off screen)
  and is not used as evidence.

### What a script can and cannot reproduce

The race is one write's latency. Scripts reproduce it only by putting a long
write ahead on the chain (the clone paste and its undo) or by making the
reload's read long (30,000 rows). They also time commands to the
hundredth of a second, and a `focus` reaches `follow` at the loupe's next
update. That shows the mechanism, on `develop` and not on the branch, but
not the rate in real use with a short write ahead. The tests are what pin
the rule. Scripts also commit values directly and send keys to a window that
is not key, so a real slider drag and real arrow keys are not exercised
(P1).

## For a person

There is no `design.md` or `review.md` (bug fix), so no designer M-items.

- **P1 (optional, 5 minutes): real keys and real files.** Use a copy of the
  bundle with its own bundle identifier, launched with `--library-root` on a
  scratch library that holds a few real camera raws and at least a few
  thousand photos (`photobench synthesize` can add them).
  1. In the loupe, drag Exposure, release, press → then ← at once, and
     drag Contrast. Do this three times.
  2. Select a few thousand photos in the grid, Paste Adjustments, and
     immediately open one photo of the selection in the loupe.
  3. Quit and relaunch.

  Look for:
  - every drag survives the relaunch;
  - after step 2, the Adjust tab shows the pasted values once it stops
    loading;
  - how long it shows loading (O1) is acceptable to you.

## Follow-up

(Reruns after fixes. Q1 is a correction to the record, not a code change.
P1: pending the owner, optional.)
