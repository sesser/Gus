Issue: #150

# HDR merge: status

Owner: swift-macos-engineer. Branch `feature/hdr-merge` (worktree `Gus-hdr-merge`).
Spec: the PRD (issue #150 body, approved and revised 2026-11-20) and
[`design.md`](design.md).

**State: Done** (2026-11-20, after the review fixes below). Every criterion of the PRD as revised (prd4: R4 widened to the stem, R19, AC2a, AC15) built and tested; nothing blocked. Next: code review's second pass (and the designer for the three new strings), then QA.

**2026-11-21: owner finding at sign-off (P5) fixed**, see "Bug: tiles at
100%". A fault in Core Image, not the merge's file; existing merged files need
nothing. The fix changes one thing the owner should know: full-size renders of
straightened or rotated JPEG, HEIC, PNG and TIFF photos now resample linear
light, as raws and the 100% live frames already did (a few edge pixels, up to
37 of 255 steps; no cached preview changes, no pipeline bump). Next:
code-reviewer's second pass on the fix, then qa-tester (no UI change, so no
design review), then back to the owner for P5.

## Baseline

- `swift build` on `develop` at `ed423d7` (plus the design commit): clean.
- `swift test` before any change: 1253 tests in 179 suites passed (70.6 s).

## Latest results (2026-11-21, after the fix for "Bug: tiles at 100%")

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

## Proposed follow-ups

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
  copies would fix it.
- **Find merged photos** (enhancement, RI-H3 of the design, ruled for later):
  a stored link to the frames, a mark on the cell and a smart-album rule; needs
  a migration.

## Open questions

None.
