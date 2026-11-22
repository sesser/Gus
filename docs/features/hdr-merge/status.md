Issue: #150

# HDR merge: status

Owner: swift-macos-engineer. Branch `feature/hdr-merge` (worktree `Gus-hdr-merge`).
Spec: the PRD (issue #150 body, approved and revised 2026-11-20) and
[`design.md`](design.md).

**2026-11-22: test and CI time: Done here, CI to confirm.** The owner refused
a longer CI limit (code review C22). The merge suites took 11 of `swift
test`'s 12 minutes because debug builds don't optimize per-pixel Swift; debug
builds now compile `PhotoCore` and `PhotoFixtures` optimized (`Package.swift`,
needs code review and the owner's nod), and three tests' own code is cheaper
or no longer timing-dependent. Merge suites 646.8 s to 42.8 s, full `swift
test` 741.3 s to about 78 s, no assertion, tolerance or image size changed.
C23 and C24 fixed. CI workflow changes are proposed, not made. After code
review's eleventh pass the flags are `-O -assert-config Debug`, so the
standard library's debug-only bounds checks stay on (C25), and the build and
the merge suites are recorded with CI's Swift 6.2.4 (C26). See "Test and CI
time". Next: code-reviewer (a short pass on the one-line flag change), then
push for CI.

**2026-11-22: CI on PR #258: Done here, CI to confirm.** A crash in
`HDRMergeJob.run` with the CI toolchains (Swift 6.2.4 and 6.3.3): its
`catalogue` parameter is now an optional with no default closure (ruled option
1). The WorkLane test (#259) and the merge suites' pool use are fixed in tests.
See "CI on PR #258".

**State: Done** (2026-11-20, after the review fixes below). Every criterion of the PRD as revised (prd4: R4 widened to the stem, R19, AC2a, AC15) built and tested; nothing blocked. Next: code review's second pass (and the designer for the three new strings), then QA.

**2026-11-21: owner finding at sign-off (P5) fixed**, see "Bug: tiles at
100%". A fault in Core Image, not the merge's file; existing merged files need
nothing. The fix changes one thing the owner should know: full-size renders of
straightened or rotated JPEG, HEIC, PNG and TIFF photos now resample linear
light, as raws and the 100% live frames already did (a few edge pixels, up to
37 of 255 steps; no cached preview changes, no pipeline bump). Next:
code-reviewer's second pass on the fix, then qa-tester (no UI change, so no
design review), then back to the owner for P5.

**2026-11-21: sheet revision (owner findings at sign-off, PRD revised the
same day, design §5.5–§5.8, §6.4, §20 D-H6 to D-H10): Done.** Built: the reference
chosen in the sheet's table, the Auto-align and De-ghost boxes, the merge's
paths without alignment and without de-ghosting, `photocli merge
--reference/--no-align/--no-deghost`. See "Revision 2026-11-21" below for the
state, each criterion's test and what changed beyond the sheet (one change to
de-ghosting that every merge gets).

**2026-11-21: design review of the revision (review.md, latest section;
design §20 D-H11 to D-H13): Done.** F6 (the captions folded into their
controls' rows, the result caption cut, the height measured and set), F7 (the
Name line secondary while a refusal shows) and F8 (the header thumbnail follows
the reference for pairs shown as their JPEG) are fixed; D-H13 needed no code.
At three frames the sheet is 560 x 640 with nothing scrolled (Form content 517
against 522 shown). See "Design review of the revision" below. Next:
code-reviewer (second pass, these commits), the designer (confirm F6 to F8,
M15), then qa-tester.

**2026-11-21: code review's sixth pass (C14, C16): Done.** C14: de-ghosting a
still JPEG-like bracket with the brightest frame as reference no longer clips a
band along the bright window (the black-frame test reads the frame's black
level, and the frame-bound tests are kept out of pixels only that frame holds);
the linear fixtures' extreme-reference results are unchanged. C16: the slow-disk
spinner is decided again on every change of reference, and an ended wait never
blocks the next. See "Sixth review pass" below. Next: code-reviewer (second
pass on these commits), then qa-tester; no layout or text changed, so no
design review.

**2026-11-21: code review's seventh pass (C17, C18): Done.** The black-frame
test now compares the reference with the larger of the frame's highest value and
its black level (the reviewer's suggestion), and the separate plane for the
frame-bound tests is gone again: one plane, cleaned and grown together, as in
`c1d10c3`. With that black test the separate plane no longer bought anything
(measured the same in every case), and without it the walker's rim is clean.
The still non-linear brackets, the linear extreme-reference walker, the rim and
the noisy still bracket all hold; see "Seventh review pass". Next:
code-reviewer (second pass on this commit), then qa-tester.

**2026-11-21: code review's eighth pass (C19, C20; the owner ruled C19 fixed on
this branch): Done.** The reference-black test now compares a brighter frame
with the larger of the reference's highest value and its black level (the
reviewer's candidate), so the darkest reference's own noise near black no
longer masks the other frames: noisy ±2 EV, nothing moves (was 769); ±3 EV, a
residual of 1,870 aligned and 2,071 unaligned (was 12,163 and 12,440), from
the two-sided test, left for a noise model (proposed follow-up). Every other
case re-measured: nothing regresses. C20 corrected. See "Eighth review pass".
Next: code-reviewer (second pass on this commit), then qa-tester.

## Baseline

- `swift build` on `develop` at `ed423d7` (plus the design commit): clean.
- `swift test` before any change: 1253 tests in 179 suites passed (70.6 s).

## Latest results (2026-11-22, after "Test and CI time")

- `swift build`: clean; no new warnings.
- `swift test`: 1428 tests in 205 suites passed (77.8 s and 78.1 s in two
  runs with `-O -assert-config Debug`; 741.3 s before the change, 70.6 s on
  `develop` before this branch). No
  golden moved; `UPDATE_GOLDENS` was not run;
  `PreviewCacheKey.currentPipelineVersion` unchanged (13).
- `Scripts/build-app.sh all`: builds both apps.

## Results after code review's eighth pass: C19, C20 (2026-11-21)

- `swift build`: clean; no new warnings.
- `swift test`: 1348 tests in 194 suites passed (712.2 s). No golden moved;
  `UPDATE_GOLDENS` was not run; `PreviewCacheKey.currentPipelineVersion`
  unchanged (13).
- `Scripts/build-app.sh`: builds; checks in "Eighth review pass".

## Results after code review's seventh pass: C17, C18 (2026-11-21)

- `swift build`: clean; no new warnings.
- `swift test`: 1348 tests in 194 suites passed (672.9 s). No golden moved;
  `UPDATE_GOLDENS` was not run; `PreviewCacheKey.currentPipelineVersion`
  unchanged (13).
- `Scripts/build-app.sh`: builds; checks in "Seventh review pass".

## Results after code review's sixth pass: C14, C16 (2026-11-21)

- `swift build`: clean; no new warnings.
- `swift test`: 1346 tests in 194 suites passed (676.7 s). No golden moved;
  `UPDATE_GOLDENS` was not run; `PreviewCacheKey.currentPipelineVersion`
  unchanged (13).
- `Scripts/build-app.sh`: builds; debug-script checks in "Sixth review pass".

## Results after the design review's F6 to F8 (2026-11-21)

- `swift build`: clean; no new warnings.
- `swift test`: 1342 tests in 194 suites passed (502.3 s; the two new tests
  and their suite are `MergePreviewItemTests`). No golden moved;
  `UPDATE_GOLDENS` was not run; `PreviewCacheKey.currentPipelineVersion`
  unchanged (13).
- `Scripts/build-app.sh`: builds; debug-script checks in "Design review of the
  revision".

## Results after the sheet revision (2026-11-21)

- `swift build`: clean; no new warnings.
- `swift test`: 1340 tests in 193 suites passed (504.4 s). No golden moved;
  `UPDATE_GOLDENS` was not run; `PreviewCacheKey.currentPipelineVersion`
  unchanged (13).
- `Scripts/build-app.sh`: builds; debug-script checks in "Revision
  2026-11-21".

## Results after the fix for "Bug: tiles at 100%" (2026-11-21)

- `swift build`: clean; no new warnings (the two in `SmartAlbumTests` and
  `VirtualCopiesTests` were there before).
- `swift test`: 1315 tests in 190 suites passed (278.4 s). No golden moved;
  `UPDATE_GOLDENS` was not run; `PreviewCacheKey.currentPipelineVersion`
  unchanged (13).
- `Scripts/build-app.sh`: builds; debug-script check on the owner's copied
  file as recorded in the Bug section.

## Results before the fix (2026-11-20, after the fourth review pass)

- `swift build`: clean; no new warnings (the two in `SmartAlbumTests` and
  `VirtualCopiesTests` were there before).
- `swift test`: 1309 tests in 189 suites passed (260.5 s), the FAT32 test
  running against a real image (189: the `MemoryHeavy` parent suite of Q3). (After the first review: 1303; at the first
  Done: 1291.) No golden moved;
  `UPDATE_GOLDENS` was not run; `PreviewCacheKey.currentPipelineVersion`
  unchanged (13).
- `Scripts/build-app.sh all`: builds both apps.

## Spikes

Measured on this Mac (macOS 27.2, Apple silicon) on 2026-11-20. Real files:
three hand-held Olympus E-M10 raws of the owner's scratch copy
(`~/gus-scratch/photos/2016-05-21/10M10354.ORF`, `…55` at −1 EV, `…56` at +1 EV,
16 MP, decoded 4608 × 3072), read only; outputs went to the scratchpad. The
command is `swift run -c release photobench merge --files A:B:C --output DIR --format both`.

### Spike 1: DNG writer (decides whether DNG ships here)

**Outcome: DNG ships in this feature.** The writer is small
(`Merge/LinearDNGWriter.swift`, about 330 lines: a little-endian TIFF with
IFD0 holding the image, an EXIF IFD, a GPS IFD and an XMP packet, the pixels
streamed in strips), written from the DNG Specification 1.4 (Adobe,
published). `exiftool -validate` says OK.

One finding changes the PRD's wording (RI-E1): **the system's RAW decoder
(macOS 27.2) gives no image for a 32-bit floating-point DNG** (uncompressed,
LinearRaw, in IFD0: `CIRAWFilter.nativeSize` is zero; only LibRaw reads it,
and then the loupe has no HDR view and other apps can't open it). It reads the
same file with 16-bit (half) floats, which is also what Lightroom writes for
its HDR merges (the owner's `10M10354-HDR.dng`: 16-bit float, deflate). So the
merge writes **16-bit floating point** (`LinearDNGWriter.bitsPerSample`, one
constant). Half floats hold about 30 stops at 11 bits of precision, more than
any bracket.

Two more findings, both handled:
- The decoder cuts what is above a DNG's `WhiteLevel` (set to 1 for float
  data). The merged light is therefore divided by its brightest value (its
  99.99th percentile) so the brightest light is the file's white, and
  `BaselineExposure` brings the reference's exposure back (plus the
  reference raw's own default exposure, so the DNG opens as bright as its
  reference does). Read back through the system decoder, values come back
  within 1.5 % (the highlights) and 0.3 % elsewhere.
- `CIRAWFilter.shadowBias` defaults to a value that bends the shadows; the
  linear decode sets it to 0 (see Spike 4).

### Spike 2: Vision registration accuracy (R9, AC7)

`VNHomographicImageRegistrationRequest` on the frames' luminance **ranks**
(histogram equalization: one scene gives nearly the same picture at every
exposure, the idea of Ward 2003's median threshold bitmaps), with a 1200 × 800
synthetic bracket at −2, 0 and +2 EV, frames shifted by (7.5, −4.25) and
(−5, 6.5) pixels and turned 0.45° and −0.3°: the worst point of a 7 × 7 grid
lands **0.31 px** and **0.14 px** from where the fixture says it is. Vision's
warp is in pixels with the origin at the bottom left (as Core Image), mapping
the floating image onto the reference (found by the fixture's known shifts:
with a y flip the error was 16 px).

On the real bracket the measured movements were 0.06 and 1.32 px (on the
2048 px copy) and −0.02° and −0.04°; the result shows no doubled edges.

- AC7's tolerance, derived from the method: alignment is measured on a copy
  of at most `MergeLimits.measureLongEdge` (2048) pixels, to Vision's pixel
  grid there, so half a pixel of the copy, scaled to the full size. For the
  1200 × 800 test the copy is the image itself: 0.5 px.
- A frame of another scene is refused when the homography is not a hand-held
  movement (`MergeLimits`: shift ≤ 8 % of the long edge, rotation ≤ 3°, scale
  ±3 %, perspective ≤ 0.02) or when the ranks still correlate less than 0.6
  after it (`MergeAlignmentTests`, `HDRMergeJobTests.unrelatedSceneRefused`).
- Lens-distortion differences between frames are not modeled (homography
  only), as the PRD expected.

### Spike 3: memory for several full-resolution frames (A5)

Peak footprint (`ri_lifetime_max_phys_footprint`) for the three 16 MP raws:

| Version of the pipeline | Peak |
|---|---|
| Lazy decodes rendered in one graph, whole image at once | 4.24 GB (both files) |
| Each frame rendered once into half floats, decoders let go (`HDRMerger.fullFrame`) | 3.57 GB |
| … and the output rendered in bands of 512 rows (`MergeOutput.renderInBands`) | **2.16 GB** (TIFF), 2.35 GB (TIFF and DNG) |

Where it goes: the system RAW decoder keeps a working set of about 800 MB
after its first decode, reused (not grown) by later ones; the held frames
are 8 bytes a pixel (113 MB each here); the TIFF is rendered into a 16-bit
buffer. Extrapolated to three 24 MP raws: about 2.8 GB, within A5's 3 GB
placeholder; nine 24 MP frames would hold 1.7 GB of frames on top of the
decoder's set (about 3.9 GB). Not measured on real 24 MP raws (none in the
scratch copy). Times for the 16 MP bracket: measuring (copies decoded,
aligned, exposure, ghosts, tone statistics) 3.7 to 5.4 s, full-size decodes
0.65 s, merge, tone mapping and the TIFF 0.13 to 0.16 s, the DNG 0.18 s:
about 6 s in all, far inside A5's "under a minute".

### Spike 4: which decoders the merge reads

Each frame is decoded linearly, as shot (A2), by the decoder the rest of the
app gives it (`MergeDecoder`):

- **System RAW decoder**: `RAWDecodeSettings.none` (pins the decoder
  version), `boostAmount` 0, `boostShadowAmount` 0, `shadowBias` 0,
  `baselineExposure` 0, `localToneMapAmount` 0, `extendedDynamicRangeAmount` 1.
  With the default `shadowBias` the 16 MP bracket's ghost masks covered 25 %
  and 31 % of the frame (shadows disagreed between exposures); with 0, 1.2 %
  and 2.5 % (moving leaves), and the measured exposures came to 0.481 and
  1.957 for nominal 0.5 and 2.
- **LibRaw** (raws the system gives no image for): its linear camera RGB
  through the color step for the camera's white balance with the tone curve
  left out (`CameraColorTransform.toneCurve = nil`), so it joins the same
  linear working space. Exercised by the DNG test (32-bit files go to LibRaw).
- **ImageIO** (JPEG, HEIC, TIFF, PNG): Core Image's decode undoes the file's
  own transfer curve. A camera's tone curve on top of that is **not**
  recovered (Debevec and Malik's response-curve recovery is not built): JPEG
  brackets merge (AC6), with the lower quality the PRD accepts; a follow-up
  is proposed.
- Exposure is measured from the pixels (median log ratio of neighbors in
  brightness over the pixels both expose well), with the files' exposure
  values only as a fallback: exact on synthetic brackets, within 4 % of the
  nominal on the real one.

### Spike 5: imports and exports beside a merge (design §10)

Safe. The catalog is a GRDB `DatabasePool`, which runs one write transaction
at a time; an import writes chunk by chunk, an export only reads, and the
merge's catalog step is one transaction (`Catalog.insertMergedMaster`). In
the app the merge's write and its undo go on the model's write chain
(`LibraryModel.writes`, as Duplicate's do), so they also follow every change
made before them. If an import catalogues the merged file first (it scanned
the folder in between), the merge reports the photo as merged and registers
no undo step (`MergeCatalogFailure.alreadyInLibrary`). Checked by
`HDRMergeJobTests.importBesideMerge` (a 40-file import and a merge at once:
both complete, 41 new rows).

## Method (clean room)

Written from published sources only; no code from another project.

- Radiance: Debevec and Malik 1997, "Recovering high dynamic range radiance
  maps from photographs" (eq. 6, the weighted average of exposure-normalized
  values, for a linear response).
- Weighting: the broad hat `1 − (2z − 1)^12` of Reinhard, Ward, Pattanaik and
  Debevec, "High Dynamic Range Imaging" (2005), times the frame's relative
  exposure (inverse variance under photon noise: Granados, Ajdin, Wand,
  Theobalt, Seidel and Lensch 2010, "Optimal HDR reconstruction with linear
  digital cameras"). The darkest frame keeps weight 1 up to clipping and the
  brightest down to black.
- Alignment: Vision's homographic registration (Apple framework) on luminance
  ranks, after Ward 2003, "Fast, robust image registration for compositing
  high dynamic range photographs from hand-held exposures".
- Ghosts: a consistency test against the reference (Grosch 2006, "Fast and
  robust high dynamic range image generation with camera and object
  movement"; Reinhard et al. 2005 on variance-based detection), one-sided
  where the reference is clipped or black; masks cleaned, grown and feathered;
  the reference keeps a floor weight so it fills masked areas (R10, A9).
- Tone mapping: base and detail of Durand and Dorsey 2002, "Fast bilateral
  filtering for the display of high-dynamic-range images", with the guided
  filter (He, Sun and Tang 2010, "Guided image filtering") as the
  edge-preserving smoother, computed on the reduced copy and applied at full
  size as He and Sun 2015, "Fast guided filter"; the base's log range is
  scaled to 5 stops, the brightest light lands at 0.9 and an exponential
  shoulder above 0.8 keeps detail from clipping. (Reinhard et al. 2002's
  global operator was tried first: on the bracket fixture it pushed the
  brightest two highlight steps into one 8-bit code, failing AC10.)
- DNG: the DNG Specification 1.4 (Adobe).

## Acceptance criteria

| AC | State | Test or check |
|---|---|---|
| AC1 | Done | Debug script (below): `print merge` gives canMerge false for one photo and for one video ("fewer than two"), while the sheet is up ("sheet up") and while a merge runs ("running"); true with three; the sheet opens with a video among three and refuses. The grid's context menu lists Merge to HDR… after Duplicate. `menuitems` shows the item and ⇧⌘L (enabled state not readable from a shell launch: no key window) |
| AC2 | Done | `HDRMergeJobTests.mergesToTIFF` (hashes unchanged, folder, `_HDR-2`), `existingFileUntouched`, `MergeSelectionTests.naming` |
| AC2a | Done | `MergeSelectionTests.numbersPastTheStem` (a DNG after a TIFF is `-2`, an orphan `.xmp`, `X_HDR.DNG` against `.dng`, `-3` after `.tif` and `-2.dng`), `mergesToTIFF` (TIFF, TIFF, DNG: `-3.dng`), `ownSidecars` (each result's sidecar holds its own rating) |
| AC3 | Done | `mergesToTIFF` (0 EV frame second in time names it), `firstByTimeNames`, `MergeSelectionTests.orderAndReference`, `earliestWithoutCompensation` |
| AC4 | Done | `mergesToTIFF` (16-bit, three samples, Display P3, catalogued with hash in the project), `mergesToDNG`, `sidecarWhenEnabled` |
| AC5 | Done | `mergesToTIFF` (library values equal; the file's title, caption, keywords, rating, label, camera) |
| AC6 | Done | `mergesToTIFF` (three raws), `mergesJPEGs`, `mixedRefused`, `pairCountsOnce` |
| AC7 | Done | `MergeAlignmentTests` (0.5 px derived tolerance), `unrelatedSceneRefused` |
| AC8 | Done | `HDRMergerTests.ghostFree` |
| AC9 | Done | `cancelLeavesNothing` |
| AC10 | Done | `HDRMergerTests.matchesReference` (CPU reference `Reference/MergeReference.swift`), `holdsTheRange`, `recoversRadiance` |
| AC11 | Done | `resultIsAPhoto` (renders, edit with history, export); goldens unchanged |
| AC12 | Done | `MergeSelectionTests` (every refusal and their order), `readOnlyFolderRefused` |
| AC13 | Done | `undoAndRedo` (catalog); debug script: `print undo` reads "Merge to HDR", Undo takes the photo out (selection back to the three frames, Activity names the path, the file stays), Redo puts it back |
| AC14 | Done | `MergeCommandTests.mergesFromTheCommandLine` (path printed, refused while locked, refused for one frame) |
| AC15 | Done | `mergesToTIFF` (a second merge: its own row, a different SHA-256, the same decoded pixels; then a DNG of the same frames, catalogued), `againAfterRemoval` (first photo removed, its file left: the next merge is `-2` and catalogued) |

Rules behind the UI, unit-tested in PhotoCore: `MergeRuleTests` (the quit
question while merging, removal off while merging, the landing rule),
`BrowserStateTests` (File ▸ Stop's job), `LibraryModalTests` (the sheet is a
`LibraryModal`), `RAWDecodeGraphTests` (the merge's decoder keys its image).

## Review findings (2026-11-20)

Code review (`code-review.md`), design review (`review.md`) and security
review (`security-review.md`), fixed in `46b5107` and `a3a597d`.

| Finding | Fix | Test |
|---|---|---|
| C1 (Blocker) merging the same frames again wrote a byte-identical file the catalog couldn't take | Every merge's XMP (TIFF and DNG) carries a new `xmpMM:DocumentID`/`InstanceID` and its `xmp:CreateDate` (PRD R19). A content the catalog still refuses (`MergeCatalogFailure.sameContent`) fails the job and removes the file; `alreadyInLibrary` now means only the same path with the same content (another import catalogued this very file) | `mergesToTIFF` (second run has its own row and hash, same pixels), `sameContentRefused` |
| C2 Stop and Quit didn't wait for cleanup | `PhotoApplication` awaits `merge.waitUntilDone(timeout: 10 s)` before terminating | By reading (an app-delegate path); manual check M4 |
| C3 a TIFF and a DNG of one bracket shared a stem and a sidecar | `MergeNaming` numbers the result past any file or master with the same stem, any extension, compared as the file system does (PRD R4 as widened, A12). `ExportNaming.freeName` is gone; `MasterFiles.Names.containsStem` added. SidecarSync's fallback is bug #248 | `numbersPastTheStem`, `ownSidecars` |
| C4 Undo after a failed Redo reported a removal | Reports and hides only when a photo was taken out | By reading |
| C5 32-bit comments and default | `LinearDNGWriter` writes half floats only (`bitsPerSample` 16); comments fixed | `MergeDNGTests.dngRoundTrip` (now asserts the system decoder reads it, values within 3 %) |
| F1 guide | DNG "opens as bright as the reference but flat"; the landing sentence names the loupe, review and comparison | — |
| F2 Name row | One line, truncated in the middle, full name as tooltip | Manual M1 |
| M1 no pixel or memory bound | `MergeLimits.maximumPixels` = 150 MP a frame (the cap LibRaw already has, above every current camera); `frameMemoryBudget` = half of physical memory for the held frames (8 bytes a pixel; the other half for the RAW decoder's 0.8–1.5 GB, Core Image, the copies and the app). Refused in the sheet from the catalog's sizes (`tooLarge`, `tooMuchMemory`), again from each decoder's size before anything is rendered at it (`MergeDecoder`) and before a frame is held (`fullFrame(budget:)`). The TIFF is encoded from a provider that renders 512 rows at a time (no whole-image buffer; peak for the 16 MP bracket 2.06 GB) | `MergeSafetyTests.refusedBySize`, `refusedByHeader` (a 550 KB PNG of 180 MP: refused, nothing written), `budgetBeforeHolding` |
| M2 DNG offsets past 4 GiB | `LinearDNGWriter` checks the size before creating the file (`Failure.tooLarge`) | `dngTooLarge` |
| L1 hidden name 46 bytes longer than the result | Hidden name `.merge-<UUID>.partial`; the result's stem is shortened so the name fits 255 bytes | `longNames` |
| L2 delete by path | The written file's device and inode are kept; it is removed only while the name still holds it | By reading (`FileIdentity`) |
| L3 absurd exposure metadata | Not finite or not positive counts as unknown; ratios outside 2^±16 are not believed (equal exposure assumed); the same-exposure note ignores non-finite values | `absurdExposure` |
| L4 stale mount path in `photocli` | Online only by the volume's identity, as the app | By reading |
| L5 paths in public logs | Errors logged `.private` | — |
| L6 `.partial` after a crash | Stop and Quit: C2. A sweep of old `.partial` files is not built (optional); the guide says Control-C on `photocli merge` can leave one | — |
| L7 hard-link fallback for any errno | Falls back only for `ENOTSUP`, `EOPNOTSUPP`, `EPERM`, with `renamex_np(RENAME_EXCL)`; any other error is a write failure | `linkFallback` |
| L8 unchecked stem and path | `MergeNaming.isPlainPlace`: the name is the relative path's last part, no empty, `.`, `..` or NUL part, not absolute; else `invalidName` | `plainPlaces` |

### Second pass (2026-11-20)

| Finding | Fix | Test |
|---|---|---|
| C6 (Blocker) on FAT32 and exFAT `renamex_np(RENAME_EXCL)` fails with ENOTSUP too, so every merge beside masters there failed | After ENOTSUP or EOPNOTSUPP from the exclusive rename, the name is reserved with an empty file made with `O_CREAT \| O_EXCL` (EEXIST: the name is taken) and the file is renamed over that placeholder; a failed rename removes the placeholder only while it is still the one made. The placed file's identity is read from the name after placing (FAT has no inodes of its own). `link` and the exclusive rename are injectable | `MergeSafetyTests.linkFallback` (both unsupported: placed, then `nameTaken` with the first file untouched), `fat32` (a 64 MB FAT32 image made and attached with `hdiutil`: placed, never replaced, no `.partial` left; prints and passes without running where `hdiutil` can't attach) |
| C7 the Stop and Quit wait had no real limit | `MainActorWait.whileTrue` (PhotoCore) polls `task != nil` on the main actor until the deadline; `MergeModel.waitUntilDone(timeout:)` uses it | `MainActorWaitTests.deadline` (with time that passes only when the wait sleeps, so the test doesn't depend on load: a 10 s limit on a condition that never ends returns at 10 s after 100 sleeps; a condition that ends on its fourth asking returns at 300 ms), `realClockReturns` (a 50 ms limit returns on the real clock). A first version with wall-clock bounds failed under the full suite's load (the main actor was busy for 90 s) |
| C8 the job's inode-checked removal had no test | — | `HDRMergeJobTests.refusedFileRemoved` (a `catalogue` that refuses: the file goes; one that also puts another file under the name: that file stays) |
| C9 DNG XMP as UNDEFINED without a packet wrapper | Tag 700 written as BYTE, wrapped in `<?xpacket …?>` | `exiftool -validate` on a merged DNG: OK; `dngRoundTrip` still reads it |
| F3 wording of the damaged-library message | As given, word for word | `LocalizationTests` |
| F4, F5 guide | The refusal bullet adds the 150 MP limit and the memory limit (half the Mac's memory; select fewer); a sentence that a merged photo can be selected with its own frames and would count that light twice | — |

Third pass (code review C10, nit): the FAT32 test now carries
`.enabled(if: canAttachFAT32)`, a probe that makes and attaches one image once,
so where `hdiutil` can't attach it shows as skipped instead of passing without
running; where the probe works, a failure to attach the test's own image is an
issue. Test only. `swift test`: 1307 tests in 188 suites passed (239.1 s), the
FAT32 test ran.

### QA findings (2026-11-20, `qa.md`)

| Finding | Fix | Check |
|---|---|---|
| Q1 (Blocker) Redo of Merge to HDR deadlocked the write chain: the Redo ran inside `persist` (the chain's tail) and called `show`, whose `writes.read` waits for the tail, itself | After the catalog puts the photo back, `show` is scheduled with `writes.afterPendingWrites`, which runs once the Redo's write has ended. Audit of the merge's other chain users: Undo calls `hide` (no read); the catalogue step (`onWriteChain`) only inserts; the sidecar step only writes; the landing `show` after a merge runs from the job's own task, not the chain. `show`'s doc now says never to call it from inside a write | Debug script on a fresh bundle and scratch library (QA's script 11): merge, `undo`, `redo`, `print items` shows `RAW_102_HDR` back; a rating of 5 given afterwards is in `catalog.sqlite` after quit (`sqlite3`: `RAW_101.dng\|5`); a merge, Undo, Redo of a JPEG bracket, then a rating of 3 on another photo, is saved too, and the next merge sheet opens. `LibraryModel` is in the app target, which `swift test` can't load, so this check is the debug script's. Proposed follow-up below: make `WriteChain.read` refuse rather than wait when called from its own tail |
| Q2 `quit` hung with the merge sheet up | The script's `quit` closes `showsMergeSheet` too | `merge sheet; quit` ends (exit 0) |
| Q3 `ImportHashMemoryTests` measured the merge suites' memory | A parent suite `MemoryHeavy` (`.serialized`, which reaches nested suites) holds `ImportHashMemoryTests` and the merge suites that decode frames (`HDRMergerTests`, `MergeDNGTests`, `HDRMergeJobTests`, `MergeCommandTests`, `MergeSafetyTests`, `MergeAlignmentTests`), so none of them overlaps another | Full suite |
| Q4 dates in the written files | Decided: every date is the reference's capture date (R7, A3). `xmp:CreateDate` is the reference's `DateTimeOriginal` (with its offset when recorded), so ImageIO's EXIF `DateTimeDigitized` and IPTC creation date follow it in the TIFF; the DNG writes the same. R19's uniqueness comes from `xmpMM:DocumentID`/`InstanceID` alone | `mergesToTIFF` and `mergesToDNG` read DateTimeOriginal, DateTimeDigitized and xmp:CreateDate back (all the capture date); `mergesToTIFF` still finds two merges' files with different SHA-256 and the same pixels; exiftool on the real bracket's TIFF and DNG shows one date everywhere, `-validate` OK |
| Q5 debug `photocli merge` slow | Recorded in `docs/PROFILING.md`: about 35 s to measure three 1536 x 1024 frames in a debug build, a few seconds in release; time release builds. Moving the sorts to Accelerate (tried: same order, pixel-identical TIFF on the real bracket) made no measurable difference in debug (34.9 s), because the time is the measuring's per-pixel Swift loops, so it was not kept | Measured with `.build/debug/photobench merge` |

### Fourth review pass (2026-11-20)

- **C11** the capture date's offset was copied as stored, so EXIF's blank
  "unknown" offset (`   :  `) made the XMP date invalid. The offset is now
  added only when it reads `±HH:MM` or `Z` (`Metadata.isTimeOffset`). Test:
  `MergeSafetyTests.captureDateOffset` (+02:00, −05:30, Z, the blank offset,
  a malformed one, none). Checked with exiftool on merges of JPEG brackets
  whose reference has a real offset, the blank one (written with ImageIO;
  exiftool itself refuses that value) and none: `xmp:CreateDate` is
  `…T10:01:01+02:00`, or no offset, and the DNG validates OK in all three.
  The TIFF's remaining `-validate` warnings are ImageIO's own TIFF and IPTC
  writing (missing ExifVersion, IPTC times written in 6 bytes, the IPTC-NAA
  tag's type) and are the same with no offset at all.
- **C12** `WriteChainTests.afterPendingWritesFromInsideAWrite` pins what the
  Q1 fix relies on: `afterPendingWrites` called inside a running write runs
  after it and after a write queued before it, and a `read` inside it
  completes, seeing a write queued during the first.

Ruled with no code (design §19 D-H5, RI-H4): numbering by stem needs no
caption; a merged DNG chosen beside its own source raws is neither flagged nor
refused in v1. New manual checks M7 and M8 are in `review.md`.

**Heads-up for the merge with #88 (`feature/ai-masks`).** #88's migration v15
adds `editHistory.maskRasters`. `Catalog.removeMergedMaster` and
`restoreMergedMaster` (`Catalog/MergedMasters.swift`) list the history
columns by name (`id, versionId, label, createdAt, stack`), so after both
land they would drop `maskRasters` on Undo/Redo of a merge, and #88's launch
cleanup would then delete rasters those rows name. **Whichever branch merges
second must add the column to those two queries** (as #88 does for the
virtual-copy undo).

## Revision 2026-11-21: the reference, Auto-align and De-ghost

Spec: the PRD as revised 2026-11-21 (R3, R9, R10, R14, R17, AC3, AC3a–AC3c,
AC7a, AC7b, AC8a, AC9a, AC12, AC14) and design §5.5–§5.8, §6.4, §7.1, §7.3,
§11, §13–§16 and §20 (D-H6 to D-H10). The Core Image tile fix above is
untouched.

**State: Done** (2026-11-21). Every criterion the revision added or changed
is built and tested (table below); one design question is open (DQ-H11, the
height at three frames), which blocks nothing: the sheet works and scrolls at
600 pt. `swift build` clean, no new warnings; full `swift test`: 1340 tests in
193 suites passed (504.4 s); `Scripts/build-app.sh` builds; debug-script checks
below. No golden moved, `UPDATE_GOLDENS` not run, no migration,
`PreviewCacheKey.currentPipelineVersion` unchanged (13). Next: code-reviewer
(second pass on the revision), the designer (review, DQ-H11, the Name line
note), then qa-tester.

### What was built

- **Engine** (PhotoCore). `MergeOptions` (`align`, `deghost`, both on unless
  told). `HDRMerger.plan(…options:)`: with `align` off, no Vision request is
  made, every homography is the identity, nothing is warped and no frame is
  refused for not lining up (A14); with `deghost` off the ghost masks are
  empty, so the merge is the plain exposure-weighted blend. The reference keeps
  its floor weight in both cases: it only decides a pixel where no other frame
  has any weight at all (a frame's uncovered border strip next to a clipped
  reference), so no region is taken from the reference alone in place of a
  blend (R10), and where nothing moved the two results are the same merge (AC8a
  measures 0.0 difference there). `HDRMergeJob.run(…options:)`; its progress
  is `MergeProgress.Schedule(aligns:)`: without alignment the 0.3 share of
  Aligning is left out and the rest scaled, so the bar still runs from 0 to 1,
  and the measuring that remains reports as Merging (design §7.1).
- **The reference** (PhotoCore). `MergeSelection.choosingReference(_:)` gives
  the same frames with another reference and decides the refusals again (only
  the different-size one depends on it: named and flagged from the chosen
  reference, every frame of another size flagged, design §6.1 case 6).
  `MergePreflight` splits case 8 (`firstUnreadable`, asked once) from case 9
  (`unwritable(reference)`). `MergeSheetState` is the sheet without its views:
  the frames, the reference (default R3's, `chooseReference(nil)` and unknown
  ids ignored, so always exactly one), the boxes, case 8's answer, each
  folder's writability asked once per folder for the life of the sheet (an
  answer that comes after the reference moved to another folder is kept as a
  fact about its folder but decides nothing on screen), the Name answer keyed
  by reference and format (a late one ignored; the unnumbered candidate,
  `isFinal` false, meanwhile), and from them the message, flagged rows and
  whether Merge is on. `messageChange(from:to:)` is §11's rule for what the
  VoiceOver announcement adds. Made new on every open (AC3c, AC9a).
- **The sheet** (PhotoApp). The Photos table is `Table(_:selection:)` bound to
  a `@State` row that the model's reference drives; a nil or refused selection
  is put straight back (design §5.5's engineer note), so the table can't be
  left without a chosen row. The "Reference" mark is `fixedSize` and the name
  truncates in the middle with its full text as a tooltip. Under the table's
  caption, two `Toggle`s with the checkbox style and their captions (indented
  20 pt, hidden from VoiceOver, given as the hint). The Name line shows the
  unnumbered candidate in secondary color until the new folder's answer. The
  Result caption is the one sentence §5.3 keeps. `MergeSheetMetrics`: 560 wide,
  ideal 600, minimum 420. `MergeModel` holds a `MergeSheetState`: a change of
  reference loads the new thumbnail (the old stays until it is ready), asks the
  new folder if needed (detached), asks the name again, and schedules one
  announcement 0.3 s after the last change, posted once the folder and the name
  are known ("Reference ‹name›. Result ‹file›." plus the new refusal, or "Merge
  is available."). Pressing Merge runs the job with the chosen reference and
  boxes; the job's own pre-flight repeats case 8 and case 9 for that reference.
- **Strings**: the caption "“%@” names the result and where it is saved. Click
  another photo to change it." replaces the old one; "Auto-align", "De-ghost",
  their captions, "Choose the reference" (table hint), the Result caption
  without "Saved next to …", the alignment failure ending "…, or turn off
  Auto-align.", "Reference %@. Result %@." and "Merge is available."; the old
  three keys removed.
- **`photocli merge`**: `--reference <version>` (one of the `--version`s; a
  pair's JPEG means its raw; otherwise an `invalidValue` error "--reference N
  is not one of the --version values", nothing written), `--no-align`,
  `--no-deghost`; the JSON gains `align` and `deghost`. A frame that doesn't
  line up fails with "‹name› doesn't line up with ‹reference›. Merge photos of
  the same scene, or pass --no-align." (D-H10).
- **Debug script**: `merge reference <name|row> [nowait]`, `merge align
  on|off`, `merge deghost on|off`, `merge slowdisk <ms>` (delays each folder
  check, to see a superseded answer), `merge table select <row>|deselect`
  (drives the sheet's `NSTableView` the way a click or ⌘-click does), and
  `merge sheet` now prints both boxes, the caption and the sheet's measured
  heights (`metrics`: the sheet window, and the Form's content against what it
  shows). `merge start` prints the boxes.
- **Fixtures**: `photobench generate --brackets N` adds `TwoFolders-n`: the
  walker bracket in `Locked` (−2 and 0 EV, read-only: the default reference is
  refused) and `Open` (+2 EV). In every series the 0 EV frame is shot second,
  not first (`Raw-n` is the walker series). `photobench merge` takes
  `--no-align` and `--no-deghost`. `HDRBracket.radianceImage(…as:)` gives the
  scene's light as a moved frame saw it.

### One change every merge gets: de-ghosting near black and clipping

Found by AC3b's test with the darkest or brightest frame as the reference
(the PRD's A13 asks whether an extreme reference makes de-ghosting worse). It
did, badly: `MergeGhosts.disagreement` skipped any frame that was black or
clipped anywhere in its 3 x 3 neighborhood. With the 0 EV frame as the
reference that rarely mattered. With the −1 EV frame of a −1/0/+1 bracket as
the reference, the +1 EV frame's object (0.9, just under clipping) was never
tested, kept its full weight times its exposure (4) and left a ghost 57 times
the wall's light; with the −2 EV frame of a ±2 EV bracket the reference's own
object came out 44% off, with the +2 EV frame 97% off.

A black frame's values are an upper bound on the light and a clipped frame's
a lower bound, so each can still say "clearly below" or "clearly above" the
reference. The test now uses exactly that (the same 1.5 factor as the existing
one-sided tests where the reference is black or clipped): a clipped frame
disagrees if even its lowest value is clearly above the reference's highest, a
black one if even its highest is clearly below the reference's lowest; a frame
that is both black and clipped in one neighborhood still says nothing. On a
still scene neither test can fire (a clipped frame's light over its exposure
is at most the scene's, a black frame's at least, up to noise, and noise near
black only masks frames that carry almost no weight there).

**Corrected after code review C14 (sixth pass):** the last sentence holds only
for values proportional to the light (raws). A JPEG's camera curve crushes its
toe below proportional by any amount, so a black frame's own values are no
upper bound, and the black-frame test fired across a still wall. **As it
stands after C17 and C18 (seventh pass):** a black frame disagrees where the
reference, all around, is clearly brighter than the larger of the frame's
highest value and its black level (`reference.low > max(frame.high, lowF) /
exposure * 1.5`). Values under the black level say nothing, crushed by a toe
(C14) or dragged there by noise (C17). The mirror for the reference, after C19
(eighth pass): where the reference is black, a brighter frame disagrees only if
it is clearly above the larger of the reference's highest value and its black
level (`frame.low / exposure > max(reference.high, lowR) * 1.5`), since the
reference's own noise reaches its black level too. Every test's result goes into one plane,
cleaned and grown together, as before C14. (The sixth pass's separate plane for
the frame-bound tests, kept only where another frame is trusted, let a moving
object's rim through, C18, and with this black test it changed nothing else.)
See "Sixth review pass", "Seventh review pass" and "Eighth review pass" below
for the numbers.

Measured on the synthetic walker (600 x 400, objects on a dim wall), object
error inside the reference's object / ghost error at the other frames' places:

| Bracket, reference | Before | After |
|---|---|---|
| ±2 EV, 0 EV (the default) | 0.017 / 0.0076 | 0.0 / 0.0076 |
| ±2 EV, −2 EV | 0.44 / 0.0052 | ~1e-7 / 0.0052 |
| ±2 EV, +2 EV | 0.97 / 0.0001 | 0.0 / 0.0001 |
| ±1 EV, −1 EV | 0.80 / 57.7 | ~1e-7 / 0.0057 |
| ±1 EV, +1 EV | 0.13 / 0.0003 | ~1e-7 / 0.0003 |

Where nothing moved, every case is the same merge as one with no ghosts (0.0).
The C14 correction leaves every number in this table as it was.
The C17 and C18 changes leave it as it was too, and the rim (each other
frame's whole disc and the masks' growth around it, not only the 11 x 11 core)
has no pixel more than 5% off with any reference, aligned or not (worst 0.0085
of the clean value, ±2 EV aligned with the default reference; `outlinesWithoutAlignment` and the rim checks in
`ghostFree`, `ghostsFollowTheReference`, `extremeReferences`).
So, answering A13: with this change an extreme reference no longer makes
de-ghosting visibly worse on the fixture; on real files that is for the owner's
eye (M12, M13). For non-linear frames (JPEG brackets), after C14 and C17: on a
still bracket with a toe (`L·L/(L + c)`, c 0.01 and 0.005) or a shoulder, no
mask fires and nothing moves, with any frame as the reference
(`stillNonLinearBracket`); on a still linear bracket with noise σ 0.004 and the
default reference, nothing moves either (`stillNoisyBracket`). Noise near the
darkest reference's black level, after C19: at ±2 EV nothing moves (769 pixels
before, worst 130%); at ±3 EV 1,870 pixels (0.8% of the frame, worst 4.7
times; unaligned 2,071, worst 9.6 times) still take the darkest frame's noisy
values in deep shadows (12,163 before, worst 11 times). That residual is
mostly the two-sided test reading the darkest frame's noise where its light is only a few
σ above its black level; it needs a noise model (proposed follow-up). The
default reference at ±3 EV moves 430 the same way, under every rule. What stays for JPEG brackets is older than this change and the same with
the rule before it: a strong S-curve (toe and shoulder together) makes the
two-sided test see still mid-tones disagree, and an area de-ghosting takes
from fewer frames differs in tone from the blend around it. Both come from not
recovering the camera's response (proposed follow-up below), not from the
choice of reference rule. Merges with the default options are not bit-for-bit what they
were before: the masks now also cover moving things where a frame is near black
or near clipping (the default case above: the object went from 1.7% off to
exact). Merged files are new files, so nothing cached or stored changes; no
golden involves a merge; no pipeline bump.

### The CPU reference's tolerance (one correction)

AC8a's plain blend against `MergeReference` failed at 1.1 times its tolerance
on one pixel at a highlight step's edge (GPU 1.3281689 against 1.3281837). A
probe of the pixel showed the only frame with weight there (the −2 EV frame,
darkest, flat weight) had its four taps' red spanning 0.318 to 0.360 while
their brightest channels spanned 0.387 to 0.390: the reference bounded the
float sample position's effect by the spread of each tap's brightest channel,
which can be far smaller than a channel's own spread. It now takes the largest
per-channel spread (`Reference/MergeReference.swift`). With it AC8a's worst
pixel is 0.31 of its tolerance and AC10's existing check 0.37 (was 0.61).
Tried and not kept, because neither was the cause: a term for the weights'
float rounding times the frames' disagreement, and treating sample positions
within float rounding of a pixel center as unconditioned; nearest sampling of
the frames (the kernel builds its own bilinear mix) gave bit-identical output.

### Acceptance criteria (revision)

| AC | State | Test or check |
|---|---|---|
| AC3 | Done | `MergeSheetStateTests.opensWithDefaults` (0 EV frame second in time is the reference, both boxes on, Merge off until the disk answers); existing `mergesToTIFF`, `firstByTimeNames`, `MergeSelectionTests.orderAndReference`, `earliestWithoutCompensation` |
| AC3a | Done | `MergeReferenceJobTests.chosenReference` (two folders, two projects: the +2 EV frame chosen; result `IMG_0003_HDR.tif` in its folder and project, its capture date, its rating, label and title in the library and in the file, nothing in the default reference's folder; numbered in its folder); `MergeSheetStateTests.nameFollows` (Name follows reference and format; a late answer ignored), `folderRefusalFollows` (folder and "several folders"); `photocli` `referenceAndSwitches` |
| AC3b | Done | `MergeChoicesTests` (in `HDRMergerTests`): `alignmentFollowsTheReference` (references 1 and 2 of a moved bracket: each frame's measured homography onto the chosen one within AC7's derived 0.5 px of the fixture's truth, the reference's own identity; the merged light within the 25% + 1% bound of the chosen frame's view where the light varies by under 25% over 5 x 5 pixels, and far from the other frame's view); `ghostsFollowTheReference` (references 0 and 2 of a ±1 EV walker: the object exact at the chosen frame's place, the others' places as with nothing moving); `extremeReferences` (±2 EV, references 0 and 2: the A13 record); job level `choicesAreOtherMerges` (another reference or De-ghost off give other pixels; the defaults again the same pixels) |
| AC3c | Done | `MergeSheetStateTests.reopensWithDefaults` (a new sheet for the same frames, even from a selection carrying another reference, has the default reference and both boxes on); `MergeModel.begin` makes a new `MergeSheetState` every time; debug script (below) |
| AC7a | Done | `withoutAlignment` (no Vision progress, every homography the identity; GPU against the CPU reference with identity movements within AC10's tolerance, worst 0.03; the moved frames' light not lined up: error 10 against the reference's view, 0.11 when aligned); `unrelatedWithoutAlignment` (core: refused with alignment, merged without); `MergeReferenceJobTests.unrelatedMergesWithoutAlignment` (job: catalogued, no `.aligning` report, the bar never goes back and ends at 1; with it on, refused naming the frame); `photocli` `unrelatedWithSwitch` |
| AC7b | Done | `MergeReferenceJobTests.refusalsWithoutAlignment` (with both boxes off: a different size, an offline frame, a video, and a read-only folder before any work, each refused, nothing read) |
| AC8a | Done | `withoutDeghosting` (masks all zero, plans otherwise identical; the hand-held walker's plain blend against the CPU reference with no masks within AC10's tolerance, worst 0.31; against de-ghosting: 6.9 in the moving region, 0.0 where nothing moved) |
| AC9a | Done | `MergeSheetStateTests.opensWithDefaults`, `reopensWithDefaults`, `boxesAreIndependent` (the four combinations leave the reference, refusal, Merge and Name alone); `fourCombinations` (each merges, finite, identity movements exactly when align is off, empty masks exactly when de-ghost is off); nothing stored (no preference key; only Format keeps one) |
| AC12 | Done | `MergeSheetStateTests.folderRefusalFollows` (default reference in a read-only folder refused, naming it; a frame in a writable folder lifts it; back to the first folder's other frame brings it on, naming that frame), `folderAskedOnce`, `sizeRefusalFollows`, `unreadableStays`; `MergeReferenceJobTests.readOnlyFollowsTheReference` (real `chmod 555` folder: refused before work for the default, merged with the chosen frame in the other folder, refused again for a frame in the first); existing refusal tests |
| AC14 | Done | `MergeCommandTests.referenceAndSwitches` (defaults in the JSON; `--reference` in another folder with both switches; a reference outside the series is an error, nothing written), `unrelatedWithSwitch` (refused naming `--no-align`, merged with it); existing `mergesFromTheCommandLine` |
| §7.1 | Done | `MergeProgressScheduleTests.schedule`; `unrelatedMergesWithoutAlignment` |
| §11 | Done | `MergeSheetStateTests.announcement` (the rule); the debounce and posting by the debug script (below) |

### Debug-script checks

Run 2026-11-21 on a copy of the bundle (`CFBundleIdentifier`
`me.sesser.gus.debugtest.merge`, re-signed ad hoc) against scratch libraries:
`photobench generate --output $S/src --jpeg 2 --dng 0 --heic 0 --videos 0 --brackets 1`,
`photobench import --library-root $S/lib --source $S/src`, a fresh copy of the
library per run, every launch with `--library-root`. (`search` applies
asynchronously: each script waits a second after it.)

- **Choosing, boxes, table, reopening** (`search RAW_10; wait 1; selectall;
  merge sheet; merge reference 3; merge reference RAW_101; merge format dng;
  merge format tiff; merge align off; merge deghost off; merge table deselect;
  merge table select 2; merge table deselect; merge cancelsheet; merge sheet`):
  opens on RAW_102 (0 EV, shot second), both boxes on, Name `RAW_102_HDR.tif`,
  caption naming it. Row 3 and then RAW_101 by name: the Name follows
  (`RAW_103_HDR.tif`, `RAW_101_HDR.tif`), Merge stays on, the announcement is
  "Reference RAW_103. Result RAW_103_HDR.tif.". The format changes only the
  extension; each box changes only itself. **The table holds one row:**
  `NSTableView.deselectAll` (what ⌘-click on the chosen row does) left row 1
  (RAW_101, the reference) selected; selecting row 2 through AppKit made
  RAW_102 the reference; deselecting again kept row 2. Closed and opened again:
  RAW_102, both boxes on (AC3c, AC9a).
- **The folder refusal follows the reference** (`TwoFolders-0`): opens refused,
  "The merged photo would be saved next to “TWOFOLDERS_102”, in “Locked”, …",
  that row flagged, Merge off. Row 3 (`Open`): no message, Merge on, Name
  `TWOFOLDERS_103_HDR.tif` in `…/Open`, announcement "… Merge is available.".
  Row 1: refused again naming TWOFOLDERS_101, its row flagged, the message
  announced (AC12). With `merge slowdisk 1500`: `merge reference 3 nowait`
  leaves Merge off while `Open` is asked; choosing row 2 meanwhile and then row
  1 after the delay prints "discarded Open": the late answer decided nothing.
- **Merges** (`merge start` after each choice): the +2 EV frame as reference
  writes `Raw-0/RAW_103_HDR.tif` (details Reading, Aligning, Merging, Saving,
  Adding; bar ends 1.000). `Unrelated-0` with Auto-align on fails: "“UNRELATED_103”
  doesn't line up with “UNRELATED_102”. Merge photos of the same scene, or turn
  off Auto-align." (Reading, Aligning; nothing written). The same with
  Auto-align off merges `UNRELATED_102_HDR.tif` (Reading, Merging, Saving,
  Adding: no Aligning; bar ends 1.000; H20). `TwoFolders-0` with the `Open`
  frame chosen and De-ghost off writes `Open/TWOFOLDERS_103_HDR.tif`, nothing in
  `Locked`. (Tone mapping takes a few milliseconds; the 5 ms poll doesn't catch it.)
- **Height** (H21): `merge sheet` at three frames prints `sheet 560x600 (ideal
  600) form content 590 shown 474 scrolls true`: the default case scrolls by
  116 pt (with the two-line folder refusal in the header, 442 shown). With 20
  frames (the table at its 250 pt cap) the content is 740. Ruled D-H11 and
  fixed: see "Design review of the revision" below (now 517 against 522).

### For a person

Design §16's M8 to M14 (the sheet's look at the default size and with nine
frames; choosing by pointer, ⌘-click and the empty space under the rows;
choosing by keyboard with Full Keyboard Access, Return with the table focused;
the folder refusal following the reference, the spinner on a slow volume;
a real merge with the +2 EV frame as reference compared by eye with the
default; the two boxes on real files; the height on a 13-inch laptop and in a
short window). M12 and M13 also with a JPEG bracket (the camera's own JPEGs,
not raws) of a scene with a bright window or sky, the brightest frame as the
reference, De-ghost on: no clipped band along the bright area's edge, and
compared with De-ghost off where nothing moved (code review C14; the fixture
can't stand in for a real camera's curve). In M12 and M13, with De-ghost on,
also look at 100% along the outline of whatever moved (the walker, with the
default and with the darkest and brightest reference): no colored speck on the
outline where something moved (code review C18). Initial focus: D-H13 withdrew "focus on Merge"; what to check
is M10 (Return and Esc with the table focused: after a click on a row, after
Tab, on opening). After the design review's fixes also M15 (each caption
inside its control's group row, no divider between them; no "Photos" header
over the table; the Name line gray while a refusal shows, black when Merge is
on) and M16 (with a bracket of RAW+JPEG pairs shown as their JPEG, choosing
another frame changes the header thumbnail; scripted, see below, but not seen).

### Deviations from the design, and choices it left open

- **Name line with a refusal.** Before this revision the Name read "—" while a
  refusal from the selection stood. §5.3 and §5.8 give the line no exception
  (it is "the name the file will get now", following the reference), and the
  announcement after a change says "Result ‹name›", so the line now always
  shows the reference's name (numbered once its folder has answered; the
  unnumbered candidate meanwhile, and if the folder can't be listed or the
  record is damaged, where pressing Merge says why). Confirmed by the designer
  (D-H12), now in secondary color while a refusal shows (F7).
- **Table selection held by the view.** `Table(selection:)` is bound to a
  `@State` row that follows the model's reference and is put back when the
  table clears or the model refuses it (§5.5's engineer note). The debug script
  shows it holding on this Mac (above); whether a one-frame flicker shows on a
  real ⌘-click is M9's.
- **Check box caption indent**: 20 pt (a regular check box and its gap), one
  constant (`OptionBox.captionIndent`), not a system metric; M8 judges it.
- **Initial focus** (§11: Merge when enabled, else Cancel) is not set by code,
  as before this revision; with the table now selectable the system may focus
  it first. Ruled D-H13: not set by code, as built.

### Design questions

- **DQ-H11, the sheet's height at three frames.** Measured: 560 x 600, the
  Form's content 590 pt against 474 shown (header 72 + buttons and divider
  about 54), so the default case scrolls by 116 pt; the design estimated 580
  in all (§5.7's budget puts the Form at about 450). The grouped Form's rows on
  this macOS are taller than the estimate, and each caption is a row of its
  own. §5.7's remedies don't reach: the check box captions are one line each,
  so shortening their words saves no height, and the cap of 640 still leaves
  76 pt. Options and their cost:
  (a) ideal height about 720 (content 590 + 126): no code beyond one constant,
  but past the 640 cap and taller than two thirds of a 13-inch laptop's screen;
  (b) captions as `Section` footers or folded into their control's row (the
  Format caption under the picker, the reference caption as the table's
  footer): a few lines of code each, saves perhaps 20 to 30 pt a caption,
  changes the reading order and look the design set;
  (c) keep 600 and accept scrolling at three frames (as built; the header and
  buttons stay put, the boxes are below the fold);
  (d) the two check boxes side by side in one row, or the Result caption
  joined to the Folder row: a row saved each, against §5.6's and §5.3's
  layout.
  Recommendation: (b) for the reference caption (table footer) and the Format
  caption, then measure, and raise to 640 only for what remains; otherwise (c).
  The ideal height stays 600 as the brief said until this is ruled.
  **Ruled 2026-11-21 (D-H11): (b) carried through; built, see below.**

### Design review of the revision (2026-11-21)

From `review.md` (section "Revision review, 2026-11-21") and `design.md` §20
D-H11 to D-H13.

| Finding | What changed | Check |
|---|---|---|
| F6 / D-H11 (1) | The Photos section's first Form row is one `VStack(spacing: 6)` of the table, the reference caption and, when it applies, the same-exposure note; the two check boxes stay their own rows | `merge sheet` (below); by reading `MergeForm` |
| F6 / D-H11 (2) | Format is one row: `VStack(spacing: 4)` of `LabeledContent("Format")` holding the segmented picker (`.labelsHidden()`, accessibility label "Format") and the format's caption | `merge format dng` prints the DNG caption; by reading |
| F6 / D-H11 (3) | Folder and the result caption (with the several-folders sentence when it applies) are one row, `VStack(spacing: 4)`; Name stays its own row above | `merge sheet` on `TwoFolders-0` shows the folder and both sentences; by reading. The spacing 4 for this row is mine (D-H11 names none for it; I used item 2's) |
| F6 / D-H11 (4) | The result caption reads "The originals are not changed, and your adjustments are not used."; the catalog key replaced and the old one removed | `LocalizationTests` pass; the bundle's `Localizable.strings` has only the new text |
| F6 / D-H11 (5, 6) | Measured, cut, `idealHeight` set: see "Height" below. Cuts i (no "Photos" header; the table keeps "Photos" as its accessibility label) and ii (`MergeSheetMetrics.barPadding` 12, was 14) applied in order; neither brought the computed ideal to 640 or under, so cut iii: `idealHeight` 640. Check box and Format captions not shortened | `merge sheet` at three frames: `scrolls false` |
| F7 / D-H12 | The Name line is secondary while it is the unnumbered candidate or a refusal shows (`MergeModel.resultNameIsTentative`, read by the view and by the debug script, which marks it `(secondary)`); "—" while the frames are read stays as before | `merge sheet` on `TwoFolders-0` (folder refusal) and `Mixed-0` (mixed kinds): name printed with `(secondary)`; choosing the `Open` frame on `TwoFolders-0` prints it without |
| F8 | The grid holds only the half of a pair it shows; the default is the RAW (`imagePair.showsCompanion` false), but RAW+JPEG Pair ▸ Show JPEG makes it the JPEG, and then the header thumbnail stayed the first target's whatever the reference. `MergeModel.loadPreview` now falls back on `MergeSelection.item(showing:in:)`: the target whose `versionID` or `partnerVersionID` is the reference, then the first target | Unit tests `MergePreviewItemTests` (pairs shown as JPEG, as RAW, single files, unknown reference, no items). Debug script on a scratch library of three RAW+JPEG pairs (Raw-0's DNGs with Jpeg-0's JPEGs renamed beside them): shown as RAW, the thumbnail is `RAW_102.dng`, `RAW_103.dng`, `RAW_101.dng` as the reference moves; after `pairfile jpeg`, `RAW_102.jpg`, `RAW_103.jpg`, `RAW_101.jpg`. `merge sheet` and `merge reference` now print the thumbnail's file. Not run against the build before the fix |
| D-H13 | Nothing to remove: no code sets the sheet's initial focus (no `defaultFocus`, `focused` or first-responder call in the sheet). Merge has `.keyboardShortcut(.defaultAction)` and Cancel `.cancelAction`, so whichever control has the focus, Return goes to Merge (when on) and Esc to Cancel unless the focused view takes the key first; whether the table's `NSTableView` lets Return through can't be read from the code or driven by the script (no key window from a shell launch) | Manual M10 |

**Height** (H21), measured with `merge sheet` on a copy of the bundle
(`me.sesser.gus.debugtest.merge`) and a fresh scratch library from `photobench
generate --brackets 1` per run, every launch with `--library-root`:

| Step | Form content at three frames | Chrome (header, dividers, buttons) | Content + chrome + 20, rounded up to 10 |
|---|---|---|---|
| Before (d9b1461) | 590 | 126 | 740 |
| Folds and the caption cut (D-H11 1 to 4) | 543 | 126 (600 - 474 shown, confirms D-H11's 126) | 690 |
| Cut i: no "Photos" header | 517 | 126 | 670 |
| Cut ii: header and button padding 12 | 517 | 118 (640 - 522 shown) | 660 |
| Cut iii: `idealHeight` 640 | 517 | 118 | 640, `sheet 560x640 form content 517 shown 522 scrolls false` |

So the default case does not scroll: the 20 pt of slack D-H11 asks for is 5 pt
at the cap. What still scrolls, as D-H11 item 7 accepts: a two-line refusal
(`Mixed-0`, mixed kinds: 517 against 504 shown, 13 pt) and the two-line folder
refusal together with the several-folders sentence (`TwoFolders-0`: 531 against
490, 41 pt). The Raw, Jpeg and Unrelated series all measure 517 against 522.
The same-exposure note (no fixture series has it) and more frames scroll too.

Also re-run on the new bundle, unchanged: choosing rows by name and number (the
Name, Folder, flagged rows, Merge on, the announcement and the discarded-answer
line as before), Cancel, and the folder refusal following the reference on
`TwoFolders-0`.

### Sixth review pass (2026-11-21, `code-review.md` "Sixth pass")

`079bf79` and the Core Image files are untouched (that fix moves to bug #253's
branch).

(Item 2 below and the black test of item 1 were revised in the seventh pass,
C17 and C18: see "Seventh review pass".)

**C14 (Should fix): de-ghosting a still JPEG bracket with an extreme
reference.** Fixed as the review suggested, both halves
(`MergeGhosts.disagreement`, `masks`, `usableElsewhere`):

1. The black-frame test reads the frame's black level, not its crushed values:
   the frame disagrees where the reference's lowest value around is above
   `lowF / exposure × 1.5`. The clipped-frame test is unchanged
   (`frame.low / exposure > reference.high × 1.5`): a shoulder lifts a
   clipped frame's unclipped neighbors, which the frame's lowest value
   already bounds, and the shoulder case below shows no mask.
2. The two tests that rest on the frame's own black or clipping go into a
   plane of their own, cleaned (3 x 3 majority) and grown as before, and are
   kept only where some other frame's brightest channel is within `trusted`
   of its clipping level. They can fire only where the reference is neither
   black nor clipped all around (the reference's own one-sided tests come
   first), so this removes only what growth and feathering carried past the
   evidence. Item 1 alone left the S-curve case below worse than the rule
   before `be5bf92` (98 pixels moved where the reference clips, worst 29%);
   with item 2 it matches it. The extra cleaning and growth run only for a
   frame where one of those tests fired; not timed.

New test `MergeChoicesTests.stillNonLinearBracket` (in `HDRMergerTests`): a
still −2/0/+2 EV bracket with a camera-like response (toe `L·L/(L + c)`, c
0.01 and 0.005; shoulder `L·(1 + s)/(L + s)`, s 1), each frame as the
reference; no pixel may move by more than 1% against the same plan with no
masks, anywhere and where the reference clips. On `c1d10c3` it fails with 5
issues (toe 0.01 with the default and the +2 EV reference, toe 0.005 with +2
EV); it passes now. Measured (mask pixels per frame; pixels moved by over
1%, of them where the reference clips; worst relative change):

| Response, reference | Rule before `be5bf92` | `c1d10c3` | Now |
|---|---|---|---|
| toe 0.01, −2 EV | none | none | none |
| toe 0.01, 0 EV (default) | none | [5560, 0, 0]; 41, 0; 0.39 | none |
| toe 0.01, +2 EV | none | [146291, 2086, 0]; 1637, 1067; 0.95 | none |
| toe 0.005, −2 or 0 EV | none | none | none |
| toe 0.005, +2 EV | none | [130529, 0, 0]; 439, 34; 0.93 | none |
| shoulder 1, every reference | none | none | none |
| toe 0.01 and shoulder 1, −2 EV | [0, 0, 16096]; 15183, 0; 0.50 | the same | the same |
| toe 0.01 and shoulder 1, 0 EV | [15910, 0, 1859]; 1437, 0; 0.42 | [76930, 0, 1859]; 2321, 114; 0.54 | as before `be5bf92` |
| toe 0.01 and shoulder 1, +2 EV | [17273, 33010, 0]; 23559, 66; 0.13 | [163458, 65555, 0]; 37737, 2279; 0.94 | [17273, 33787, 0]; 24152, 66; 0.13 |

("none": no mask pixel, nothing moved.) The S-curve rows are not in the test:
there the two-sided test sees still mid-tones disagree under every rule
(response recovery is the proposed follow-up). The default reference is now
untouched by the toe (it was 41 pixels, worst 39%).

The linear walker, where the point of `be5bf92` was (object error inside the
reference's object / ghost error at the other frames' places / difference
from the clean merge where nothing moved), is unchanged by C14:

| Bracket, reference | `c1d10c3` | Now |
|---|---|---|
| ±2 EV, 0 EV (`ghostFree`) | 0.0 / 0.0076 / 0.0 | 0.0 / 0.0076 / 0.0 |
| ±2 EV, −2 EV (`extremeReferences`) | 9.3e-8 / 0.0052 / 0.0 | 9.3e-8 / 0.0052 / 0.0 |
| ±2 EV, +2 EV (`extremeReferences`) | 0.0 / 0.00011 / 0.0 | 0.0 / 0.00011 / 0.0 |
| ±1 EV, −1 EV (`ghostsFollowTheReference`) | 1.3e-7 / 0.0057 / 0.0 | 1.3e-7 / 0.0057 / 0.0 |
| ±1 EV, +1 EV (`ghostsFollowTheReference`) | 9.3e-8 / 0.00026 / 0.0 | 9.3e-8 / 0.00026 / 0.0 |

Only some mask sums moved, at the objects' edges, because the bound tests are
now cleaned on their own (±2 EV default: frame +2 6820.6 → 6768.0; ±1 EV,
−1 EV reference: 6711.7 and 6712.7 → 6617.6 and 6482.1); every error above is
the same to the printed digit.

A probe not kept as a test, the walker with a toe (c 0.01 and 0.005), each
reference: the ghost error at the other frames' places is 0.37, 0.41 and
0.0092 (c 0.01; references −2, 0, +2 EV) and 0.28, 0.31 and 0.0085 (c 0.005),
the same under the rule before `be5bf92`, under `c1d10c3` and now. That is
the toe's own disagreement between frames (an area taken from fewer frames
differs in tone from the blend of all), not an object left behind; the masks
cover the objects under every rule.

**C15 (Nit, no change asked).** Noted: a tolerance correction goes in a
commit of its own with a one-line reason from now on.

**C16 (Nit): the slow-disk spinner across reference changes.** The rule moved
into `MergeSheetState` (PhotoCore), so it can be tested: `spinner` is
`hidden`, `waiting(n)` or `shown`. `decideSpinner(restart:)` runs after the
disk is asked, after each answer, and on every change of reference
(`restart` true): hidden as soon as the disk has answered for the current
reference; otherwise a new numbered half-second wait starts (on a change of
reference, or when none runs), unless the spinner already shows, which stays
rather than blinking. `spinnerWaitEnded(n)` shows it only if wait `n` is still
the current one and the disk hasn't answered, so a wait that ended for an
earlier reference holds nothing and blocks nothing. `MergeModel` keeps only
the timer (`slowTask`, replaced or cancelled on each decision) and reads
`isCheckingSlowly` from the state. Tests: `spinnerHidesForAnAnsweredFolder`
(trace A: slow folder, spinner on, back to an answered folder: hidden at once,
Merge on, the slow folder's late answer changes nothing),
`spinnerWaitsAgainForEachCheck` (trace B: slow /c, back to answered /a within
the half second, the first wait ends and shows nothing, then slow /b: a new
wait and the spinner after it; /c's late answer leaves it, /b's hides it),
`spinnerAcrossPendingFolders` (two folders still being asked: the wait
restarts; back to one being asked with the spinner on: it stays). The tests
pin the new rule; the old one lived in the app target, which `swift test`
doesn't load, so they can't be run against it. `print merge` now prints the
sheet's reference, disk state, Merge and the spinner; `merge sheet` and
`merge reference … nowait` print the spinner.

**Results.** `swift build` clean, no new warnings. Full `swift test`: 1346
tests in 194 suites passed (676.7 s; the four new: `stillNonLinearBracket` and
the three spinner tests). No golden moved, `UPDATE_GOLDENS` not run,
`PreviewCacheKey.currentPipelineVersion` unchanged (13); merges are new files,
so nothing cached or stored changes. `Scripts/build-app.sh` builds.

**Debug-script checks (sixth pass)**, on a copy of the new bundle
(`me.sesser.gus.debugtest.merge`, re-signed ad hoc) and fresh copies of a
scratch library from `photobench generate --output $S/src --jpeg 2 --dng 0
--heic 0 --videos 0 --brackets 1` and `photobench import`, every launch with
`--library-root`:

- Trace A (`search TWOFOLDERS; wait 1; selectall; merge sheet; merge slowdisk
  3000; merge reference 3 nowait; print merge; wait 0.8; print merge; merge
  reference 2 nowait; print merge; wait 3; print merge`): `Open` checking with
  the spinner off, then on after the pause; back to TWOFOLDERS_102 (`Locked`,
  answered at open): `disk answered … spinner off` at once, and still off after
  `Open`'s late answer. (Merge stays off there because `Locked` is read-only;
  the fixture has no second writable folder.)
- Trace B, with two folders (`merge reference 3 nowait; merge reference 2
  nowait; wait 0.8; print merge; merge reference 3 nowait; print merge; wait
  0.8; print merge; wait 3; print merge`): after the first wait ended on the
  answered reference, spinner off; back to `Open`, still being asked from the
  first visit (no new folder check, which is where the old code started no
  timer): off at once, **on** after the pause, then `disk answered merge on
  true spinner off` when `Open` answers.
- Merges still run: `Jpeg-0` with JPEG_103 (+2 EV) as reference and `Raw-0`
  with the default, De-ghost on, both written beside their reference. The
  fixture's JPEGs have no camera curve (linear light through the sRGB profile),
  so they are no eye check for C14; that is M12/M13 on a real camera's JPEGs.

### Seventh review pass (2026-11-21, `code-review.md` "Seventh pass")

C14 and C16 closed; two nits on C14's fix, both fixed in one change to
`MergeGhosts` (`079bf79` and the Core Image files untouched).

**The rule now.** `MergeGhosts` is `c1d10c3`'s again (one disagreement plane,
cleaned and grown together) with one line changed, the black-frame test:
`reference.low > max(frame.high, lowF) / exposure * 1.5` (the reviewer's
suggestion for C17). The sixth pass's separate plane for the frame-bound tests,
and `usableElsewhere`, are gone (C18).

**How it was chosen.** Five variants measured side by side on the fixture
(probe not kept as a test), then the rules of `c1d10c3` and before `be5bf92`
as baselines: V0, the sixth pass (`e787efe`); V1, V0 with the new black test;
V2, one plane with the new black test, with the sixth pass's restriction only
where the reference clips and no other frame is trusted; V3, the same
restriction wherever no other frame is trusted; V4, one plane with the new
black test and no restriction. V1 and V3 keep the rim leak. V2 and V4 gave the
same numbers in every case measured, so V4, the one with less code, is the
rule. With the new black test the separate plane bought nothing: the S-curve
case that item 2 was for comes out as with the rule before `be5bf92` with one
plane too (the reviewer's 30,612 for one plane was with the sixth pass's black
test).

**C17, noise (still linear bracket, σ 0.004).** Pixels moved by over 1%
against the same plan with no masks, darkest / default / brightest reference:

| Bracket | Rule before `be5bf92` | `c1d10c3` | `e787efe` | Now |
|---|---|---|---|---|
| ±2 EV, alignment on | 769 / 9 / 99 | the same | 769 / 30 / 108 | 769 / 9 / 99 |
| ±3 EV, alignment on | 12163 / 430 / 547 | the same | 12163 / 533 / 673 | 12163 / 430 / 547 |
| ±2 EV, alignment off | 0 at the default (review) | 0 at the default (review) | 767 / 94 (worst 3.0%) / 230 | 767 / 0 / 77 |
| ±3 EV, alignment off | 431 at the default (review) | | 12440 / 766 / 950 | 12440 / 431 / 545 |

New test `stillNoisyBracket` (±2 EV, default reference, alignment off: nothing
moves); it fails on `e787efe`. The darkest-reference numbers are the same under
every rule: a separate, older matter (proposed follow-up "De-ghosting with the
darkest frame as reference reads noise in the deep shadows").

**C18, the rim.** `ghostCheck` now also measures each other frame's whole
disc and the masks' growth around it (`rim`, worst relative difference from the
clean merge, and `rimOver`, pixels over 5%), beside the 11 x 11 core. Pixels
over 5% / worst, the walker (linear):

| Bracket, alignment, reference | Rule before `be5bf92` | `c1d10c3` | `e787efe` | Now |
|---|---|---|---|---|
| ±1 EV, on, 0 EV (default) | 2953 / 64x | 0 / 0.008 | 4 / 2.41x | 0 / 0.008 |
| ±1 EV, off, 0 EV | 2876 / 64x | 0 / 0 | 2 / 21.2x | 0 / 2.4e-7 |
| ±2 EV, on, 0 EV | 33 / 24.5x | 0 / 0.009 | 0 / 0.016 | 0 / 0.0085 |
| ±2 EV, off, 0 EV | 56 / 27.1x | 0 / 0 | 1 / 10.4x | 0 / 2.4e-7 |
| ±1 EV, on and off, −1 EV | 2969 and 2876 / 63x | 0 | 0 | 0 |
| ±1 and ±2 EV, on and off, the brightest | 0 | 0 | 0 | 0 |
| ±2 EV, on and off, −2 EV | 44 and 56 / 24x to 26x | 0 | 0 | 0 |

The core, object and elsewhere figures of every walker case are as in
`c1d10c3` and the sixth pass (to the printed digit), and the mask sums are
`c1d10c3`'s again (±2 EV default: [6734.6, 0, 6820.6]). Tests: `rimOver == 0`
added to `ghostFree`, `ghostsFollowTheReference` and `extremeReferences`, and
the new `outlinesWithoutAlignment` (±1 and ±2 EV, each reference, alignment
off: object, core and rim); it fails on `e787efe`.

**Still non-linear brackets** (alignment on; moved by over 1%, of them where
the reference clips, worst), the brightest reference unless named:

| Response, bracket | Rule before `be5bf92` | `c1d10c3` | `e787efe` | Now |
|---|---|---|---|---|
| toe 0.01, 0.005; shoulder 1; ±2 EV, every reference | none | up to 1637 / 1067 / 95% | none | none |
| toe 0.02 and 0.05, ±2 and ±3 EV, every reference | none, except at ±3 EV: 7883 / 0 / 69% (toe 0.02, −3 EV), 414 and 688 / 0 / under 2% (0 EV) | up to 4970 / 4553 / 99% | as before `be5bf92` | as before `be5bf92` |
| shoulder 0.3, ±2 EV | 28366 / 28338 / 16315 moved, none where the reference clips | the same | the same | the same |
| S (toe 0.01, shoulder 1), ±2 EV | 23559 / 66 / 12.6% | 37737 / 2279 / 94% | 24152 / 66 / 12.6% | 23559 / 66 / 12.6% |
| S, ±3 EV | 52796 / 620 / 38.8% | 84412 / 3774 / 97.7% | 68201 / 872 / 38.8% | 57188 / 657 / 38.8% |

The one case where the rule now does worse than before `be5bf92` is the
S-curve at ±3 EV with the brightest reference (4,392 more pixels moved, 37 more
where the reference clips, the same worst). It is the case the two-sided test
already gets wrong under every rule (the response-curve follow-up), and the
`be5bf92` rule there fails the linear walker (above). The shoulder-only rows
are the two-sided test reading a shoulder, the same under every rule.

**Cost.** One plane again: the ghost step is `c1d10c3`'s (the reviewer timed
the sixth pass's second plane at up to +45% in a debug build).

**M12 and M13** now also ask for no colored speck on the outline of what moved
(see "For a person" above).

**Results.** `swift build` clean, no new warnings. Full `swift test`: 1348
tests in 194 suites passed (672.9 s; new: `outlinesWithoutAlignment`,
`stillNoisyBracket`). Both new tests fail on `e787efe` (rim 2 pixels at 21.2x
and 1 at 10.4x; 94 pixels moved, worst 3.0%). No golden moved, `UPDATE_GOLDENS`
not run, pipeline version unchanged (13). `Scripts/build-app.sh` builds; on a
copy of the bundle with its own identifier and a scratch library
(`--library-root`), `Raw-0` merges with the darkest frame as reference, De-ghost
on, written beside it.

### Eighth review pass (2026-11-21, `code-review.md` "Eighth pass")

C17 and C18 closed. The owner ruled C19 fixed on this branch.

**C19 (Should fix): the reference-black test read the reference's noise.**
Where the reference's light is just above its black level, its noise drags
its 3 x 3 minimum under that level; the pixel then goes to the one-sided
reference-black test, which compared a brighter frame with the black level
(`lowR × 1.5`) instead of with what the reference holds. Now
`frame.low / exposure > max(reference.high, lowR) * 1.5`, the reviewer's
candidate: never looser than before (it fires only where the old test fired),
and the mirror of C17's black-frame test. One line in `MergeGhosts`.

Re-measured, every case of the seventh pass's tables, `a175ef2` → now
(the same probe as before, not kept as a test).

Noise σ 0.004, still linear bracket, pixels moved by over 1% against the same
plan with no masks, darkest / default / brightest reference:

| Bracket | `a175ef2` | Now |
|---|---|---|
| ±2 EV, aligned | 769 / 9 / 99 | 0 / 9 / 99 |
| ±2 EV, unaligned | 767 / 0 / 77 | 0 / 0 / 77 |
| ±3 EV, aligned | 12163 (worst 11.4x) / 430 / 547 | 1870 (worst 4.7x) / 430 / 547 |
| ±3 EV, unaligned | 12440 (worst 13.5x) / 431 / 545 | 2071 (worst 9.6x) / 431 / 545 |

The ±3 EV residual with the darkest reference, measured by counting each test's
raw disagreeing pixels (before cleaning, both other frames, aligned): the
reference-black test 0 now (4,777 before), the frame-black test 45, the
two-sided test 3,362 (the same before). So what is left is the two-sided test
reading the darkest frame's noise where its light is a few σ above its black
level, which the proposed follow-up's noise model is for (its title and
mechanism as the reviewer corrected them). The default and brightest
references' counts are those of every rule before.

Still non-linear brackets (aligned; moved / where the reference clips / worst;
darkest, default, brightest reference):

| Response, bracket | `a175ef2` | Now |
|---|---|---|
| toe 0.01, toe 0.005, shoulder 1, ±2 EV | none | none |
| toe 0.02 and 0.05, ±2 EV | none (toe 0.02 brightest: worst 0.4%) | the same |
| toe 0.02, ±3 EV | 7883 / 0 / 69%; 414 / 0 / 1.6%; none | the same |
| toe 0.05, ±3 EV | none; 688 / 0 / 1.9%; none | the same |
| shoulder 0.3, ±2 EV | 28366; 28338; 16315 (none where the reference clips) | the same |
| S (toe 0.01, shoulder 1), ±2 EV | 15183 / 0 / 49.5%; 1437 / 0 / 42.5%; 23559 / 66 / 12.6% | 15183 / 0 / 49.5%; **97 / 0 / 1.6%**; 23559 / 66 / 12.6% |
| S, ±3 EV | 28606 / 0 / 83%; 70541 / 0 / 63%; 57188 / 657 / 38.8% | **25521** / 0 / 83%; **59727** / 0 / 55%; 57188 / 657 / 38.8% |

Walker (linear), ±1 and ±2 EV, alignment on and off, each reference: core,
object and elsewhere unchanged to the printed digit; rim 0 pixels over 5% in
all 12 cases, worst 0.0085 aligned (±2 EV, default reference) and under 3e-7
unaligned. Two mask sums moved by about a pixel's worth, with no error moving:
±2 EV aligned, default reference, frame +2 6820.6 → 6819.5; ±1 EV aligned,
default reference, [6763.6, 0, 6885.2]. Nothing regresses anywhere.

**Tests.** `stillNoisyBracket` now has five cases: the default reference at ±2
EV unaligned (nothing moves, C17); the darkest reference at ±2 EV, aligned and
unaligned (nothing moves); the darkest at ±3 EV, aligned and unaligned (at
most 1% of the frame, 2,400 pixels: the residual's order, 1,870 and 2,071,
against 12,163 and 12,440 before; a bound that records the residual rather
than one derived from the noise, which needs the follow-up's model). On
`245c415`'s rule it fails in the four darkest-reference cases (769, 767,
12,163 and 12,440 moved);
it passes now.

**C20 (Nit).** The rim's worst in the A13 paragraph now reads 0.0085 (±2 EV
aligned, default reference), as the C18 table says; 0.016 was `e787efe`'s.

**Results.** `swift build` clean, no new warnings. Full `swift test`: 1348
tests in 194 suites passed (712.2 s). No golden moved, `UPDATE_GOLDENS` not
run, pipeline version unchanged (13); merges are new files. `Scripts/build-app.sh`
builds.

## Bug: tiles at 100% (owner sign-off P5, 2026-11-21)

**Report.** `IMG_3894_HDR.tif` (a merge of five Canon EOS 6D CR2s, 5472 × 3648,
16-bit Display P3 TIFF written by the merge), with Exposure +1.05, Contrast
+66, Highlights −45, Blacks −100: fine at Fit; at 100% the picture showed two
halves that didn't line up, the left part a different place in the photo than
the right, with a hard vertical seam. TIFFs merged from GX85 frames
(4592 × 3448) did not show it for the owner.

**Steps to reproduce** (before the fix, macOS 27.2, Apple silicon).
1. A copy of the owner's file in a scratch folder, a scratch library and a
   bundle copy with its own identifier (`me.sesser.gus.debugtest.tiles`):
   `windowsize 2200 1300; addfolder <copy>; waitimport; focus 0; loupe;
   adjust exposure 1.05; adjust contrast 66; adjust highlights -45;
   adjust blacks -100`, then eight times `zoom; wait 2; pan 2400 0; wait 7;
   snapshot …; zoom; wait 3`.
2. Headless: render a 5472 × 3648 (or 4592 × 3448) TIFF or PNG with
   Highlights −45 or any Shadows at full size, several times
   (`PreviewGenerator.cgImage`, the loupe's 100% rendition).

**Expected.** The photo at 100%, the same every time.

**Actual.** In the app, 8 of 8 zooms showed the seam: left of x = 2736 (half
the width) the view showed pixels from the photo's right part. Headless, about
one render in three came out with the left half repeating the right (7 of 24,
12 of 36, 8 of 30 in separate runs), at 4592 × 3448 as often as at
5472 × 3648, for PNGs and TIFFs written by other means too, and at
6000 × 4000 and 8192 × 5464. Which process gets it is timing (one run of
5472 × 3648 had 0 of 8, the next 4 of 12): the GX85 merges not showing it for
the owner is that timing, not their size.

**Root cause.** Not our TIFF writer, not Canon data: the owner's file and a GX85
merge have the same layout (uncompressed chunky 16-bit RGB strips, Display P3,
orientation 1, 300 ppi; only the size and ImageIO's RowsPerStrip differ), and a
PNG fails the same way. It is a fault inside Core Image, seen from outside with
`CI_PRINT_TREE=4`:
- A full-size render of this size to a GPU destination is split into two parts
  (`render_to_surface … rois=[0 0 5472 3648]/2`, `intermediatesLimit=256MB`).
- The full-size decode was `CIImage(contentsOf:)`, which Core Image reads from
  the CPU: each part copies its share of the file into a pooled texture
  (`CGImageRef … rois=[0 0 2939 3648],[2533 0 2939 3648]`).
- Local tone (Shadows, negative Highlights) reads the photo in several programs
  per part. Now and then the right part's copy lands before the left part's
  programs have read theirs: the right part's pixels under the left part's
  own gain, which is the signature in the bad renders.

Measured to separate the causes (same process, fresh engines, Highlights −45):
the same graph over a texture, still split into the same two parts, 0 of 30;
the file read directly 8 of 30; a render to a bitmap (which reads each part
back) 0 of 69; the gain image alone 0 of 24. The copy of the file into a
texture is itself such a split render (`render_to_texture … /2`), and
`LiveRegionRenderer.materialize` (the 100% base for live frames) made exactly
that copy: a second route to the same seam.

Tried and not kept, with the reason:
- A `CGImage` from `CGImageSourceCreateImageAtIndex` instead of
  `CIImage(contentsOf:)`: clean on PNGs (0 of 36) but 8 of 16 on the 16-bit
  TIFF. It only changed the timing.
- Rendering in bands of 1 to 4 MP: no swaps on the owner's stack, but a stack
  with masks is still split inside a band (the masks' whole-photo estimates),
  each part copying the file. Cost +19 to +200%.
- A larger `CIContextOption.memoryTarget` (`kCIContextMemoryLimit`, macOS
  14): 1 GB keeps the owner's 20 MP render whole, but a stack with masks is
  split even at 2 GB.
- A copy in the file's own color space and encoding (16-bit unorm), meant to be
  read exactly as the file: bit for bit on the 16-bit TIFF, but JPEGs differed
  even unedited and straightened regions by up to 229 steps.

**The fix.** `PreviewGenerator.decodeWithImageIO` at full size copies the decode
into a 32-bit float texture in the working space (`ResidentDecode`, new), in
bands of at most 4 megapixels, each finished before the next starts (a copy
that small is never split), and the rest of every graph reads the texture: no
render reads the file from the CPU any more, however it is split. Every
full-size use goes through it: the loupe's 100% rendition, the 100% base,
export, `photocli render`, the sharpening map's refinement, the fringe picker.
`outputSize` (the loupe's early size) measures the lazy graph and stays a
header read (`forSizeOnly`). Previews and thumbnails are decoded smaller by
ImageIO and are untouched. Larger than 16384 pixels on a side (one texture's
limit), no Metal device, or a failed copy: the decode is read lazily as before,
logged.

The texture is rendered and read unflipped. Read through a flip transform (as a
first version did, and as `LiveRegionRenderer.materialize` did), a texture was
sampled one row off by run-time kernels: a heal's far pixels came out 0.4%
brighter on a gradient (`SpotTests.everyDecoderHeals` caught it), and the
100% renderer's crop-and-straighten region drifted from the whole render
(`LiveRegionRendererTests`, 12 values over tolerance). So
`LiveRegionRenderer.materialize` now fills and reads its texture unflipped
too; with both, that test is back to 6 steps at worst, under its tolerance.

**What changed in rendering** (measured on the owner's merge and a 20 MP JPEG of
it, file against copy, in 8-bit output steps):
- Unedited: bit for bit in float (`renderUnchanged`).
- The owner's stack, a heal, an export-style resize to 2048 px: at most one
  step. Core Image may place its half-float intermediates differently over the
  copy; `renderUnchanged` checks the owner's stack and a heal against the 100%
  renderer's derived tolerance (one half-float rounding times the stack's
  gain).
- Straighten 2° (alone or with the owner's stack): worst 20 to 37 steps at a
  few high-contrast edges, 0.01% to 0.15% of values more than one step off,
  mean under 0.08 of a step. Reading the file, Core Image interpolated its
  encoded values before linearizing them; the copy is linear, so resampling now
  interpolates linear light. Raws were always resampled so (their decode is
  linear), and so were the loupe's live frames at 100% (their base is a linear
  texture): the full-size render now agrees with them.

Half float instead of float32 would hold half the memory, but changed about a
third of the values of an edited render (up to 0.005). No golden moved (goldens
render their scenes from memory and a DNG). **No
`PreviewCacheKey.currentPipelineVersion` bump:** no cached preview or thumbnail
comes from this decode (they come from ImageIO's reduced decode, unchanged),
so nothing cached is stale. Full-size renders (the 100% rendition, exports,
`photocli render`) of straightened or rotated JPEG, HEIC, PNG and TIFF photos
change as above.

**Cost.** One more pass over the photo per full-size decode, and 16 bytes a
pixel of GPU memory held while it is in use (320 MB for 20 MP), released with
it. Measured for 20 MP, decode and render: TIFF 0.083 s against 0.073 s, PNG
0.36 s against 0.30 s, JPEG 0.09 s against 0.04 s.

**Existing merged files** need nothing: the file was never the cause. The
owner's `IMG_3894_HDR.tif` (copied to a scratch library) renders right at 100%
with the fix; re-merging is not needed. Merged DNGs go through #181's
`LinearRawDecode` and did not show the fault (0 of 24 renders of a
5472 × 3648 DNG written by `writeDNG`); unchanged.

**Tests** (`Tests/PhotoCoreTests/ImageIOFullDecodeTests.swift`, in
`MemoryHeavy`). Checked failing without the fix (the copy turned off in
`decodeWithImageIO`, two runs each):
- `fullDecodeIsResident`: the full-size decode of a TIFF and a JPEG no longer
  reads the file (`CIImage.url` nil; Core Image's own reader keeps it), and
  the measuring decode still does. Fails without the fix, deterministically.
- `largeRenderKeepsItsParts`: a 5472 × 3648 TIFF written by
  `MergeOutput.writeTIFF`, the owner's values, 16 renders on four fresh
  engines: no left half repeating the right, all the same. Without the fix:
  1 of 16 swapped, 15 of 15 unlike the first, in both runs.
- `residentCopyIsTheFile` (several bands give the file's values exactly),
  `renderUnchanged` (above), `bandsCoverTheExtent`, `fullDecodeIsOriented`
  (an EXIF-rotated JPEG renders as Core Image's own reading of it).

Existing tests changed: `LensAlignStaleAreaTests.tileSeesTheInputArea`'s JPEG
case (#228's guard) asserted that the pipeline's full-size JPEG could show a
stale input area, because its lazy decode rendered only the area asked. The
copy has every pixel, as a bitmap's, so that case now pins the opposite (no
area can be stale); the blurred-scene case remains the guard that the tests
can see a stale area. For code review to confirm.

**Debug-script check** (the commands of step 1 above, on the copied file): the
unfixed bundle showed the seam on 8 of 8 zooms; the fixed bundle (the final
build) on none of 8, all eight snapshots byte for byte the same.

**Not covered.** The HDR rendition of a gain-map or HLG/PQ photo
(`decodeHDR`) still reads `CIImage(contentsOf:)`; it renders to a bitmap,
which never showed the fault, but it was not soaked. Camera raws (system
decoder) were not soaked either; #181 found them stable. Photos larger than
16384 pixels on a side keep the lazy decode.

## CI on PR #258 (2026-11-22): fixed here, CI is the only confirmation

Run 45034608676 (after the merge of `develop`, `4f50003`, and Ship,
`2c4d93f`) failed on macOS 15 and macOS 26 in both attempts, each after the
workflow's own retry.

**The signal 11 is a crash in `HDRMergeJob.run`, not the runner's (#77).**
Every crash that left a record has the same frame (C24, corrected). The three
macOS 15 crash reports (artifacts `crash-reports-macos-15`, `.ips`,
`EXC_BAD_ACCESS` at 0x18), the two macOS 26 crash reports (artifacts
`crash-reports-macos-26`, `.ips`, SIGSEGV at 0x14) and both macOS 26
backtraces in the log (`Bad pointer dereference at 0x14`) show:

```
swift_task_dealloc (libswift_Concurrency)
closure #1 in default argument 4 of HDRMergeJob.run(_:format:options:progress:catalogue:)  HDRMergeJob.swift:128
closure #5 in HDRMergeJob.run(…)  HDRMergeJob.swift:246   (the Task.detached around catalogue)
completeTaskWithClosure (libswift_Concurrency)
```

Default argument 4 is `catalogue`'s `{ try await $0() }`, called inside
`Task.detached` once the file is written. The test that was running is the
first in the serialized `MemoryHeavy` suites, `HDRMergeJobTests.mergesToTIFF`
("AC2, AC3, AC5: …names a TIFF beside it…"). It started 1 min 45 s to
4 min 15 s before each crash (attempt 2, from the log's times: 4 min 15 s and,
in the retry, 3 min 32 s on macOS 15; 1 min 45 s and 3 min 18 s on macOS 26;
C24, corrected from "about 4 to 5 minutes") and never finished, on both systems
and in all four runs. The macOS 15 retry of attempt 2 left no report and no
backtrace, only "Exited with unexpected signal code 11". The test's
first `job.run` uses the default `catalogue`. The last test name printed before
the crash ("Distortion moves the grid's lines…") is only another suite's output
running in parallel. CI builds with Swift 6.2.4 (Xcode 26.3, macOS 15) and 6.3.3
(Xcode 26.6, macOS 26); here it is 6.4.2, where the same tests pass. So this is
a toolchain-dependent fault at that call: a miscompile of an async
default-argument closure, or a task-allocator ordering fault in those runtimes.
It is not load: it happens at the first such call. It is also not limited to
tests. `photocli merge` (`MergeCommands.swift:84`) calls `run` with the default
`catalogue` too, so a `photocli` built with Xcode 26.3 or 26.6 would likely
crash on every merge. The app passes its own closure (`MergeModel`), a different
closure that no CI test covers. `develop` is green because it has no merge code.
No crash comes from memory: the merge core suite peaks at 627 MB resident here
(`/usr/bin/time -l`, 15 tests, 427 s, CPU-bound on one thread in debug).

**Options put to the main session** (option 1 ruled and built; see "The fix"
below):

1. **`catalogue` optional, default nil** (recommended). When nil, the detached
   task calls the catalog insert directly; with a closure, as now. No async
   closure is a default argument any more. The signature is source-compatible
   for both callers (the app passes `catalogue:`, `photocli` passes nothing),
   and behavior is the same. It can only be confirmed on CI (no 6.2 or 6.3
   toolchain here).
2. An overload without `catalogue` that passes an explicit closure literal.
   This is smaller, but the same closure shape may hit the same fault.
3. Pass an explicit `catalogue` in the tests only. Rejected: it hides the crash
   and leaves `photocli merge` exposed.

**The WorkLane failure (macOS 26, retry run) is #259, made worse by the
branch's long serialized suites.** On `develop`'s green run
`cancellingTheLastWaiterCancelsTheJob` already "passes after" 222 to 226 s, so
the pool is starved there too. The test's job slept 10 s and its waiters'
cancellation arrives through an unstructured task. On the starved pool that
task ran after the 10 s, so the job finished, the pending job ran, and all four
expectations failed. Here the whole suite now takes 729 s, with the
`MemoryHeavy` suites (serialized) as the critical path ("HDR merge job" 208 s,
"HDR merge core" 433 s, until now on a cooperative thread).

**Tests changed (no change under Sources):**

- `WorkLaneTests.cancellingTheLastWaiterCancelsTheJob` no longer depends on
  wall time (#259, fix 1). The running job waits on a gate that only
  cancellation opens, not a 10 s sleep. The pending job is cancelled once
  `lane.pendingCount` shows it queued, not after 20 ms. The job's own
  cancellation is awaited through a gate, not a 50 ms sleep. "A pending job
  with no waiters must not start" is checked after the next job has run
  (one slot: a pending job still queued would have run first). `WorkLane` is
  unchanged.
- Every test of the heavy merge suites (`HDRMergerTests` with
  `MergeChoicesTests`, `MergeDNGTests`, `HDRMergeJobTests`, `MergeCommandTests`,
  the reference and options suite, `MergeSafetyTests`, `MergeAlignmentTests`;
  53 tests) runs its body through `offCooperativePool`, so their synchronous
  renders and measuring hold a Dispatch thread, not one of the pool's three
  (#259, fix 2). They were already serialized (`MemoryHeavy`). The cheap merge
  suites (sheet, selection, rules, progress) are unchanged. No image size,
  tolerance or assertion changed.

Results of the tests-only change: `swift build` clean; full `swift test` 1427
tests in 205 suites passed (728.7 s); `Scripts/build-app.sh` builds.

**The fix (option 1).** `HDRMergeJob.run(…, catalogue:)` takes
`(@Sendable (@escaping @Sendable () async throws -> MergedMaster) async throws
-> MergedMaster)? = nil`. The insert is a named closure, and the detached task
calls `catalogue(insert)` when one is given, else `insert()` directly. No async
closure is a default argument any more, and the doc comment says why. Both
callers compile unchanged: the app's `MergeModel` passes its write-chain closure
and `photocli merge` passes none. Behavior is the same, including how errors
from either path map (`sameContent`, `alreadyInLibrary`).

- **Why toolchain specific.** The fault is in code the compiler generates for
  calling an async closure given as a default argument (the frame is "closure
  #1 in default argument 4"; the crash is inside `swift_task_dealloc`, the task
  allocator, when that closure's frame is torn down). It shows with Swift 6.2.4
  and 6.3.3 and not with 6.4.2, which is all this Mac has, so it can't be
  reproduced here.
- **`photocli` was exposed.** Its `merge` used the default and so would crash
  on every merge when built with Xcode 26.3 or 26.6. The app passes its own
  closure, which no crash frame names; no CI test runs the app target, so that
  is not proven either way.
- **Other default arguments of that shape: none.** A scan of `Sources/` (every
  parameter of function type with a `= { … }` default, outside the vendored
  LibRaw) found 47 matches. This was the only async one; the rest are
  synchronous. Async
  closures passed as literals at a call site (for example `MainActorWait`'s
  `sleep: { try? await Task.sleep(for: $0) }`) are a different shape and were
  left alone.
- **Tests.** The default path is every job test that calls `run` without
  `catalogue` (`mergesToTIFF` first). New `catalogueOptional`: a given closure
  is called once around the insert and its result is the job's; its
  `alreadyInLibrary` error still gives that version as `existingVersionID`; and
  without one the job catalogues directly. `refusedFileRemoved` still covers a
  given closure's `sameContent` (file removed only while its name holds it).
- **Confirmation.** Only CI can confirm the fix (no Swift 6.3 toolchain
  here; Swift 6.2.4 is, as Xcode 26.3, and was not used for this fix: C26,
  see "Test and CI time", "With CI's Swift 6.2.4"; the crash was on macOS 15's
  and 26's runtimes, which this Mac doesn't have either). Risk to watch there: with a signal 11 retry, the suite's length (about
  12 minutes here, more on the runners) and the 45-minute job limit. (Answered
  the same day: see "Test and CI time"; the suite takes about 78 s here now.)

Results after the fix: `swift build` clean, no new warnings; full `swift
test` 1428 tests in 205 suites passed (730.2 s); `Scripts/build-app.sh all`
builds both apps (the app's `MergeModel` call compiles unchanged).

## Test and CI time (2026-11-22): the merge suites from 11 minutes to 43 seconds

The owner's ruling on code review's C22: a 45 or 90 minute CI job is not
acceptable for a gating pipeline, so the limit is not raised; the tests get
faster instead, with every assertion, tolerance and image size kept. Measured
on this Mac (M4 Pro, 14 cores, Swift 6.4.2, debug builds, `/usr/bin/time -l`).

**State: Done here; CI is the confirmation.** One change is a build setting in
`Package.swift` that every debug build gets: it needs code review and the
owner's nod (see "Needs a decision").

### Where the time went (profile)

`sample` at 1 ms on the test process, one test at a time, before any change:

| Test (time before) | `HDRMerger.plan` (PhotoCore) | `HDRBracket.image` (PhotoFixtures) | Everything else |
|---|---|---|---|
| `ghostFree` (15.2 s) | 45% | 51% | 4% (the test's own loops) |
| `stillNonLinearBracket` (72.4 s; 9 plans) | 80% | 15% | 5% |
| `matchesReference` (15.9 s) | 39% | 22% | 39% (the tests' CPU reference, `MergeReference.radianceAndConditioning`, 36%) |
| `mergesToDNG`, a job test (6.3 s) | 58% | 36% (in `MergeLibrary.make`) | 6% (decoding, writing, the import) |
| `linesUpShiftedFrames` (18.3 s) | 20% (`MergeAlignment.align`) | 80% (three 1200 x 800 frames) | under 1% |

- **It is unoptimized Swift, not the amount of work.** One plan took 5 s for a
  600 x 400 copy (21 µs a pixel) and one fixture frame 0.95 s (4 s at
  1200 x 800). The self time is in `malloc`/`free`, the runtime's generic
  metadata lookups and range and array iterators: a debug build does not
  specialize generic or SIMD code, so every `SIMD3` sum, `min`, `max` and loop
  step is a call through a witness table. Inside `plan`: the ghost masks 55%
  (`Neighborhood.init` and its blur 39%), the rank sort for alignment 12%,
  exposures 10%, tone statistics 9%, clipping levels 8%.
- **Nothing is rendered twice by mistake, and little is repeated.** The core
  suite builds 41 plans, of which 2 share their inputs with another test, and
  about 145 fixture frames, of which about 30 are distinct. The 11
  `ghostCheck` cases and the 14 still-bracket cases each have their own
  bracket, reference or options.
- **Memory is not the limit.** The serialized chain alone peaks at 0.99 GB
  resident (1.28 GB after the change, with the same tests); the full run at
  5.95 GB before and 6.1 to 6.4 GB after.
- **In the full run the chain was the critical path**: every other suite ended
  by about 97 s, and the chain ran alone for the remaining 10 minutes, one
  thread, CPU-bound.

### What changed

1. **`Package.swift`: debug builds compile `PhotoCore` and `PhotoFixtures`
   with the optimizer** (`.unsafeFlags(["-O", "-assert-config", "Debug"],
   .when(configuration: .debug))`; `-assert-config Debug` since code review's
   C25, see "Review findings (eleventh pass)").
   Release builds are untouched. `@testable import` works as before (it needs
   `-enable-testing`, which stays). The flag follows SwiftPM's `-Onone` on the
   compiler's command line in both build systems (checked with `-v`: `-Onone
   -enable-testing … -O` with the native one, which the CI toolchains use), so
   it wins. This alone (measured with `-O` only, before C25): merge suites
   646.8 s to 57.6 s, full `swift test` 741.3 s to 93.1 s. The other suites gain too (they ended by 97 s, now by
   about 47 s). No test changed for it.
2. **`MergeReference.radianceAndConditioning` (tests' CPU reference)**: the
   two statements that built nine arrays per frame and pixel (the taps'
   brightest values and each channel's spread) now compute the same maxima
   and minima without arrays, and each tap's brightest channel is taken once
   instead of twice. 4.6 s to about 1 s a call. Same values: compared bit for
   bit with the function as it was (kept beside it for the comparison, then
   removed) on 960,000 pixels of four plans (the three the tests use and one
   with another reference): 0 differ in the light's three channels, the
   conditioning flag or the tolerance (5,635 unconditioned pixels and 220,167
   with a tolerance above 0 in the first, so both paths are exercised).
3. **`radianceError` (tests)**: the 5 x 5 neighbourhood test reads a luminance
   computed once per pixel, with `while` loops instead of two range loops
   (5.4 million range steps a call, 85% of the function). Same 25 values, same
   order, same comparison.
4. **`cancelLeavesNothing` (AC9)** now cancels from the job's own task when it
   reports Aligning (`withUnsafeCurrentTask`, as `ExportTests`,
   `CopyImportTests` and `OutputSizeTests` do), not from the test's task
   through a stream. Reason: with the library optimized, the measuring the
   cancel had to arrive within is 0.13 s here (3 s before); a busy runner can
   deliver it later, and the job would then finish. Same assertions. Passed 30
   of 30.

Every number the merge tests print (70 lines: measured exposures, clipping
levels, ghost-mask sums, rim counts, worst errors against the light and
against the CPU reference, alignment errors) is identical to the last digit
before and after, so the optimized measuring code gives the values the
unoptimized one gave.

### Results

| | Before | With `-O` (as first committed) | With `-O -assert-config Debug` (now) |
|---|---|---|---|
| Merge suites alone (`swift test --filter MemoryHeavy`, 59 tests) | 646.8 s, 642 s CPU | 40.2 s, 38 s CPU | 42.8 s (twice), 40 s CPU |
| "HDR merge core" | 430.2 s | 22.7 s | 24.3 s |
| "HDR merge job" | 130.2 s (208 to 224 s inside the full run) | 6.9 s (39 s inside the full run) | 7.3 s |
| "HDR merge job, reference and options" | 41.2 s | 2.3 s | 2.6 s |
| "photocli merge" | 19.9 s | 1.5 s | 1.5 s |
| "HDR merge alignment" | 18.3 s | 0.5 s | 0.6 s |
| Full `swift test` (1428 tests in 205 suites) | 741.3 s, 1,772 s CPU, 5.95 GB peak | 73 to 79 s (three runs), 513 s CPU, 6.1 GB peak | 77.8 s and 78.1 s, 521 to 535 s CPU, 6.1 to 6.4 GB peak |
| Clean debug build with tests | 34.3 s, 288 s CPU | 43.3 s, 391 s CPU | 47.4 s, 417 s CPU |

`swift build` clean with no new warnings (the two in `SmartAlbumTests.swift:165`
and `VirtualCopiesTests.swift:170` are `develop`'s); `swift test` 1428 tests
in 205 suites passed; `Scripts/build-app.sh all` builds both apps.

### Considered and not done

- **Sharing fixtures or merge results between tests, cutting ghost cases.**
  After the build change a fixture frame costs 20 ms and a plan 150 ms: all
  145 frames are 3 s, and only 2 of 41 plans are another test's. No case is a
  duplicate of another, so none was cut.
- **Running the chain's tests concurrently.** `MemoryHeavy` is serialized so
  that `ImportHashMemoryTests` never measures a merge's frames (QA Q3), not to
  cap memory. Concurrency would shorten 43 s on this Mac and nothing on a
  three-core runner, where the run is CPU-bound.
- **Optimizing the test target too**, or running the tests in release. The
  22 s left in the core suite is the tests' own unoptimized loops, spread thin
  (`ghostCheck`'s per-pixel loops about 0.25 s a case). Not measured, not
  done: the test target is the largest thing CI compiles (86 to 99 s), and
  optimized code may end a value's life at its last use, which no test was
  written for.
- **Rewriting the measuring code for speed, Accelerate or Metal.** Larger
  changes to shipped math for the tests' sake; a blur or sum in another order
  is not bit-identical.
- **Raising the job limit** (C22's suggestion): refused by the owner, and no
  longer needed.

### What CI should become (to be confirmed by the run)

Evidence: `develop`'s last three green runs (45031969249, 44934276425,
44919066660): 12.8 to 16.9 min a job; Build 83 to 170 s; Test 298 to 424 s (in
the newest: the test build 145 and 164 s, the run 257 s); app bundles 285 to
405 s.
The failed run on this branch (45034608676) crashed 1 min 45 s to 4 min 15 s
into its first merge test.

- **Test run**: the suites `develop` has take about half as long here (97 s to
  47 s) and the merge chain is 43 s of one thread: about 2.5 to 3.5 min on a
  runner, where `develop`'s run is 4.3 min today.
- **Build**: about 1 min more (the two optimized targets).
- **Job**: about 15 to 18 min, as `develop` today, where this branch could not
  finish in 45. With the bundles in a job of their own (proposed below), about
  10 to 11 min.
- **Risks only CI can show**: Swift 6.3.3 (Xcode 26.6, the macOS 26 job)
  compiles `PhotoCore` optimized with testing enabled for the first time (it
  already compiles it optimized for the bundles); Swift 6.2.4 has done so here
  (see "With CI's Swift 6.2.4" below), though on this Mac's macOS 27.2, not
  macOS 15's runtime. And tests whose timing leaned on slow code: the one
  found is fixed (`cancelLeavesNothing`); the full suite passed here six
  times with the change.

### CI workflow: proposed, not changed (needs the owner's go-ahead)

Nothing under `.github/` was edited.

1. **App bundles in a parallel job** (`Scripts/build-app.sh all` on its own
   runner, same matrix). Saves the bundle step's 4.8 to 6.8 min of wall time a
   run for about 40 s more runner time (checkout and toolchain). The
   repository is public, so runner minutes are free. To decide: the rulesets
   "Default" and "master: required checks" require `Build and test (macos-15)`
   and `Build and test (macos-26)`; the new job's two checks would have to be
   added there, or a broken bundle no longer blocks a merge. The docs-only
   detection has to be in both jobs.
2. **A limit on the Test step** (`timeout-minutes: 20`). A hang (a regression
   in the WorkLane test now hangs, tenth pass) then fails after 20 min with
   the crash reports uploaded, not after 45 with the job cancelled and nothing
   kept.
3. **Remove the `.build` cache step, or accept that it does nothing.**
   Evidence: run 45031969249 restored it ("Cache hit", 528 MB, 10 to 18 s)
   and still compiled all of LibRaw, GRDB and every target (Build 141 s). The
   key is only `Package.resolved`, so it was saved once and never again. A
   fresh checkout gives every file a new date and inode, which the build
   system most likely takes as changed. A cache that works would save about
   3 min a job (LibRaw: 25 s debug, 52 to 74 s release; GRDB) but needs
   compilation caching by content, which these toolchains don't offer in
   SwiftPM: later.
4. **Not proposed**: building tests once (already so: the Test step compiles
   only the test target, 153 steps after the Build step's 464) and `swift test
   --parallel` (Swift Testing already runs in parallel).

### Review findings (tenth pass)

- **C22**: answered by this section; the limit stays 45 min.
- **C23**: fixed. The WorkLane test's "after" job runs at priority 0, so a
  pending job still queued (priority 1) starts first whichever reaches the
  lane first; the comment says so. Against a copy of `WorkLane` whose
  `cancelWaiter` keeps the pending job (a scratch package, the test's body
  300 times a run, six runs, two with `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`):
  detected 1,800 of 1,800 with priority 0, and the real `WorkLane` raised
  none in 1,800. With priority 1, as before, the mutant got through 7 to 16
  times in 300 while the machine was busy (0 with the strict pool): the
  reviewer's race, seen. In the tree, with `WorkLane.swift` broken the same
  way for the check: the test failed 20 of 20 (`!pendingRan`), and passes 20
  of 20 with it restored.
- **C24**: corrected in "CI on PR #258" (1 min 45 s to 4 min 15 s, checked
  against the log's times; the two macOS 26 `.ips` reports named).

### Needs a decision

- **The debug optimization in `Package.swift`** (owner, and code review). What
  it costs: a debugger steps through optimized code in `PhotoCore` and
  `PhotoFixtures` (variables optimized away, lines out of order), and a clean
  debug build takes about 45% more processor time (288 s to 417 s). What it
  buys: 12 minutes to 78 seconds for every `swift test`, here and on CI, and tests that run the
  library as the app ships it. What it does not cost, since C25: checks.
  `Sources/` has no `assert` and no `#if DEBUG`; `precondition`, overflow and
  exclusivity checks are on at every level; and `-assert-config Debug` keeps
  the standard library's debug-only checks (the bounds checks on unsafe buffer
  pointers) that `-O` alone turns off. If the owner would rather keep
  unoptimized debug builds, the alternative is the same flag for tests only (`swift test
  -Xswiftc -O` in CI and `CLAUDE.md`), which rebuilds everything whenever a
  plain `swift build` came before it.
- **The CI proposals above.**
- **`CLAUDE.md`** (the owner's): its Commands section could say that debug
  builds of `PhotoCore` and `PhotoFixtures` are optimized, with the debug
  checks (bounds checks on unsafe buffers) kept on, and why.

### Review findings (eleventh pass)

- **C25 (Should fix): fixed.** The reviewer is right and the record was
  wrong: `-O` alone turns off the standard library's debug-only checks
  (`_debugPrecondition`), among them the bounds checks on
  `UnsafeBufferPointer` and `UnsafeRawBufferPointer`, which `swift test` had
  on the library's unsafe reads until `bc68ed5` (`NoiseModel.swift`,
  `LibRawDecoder+GPU.swift`, `BrushRasterizer.swift`). The flags are now
  `["-O", "-assert-config", "Debug"]`, and the `Package.swift` comment and
  "Needs a decision" say what is kept. Checked:
  - The reviewer's case as a program (`[UInt8](repeating: 7, count: 3)
    .withUnsafeBufferPointer { $0[5] }`, and `withUnsafeBytes`), with Swift
    6.4.2 and 6.2.4: "Fatal error" at `-Onone`, reads 0 and goes on at `-O`,
    "Fatal error" again at `-O -assert-config Debug`.
  - In this package, the same two reads in a function added to
    `PhotoFixtures` for the check and called from a test (both removed
    again): with the new flags the test process stops with "Fatal error"; with
    `-O` alone, as `bc68ed5` had it, the function returned (0, 0) and the
    test passed.
  - The flags reach the compiler with the native build system (Xcode 26.3's
    SwiftPM, `-v`): the driver gets `-Onone -enable-testing … -O
    -assert-config Debug` for `PhotoCore` and `PhotoFixtures` and `-Onone`
    only for every other target; their frontend jobs get `-O -assert-config
    Debug` and no `-Onone`.
  - Cost: merge suites 40.2 s to 42.8 s (6%), full `swift test` 73 to 79 s
    to 78 s, a clean debug build 391 s to 417 s of processor time. All 70
    lines the merge tests print are still identical to the unoptimized
    build's.
- **C26 (Nit): recorded**, below. `docs/WORKFLOW.md`'s CI-toolchain build was
  not run before Done was reported for this change; it is now.

### With CI's Swift 6.2.4 (Xcode 26.3)

`DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer` (Swift
6.2.4, the macOS 15 job's toolchain; native build system), scratch path
outside the repository, at the tree with the C25 flags:

- `swift build --build-tests`: clean (55.6 s; the only warnings are the two
  in `SmartAlbumTests.swift` and `VirtualCopiesTests.swift` that `develop`
  has).
- `swift test --skip-build --filter "MemoryHeavy|WorkLaneTests"`: 64 tests in
  10 suites passed (40.3 s), among them `catalogueOptional`,
  `refusedFileRemoved` and the three "photocli merge" tests, the new shapes
  of `HDRMergeJob.run`'s `catalogue`. The 70 printed lines are identical to
  the unoptimized Swift 6.4.2 build's.
- This is Swift 6.2.4's compiler on macOS 27.2's runtime, so it does not
  replace the macOS 15 job. Swift 6.3.3 (Xcode 26.6, the macOS 26 job) is not
  installed here: CI's alone.

## Debug-script checks

Run 2026-11-20 on a copy of the bundle (`CFBundleIdentifier`
`me.sesser.gus.debugtest`, re-signed ad hoc) against a scratch library:
`photobench generate --output $S/src --jpeg 2 --dng 0 --heic 0 --videos 1 --brackets 1`,
then `photobench import --library-root $S/lib --source $S/src`, a fresh copy
of the library per run, every launch with `--library-root`.

- `search RAW_1; selectall; merge sheet`: three frames in capture order,
  RAW_102 (0 EV) the reference, no message, disk clear, name
  `RAW_102_HDR.tif`, formats TIFF and DNG; `merge format dng` changes the name
  to `.dng` and the caption; `merge start`: "Merge to “RAW_102_HDR.tif”",
  "Reading 1 of 3", then "Merged 3 photos into …/RAW_102_HDR.tif."; the new
  photo is the selection; `undo`/`redo` as AC13.
- Refusals in the sheet, Merge off, nothing written: Mixed-0 (the raw
  flagged), ReadOnly-0 (case 9, the reference flagged), two JPEGs and a video
  (the video named and flagged), a photo and its own copy (named, the copy
  flagged; the same-exposure note shows too). Unrelated-0 merges until
  aligning, then Activity: "“UNRELATED_103” doesn't line up with
  “UNRELATED_102”. Merge photos of the same scene.", no file.
- `merge start nowait; print merge; merge stop`: while running, File ▸ Stop's
  job is the merge and Remove from Library is off; after Stop, "The merge was
  stopped. Nothing was added to the library.", no file and no partial file in
  the folder.
- Merging again with the earlier files on disk writes `RAW_102_HDR-2.tif`,
  then `-3`.
- `merge start nowait`, then another search and `focus 0`, then `merge wait`:
  the selection stays on the photo picked meanwhile (design §8.3); the DNG is
  catalogued (`print items`).
- `about quitask merging`: "Quit While Merging?", "The merge is stopped and
  nothing is added.", Keep Merging, on the library window.

After the review fixes, on a fresh bundle and scratch library: three merges
in a row from the app (each a new photo with its own row; `print items` lists
three), the TIFF banded writer's output looks as before on the real bracket.

## For a person (not scriptable here)

- M1 to M7 of design §16 (the sheet's look, a real ⇧⌘L with a real keyboard and
  with the search field focused, Stop with a real mouse and ⌘., ⌘Q during a
  merge, the result's look in the loupe and in another viewer, the Activity
  item with a long name, undo/redo/merge again from real menus). Menu enabled
  states need a key window, which a shell launch on this Mac didn't get.
- A real hand-held bracket of 24 MP raws for time and memory (Spike 3 has 16 MP).
- A failure with a full disk image (the "Space" message) and a master deleted
  mid-merge (the "Read" message): built, not run.

## Not built

- R18 (Could): the "Show in Library" action on the Activity row. Without it
  the row's path and the search field find the photo (design §8.3 allows this).

## Requirements issues

- **RI-E1** (16-bit float DNG) and **RI-E2** (a sidecar only when the photo
  has values to write): ruled by the product manager 2026-11-20 and recorded
  in the PRD (R5, R6, AC4, A10). One correction for the PRD's Revisions: the
  bit depth's one constant is now `LinearDNGWriter.bitsPerSample`
  (`MergeOutput.dngBitsPerSample` was removed by code review C5).
- None open.

## Design questions

- **New strings for the designer (security review M1, L8, code review C1),**
  written after §6's pattern, to confirm: "“%@” is too large to merge. A photo
  can have at most %lld megapixels." (sheet and Activity), "These photos are
  too large to merge together on this Mac. Select fewer." (sheet), "“%@” has a
  name or place a merged photo can't be saved beside." (Activity: a damaged
  library), "The library already has a photo with the same content."
  (Activity, after C1's fix practically unreachable). Confirmed at the
  designer's second pass; the damaged-library text was reworded (F3): "A merged
  photo can't be saved beside “%@”. The library's record of its file name or
  location isn't valid." 

Ruled at design review (D-H1 to D-H4, design.md §19), as built:

- The quit alert's buttons are QuitGuard's existing **Keep Merging** and
  **Stop and Quit** (design §7.4 wrote "Quit … as the other quit alerts have
  it"; the others say Stop and Quit).
- In the loupe, a merge that lands leaves the loupe and the selection as they
  are (design §8.3 says both "the new photo replaces the selection" and "the
  loupe stays on the photo it was on"; the loupe acts on one photo, so the
  selection is not changed there either).

## README

- The app now writes a new file into a source folder (the merge's TIFF or
  DNG beside its reference); masters are never written. The README's line on
  what the app writes needs a sentence (PRD "Dependencies").
- `photocli merge` and `photobench merge` are new commands.
- Revision 2026-11-21: `photocli merge` takes `--reference <version>`,
  `--no-align` and `--no-deghost` and prints `align` and `deghost`;
  `photobench merge` takes `--no-align` and `--no-deghost`; `photobench
  generate --brackets` also writes a `TwoFolders` series.
- 2026-11-22: debug builds compile `PhotoCore` and `PhotoFixtures` with the
  optimizer (`Package.swift`); the build and test commands are unchanged. If
  the README says how long `swift test` takes or how to debug the library, it
  needs a sentence.

## Proposed follow-ups

- **CI: app bundles in a parallel job, a limit on the Test step, and the
  `.build` cache that restores and saves nothing** (enhancement, tooling; see
  "Test and CI time", "CI workflow: proposed"). Needs the owner's go-ahead and
  a ruleset change for the new checks.
- **Two compiler warnings in the tests** (enhancement, tidy):
  `SmartAlbumTests.swift:165` (unused result of `insertMasters`) and
  `VirtualCopiesTests.swift:170` (a redundant `#require`), on `develop` too.

- **HDR merge: de-ghosting reads the reference's noise near black as
  movement** (bug, PhotoCore `MergeGhosts`; the residual after C19): where the
  reference's light is only a few noise σ above its black level, the two-sided
  test (log ratio over 1.5 between a frame's and the reference's blurred
  values, with a floor of 0.2% of clipping) reads the reference's noise as
  disagreement, so those areas take the reference's own noisy values. The
  one-sided reference-black test did the same until C19 (fixed:
  `max(reference.high, lowR)`). At ±3 EV with the darkest reference, of the
  raw disagreeing pixels (before cleaning, both other frames) 3,362 are the
  two-sided test's, 45 the frame-black test's and none the reference-black
  test's (before C19: 4,777 more from it). The darkest reference is the worst case, but any reference with a
  brighter frame shows it once the bracket is wide enough. Fixture, still
  linear bracket, noise σ 0.004 (`stillNoisyBracket`): ±3 EV, darkest
  reference, 1,870 pixels moved by over 1% against the merge with no masks
  (worst 4.7 times; unaligned 2,071, worst 9.6 times), default reference 430
  (worst 98%); ±2 EV, nothing with the darkest or the default reference. A
  threshold from a noise model near black (the reference's and the frame's
  expected noise at that level, after exposure) would fix it; needs real
  high-ISO brackets to set.

- **`WriteChain.read` called from inside a write waits for itself**
  (enhancement or bug, PhotoCore): QA Q1 was this mistake in the merge's Redo.
  The chain could notice that the caller is its own running tail and throw
  (or read without waiting) instead of hanging the window's saving for the
  session. Any future undo step that reloads its list would be protected.

(SidecarSync's `stem.xmp` fallback is filed as bug #248.)

- **A split render can read another part's copy of a CPU-side image** (bug or
  watch item, PhotoCore): the fault behind "Bug: tiles at 100%" is Core Image's
  and is avoided for full-size ImageIO decodes only. Still exposed in theory:
  the HDR rendition's `decodeHDR` (renders to a bitmap, never seen to fail),
  photos over 16384 pixels on a side, and any other lazily read image in a
  render large enough to be split. Worth a soak of camera raws and gain-map
  photos at full size with Shadows on every new macOS, as `RAWEdgeSmearTests`.

- **Recover the camera's response curve for JPEG brackets** (enhancement):
  non-raw frames are linearized by their color profile only, so a camera's
  tone curve skews the measured exposures (0.35 against a nominal 0.5 on the
  owner's E-M10 JPEGs) and can brighten clipped cloud patches. Debevec and
  Malik 1997's response recovery (or Robertson et al. 2003) on the measuring
  copies would fix it. It would also take away what C14 left for JPEG
  brackets: a strong S-curve makes de-ghosting see still mid-tones disagree
  (24,152 of 240,000 pixels moved by over 1% on the fixture with the brightest
  reference, 23,559 with the rule before `be5bf92`), and areas taken from fewer
  frames differ in tone from the blend.
- **Find merged photos** (enhancement, RI-H3 of the design, ruled for later):
  a stored link to the frames, a mark on the cell and a smart-album rule; needs
  a migration.

## Open questions

None.
