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
