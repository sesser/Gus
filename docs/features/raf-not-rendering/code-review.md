# RAF not rendering: code review

Owner: code-reviewer. Date: 2026-11-13. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `bug/raf-not-rendering`, `ef592d9`..`0f2b4ee` (two commits). Build and
tests: `swift build` complete, one new warning (C9); `swift test` 859 tests in
129 suites passed, 1 known issue; `LibRawFallbackTests` is skipped by default and
passes with `RAF_SAMPLE` set to an X-E3 file (2 tests, 30 s). macOS 27.2.1
(26B131). `Scripts/build-app.sh` not run.

Checked against the **Bug** section of `status.md`, issue #161, the rulings
recorded there (LibRaw only where the system decoder gives no image; no embedded
preview in place of a render) and `CLAUDE.md`. `status.md` still says
**In progress**, not Done.

## Verdict

Not ready for QA: one blocker. The fallback is in the right place and does what
the Bug section asks (the X-E3 file renders at thumbnail, preview and full size,
and a stale pre-fix `photocli` still answers `undecodable` for it), and no
existing render changed. But the vendored library is built with
`LIBRAW_NOTHREADS`, which makes its decoder state process-wide, and the app
decodes on up to eight threads: two LibRaw decodes at once return wrong pixels
with a success code (C1, reproduced). C2 to C6 should be fixed or ruled on
before sign-off; the license question (Q1) is the owner's.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
| --- | --- | --- | --- | --- | --- |
| C1 | Blocker | `Package.swift:33`; `Sources/PhotoCore/Preview/LibRawDecoder.swift:36` | `LIBRAW_NOTHREADS` turns LibRaw's per-instance decoder state into function statics shared by the whole process (`getbithuff` bit buffer, `pana_data` buffer, `sony_decrypt` pad, `ph1_bithuff`, `cielab`'s `xyz_cam`: `nm` shows them as `b` symbols in the built `CLibRaw.o`). `LibRawDecoder.decode` takes no lock, and it is called concurrently: `PreviewService.generateLane` (up to about eight jobs), the export task group, the 1:1 lane and the live sessions. Upstream builds its thread-safe `libraw_r` without this define. | A scratch program making the same C API calls as `LibRawDecoder`, linked against the branch's `CLibRaw.o`, one thread per file. Half size (the thumbnail and preview path), two CR2 + two RW2 + two ARW + two ORF at once: both CR2 and both RW2 differ from their decode alone in every round, an ARW in two of three, LibRaw prints "data corrupted at …", and every call returns 0. Full size, four different cameras at once: CR2, ARW and RW2 differ in every round (the last camera's color matrix wins). In the app those pixels are cached to disk under a valid key, or exported. The same program against the same sources compiled without the define: 24 of 24 half-size and 12 of 12 full-size decodes equal the decode alone. Two X-E3 files and an X-T3 at once did not differ (Fuji's loader keeps its own state), so the owner's files happen to be spared at half size. | Correctness; Swift 6 concurrency |
| C2 | Should fix | `PreviewGenerator.swift:183-194`; `Sources/PhotoApp/Model/AdjustmentEditor.swift:360`; `Views/AdjustView.swift:173,275,282`; `Edits/AutoAdjust.swift:45,114` | Two sources of truth for "is a raw": the decode says `isRaw` false for a LibRaw image, everything else asks the file extension. For an X-E3 file `CIRAWFilter(imageURL:)` is not nil (native size 0x0, decoder versions `["None"]`, neutral 5001 K / tint 10), so the Adjust tab shows the Profile group, the Kelvin Temperature and Tint sliders and the raw presets, and Auto White Balance takes the raw path. None of them reach the render: only `decodeRAW` applies `RAWDecodeSettings`, and the renderer's `relativeWhiteBalance` reads only the relative values. | `photocli render XE3_DSCF5123.RAF --long-edge 600` with and without `--set whiteBalance.preset=custom --set whiteBalance.temperature=2500 --set whiteBalance.tint=60`: byte-identical PNGs (same SHA-256), different `renderHash` (so a second cache entry of the same pixels). The same two commands on the X-T3 file (system decoder) give different images. In the app: Temperature, Tint, Daylight…Flash, the decoder pop-up and Color noise reduction save an edit, an undo step and a history entry and change nothing; Auto White Balance (measure returns nil, `neutralize` returns its start) writes 5001 K and changes nothing. | Correctness: state that drifts between two sources of truth |
| C3 | Should fix | `Edits/LiveRenderSession.swift:250-252,424`; `Edits/LiveRegionRenderer.swift:77-80,117-131`; `Edits/SharpeningMapRefiner.swift:61,100`; `Edits/FringePicker.swift:216` | The same extension test still builds decode settings for a LibRaw photo, and those settings key the decode. Every change of a decode setting decodes the file again with LibRaw for an image that cannot differ. By trace, not run in the app. | Dragging Temperature on an X-E3 photo: each frame has a new `BaseKey.settings`, so each frame runs `PreviewGenerator.decode` again, 0.58 s at half size and 8.6 s at full size (`status.md`'s release timings) against about 0.05 s for the system decoder, and the picture does not change (C2). Exposure or Highlights going below 0 (`extendedDynamicRange`), the first crop or mask (`fullFrame`) and Noise Reduction each cost one more decode; at 100% each is the 8.6 s full decode in `LiveRegionRenderer.prepare`. | Correctness; owner's ruling that nothing gets slower |
| C4 | Should fix | `PreviewGenerator.swift:127-142`; `LiveRenderSession.swift:407-412`; `LibRawDecoder.swift:58-59` | `PreviewGenerator.nativeSize` is nil for these files (`CIRAWFilter.nativeSize` 0x0, ImageIO has no pixel size), so `decodeLongEdge` never enlarges the decode for a crop, and `LibRawDecoder` chooses half size from the uncropped target. | `photocli render … --long-edge 2560 --set crop.x=0.3 --set crop.y=0.3 --set crop.width=0.3 --set crop.height=0.3`: the X-E3 file gives 900x600, the X-T3 file (system decoder) 1872x1248. A cropped X-E3 photo's cached preview and loupe frames have half the resolution the file holds (1799 px across the same crop at full size). Export (no long edge) is not affected. | Correctness |
| C5 | Should fix (owner's call, Q4) | `Preview/PreviewService.swift:203-213`; `Preview/PreviewCacheKey.swift` | A LibRaw render is stored on disk under the same key (content hash, stack hash, tier, pipeline 8) as a system render of that file would be. The two looks differ (`status.md`: 18 to 40 mean-luma levels, flatter, 5998x3997 against the camera's 6000x4000), and which decoder a file gets depends on the macOS release, which this bug itself shows changes. The machine learning fallback has the same problem and keeps such renders for the session only (`storeForSession`). | After a macOS update that reads X-E3 files again, the grid and the loupe's fitted preview keep the cached LibRaw render (flat, darker) while 100%, live frames and exports of the same unedited photo come from the system decoder: one photo and one stack with two looks, until an edit or a cache delete. The reverse (a camera losing support) shows the system look in the grid and LibRaw's in the loupe as soon as a slider moves. Not reproduced: it needs a second macOS build. | Rendering: preview cache keys |
| C6 | Should fix | `Tests/PhotoCoreTests/LibRawFallbackTests.swift`; `PreviewTests.swift:437-459`; `status.md` Bug section | No test of the new decoder or the fallback runs by default, so CI on macOS 15 and 26 never executes a line of LibRaw. A deterministic case exists: `SyntheticDNG` at 256x192 is exactly the Bug's condition on this Mac (`CIRAWFilter` native size 0x0, versions `["None"]`, ImageIO count 0) and LibRaw decodes it at 256x192; at 1536x1152 both decoders read it. `RAWDecodeGuardTests` already writes that file and now goes through LibRaw, but accepts either a decode or `undecodable`. Nothing covers orientation, the half-size rule, the inset crop, a failing file, or two decodes at once (C1). The Bug section does not name the failing test; the paragraph above it does. | Removing the fallback, breaking the 16-bit copy or the crop math, or putting `LIBRAW_NOTHREADS` back leaves `swift test` green here and in CI. | Tests |
| C7 | Nit | `PreviewGenerator.swift:164-174` | A stack that asks for machine learning noise reduction (pasted or from a preset) on a LibRaw photo comes back as `.notApplied(.failed)`: the machine learning decode gives no image, the classical retry returns LibRaw's image, and line 172 overwrites the reason. By trace. | The Adjust tab says the decode failed for a camera the system decoder does not support at all, and the preview is kept for the session only, so it is decoded again with LibRaw at every launch. | Correctness |
| C8 | Nit | `PreviewGenerator.swift:191` | `try?` drops `LibRawDecoder.Failure`. | A raw neither decoder reads is reported as `undecodable` with no trace of LibRaw's reason ("Unsupported file format", "Input/output error"); only `photobench rawcompare` ever shows it. A log line would do. | Correctness: `try?` |
| C9 | Nit | `Package.swift:27-36` | `src/Makefile` is not excluded: every build prints "no rule to process file …/Sources/CLibRaw/src/Makefile". `linkedLibrary("z")` links zlib although `USE_ZLIB` is not defined, so nothing uses it (and deflate DNGs stay unsupported, as `status.md` found). | A build warning on every `swift build` and `swift test`; a link dependency with no user. | Dependencies |
| C10 | Nit | `THIRD_PARTY_NOTICES.md` (LibRaw, "Not built"); `README.md:161`; `CLAUDE.md:158`; `LibRawDecoder.swift:8,48`; `status.md`; `docs/USER_GUIDE.md` | Records out of step with the branch. The `_ph.cpp` files are placeholder stubs for builds without post-processing ("Placeholder functions to build LibRaw w/o postprocessing tools"), not files "included by other LibRaw files". README line 161 and `CLAUDE.md` line 158 still say GRDB is the only dependency (`.claude/agents/code-reviewer.md:37` too; that one is the main session's). `LibRawDecoder`'s doc comment still calls it a spike and says 6000x4000 where LibRaw's inset for the file is 5998x3997. `status.md`: Spike still says "Its crop needs setting", Open lists calls the owner has made, there is no **README** note, and the user guide says nothing about raws that render flatter and without raw controls. | A reader of the notices, the README or `status.md` is told something the code does not do. | `docs/WORKFLOW.md` ownership |
| C11 | Nit | `LibRawFallbackTests.swift:15` | `#expect(full.image.extent.width > 4000)` assumes landscape. | Run with a portrait X-E3 file as `RAF_SAMPLE` (3997 wide after orientation) the test fails although the decode is right. Compare the long edge. | Tests |
| C12 | Nit | `Sources/PhotoBench/RawCompareBenchmark.swift:29-38`; `main.swift` usage; `docs/PROFILING.md` | "Best of N" on one `CIContext` reports the system decoder's warm run. `rawcompare` is in neither the usage text nor `docs/PROFILING.md`. | `--runs 1` on the Sony ARW: system 0.19 s; `--runs 3`: 0.05 s (LibRaw 1.15 s and 1.12 s). `status.md`'s "too fast" system column is the warm figure; the first run also pays set-up, so neither is the cold decode. Nothing depends on it since the ruling. | Tests and tools |

## Questions

- **Q1, owner: which of LibRaw's two licenses.** The app is GPL-3.0-or-later
  (`README.md`, `LICENSE`). The branch takes LibRaw under CDDL-1.0
  (`Package.swift`, `THIRD_PARTY_NOTICES.md`, only `LICENSE.CDDL` vendored). The
  FSF lists the CDDL as incompatible with the GPL; LibRaw's other offer, LGPL
  2.1, is GPL-compatible. This is not legal advice, but the choice should be the
  owner's with that in view, before a binary is distributed. Either way, should
  the app bundle carry `THIRD_PARTY_NOTICES.md` (the CDDL asks that recipients of
  a binary be told where the source is)?
- **Q2, owner: `CLAUDE.md`'s Dependencies rule** was edited on the branch
  (`0f2b4ee`). That section is the owner's (`docs/WORKFLOW.md`, Ownership). The
  issue and `status.md` record the ruling to explore LibRaw, vendored; please
  confirm the wording, and that it stands for shipping and not only for the
  spike. Line 158 of the same file then needs the same change (C10), and the
  Layout and Commands sections say nothing of `Sources/CLibRaw` or `RAF_SAMPLE`.
- **Q3, owner or product manager (Requirements issue): what the Adjust tab
  offers for a photo LibRaw decoded** (C2, C3). The smallest consistent answer
  is to treat it as a rendered image everywhere (relative white balance, no
  Profile, no machine learning), from one test of "the system RAW decoder reads
  this file" shared by the decode, the editor, the live sessions, Auto and the
  batch actions. Applying white balance and the rest in LibRaw is the larger
  one. `status.md` lists decode settings as not done.
- **Q4, owner: cached LibRaw previews** (C5). Keep them on disk and accept two
  looks after a macOS change, keep them for the session only as machine
  learning fallbacks are (every launch then decodes them again, 0.6 s a
  thumbnail), or give the fallback's renders a key of their own?
- **Q5, engineer: the frame.** LibRaw's first inset crop is 5998x3997 for the
  X-E3 (the camera's JPEG is 6000x4000) and 6240x4155 for the X-T3 (the system
  decoder gives 6240x4160). Is that the frame wanted, and what should a file
  shot at 16:9 or 1:1 show (`raw_inset_crops[1]` is not read)? No sample here.

## Checked and fine

- **Vendored tree.** `Sources/CLibRaw/src`, `internal` and `include/libraw`
  compared with LibRaw tag `0.22.3` (`cf02d66`): identical except the two
  `#include` lines `THIRD_PARTY_NOTICES.md` names. `LICENSE.CDDL` and
  `COPYRIGHT` are upstream's. No GPL demosaic pack, RawSpeed or DNG SDK.
- **Package target.** The three `_ph.cpp` exclusions are right (they define the
  same symbols as the real sources); the other 79 sources all compile; the
  module map exposes only the C API.
- **Only when the system gives no image.** The fallback sits after `decodeRAW`
  on both the plain and the machine learning path and before ImageIO. For the
  X-E3 file and the 256x192 DNG ImageIO gives nothing either, and I found no raw
  that ImageIO reads and `CIRAWFilter` does not, so no render that existed
  changed; all goldens and references pass. No pipeline bump is needed for that.
- **HDR.** `decodeHDR` returns nil for a raw that is not a floating-point DNG
  before any decode, so LibRaw is never asked for an HDR rendition of a camera
  raw.
- **C API use.** One `libraw_data_t` per call, closed on every path
  (`defer`); the processed image freed on every path; error codes checked after
  open, unpack, process and make image; bits and colors checked before the copy.
  The data offset (16) is aligned for `UInt16`; 16-bit samples are host order;
  output color 8 is Rec. 2020 in this version; gamma 1/1, no auto bright, camera
  white balance. Orientation matches the system decoder's (CR2 with flip 5).
- **Crop math.** Cropbox origin is the inset minus the margins, guarded against
  underflow and an unset inset (width 0); checked on six cameras (5998x3997,
  6240x4155, 5472x3648, 5184x3888, 6000x4000, 3744x5616 after rotation). Half
  size gives scale 0.5 with `fullSize` within one pixel.
- **Bad files.** A truncated RAF and CR2, a 4 KiB header, an empty file and
  random bytes all fail with an error code (I/O error or unsupported), no crash,
  no image.
- **Memory.** Peak footprint of a full-size `photocli render` (debug): 887 MB
  for the X-E3 through LibRaw against 1.26 GB for the X-T3 through the system
  decoder; at 512 px, 384 MB against 542 MB.
- **The test with the sample.** `RAF_SAMPLE=…/XE3_DSCF5123.RAF swift test
  --filter LibRawFallbackTests` passes; a pre-fix release `photocli` gives
  `undecodable` for the same file.
- **Rules.** No UI string, no persisted name, no brand value, no migration, no
  catalog or sidecar write, no network, no subprocess. `BrandingTests` and
  `LocalizationTests` pass.

## Follow-up

### Second pass, 2026-11-13

Reviewed: `0f2b4ee`..`69bb1c5` (ten commits). Source and tests change in
`7957ed1`, `573a3ec`, `4e3441a`, `a150f76`, `ac2a1fd` and `3f1ec1b`; the last
one (the design review's fixes F1 to F5) landed while this pass was running and
is included. Build and tests at `69bb1c5`, working tree clean: `swift build`
complete, no warning from the package (a clean build of `4ff5d30` in a scratch
copy shows only two older warnings in `SmartAlbumTests` and
`VirtualCopiesTests`); `swift test` 879 tests in 131 suites passed, the same 1
known issue (`LiveSessionTests`); `RAF_SAMPLE=…/DSCF5123.RAF swift test --filter
LibRawFallbackTests` 5 tests passed (31 s). macOS 27.2.1 (26B131).
`Scripts/build-app.sh` not run; the app not launched.

**Verdict.** C1 to C12 are closed: ten fixed, C5 ruled (Q4), C10 fixed where
the engineer owns the file. No blocker. One new Should fix, C14, came in with
the last commit and is the designer's call: choosing Custom in the White
Balance Mode pop-up of any JPEG now looks dead and still saves an edit. Rule on
it before QA so QA runs once; C13 and C15 are nits.

#### Earlier findings

| # | Outcome | Commit | How it was confirmed |
| --- | --- | --- | --- |
| C1 | Fixed | `7957ed1`, tests in `4e3441a` | `Package.swift` no longer defines `LIBRAW_NOTHREADS`. The process-wide statics the finding named are gone from the built `CLibRaw.o` (`nm`: two function statics left, see Checked). A scratch copy of `4ff5d30` with the define put back: `concurrentDecodesMatchSoloDecodes` fails (13 of 48 decodes differ), `buildIsThreadSafe` fails, and one orientation case fails beside them; without it all pass. |
| C2 | Fixed | `4e3441a`, `a150f76`, `3f1ec1b` | One test, `SystemRAWDecoder.reads`; `RawDefaults` is nil exactly when it is false, and the editor's `isRaw`, the Adjust tab, Auto White Balance and `RenderContext.isRaw` follow it (`oneTestOfWhatIsDecodedAsRaw`, `autoWhiteBalanceFollowsTheDecoder`, `rendererAdjustsTheLibRawImage`; on the X-E3 file `adjustmentsChangeTheRender`, Auto gives relative 16, -22). Kelvin values still reach such a photo by paste, a preset or `photocli` and change nothing: ruled by the designer (D2), kept in the stack, the pop-up shows what renders (but see C14). |
| C3 | Fixed | `4e3441a` | Decode settings reach only a raw the system decodes (`SystemRAWDecoder.Memo`). On the X-E3 file, one `LiveRenderSession`: an interactive frame, a final one, a Kelvin change, noise reduction, Exposure and Highlights below 0, relative white balance and a 0.9 crop made 1 decode (frames after the first 0.01 to 0.06 s); a 0.3 crop made the second, full one; removing the crop reused the first. For raws the system decodes the keys and the crop arithmetic are as before. |
| C4 | Fixed | `4e3441a` | `PreviewGenerator.nativeSize` is 5998x3997 for the X-E3 file (`LibRawDecoder.frameSize`, 1.8 ms); the 0.3 crop renders 1799x1199 in the pipeline and in the live session. |
| C5 | Ruled (Q4): no change | | The owner accepts two looks after a macOS change; the user guide says so. |
| C6 | Fixed | `4e3441a`, `3f1ec1b` | 17 tests in two suites run by default on synthetic DNGs. With the fallback's line switched off in a scratch copy, `rawWithoutSystemImageRenders` (the test the Bug section now names) fails with `undecodable`, and five more with it. |
| C7 | Fixed | `4e3441a`, changed by `3f1ec1b` | A machine learning request on a raw the system does not read reports `cameraNotSupported` on every macOS (design review F3), never `failed`; the check box stays enabled while asked, so it can be turned off. The render is still kept for the session only, as every not-applied render is. |
| C8 | Fixed | `4e3441a` | LibRaw's reason is logged (category `decode`, file name private). |
| C9 | Fixed | `573a3ec` | `src/Makefile` excluded, zlib not linked. |
| C10 | Fixed where the engineer owns the file | `573a3ec`, `4e3441a`, `4ff5d30` | Notices, the decoder's comments, the user guide. `CLAUDE.md` (line 158 and Dependencies) and `.claude/agents/code-reviewer.md` were changed in `4ff5d30` and read correctly. `README.md` waits for Ship (the product manager's). See C15. |
| C11 | Fixed | `4e3441a` | Long edges compared. |
| C12 | Fixed | `ac2a1fd` | First run and best of N; usage text and `docs/PROFILING.md`. |

#### New findings

| # | Severity | Where | Finding | Failure | Rule |
| --- | --- | --- | --- | --- | --- |
| C13 | Nit | `Sources/PhotoCore/Preview/LibRawDecoder.swift:98` | `Frame.isTurned` is true for LibRaw's flips 5 and 6 only. Flips 4 and 7 (orientations 5 and 7, mirrored and turned) also swap width and height. | A synthetic DNG with orientation 5 or 7: the decode is 192x256, `LibRawDecoder.frameSize` (and so `PreviewGenerator.nativeSize`) says 256x192, against its comment "as it is shown". Nothing uses the difference today (`Crop.sourceZoom` tries both ways, the decode key takes the long edge); `LibRawFallbackTests.decodesAtFullAndSmallSizes` would fail on such a file. `flip & 4 != 0` covers all four. | Correctness |
| C14 | Should fix (designer's call, Q8) | `Sources/PhotoApp/Views/AdjustView.swift:299,349-350`; `Sources/PhotoCore/Edits/Adjustments.swift:507-510` (`3f1ec1b`) | The Mode pop-up of every file that is not decoded as a raw (JPEG, HEIC, TIFF, PNG and LibRaw photos) now selects `relativeDisplayPreset`, which is As Shot whenever both relative values are 0. Choosing Custom still stores `preset = custom` (`pick`). | Any JPEG with Temperature and Tint at 0: choose Custom. The pop-up goes back to As Shot, and an edit is saved: a White Balance undo step, a history entry and a new render hash for the same pixels (`photocli render photo.jpg --set whiteBalance.preset=custom`: one `whiteBalance` operation, another `renderHash`, the PNG byte for byte the unedited one). Before `3f1ec1b` the pop-up showed Custom. By trace for the pop-up (the app was not launched); `print ml` prints `wb mode`, so QA can script it. The rule is the design review's F2 as written ("As Shot when both relative values are 0"), which also says picking a mode "behaves as today". | Correctness: state that drifts between two sources of truth |
| C15 | Nit | `docs/features/raf-not-rendering/status.md` (Not done, and why; Owner's rulings Q2) | Says `CLAUDE.md` still says CDDL and "GRDB is the only dependency", and that `.claude/agents/code-reviewer.md` is not edited. `4ff5d30` changed all three. `CLAUDE.md`'s Layout and Commands still say nothing of `Sources/CLibRaw` or `RAF_SAMPLE` (the owner's sections; a proposal, not a finding). | A reader of `status.md` is told the rules still name the CDDL. | `docs/WORKFLOW.md` ownership |

#### Questions

- **Q5, owner: the frame.** Still open, as `status.md` lists it.
- **Q6, engineer: two assumptions in the new keying, neither reproduced.**
  `LiveRenderSession.decodeKey` (`LiveRenderSession.swift:426-447`) treats
  every raw the system does not read as decoded by LibRaw and keeps its decode
  under one of two keys. If ImageIO decodes such a file instead, the first
  request's size serves every later one (forced with `systemDecodesRaw: false`
  on a file LibRaw cannot open: a 250 pixel base for a 400 pixel frame and for
  its crop). I found no file that takes that path: twelve mis-named JPEG, PNG,
  TIFF and HEIC files and six truncated raws are each read by the system
  decoder or by nothing. And `SystemRAWDecoder.reads` asks with default
  settings, while `PreviewGenerator.decode` asks with the stack's (a pinned
  decoder version once a macOS makes version 9 the default, the whole-sensor
  copy): if the two ever disagree for a file, the Adjust tab offers a raw's
  controls for a LibRaw image. Keying on what the decode returned
  (`context.isRaw`, and whether LibRaw made it) would close both.
- **Q7, qa-tester: several LibRaw photos at 100%.** A full LibRaw decode takes
  about 9 s, cannot be cancelled, and peaks near 0.9 GB. `scheduleRegionPrepare`
  starts one 150 ms after a photo is ready at 100% and leaving the photo drops
  the renderer, not the decode. Step through five or six X-E3 photos at 100%
  and watch memory and how long the last one takes to get sharp. Not measured
  here (it needs the app).
- **Q8, designer (Design question): C14.** What should the Mode pop-up show
  after Custom is chosen with both values at 0, and should that choice save
  anything? Showing the stored mode when it is one of the three offered and
  has no Kelvin values would keep F2's fix for pasted modes; not saving when
  nothing renders differently is the other way.

#### Checked and fine

- **`SystemRAWDecoder`.** `reads` and `RawDefaults.init?` make the same test
  (`givesImage`: an image with a non-empty extent from `RAWDecodeGraph.output`,
  never rendered; the tripwire in `RAWDecodeGraphTests` lists the file).
  0.055 s on the X-E3 file. Never called on the main actor: the editor reads it
  with `RawDefaults` in a detached task and hands the answer to the three
  actors; `Memo` is a value inside each actor; `rectForCropping`, the fringe
  picker and Color Alignment run detached.
- **Editor.** `isRaw`, `usesFallbackDecoder`, `rawDefaults`, `cameraRect` and
  the sessions are set in one main-actor step before `state = .ready`, and the
  Adjust tab lays out controls only when ready, so no layout of the wrong kind
  is drawn. Crop sessions, Rotate in the loupe and the grid's Rotate
  (`rectForCropping`) take no camera frame for a LibRaw photo.
- **Thread-safe build.** The two function statics left in `CLibRaw.o`
  (`ljpeg_idct`'s cosine table, `vng_interpolate`'s cursor) are upstream's own
  and are in its thread-safe build too; the first is for lossy DNGs, which this
  build does not decode, the second for the VNG demosaic (four-color sensors at
  full size). No sample, not reproduced.
- **Vendored tree.** Unchanged since the first pass except `LICENSE.LGPL`
  added, identical to upstream's at tag `0.22.3`.
- **Pipeline version, goldens.** No bump needed: before this branch these files
  did not render, so no stored stack renders differently; raws the system
  decodes keep their decode arithmetic; `reducedOnce` leaves images up to 512
  pixels alone, so Auto White Balance for JPEGs measures as before. No golden
  moved, no tolerance changed. The two existing tests that changed
  (`RAWDecodeGraphTests`, `LiveRegionRendererTests.decodeWhileMoving`) are not
  loosened.
- **Strings.** The note, "Not applied: this camera isn't supported. Luminance
  applies instead." and the badge tooltip are in the catalog; the replaced
  note's old key is gone; every caller of `MachineLearningText.caption`,
  `checkBoxHelp` and `badgeHelp` passes `fallbackDecoder`. `LocalizationTests`
  and `BrandingTests` pass. No persisted name, no migration, no catalog or
  sidecar write, no network, no subprocess. `print ml` only reads, so it needs
  no undo group.
- **Tests.** Swift Testing, no sleeps, synthetic files in temporary folders;
  expected values derived (linear levels from the mosaic's, orientation by
  definition, the inset crop pixel for pixel). Tests that need the bug's
  condition say so and still pass through the system decoder where it reads the
  256 x 192 DNG.

#### `/security-review`

Should run on the branch: it adds a parser of untrusted files. What to look at
now:

- LibRaw 0.22.3 (C++, in process) now opens any raw the system decoder gives no
  image for, with no action by the user: thumbnails of a folder or card just
  added, the loupe, export, `photocli`. Known advisories against 0.22.3, and
  what a hostile file costs in memory and time (LibRaw's own limits are left at
  their defaults; a decode cannot be cancelled).
- `LibRawDecoder.frameSize`: a header parse (`libraw_open_file`) of every raw
  whose size the system decoder does not give, reached from
  `PreviewGenerator.nativeSize`.
- The bridge in `LibRawDecoder.decode`: the copy loop trusts the processed
  image's `width`, `height`, `colors` and `bits` (checked for 16 bits and three
  colors, not against `data_size`), and `Data(count: width * height * 8)` is
  sized from them.
- The build: thread-safe (no `LIBRAW_NOTHREADS`), all warnings off (`-w`), no
  zlib, libjpeg or lcms, so those code paths are compiled out.
- What LibRaw prints on standard error for damaged files, and the new log line
  (file name private, LibRaw's reason public).

### Third pass, 2026-11-13

Reviewed: `3bec924`..`b162839` (three commits): `f5495be` (source and tests),
`1cd27ab` (`status.md`), `b162839` (`CLAUDE.md` Layout and Commands,
`status.md`). Build and tests at `b162839`, working tree clean: `swift build`
complete (a clean build of the same sources in a scratch copy shows only the
two older warnings in `SmartAlbumTests` and `VirtualCopiesTests`); `swift test`
879 tests in 131 suites passed, the same 1 known issue (`LiveSessionTests`);
`RAF_SAMPLE=/private/tmp/claude-501/x/DSCF5123.RAF swift test --filter
LibRawFallbackTests` 5 tests passed (32 s); `Scripts/build-app.sh all` built
both bundles (SDK 27.2, minimum 15.0, LibRaw linked in statically, ad hoc
signature). macOS 27.2.1 (26B131). The app not launched.

**Verdict.** Ready for qa-tester. C13, C14 and C15 are fixed and Q6 is
answered in code; each of the three code fixes has a test that fails without
it. Two new nits (C16, C17), neither blocking, and one Design question still
with the designer (Q9). The security read of the bridge and the build found
nothing above Low; no known advisory applies to LibRaw 0.22.3.

#### Second pass findings

| # | Outcome | Commit | How it was confirmed |
| --- | --- | --- | --- |
| C13 | Fixed | `f5495be` | `Frame.isTurned` is `flip & 4 != 0`. `decodeIsOriented` now runs orientations 2 to 8 pixel for pixel and compares `frameSize` with the decode; `frameFromSizes` runs every flip. In a scratch copy with `flip == 5 \|\| flip == 6` put back, `decodeIsOriented` fails for orientations 5 and 7 and `frameFromSizes` for flips 4 and 7. |
| C14 | Fixed, as ruled in D5 | `f5495be` | `WhiteBalance.relativeDisplayPreset` is D5's two rules word for word (the stored mode when it is As Shot, Auto or Custom and holds no Kelvin values; otherwise As Shot at 0/0, else Custom); `pick` is unchanged, so Custom at 0/0 still saves one step and now shows Custom. `relativeModeShown` covers D5's four cases; with the old rule put back it fails on Custom at 0/0 and on a raw's Auto carrying Kelvin values. The pop-up itself was not driven here (the app was not launched): D5's manual check M6, and `print ml` for QA. |
| C15 | Fixed | `1cd27ab`, `b162839` | `status.md` no longer says the rules name the CDDL. `CLAUDE.md` gained the `RAF_SAMPLE` command (run above, as written) and the `Sources/CLibRaw` Layout entry; "called only from `Preview/LibRawDecoder.swift`" holds (the one `import CLibRaw`). Those sections are the owner's; `status.md` says the main session applied them on the owner's confirmation, which I cannot check from the branch. |
| Q6 | Answered in code | `f5495be` | (b) `PreviewGenerator.Decoded.decoder` names the decoder, and `LiveRenderSession.learn` keeps a decode by LibRaw's two sizes only when LibRaw made it. With `learn` switched off in a scratch copy, `decodeSettingsDoNotDecodeAgain` fails (one decode where two are due, the draft's base serving the 400 pixel frame): the failure the question described. (a) `SystemRAWDecoder.reads`, `RawDefaults` and Auto White Balance now test the filter set up as an untouched photo decodes (`givesImageUntouched`), and `PreviewGenerator.decode` tries the system decoder again without the stack's own choices before it turns to LibRaw. `oneTestOfWhatIsDecodedAsRaw` checks the agreement on every file here, with a whole-sensor request and an unknown decoder version. See C16 for the retry itself. |

#### New findings

| # | Severity | Where | Finding | Failure | Rule |
| --- | --- | --- | --- | --- | --- |
| C16 | Nit | `Sources/PhotoCore/Preview/PreviewGenerator.swift:205-210` | The retry without the stack's decoder choices has no test, as `status.md` says: no file here takes it. | With the branch switched off (`if false, …`) in a scratch copy, the LibRaw, RAW decode, machine learning, camera frame and crop suites (105 tests) all pass. A later change that breaks it, or the agreement it stands for, is not caught. It also costs a LibRaw photo with a crop, a mask or a decoder choice one more `CIRAWFilter` set-up per decode (about 0.05 s on the X-E3 file, second pass) before LibRaw's 0.6 s or 9 s; by trace. A test needs a seam; leaving it as stated is acceptable. | Tests |
| C17 | Nit (Security notes S1) | `Sources/PhotoCore/Preview/LibRawDecoder.swift:137-162` | The bridge sets no limit of its own on the frame it decodes: the image buffer is `width * height * 8` bytes whatever the header says, bounded only by LibRaw's 2 GiB raw buffer limit (about a gigapixel). | A 192 megapixel DNG (16000 x 12000, a sparse file of zeros): `photobench rawcompare --runs 1` (debug build) took 45.6 s for LibRaw's full decode and 6.4 s for the half one, with a peak footprint of 10.0 GB for the run. In the app such a decode starts with no action by the user for any raw the system decoder gives no image for, up to about eight at once, and cannot be cancelled. A file that only claims the size fails at once (see S1). A cap on `Frame`'s pixel count after `libraw_open_file`, at a size the owner picks, would bound it. | Security: sizes checked before allocation |

#### Questions

- **Q9, designer (Design question, raised by the engineer in `status.md`
  Open): Custom chosen over pasted Kelvin values.** On a photo not decoded as
  a raw that holds a pasted Daylight (`preset` daylight, 5500 K), choosing
  Custom stores `preset` custom, keeps the Kelvin values and saves one step,
  and by D5's rule 2 the pop-up still shows As Shot until a slider moves
  (`relativeModeShown` expects exactly this for Custom with Kelvin values).
  It is what remains of C14, in a corner only a paste or preset reaches.
  Built as ruled; not a finding.
- **Q10, main session or owner (a proposal).** `.claude/settings.json` allows
  `CAMERA_RAW_SAMPLE=`, `RAW_EDGE_SAMPLES=` and `RAW_CONTEXT_SOAK=` test runs
  but has no entry for `RAF_SAMPLE=* swift test *`, while `CLAUDE.md` says the
  commands it lists run without a prompt.
- **Q5** (the frame) and **Q7** (several LibRaw photos at 100%, for
  qa-tester) stand as written.

#### Checked and fine

- **The retry in `decode`.** Reached only when the system decoder gave no image
  for the stack's settings; the machine learning path reaches it through its
  classical decode and still reports `failed` for a raw the system reads. Its
  log line keeps the file name private. No file here takes it, so no stored
  stack renders differently: no pipeline bump is due, no golden moved, no
  tolerance changed.
- **`givesImageUntouched`.** `RAWDecodeSettings.none.apply` only pins the
  decoder version below 9, which changes nothing while the system's default is
  older, as on this macOS. In `AutoAdjuster.whiteBalance` the stack's settings
  are applied after it and end at the same version as before; `RawDefaults`
  reads the same values in the same state as before.
- **`LiveRenderSession`.** `libRawFrame`, `learn` and `decodeKey` are actor
  state and run on the session's actor; the header reads (`reads`, 20 to
  100 ms; `frameSize`, about 2 ms) are never on the main actor. After `learn`
  changes its mind the base is stored under the key that fits what made it; a
  base stored earlier under the other kind of key is still a decode of the size
  its key names. `LibRawDecoder.usesHalfSize` decides both the key and the
  decode from the same long edge.
- **`Decoded.decoder`.** Set by all five constructors: `systemRAW` only in
  `decodeRAW`, `libRaw` only in `decodeWithLibRaw`, the default for ImageIO.
- **Rules.** No UI string, no persisted name, no brand value, no migration, no
  catalog or sidecar write, no network, no subprocess, no new dependency.
  `Sources/CLibRaw` untouched. Tests are Swift Testing, no sleeps; the two
  blocks of `decodeSettingsDoNotDecodeAgain` that depend on what this macOS
  reads are skipped where their premise does not hold.

#### Security notes

A read of the new Swift bridge and the build settings only
(`Sources/PhotoCore/Preview/LibRawDecoder.swift`, `Package.swift`), with
LibRaw's side of each call checked in the vendored source. LibRaw's parsers
were not audited. Severity is for a local app that opens files the user
points it at, with no user action per file.

| # | Severity | What | Detail |
| --- | --- | --- | --- |
| S1 | Low | No frame size limit in the bridge (C17) | After `libraw_open_file` the frame comes from the header (16-bit sizes, so at most 65535 on a side); nothing in Swift refuses a large one. LibRaw refuses a raw buffer over 2048 MB (`max_raw_memory_mb`, left at its default, `unpack.cpp`), about a gigapixel. Beyond the raw buffer, a full decode holds LibRaw's image (8 bytes a pixel), the processed copy (6) and the Swift copy (8, `Data(count:)`, which traps if it cannot allocate). Measured: a 99 KB DNG whose header claims 12000 x 9000 fails in 0.07 s at 9 MB ("Unexpected end of file", then `undecodable`), so a hostile file has to hold the data, or data that expands to it (compressed payloads not tried); a 192 megapixel sparse DNG costs what C17 says. Denial of service only. |
| S2 | Info | `width`, `height`, `colors`, `bits` are trusted, not `type` or `data_size` | Safe with this LibRaw: `dcraw_make_mem_image` (`mem_image.cpp:277-304`) allocates exactly height x width x colors x bits/8 from the same four values it writes into the struct, and the bridge refuses anything but 16 bits and 3 colors before reading, so the loop reads `width * height * 6` bytes of a buffer of that size. All four are 16-bit, so `width * height * 8` cannot overflow. `data` is at offset 16 of a `malloc` block: aligned for `UInt16`. A check of `type == LIBRAW_IMAGE_BITMAP` (and of `data_size`, which is 32 bits and wraps above 4 GiB) would keep that true across LibRaw updates. A one-color (monochrome) raw is refused, not misread. |
| S3 | Info | `frameSize` and `Frame` | No allocation in Swift from header values. The inset subtraction is guarded (`insetLeft >= leftMargin`, `insetTop >= topMargin`), so `UInt32(…)` cannot trap; an inset larger than the visible area is clamped by LibRaw (`raw2image.cpp:374-377`), and one that leaves nothing returns `LIBRAW_BAD_CROP`, which the bridge throws. The path reaches LibRaw as a C string from `URL.path`; nothing is passed through a shell. `frameSize` runs LibRaw's whole header parse (`open_file`: identify and the maker-note parsers) on any raw whose size the system decoder does not give, from `PreviewGenerator.nativeSize`: that parse, not the bridge, is the exposed surface. |
| S4 | Info | Exceptions across the C boundary | `libraw_init` catches `std::bad_alloc`; `open_file` and `unpack` catch LibRaw's exceptions, `std::bad_alloc` and `std::exception`; `dcraw_process` catches the first two only (`dcraw_process.cpp:269-277`); `dcraw_make_mem_image` throws nothing and returns null on a failed `malloc`, which the bridge checks. The only other `throw`s in the tree are in code this build leaves out (the Windows datastream, RawSpeed). Should another exception leave `dcraw_process`, it meets Swift frames with no handler and the process ends (`std::terminate`): a crash, not memory corruption. By reading; not reproduced. |
| S5 | Info | Camera make and model strings | `String(cString:)` reads a copy of each 64-byte field with no length limit. LibRaw ends both at byte 63 after identifying the file (`identify.cpp:925, 983`), so it stops inside the copy. Only a test reads the strings. A bounded read would not depend on that. |
| S6 | Info | Build settings | `Package.swift` passes LibRaw one flag, `-w` (warnings off, for that target only), and defines nothing: thread-safe, no zlib, libjpeg, lcms, RawSpeed or DNG SDK, so those decoders are compiled out. Release objects are built `-Os` with exceptions on and the stack protector (Darwin's default; `___stack_chk_fail` is referenced). macOS headers apply checked `strcpy` and `sprintf` to C only, so LibRaw's are the plain ones. Optional hardening, tried in a scratch copy only (both build, and the 17 LibRaw tests pass; speed not measured): `_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_FAST` and `-ftrivial-auto-var-init=zero` on the target. The owner's call: the second is another unsafe flag. |
| S7 | Info | Where a parser bug would run | LibRaw is linked into both apps and `photocli` and decodes in process. The bundles `build-app.sh` makes are signed ad hoc without the hardened runtime, and the app is not sandboxed (as before this branch), so memory corruption in a LibRaw parser would run with the user's rights. Decoding in a helper process would be a feature of its own. |
| S8 | Info | Standard error | LibRaw's default callbacks print the file's full path there for a damaged file (seen: "…/claim-12000x9000.dng: Unexpected end of file" before `photocli`'s JSON). A fixed format string, local output only. `libraw_set_dataerror_handler` would silence it. |

**Known advisories for LibRaw 0.22.3** (the newest release, 2026-10-24;
looked up 2026-11-13 in the NVD by keyword and in LibRaw's changelog at tag
`0.22.3`). The NVD lists 70 entries for LibRaw; none names 0.22.3 as affected.

- Fixed before 0.22.3: CVE-2026-5318 and CVE-2026-5342 (0.22.1), and the six
  Talos reports of April 2026 (CVE-2026-20884, -20889, -20911, -21413, -24450,
  -24660; the changelog lists their fixes under 0.22.1).
- CVE-2026-88387 (`parse_tiff_ifd`, an out-of-range NewSubfileType converted
  to `int`; the NVD names 0.22.0, analysis deferred). 0.22.3 took upstream's
  type check and then reverted it, and added a not-a-number and infinity check
  in `getreal`; the vendored line (`src/metadata/tiff.cpp:572`) still converts
  a finite out-of-range value. That is undefined behavior in C++, reported as
  a crash under a sanitizer; arm64 saturates the conversion and this build has
  no sanitizer, and the value only selects DNG frames. No effect expected
  here; not reproduced.
- CVE-2026-111272 (Nikon ShotInfo read past a short buffer, "through 0.22.2").
  Upstream's 0.22.3 changelog calls it a false positive: the buffer comes from
  LibRaw's own allocator, which pads every block (1024 bytes in the vendored
  source, `init_close_utils.cpp:29`). Not checked beyond that.

`/security-review` on the branch is still worth running for the parser side:
this section covers the bridge and the build, not LibRaw's decoders.

### Fourth pass, 2026-11-13

Reviewed: `741878c`..`d54beb3` (three commits): `e125555` (`FujifilmRAF.swift`
and its tests), `42e11a5` (the camera's frame and the lens corrections in
`LibRawDecoder`, `EmbeddedLensCorrection.swift`, the `embeddedLens` kernel,
their tests, the notices and the user guide) and `d54beb3` (`status.md`). The
addition is the owner's ruling of 2026-11-13 recorded in `status.md` (Lens
corrections, new scope). Build and tests at `d54beb3`, working tree clean:
`swift build` complete; `swift test` 898 tests in 133 suites passed, the same 1
known issue (`LiveSessionTests`); `RAF_SAMPLE=/private/tmp/claude-501/x/DSCF5123.RAF
swift test --filter LibRawFallbackTests` 7 tests passed (52 s; `status.md` still
says 5); `Scripts/build-app.sh all` built both bundles (SDK 27.2, minimum 15.0,
ad hoc signature). macOS 27.2.1 (26B131). The app not launched.

**Verdict.** No blocker. The parser is bounded everywhere I could reach, the
math is darktable's second algorithm as its source has it, the kernel matches
its reference, and raws the system decodes are byte for byte as on `develop`.
Three Should fix: a class of old Fujifilm files now renders as garbage (C18,
from the first pass's crop code, found now), clipped highlights come out
brighter than white toward the corners (C19), and the layout newer cameras
write is read differently from darktable below its first knot (C20). C18 to
C20 each change what renders, so fixing them before qa-tester lets QA run
once; nothing else stops QA.

#### Third pass findings

| # | Outcome | How it was confirmed |
| --- | --- | --- |
| C16 | Not fixed: no answer in `status.md` | The retry still has no test. A nit; `qa.md` lists it as open. |
| C17 | Not fixed: no answer in `status.md` | No frame size cap in the bridge. For a RAF LibRaw now always decodes the whole visible area (no crop box), which changes nothing about the bound. A nit; `qa.md` lists it as open. |
| Q9 | With the designer | Unchanged by these commits. |
| Q10 | Open | `.claude/settings.json` still has no `RAF_SAMPLE=` entry; `CLAUDE.md` lists the command. |

#### New findings

| # | Severity | Where | Finding | Failure | Rule |
| --- | --- | --- | --- | --- | --- |
| C18 | Should fix | `Sources/PhotoCore/Preview/LibRawDecoder.swift:127-132,203-205` (the inset crop of `0f2b4ee`, not these commits; found now with new samples) | For a Fujifilm Super CCD file (LibRaw's `fuji_width` set: the sensor is read turned 45 degrees) the RAF's crop records are not a rectangle of LibRaw's visible area, and the bridge hands them to LibRaw as a crop box. The system decoder gives no image for these files, so they take this path. | Two public samples (raw.pixls.us, FinePix F700 and FinePix S5000), `photocli render`: 3511 x 755 and 3477 x 752, a strip of the scene with a magenta copy beside it. A scratch C program on the branch's `CLibRaw.o`: without a crop box LibRaw gives 2035 x 1533 and 2012 x 1521, the whole picture; with the bridge's crop box, the strip. `LibRawDecoder.frameSize` says 2832 x 1064 for the first, so `PreviewGenerator.nativeSize` is wrong as well. On `develop` these files say `undecodable`; here they are cached as garbage. No crop box when `rawdata.ioparams.fuji_width` is set would give the whole picture. The camera frame of these commits is refused for both files (it does not fit the sensor's size), so they did not make it worse; a FinePix S5 Pro's frame is refused the same way. | Correctness |
| C19 | Should fix | `Sources/PhotoCore/Edits/Kernels/LensKernels.swift:190-195`; `Sources/PhotoCore/Preview/EmbeddedLensCorrection.swift:136-138` | The vignetting gain multiplies whatever the decode holds, clipped values included. LibRaw's decode ends at its white (1.0); after the gain a clipped area is 1.0 at the center and up to 100 / vignetting toward the corner. Before these commits a clipped area was 1.0 everywhere. | The kernel on a decode that is 1.0 everywhere, the XF 35mm f/2's tables (compiled alone from the branch's sources): 1.00 at the center, 1.47 at the middle of the short edges, 1.73 in the corner. On a file: `photocli render DSCF5170.RAF --long-edge 300 --set exposure.ev=-3` (XF 14mm, 56% of the light at 0.85): the blown reflection at the left edge is linear 0.17 to 0.23 where white is 0.125 (34 pixels, all at 0.7 to 0.8 of the radius); in `DSCF5150.RAF` (the 35mm at f/2.8, 99.6% of the light at 0.4) the clipped area at 0.3 to 0.5 of the radius is 0.125, and in `DSCF5162.RAF` (tables that correct nothing) it is 0.124 to 0.125 at every radius from 0.1 to 0.7. So with Exposure or Highlights pulled down, a blown sky that reaches the corners is gray in the middle and up to 1.9 times brighter at the corners, a bright ring that was not in the photo, and `status.md`'s "what the decode holds (as a JPEG)" no longer bounds a LibRaw photo at white. The camera's JPEG and the system decoder clip after the gain. Capping the result at the decode's white is one way; the engineer's call. No test covers a clipped source. | Correctness |
| C20 | Should fix | `Sources/PhotoCore/Preview/EmbeddedLensCorrection.swift:79-86`; `Sources/PhotoCore/Preview/FujifilmRAF.swift:22,68-72`; `Tests/PhotoCoreTests/FujifilmRAFTests.swift:122-141` | The nine-knot layout's knots do not start at 0: both real files here (the X-T3 sample `DSCF4583.RAF` and a public X-T30 one) have 0.3535, 0.5 … 1, 1.0606. `value` holds the first knot's value from there to the center. darktable (`_init_coeffs_md_v2`, "add a knot with no corrections at 0 value if not existing") adds a knot at 0 with no distortion, no shift and full light, and reads linearly from it. `LensTables.knots` is documented "the first one 0", and the nine-knot test uses made-up knots that start at 0, so the difference is not exercised. | The X-T30 sample's tables (XF 35mm f/2, the owner's lens): −0.469% at the first knot. This code applies −0.469% from the center out, so the multiplier at the center is 0.99531, not 1, and green is taken up to 1.56 pixels (of 6240 x 4160, at 0.175 of the radius) from where darktable's reading takes it. The same lens's eleven-knot table in the owner's X-E3 file gives −0.027%, −0.11% and −0.302% at 0.1, 0.2 and 0.3: the distortion does go to nothing at the center. Against the X-T30 file's own JPEG (a scratch test, Q12) the corrected render is 2.3 to 2.6 pixels further out at 0.15 to 0.25 of the radius and back to 0.7 at 0.35, the first knot: the bump this predicts (darktable's reading would leave about 1; against the system decoder's image of that file the same places are only 0.3 and 0.6 out). The X-T3 sample's vignetting (98.46 at the first knot): gain 1.0156 at the center where darktable has 1, so the inner third of the frame is 1.6% brighter. Small, and no nine-knot file takes the LibRaw path on this Mac (the X-T3 and X-T30 are read by the system decoder); it is the layout every newer camera writes, which is where a camera macOS does not know yet will come from. `status.md` and the notices say the formulas are darktable's. | Correctness |
| C21 | Nit | `Tests/PhotoCoreTests/LibRawFallbackTests.swift:107-205`; `Sources/PhotoCore/Preview/LibRawDecoder.swift:249-271` | The part of `decode` that reads a RAF's tables and frame and applies them (which tables, the half-pixel resample, the whole-pixel cut, `fullSize`, the log line) runs only with `RAF_SAMPLE`: no default test names `hasLensCorrections` or `lensCorrections:`. The pieces it joins are well covered (see Checked). The light check of `theCorrectedRenderLinesUpWithTheCamerasJPEG` does not run on the documented sample (`DSCF5123`: "nan", too dark), so the documented command never checks vignetting on a file; it does on `DSCF5139` and `DSCF5170` (1.001, 1.003). | With `let tables = lensCorrections ? camera?.lens : nil` replaced by `nil`, `swift test` and CI stay green; only the run with a sample fails. By reading (the four mutations I ran were in the pieces, and all were caught). A synthetic RAF LibRaw can decode would be needed; leaving it as stated is acceptable. | Tests |
| C22 | Nit | `docs/features/raf-not-rendering/status.md` (Build and tests; Bug); `Sources/PhotoCore/Preview/EmbeddedLensCorrection.swift:32-36`; `Sources/PhotoCore/Preview/FujifilmRAF.swift:22`; `docs/USER_GUIDE.md:355` | Records out of step. `status.md` says the sample run is 5 tests (7 now). The correction's comment says the scale rule "is also what the camera does": it is for the three X-Trans samples below, not for the X-A5 one (Q12). "The first one 0" (C20). The user guide and the Bug section say the system decoder cannot read "the Fujifilm X-E3's" files: it reads a public uncompressed X-E3 file (raw.pixls.us `DSCF2175.RAF`, sensor 6160 x 4032) and gives its image at 6000 x 4000; the ones it gives nothing for are lossless-compressed (6048 x 4038: all 54 of the owner's folder by their headers, and the public `DSCF2176.RAF`, for which `SystemRAWDecoder.reads` is false). An X-T3's lossless-compressed file is read. A RAF whose tables are plausible but whose frame is refused is left uncorrected with no log line. | A reader is told something the code or the files do not bear out. | `docs/WORKFLOW.md` ownership |

#### Questions

- **Q11, engineer: the 1.25x crop modes (by reading, no sample here).**
  darktable multiplies the knots by 1.25 when the maker note's `CropMode` is 2
  or 4 (`exif.cc`, "Account for the 1.25x crop modes in some Fuji cameras").
  `FujifilmRAF` does not read `CropMode`, and `isPlausible` lets knots up to
  1.25 through, so such a file would have each table value applied at 0.8 of
  the radius it belongs to. No file here has the mode set (the X-T3 and X-T30 samples say n/a; the others have no such tag). The
  tags' leading value is not used either: it is the frame's half diagonal over
  the knot count in every file here (3605 / 11 for 6000 x 4000, 3749 / 9 for
  6240 x 4160), so comparing it with the frame would tell a file whose tables
  are for another frame, whatever the reason. Read the mode, check the leading
  value, or leave such files uncorrected?
- **Q12, engineer and owner: the scale rule against the camera, by lens.**
  With a scratch test that looks up blocks of the camera's JPEG and of the
  system decoder's image in the corrected LibRaw render (LibRaw called
  directly, also for files the system reads):

  | Sample | Table | Scale | Against the system decoder | Against the camera's JPEG |
  | --- | --- | --- | --- | --- |
  | X-E3, XF 50mm f/2 (public, uncompressed) | pincushion, +0.98% | 1.0098 | median 0.4, no trend by radius | median 1.6 (the system decoder's image: 1.3) |
  | X-T20, XF 18-55mm at 53mm (public) | pincushion, +3.84% | 1.0384 | median 1.3, rising to 2 at 0.75 of the radius | median 3.7 |
  | X-T30, XF 35mm f/2 (public, nine knots) | barrel, −8.9% | 0.9848 | median 2.3; within 3 out to 0.75, then −9 at 0.85 (37 blocks) and −22 at 0.95 (3 blocks) | median 1.8; −3 at 0.85, −17 at 0.95; the bump of C20 near the center |
  | X-T3, XF 23mm f/1.4 (`DSCF4583`) | no distortion | 1 | not run | the suite: 0.40 JPEG pixels |
  | X-E3, XF 35mm f/2 and XF 14mm (the owner's) | barrel −7.6%; none | 0.985; 1 | no image | the suite: 0.35, 0.43 and 0.27 JPEG pixels of 3.1 (`status.md`'s figures, reproduced) |
  | X-A5, XC 15-45mm (public, a Bayer body) | barrel −9.6% | 0.9618 | 3.6% smaller, evenly from the center out | 3.6% smaller; JPEG and system decoder agree to 1.6 |

  (Shifts in pixels of the full-size photo.) So for the X-Trans files the
  rule is the camera's and macOS's through the middle of the frame, for both
  signs of distortion. With barrel distortion the outermost tenth is off by 10
  to 22 pixels against either reference, which also differ from each other
  by about 6 at 0.85 of the radius (the X-T30 file): what `status.md` already lists for the owner ("what does
  not match the camera"), now seen on a second body. For the X-A5 file the
  camera and macOS both show the picture at its center scale (3.6% tighter,
  130 pixels at the corner) where this code and darktable show more of the
  scene. Lines are straight either way, and the X-A5 is read by the system
  decoder, so no photo in the app is affected today. Whether that difference
  is the body, the lens or the size of the correction I cannot tell from one
  file: worth a look with an X-E3 file taken with a strongly distorting zoom
  at its wide end, if the owner has one. Not a finding.
- **Q13, owner: the clean-room rule and darktable.** `CLAUDE.md` says no code
  from an existing photo application. The correction was written after reading
  darktable's source (GPL 3 or later, the app's own license), as the mask math
  was after LightCraft's, and `THIRD_PARTY_NOTICES.md` records it the same way.
  I compared the Swift and Metal with `lens.cc` and `exif.cc` at `master`: no
  line, identifier or comment is taken over, and the structure differs (the
  recorded radius is solved for by bisection and kept in a 1024-entry table
  where darktable resamples a spline at 16 knots; one kernel where darktable
  makes two passes). Please confirm the rule allows it, as for LightCraft.
- **Q14, owner: sharpness.** The resampling is bilinear (darktable uses the
  interpolation the user chose). And a half-size decode of an X-E3 file is
  resampled even without tables, because the camera's frame starts half a
  pixel down in it (row 7.5): each row is the mean of two. Accepted in
  `status.md` so that every size shows one frame; said here so it is a choice.
- **For qa-tester.** Thumbnails and previews cached by an earlier build of
  this branch are stale (`status.md`): start from an empty preview cache. A
  photo with a blown sky and Exposure −2 shows C19. Q7 stands. A 16:9 or 1:1
  RAF: by LibRaw's reading of the same records (`open.cpp:862-899`) the crop
  record stays the whole 3:2 frame and the aspect is a record of its own
  (0x115), which `FujifilmRAF` does not read, so such a photo would show the
  whole frame; no sample.

#### Checked and fine

- **Raws the system decodes are untouched.** `photocli render` of
  `/private/tmp/claude-501/cmp/in/DSCF4583.RAF` (X-T3) from a build of
  `develop` (`ef592d9`) and from the branch: the same SHA-256 for the PNG at
  600 pixels unedited, with a Kelvin white balance, with +1 EV, with a 0.3
  crop at 2560, with Highlights −80 and noise reduction at 1200, and at full
  size (6240 x 4160). The new code is reached only from `LibRawDecoder`
  (`decode` and `frameSize`); a file that is not a RAF costs one more open and
  a 108-byte read there, and keeps the path it had.
- **The layouts against darktable** (`exif.cc` at `master`, read today): which
  of the 23, 31, 23 and 19, 29, 19 values are knots, distortion, red, blue and
  vignetting, the missing first knot of the eleven-knot chromatic aberration
  tag, and the check that the three tags' knots agree, are as darktable has
  them. Against ExifTool on six real files (X-E3, X-T3, X-T30, X-T20, X-A5 and a
  FinePix F550EXR) the frames and every table value the parser returns are
  the ones ExifTool prints.
- **The math against darktable** (`lens.cc`, `_init_coeffs_md_v2` and
  `_process_md`): knots are radii of the recorded image over half its
  diagonal; the corrected radius is r / (1 + distortion / 100); red and blue
  multiply green's source radius by 1 + their shift at that radius; the scale
  is the largest multiplier of any color at 200 radii from the short side to
  the corner, applied to radii and multipliers; vignetting divides the source
  at the radius the sample comes from; beyond the last knot the last value
  holds; samples outside the image repeat its edge. All as the source has it,
  except C20 and Q11. The units are right: the kernel's `scales` turn pixels
  of output radius and of source radius into table positions, both clamped to
  the last entry, whose neighbor outside the table has no weight.
- **The frame.** 6000 x 4000 at (16, 15) of LibRaw's 6032 x 4028 for the X-E3
  file, the same at full and half size (3000 x 2000, from (8, 6.5)), and
  `nativeSize`, `frameSize`, `fullSize` and the live session's half-size rule
  all take it from one `Frame`. All eight orientations are checked pixel for
  pixel against LibRaw's `flip_index` (and with that line of `windowRect`
  removed in a scratch copy, flips 2, 3, 6 and 7 fail); a portrait file
  (`DSCF5139`, turned 270) passes the suite with the sample. On the X-T3
  sample LibRaw's frame is the system decoder's 6240 x 4160.
- **Tests fail without the code.** In a scratch copy: no gain for blue in the
  kernel, the mirrored rows left out of `windowRect`, blue read one value
  early in the eleven-knot layout, and the scale searched from the center:
  six tests fail across `EmbeddedLensTests` and `FujifilmRAFTests` (the
  reference, the half-float bound, the restored picture, four flips, the
  layout, the scale). The reference is plain Swift and shares only the lookup
  tables with the kernel; the tables are checked against the functions, and
  the functions against their inverse. Bounds are derived, no sleeps, no
  golden touched, `kernelsCompile` counts 8.
- **On real files** (`RAF_SAMPLE`, the suite as written): `DSCF5123` 7 passed
  (median 0.35 JPEG pixels, 90th percentile 0.85; uncorrected 5.7); `DSCF5139`
  (portrait) 0.43 and 1.43, light 1.001; `DSCF5170` (XF 14mm) 0.27 and 0.73,
  light 1.003; the X-T3 sample, nine knots, 0.40 and 0.87, light 1.000 (its
  premise test fails there, as it should: the system reads the file).
- **Kernel and fallback.** `embeddedLens` is in a library of its own, as the
  others. All kernels compile together, so a source that does not compile
  takes the Lens heading's kernels with it; `kernelsCompile` would say so.
  Without the kernel `apply` returns nil and `decode` cuts the frame on whole
  pixels and logs once per decode (file name private). A shared context never
  gave one lens's table to another photo: 30 renders of five lenses and two
  pictures in one context with cached intermediates equal fresh contexts'
  exactly (the fault of #55 does not show here).
- **Concurrency.** Everything new runs inside `LibRawDecoder.decode` and
  `frameSize`, which were already off the main actor; the new types are value
  types; building a correction takes about 1 ms (optimized).
- **Pipeline version.** No bump is due: on `develop` these files do not
  render, and no stack of a file the system decodes renders differently (see
  the first point). The caveat for libraries opened with an earlier build of
  this branch is in `status.md`.
- **Rules.** No UI string, no persisted name, no brand value, no migration, no
  catalog or sidecar write, no network, no subprocess (ExifTool is not used),
  no new dependency, `Package.swift` and `Sources/CLibRaw` untouched. The
  notices name darktable, its license and what was taken from where.

#### Security notes, fourth pass

`Sources/PhotoCore/Preview/FujifilmRAF.swift` is a new parser of untrusted
files, in process, run for every raw LibRaw opens (`frameSize` and `decode`),
with no action by the user. Read line by line, and fuzzed with a scratch
program that compiles the file alone: 2,000,000 damaged synthetic RAFs (random
bytes, boundary values over 32-bit fields, the header's six offsets and
lengths, IFD counts, types and offsets, truncation after damage, slices with a
non-zero start, one in fifty through the file handle) with no trap; 317,905 of
them gave tables, every one within `isPlausible`'s bounds, and the file handle
and in-memory readers agreed on every file.

| # | Severity | What | Detail |
| --- | --- | --- | --- |
| S9 | Info | Offsets, lengths and counts in `FujifilmRAF` | The header must be 108 bytes with the magic. Section offsets and lengths are 32-bit values widened to 64 bits before any sum. Reads are capped (1 MiB of records, 64 KiB of the raw section) whatever the header claims, and a short read is checked wherever bytes are indexed (`parseRecords` guards the count; each record's four bytes and its length are checked against what was read; at most 4096 records). An IFD offset must be at least 8 and its 2 + 12 x count bytes inside the 64 KiB (at most 512 entries); there are two levels and no loop to follow. A table is 1 to 64 signed rationals of type 10 whose bytes must lie inside what was read. No allocation is sized by a file's value beyond those caps, no path comes from the file, and nothing is written. |
| S10 | Info | Values that reach the kernel | A zero denominator is NaN and is refused with every other non-finite value. `isPlausible` then bounds distortion to ±30%, shifts to ±2%, vignetting to 5 … 200 and knots to ascending within 0 … 1.25, so the source radius is 0.69 to 2.04 times the corrected one, the multipliers the kernel reads (that over the scale, which has the same range) stay within about 0.3 … 3, and the gain within 0.5 … 20, all finite; the lookup tables are 1024 x 2 whatever the file says; the kernel clamps table positions and the source is clamped to its extent; the region of interest is the output rectangle scaled by the smallest and largest multiplier. Knots a damaged file could still carry (10⁻¹² apart, subnormal spacing, values jumping between −30 and 30, 5 and 200) make the solved radius any root of a function that is no longer monotonic: 60 such tables rendered a finite, wrong picture in at most 8 ms each. A garbage picture, no crash, no growth. |
| S11 | Info | The camera frame from the file | Used only when it lies inside LibRaw's visible area, so the output is never larger than LibRaw's image and the resample never reads outside it. A file can claim a frame as small as 1 x 1: its picture is then that small, and every decode of it is a full one (the half-size rule compares with the frame). Bounded by C17's bound. |
| S12 | Info | `embeddedJPEG` | A range taken from the header with no check against the file's size (up to 8 GiB long). Only a test reads it. If app code ever does, cap the read. |
| S13 | Info | Two opens of one file | `FujifilmRAF(contentsOf:)` opens the file after LibRaw has. A file swapped in between gives a frame from one and sizes from the other; the frame is still checked against the sizes in use. |

Hostile tables and frames cost a wrong picture at worst. S1 to S8 stand;
C17 (no cap on the frame LibRaw decodes) is still open and is now also the
bound for a RAF, which is always decoded whole.

`/security-review` should run on the branch: it now has a second parser of
outside files in process, besides LibRaw.

### Fifth pass, 2026-11-13

Reviewed: `a2e5b19`..`a2301a9` (three commits): `aaf4ab5` (`FujifilmRAF`: the
knot at the center, the tables' frame radius, the crop mode from the embedded
JPEG's Exif, tests), `20fb3b5` (`LibRawDecoder`: Super CCD frames, the size
cap, the `framed` and `lensTables` seams; white after the gain in the kernel
and its reference; `PreviewGenerator.rawImage`; tests; the user guide) and
`a2301a9` (`status.md`). Build and tests at `a2301a9`, working tree clean:
`swift build` complete; `swift test` 906 tests in 133 suites passed, the same 1
known issue; `RAF_SAMPLE=/private/tmp/claude-501/x/DSCF5123.RAF swift test
--filter LibRawFallbackTests` 7 tests passed (50 s, the figures of the fourth
pass to the digit); `Scripts/build-app.sh all` built both bundles (SDK 27.2,
minimum 15.0). macOS 27.2.1 (26B131). The app not launched.

**Verdict.** Ready for qa-tester. C16 to C22 are fixed and Q11 is answered in
code; each fix has a default-run test that fails without it, and the three that
change a render were also confirmed on real files. One new nit (C23, the
cap's number, which `status.md` already leaves to the owner). Raws the system
decodes are still byte for byte as on `develop`.

#### Fourth pass findings

| # | Outcome | Commit | How it was confirmed |
| --- | --- | --- | --- |
| C16 | Fixed | `20fb3b5` | The order of decoders is `PreviewGenerator.rawImage`, which `decode` calls with the same three steps as before (read side by side: the system decoder with the stack's settings, then without its decoder choices with the log line, then LibRaw). `decoderOrder` drives it with stand-ins; with the retry switched off in a scratch copy it fails. |
| C17 | Fixed | `20fb3b5` | `decode` throws `Failure.tooLarge` after `libraw_open_file` when raw width times raw height is over 150,000,000, before anything is unpacked, and `frameSize` is nil for such a file; the reason reaches the log through `decodeWithLibRaw`. `sensorSizeLimit` fails with the limit raised in a scratch copy. See C23 for the number. |
| C18 | Fixed | `20fb3b5` | A file with `fuji_width` set gets no crop box and no camera frame; its frame is the size LibRaw works out from the header on an instance of its own (`libraw_adjust_sizes_info_only`, which already turns the size for flips 4 to 7, as `Frame` expects). The public FinePix F700 and S5000 samples render whole through `photocli`: 2035 x 1533 and 2012 x 1521 (were 3511 x 755 and 3477 x 752), looked at; `nativeSize` now equals the decode for both. A RAF's camera frame is used only when the records' sensor size is the one LibRaw reads: `theFrameIsTheCameras` still passes on eleven real files (the owner's X-E3, two public X-E3, X-T3, X-T30, X-T20, X-T2, X-Pro2, X-T5, X-A5, X100). |
| C19 | Fixed | `20fb3b5` | `min(…, 1)` on the three channels in the kernel and in the reference. `photocli render DSCF5170.RAF --long-edge 300 --set exposure.ev=-3`: the blown reflection at 0.7 to 0.8 of the radius is 0.124 and 0.125 (was 0.17 to 0.23; white is 0.125). `gainEndsAtWhite` renders a white and a part-clipped picture; without the `min` it fails, and so do the reference, half-float and decode tests. The decode's working space is the kernel's (linear Rec. 2020), so 1 is the decode's white in every channel. |
| C20 | Fixed | `aaf4ab5` | A knot at 0 with no distortion, no shift and all the light is put before knots that start further out, as darktable does. All four real nine-knot files here (X-T3, X-T30, two X-T5) now read ten knots from 0. The X-T30 file against its own JPEG, the scratch test of the fourth pass: 0.6 and 1.2 pixels at 0.15 and 0.25 of the radius (were 2.3 and 2.6), median 1.5 (was 1.8). `readsARealNineKnotLayout` uses the X-T3 file's values and fails without the knot. |
| C21 | Fixed | `20fb3b5` | What `decode` does with LibRaw's image is `LibRawDecoder.framed` and `lensTables`, tested by default (`decodeFramesAndCorrects`: the cut, the correction against the reference, the half-pixel resample, `fullSize`, a frame LibRaw cropped itself; `whichTablesADecodeUses`). What is left in `decode` is the one call that joins them. |
| C22 | Fixed | `aaf4ab5`, `20fb3b5`, `a2301a9` | `status.md` says 7 tests and lossless compressed X-E3 files, as do the user guide and `rawImage`'s comment; the scale rule's comment names the X-A5 exception; a file whose tables are not used says why in the log (file name private, reason public). |
| Q11 | Answered in code | `aaf4ab5` | `cropMode` reads 0x104D from the maker note of the embedded JPEG's Exif; `frameRadius` is the tags' leading value times the knot count; tables are used only outside modes 2 and 4 and when that radius is the camera frame's half diagonal within 2 pixels. On twelve real files with tables and no crop mode the radius is the frame's to under a pixel (3605.00 against 3605.55, 3749.00 against 3749.77, 4643.00 against 4643.95, 2573.00 against 2573.81, 2030.00 against 2030.00) and none is refused; the mode reads 0 where ExifTool prints 0 (X-T3, X-T30, X-T5) and nil where the file has no such tag. A real crop-mode file (public X-T5, `DSCF4964_70-300.RAF`, ExifTool: mode 2): read as 2 and refused; see the note below. |

#### New finding

| # | Severity | Where | Finding | Failure | Rule |
| --- | --- | --- | --- | --- | --- |
| C23 | Nit (the owner's number) | `Sources/PhotoCore/Preview/LibRawDecoder.swift:57-66`; `Tests/PhotoCoreTests/EmbeddedLensTests.swift` (`sensorSizeLimit`); `status.md` (C17) | The comment and `status.md` say 150 megapixels is "above every camera's single frame (the largest medium format backs)". The test's own comment says the 150 megapixel backs (14204 x 10652, 151.3 megapixels before their margins) are refused. | A raw of such a back that the system decoder gives no image for is `undecodable` with "over the 150 megapixels LibRaw is given here" in the log. No such file here; whether macOS reads them I did not check. 160 megapixels would take them at about 3.5 GB a full decode by the comment's own 22 bytes a pixel. Either the number or the sentence. | Correctness of a record; the cap itself is as asked in C17 |

#### Notes

- **The crop-mode file.** In the public X-T5 file shot in mode 2 the tables'
  radius is still the whole frame's (4643) while the camera's frame is 6000 x
  4000 (half diagonal 3605.55): 1.288 times, not darktable's 1.25. So the
  radius check alone tells such a file, and the knots times that ratio would
  be the exact reading if these files are ever to be corrected. Today the file
  is refused twice over (LibRaw's visible area for it is 6000 x 3997, three
  rows short of the camera's frame, so it keeps LibRaw's frame and the log says
  its frame is not part of LibRaw's image), and the system decoder reads it
  anyway. A follow-up at most (below); nothing to fix here.
- **Against the system decoder** the X-T30 file's middle moved from 0.3 and
  0.6 pixels out to 0.9 and 0.3 in at 0.15 and 0.25 of the radius: macOS reads
  the nine-knot table nearer the old way. Under a pixel either way; the camera's
  JPEG and darktable agree with the new reading.
- **Q10** is still open (`.claude/settings.json` has no `RAF_SAMPLE=` entry).
  **Q12 to Q14** are the owner's, as `status.md` says; **Q9** the designer's.

#### Checked and fine

- **Raws the system decodes are untouched.** The six `photocli render`
  variants of `/private/tmp/claude-501/cmp/in/DSCF4583.RAF` of the fourth pass
  have the same SHA-256 as `develop`'s again.
- **Tests fail without the fixes.** Seven changes undone at once in a scratch
  copy (the `min` in the kernel, the knot at 0, the crop mode refusal, the
  radius check, the sensor size and Super CCD conditions of `cameraFrame`, the
  size limit, the retry in `rawImage`): ten tests fail, at least one for each.
- **The new parser code** (`cropMode(inJPEG:)`, `cropMode(inExif:)`): the JPEG
  must start FF D8; each segment's four header bytes are checked before they
  are read, a length under 2 or a start of scan ends the walk, and every step
  advances at least four bytes; the Exif payload is cut to what was read; IFD0,
  the Exif IFD and the maker note's IFD go through the same bounded `entries`
  as the Fujifilm IFD; the note must be at least 12 bytes and lie inside the
  segment before its header is read; the value must be one SHORT. At most
  64 KiB + 16 bytes of the JPEG are read, whatever its length says.
- **`frameRadius`** is refused when not finite (a zero denominator in the
  leading value), with the tables.
- **Super CCD frames at half size.** `fullSize` falls back to twice the
  decode, within a pixel of `frameSize`, as for every frame LibRaw sizes
  itself.
- **Rules.** No UI string, no persisted name, no migration, no catalog or
  sidecar write, no network, no subprocess, no new dependency; `Package.swift`
  and `Sources/CLibRaw` untouched; no golden moved; no pipeline bump is due
  (these files do not render on `develop`). The user guide says what the
  code does (blown highlights, crop mode, Super CCD).

#### Security notes, fifth pass

The parser grew by the Exif walk above. The fuzzing of the fourth pass was run
again on the new source, with an Exif segment and maker note in every file and
two more kinds of damage aimed at them (marker lengths, the Exif header, IFD
counts and offsets, the note): 3,000,000 files, no trap; 2,013,163 returned a
crop mode, all within 0 … 65535; 749,111 returned tables, every one plausible
with a finite radius; `lensTables(for:)` never returned tables together with a
refusal; the file handle and in-memory readers agreed on all 60,000 files run
through both.

| # | Severity | What | Detail |
| --- | --- | --- | --- |
| S1 (C17) | Closed | The frame size limit | 150,000,000 pixels of raw width times raw height, checked after `libraw_open_file` and before `libraw_unpack`, in `decode` and in `frameSize`. The product of two 16-bit values cannot overflow. |
| S14 | Info | The Exif walk | As under Checked. It adds one read of at most 64 KiB + 16 bytes per parse and no allocation sized by a file's value beyond that. A hostile crop mode or leading value can only turn the corrections off for its own file. |
| S15 | Info | A second LibRaw instance for Super CCD files | `diagonalOutputSize` opens the file again for a header parse (`libraw_open_file`, `libraw_adjust_sizes_info_only`): the same surface as `frameSize` (S3), once more per decode of such a file. Closed on every path. |

S2 to S13 stand. `/security-review` should still run on the branch.
