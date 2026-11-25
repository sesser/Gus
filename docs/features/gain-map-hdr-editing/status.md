Issue: #282 · Complexity: Hard

# Edit and show gain-map photos in HDR: implementation status

Owner: swift-macos-engineer. Branch `feature/gain-map-hdr-editing`, from
`7bf972d` (develop merged in). Spec: the PRD (issue #282's body, revised
2026-11-25 for RI-6 and RI-7; read from the scratch copy the main session
gave, GitHub was refusing the body update) and `design.md`; evidence from
spike #285 (`docs/features/gain-map-hdr/spike.md`).

**State: Done** (2026-11-25, after QA's first pass). Stage 1 passed
the owner's early check; stage 2 built the rest of the PRD and design; the
first-pass findings of `code-review.md` and `review.md` are fixed or answered
below ("Review round 1"), and the second pass's open ones (F1's rest, F11, C8,
C9) under "Review round 2". QA's findings Q1 to Q5 (`qa.md`, first pass) are
fixed under "QA round 1"; Q3's layout waits on the designer's confirmation
(DQ-2, below). Every acceptance criterion is built and mapped to a test or a
check below; nothing is blocked. What only a person can check is listed under
"For a person". Next: code review (a risk area: rendering of HDR pictures) and
the designer (Q3 changes the loupe caption), then QA again.

States: Not started · In progress · Done · Blocked · Deferred.

## Early check (design §13): passed

The owner ran E1 to E4 on 2026-11-25 and reported, in full: "All four pass.
The built-in display showed 2.6x I think. It looks good and works as it
should". Q2 stands. The "2.6x" is from memory and not a measurement (design
§13.1).

DQ-1 (the second, smaller change on arrival on a screen that allows less
than the photo needs): the designer ruled option (a) (design §18.1) and the
owner accepted it on 2026-11-25: "Yes, Accept it. I did notice it in fact.
It's fine". Recorded in the PRD as RI-6 (R6, R8, AC7, AC18). Built as §18.1
says; the rule is `DisplayHeadroomReading.read` and `DisplayHeadroomMemory`
(PhotoCore), so changing it touches one type and its tests.

## Stage 2: where the choice is stored, and why

**Decision: an edit-stack operation, with a copy in the catalog.** The choice
is one operation in the version's edit stack (kind `hdr`, parameter `on`,
schema 1, left out when off: `Edits/HDRChoice.swift`), and migration v17 adds
`version.hdr`, a copy of it written with the stack.

- In the stack because R2 and the owner's Q3 ruling make it an edit like any
  other: one undo step, one History entry, a History revert restores the
  entry's value (entries older than the feature have no operation, so off),
  Reset All Adjustments removes it (`resettingAll`), a virtual copy starts
  with it, and each file of a pair has its own. All of that comes from the
  stack's existing paths with no new code. A `version` column alone would
  need its own undo step and would not be in History snapshots.
- Left out of `EditStack.renderHash` (and `isIdentity`) because it changes no
  SDR pixel (R12): toggling keeps every cached preview, and previews, exports
  and `photocli render` are byte for byte the same either way. No existing
  stack holds it, so no existing hash moved; no pipeline bump.
- Not a `Group`: presets, Copy Adjustments and paste never carry or change it
  (R3; `replacing` and `CopiedAdjustments.pasted` copy groups only).
- The `version.hdr` column exists because the loupe must know the choice
  before it reads the stack: to show an HDR rendition already in memory on
  arrival (design §6.1), to preload neighbors with the choice on, for the
  comparison panes and the export notice. It is written in the one place
  every stack write goes through (`Catalog.setEditStacks`), copied with a
  virtual copy and set again when Undo of Duplicate's removal puts a copy
  back (`storeHDRChoice`). `CatalogItem.hdr` carries it. It is deliberately
  not a property of `VersionRecord`: migration v2 reads and writes version
  records before v17 exists (the full suite caught this). An older build
  writing a stack does not update the column; the editor reconciles it from
  the stack whenever it opens the photo.

## Stage 2: progress

Built (commit "The stored HDR choice replaces the temporary switch"):
- The choice in the stack and catalog (above); `photocli develop --set
  hdr.on=true|false` and `--reset hdr` (R17, AC15): turning it on reads the
  original's header and refuses a file without a gain map (`invalidEdit`) or
  an original it can't read (`fileNotFound`); `photocli adjustments` lists
  the `hdr` module (no group); `query images` shows it in the stack.
- Editor: `hasGainMap` (header read with the other per-file facts, before the
  tab lays out), `setHDR` (**Turn On HDR** / **Turn Off HDR**, one undo step
  and History entry), live frames HDR exactly when the values rendered have
  the choice on, Show Original keeps the choice (unedited HDR, R8).
- Adjust tab header: the **HDR** check box after Original (design §2.1);
  Adjust ▸ Turn On / Off HDR above Auto Exposure (§2.2); View ▸ Show / Hide
  HDR (§3).
- Loupe: the visit follows the shown photo's choice (the editor's values once
  ready, else `CatalogItem.hdr`); changing it starts a new visit with the old
  picture kept until the new one; neighbors with the choice on are preloaded
  in HDR; a failed HDR version keeps the visit SDR (design §5, reason 4).
- Version badge and reasons (§4, §5, §12): `HDRVersionBadge` (PhotoCore, the
  rule) and `HDRText` (words); the caption shows one badge, a warning triangle
  for a reason, a short form when the row is too narrow (`ViewThatFits`
  bounded by the centered culling marks), the spinner after 0.5 s.
- What a screen allows (§18.1, §18.2): `DisplayHeadroomMemory` per screen in
  `LibraryModel`, outliving the loupe; a reading at a lower request keeps the
  remembered value; one showing more replaces it; readings while the app is
  not active are followed, not kept, and dropped on activation.
- HDR histogram (§7): `HDRHistogram` (153 SDR + 102 HDR bins, fixed +3 stop
  axis, share above white) from the whole HDR version at the file's full
  brightening, computed with each HDR live frame; `HDRHistogramView`; the
  Tone Curve keeps the SDR histogram (§7.3).

Built (commit "The gain map follows Distortion and spots; every adjustment tested in HDR"):
- R19: the gain map goes through Distortion's warp, then the spots (heal and
  clone, the spot's own mode), then turns, straightening and crop
  (`AdjustmentRenderer.gainMapGeometry`, used by `GainMap.placed(over:values:context:)`
  in the settled render, live frames and region frames). Lens Vignetting,
  Color Alignment and Color Fringes move nothing a one-channel gain map holds.
- AC6 and AC17 tests (`GainMapAdjustmentTests`), below under Tests.
- A test-harness fix: `GainMapHDRTests.Pixels` rendered CIImages in a default
  context (linear sRGB working space), so a recipe built for the app's
  working space (Black & White's matrix, Saturation, Vibrance) was measured
  differently on its SDR side than the engine rendered the HDR side. Black &
  White read as 0.40 stops RMS of drift; with the app's working space it reads
  as the others. Found by probing: Core Image's `applyingGainMap` scales each
  pixel by one factor (flat colors, ISO maps: exact; IMG_0561's map: within
  3%), so a gray picture stays gray in HDR.

Built (commit "Crop, comparison and the export notice in HDR"):
- Crop session (§8): the image under the frame is the HDR version (the live
  session renders it with the choice's headroom), in an extended-range layer
  of its own, rendered again when the headroom moves; the shade, frame,
  handles and grid are drawn as before.
- Maps (§8, RI-4): no version badge while a map shows; the HDR histogram's
  last counts stay (`LibraryModel.loupeHistogramIsHDR`, set by the visit, not
  by the badge).
- Comparison and review (§9): each pane shows its photo's choice (gain-map
  HDR rendition at fit and 100%, never replaced by SDR in that showing, a
  failure keeping it SDR), its own version badge (`comparisonHDRStatus`),
  which never drops from a narrow caption and takes its short form last; a
  choice-off photo's header is read once so its pane can say SDR. Panes read
  the screen into the same per-screen memory as the loupe (§18.1) and
  re-render when it moves. The inspector's HDR histogram follows the active
  pane (`PreviewService.gainMapHDRHistogram`, a 512 px render of the whole HDR
  version). Review is the loupe.
- Export notice (§10): "1 photo has HDR on. Exports are SDR." / "%lld photos
  have HDR on. …" (plural variations) under the subtitle, `info.circle`,
  counted over the sheet's photos when it opens (`ExportTargets.hdrCount`: a
  pair that exports its raw doesn't count; videos never).
- VoiceOver (§12): the loupe canvas's value includes the badge's phrase,
  without announcing a change of it alone.

Built (commit "HDR frames render the graph once; tests for SDR output, measurements, histogram, timing"):
- R11: an HDR live frame first rendered the whole adjustment graph three
  times (the frame, the SDR histogram's reduction, the HDR histogram's), 2.5
  to 3.2 times an SDR frame. Now the edited SDR frame is rendered once into a
  half-float IOSurface (`RenderEngine.materialized`) and the HDR frame and
  both histograms read it; the gain map is scaled to the frame as the decode
  is. Live and settled frames still agree (AC8 test unchanged and passing).
- Tests for AC9, AC11, AC12, AC13 and the timing run (AC10), below.

## Review round 1 (2026-11-25)

Fixes for `code-review.md` (first pass, `3c3867f`) and `review.md` (with
design §19), commits `507edc2`, `27f5899`, `4790f7f`, `d5e2486`. The designer
read code only, so each finding was reproduced first where a test or the
debug script could; "reproduced" below means a run of code without the fix
showed it. Debug-script runs: a copy of the bundle with identifier
`me.sesser.gus.debugtest.hdrreview282`, scratch libraries in the session
scratchpad (copies of the owner's three HEICs; for offline, the same copies
on a FAT32 disk image detached and attached again while the app ran),
shell-started, on the DELL U2723QE (potential 4.18).

| Finding | Outcome | Test or check |
| --- | --- | --- |
| C1 (offline: HDR in memory shown under SDR; "HDR Failed" after a remount) | Fixed. The loupe and panes never ask for or show the HDR version while the original is offline (`possibleHeadroom`); a visit, or a pane, reloads when HDR becomes possible or impossible in place (`reloadIfHDRPossibilityChanged`, on `show` and the 0.25 s headroom poll), so going offline shows the cached SDR preview and a remount brings HDR back without reopening; only a real error is a failure (`PreviewService.gainMapHDROutcome`). | `GainMapHDRTests` "Code review C1, C3: only a real error is a failure…" (cancellation, `staleEditStack`, `sourceUnavailable` and an offline request are not; a render error and a file without a gain map are). Script (disk image detached with the HDR photo open, then attached): offline `shown sdr`, badge `sdr offline`, `versions sdr`; back to the photo while offline `versions sdr` (no HDR from memory); after the attach, still open: `shown hdr`, `hdr fitted`, `failed false`. |
| C2 (pane: preview-size HDR replacing full resolution) | Fixed as proposed: the `\|\|` clause is gone; refits render at the size shown, so they still pass `kind >= rendition`. | Timing-dependent, not reproduced (as in the review). By reading: no path needs the clause. |
| C3 (`staleEditStack` counted as a failure) | Fixed with C1 (a request a newer save replaced is `superseded`). | The C1 test's stale-stack case (a service whose saved stack differs from the request's hash). |
| C4 (`hdr` operation turned off read two ways) | Fixed: `Adjustments.hdrIsOn` reads the choice as `EditStack.hdrChoice` does (on and not turned off), and setting it turns the operation on; every app read goes through it (check box, menu, loupe, editor, Show Original's values, debug print). | `HDRChoiceTests` "Code review C4: a turned-off `hdr` operation reads as off…" (both readings off, written back unchanged, turning it on agrees again). |
| C5 (older build editing the library) | Closed, no change: the owner's ruling on code-review Q1, 2026-11-25, asked "Does an older app build ever need to edit a library that this new build has opened?": "No, ignore it". | n/a |
| C6 (v16 doc comment above the v17 function) | Fixed. | Read. |
| C7 (stale comments) | Fixed (`LiveRenderSession.render`, `GainMap.hdr`). | Read. |
| F1 (no or stale HDR histogram after Show HDR) | Reproduced, fixed. The editor renders a frame for the counts whenever its headroom goes from none to a value with the choice on (View ▸ Show HDR, a display that gains range, a failed visit replaced), and drops HDR counts when an SDR frame of other values lands. | Script, the review's check: `hdr off`, open the photo, `hdr on`: without the fix `histogram none shows hdr histogram true` (reproduced); with it `histogram hdr above white 0.027`, inspector `hdr`. Hide, Exposure −1, show: counts dropped while hidden (`histogram none`), then new ones (0.011). |
| F2 (SDR counts under HDR on arrival; other pane's counts) | Fixed per §19.2: while HDR is on screen and its counts aren't there, the inspector draws the HDR frame with no curve and VoiceOver gives the label with no value (`LibraryModel.showsHDRHistogram`, `hdrHistogramCounts`); in comparison it reads the active pane's badge, and a new active photo clears the old counts first. | Script: `print hdr` and `print compare` now print `inspector histogram hdr|hdr empty|sdr`; the F1 run without its fix showed `hdr empty` (never `sdr`) under the HDR picture; a side switch shows the new photo's share. The moment between is too short to catch by script on these files. |
| F3 (Turn Off HDR flashes the old HDR frame) | Reproduced, fixed: a live frame (or tile) of the other choice, or an HDR frame once HDR can't be shown, never goes on screen and doesn't cancel the renditions loading. The second half was found while checking F1: hiding HDR, then an edit, put the last HDR frame up under **SDR: HDR Hidden**. | Script: settled HDR, `adjust hdr off`: without the fix `versions sdr,hdr,sdr` (reproduced, both cases); with it `versions sdr`. |
| F4 (no spinner in comparison) | Fixed: each pane's caption shows the mini spinner beside its version badge after 0.5 s of loading, with the badge's never-drop rule (`comparisonHDRSpinner`). | Script prints each pane's `spinner`; on these files the HDR version arrived inside the 0.7 s the `compare` command waits even cold, so the spinner's appearance is a check for a person (below). |
| F5 (fringe slot picked again at 100% never sharpens) | Fixed: `SharpeningMapRefiner` renders the photo refinement in HDR when given a headroom; the editor passes the values' headroom. | `GainMapHDRTests` "Review F5: the full-resolution photo refinement… is HDR" (tagged, same mean and maximum as the full-resolution HDR render within 0.005 and 0.01 stops, brighter than the SDR refinement, maps stay SDR). By eye: for a person (below). |
| F6 (screen gains or loses range in place) | Fixed in the loupe and the panes (the C1 mechanism). | Script `hdr display flat` (new: the screen's potential reads 1 in place, with no View-setting reload): loupe and both panes go to **SDR: No HDR Display** with SDR on screen; `hdr display system` brings HDR back without reopening. Whether macOS changes a potential without a screen notification is still M12's. |
| F7 (failure after HDR on screen keeps HDR) | Fixed: a failed visit (or pane) with HDR on screen loads the SDR renditions, keeping the failure for the rest of the opening; live frames turn SDR through the editor. | Script: HDR on screen, `hdr fail on`, an Exposure change: `shown sdr`, `sdr failed`, `versions hdr,sdr`. |
| F8 (offline help tag names a dimmed command) | Fixed per §19.1: `HDRVersionBadge.sdr(offline:)`; the badge and VoiceOver label unchanged. | `HDRChoiceTests` badge test (`.sdr(offline: true)`, `sdr cached`); script, offline: help "Showing the cached SDR preview. This file also has an HDR version, which needs the original." |
| F9 (pane VoiceOver value lacks the version) | Fixed: the pane's value has the badge's phrase; a change of it alone is not announced (`withVersion: false` for the comparison). | Script `print compare`: "Left photo, Showing the HDR version, fitted to this display, 1 of 3"; under a reason "… HDR is on, showing the SDR version: this display can't show HDR, …". |
| F10 (user guide) | Fixed: Show HDR wording, the reasons as a list after the sentence, Reset All from the grid and cropping, the second fit's frequency; also the pane spinner, the empty histogram, HEIC and JPEG only. | Read. |
| §19.1, §19.2 | Built (F8, F1, F2). | As above. |
| §19.3 (help tag before the file's headroom is known) | Accepted as built; nothing to do. | n/a |
| Designer's note: `GainMap.eligibleSource` not limited to HEIC and JPEG | Real, fixed. On macOS 27.2 ImageIO neither writes nor reads a gain map in a TIFF or PNG (probe: auxiliary data added to both is not read back), so a true TIFF or PNG gain map can't be made here; but the check took any file by content, so a JPEG named `.tif`, `.tiff` or `.png`, or an AVIF (whose gain map ImageIO does read) named `.heic`, got the choice. Now HEIC, HEIF and JPEG only, by name (`FileKind`) and content type (`public.heic`, `public.heif`, `public.jpeg`). | `GainMapHDRTests` "AC1: only a HEIC or JPEG, by name and content…": fails without the fix (8 expectations: the three misnamed copies and the AVIF), passes with it; `.HEIF` and `.JPEG` names still count. |

Also: a test helper's `#require` passed an optional size through unchanged
(the compiler warned); it now unwraps. Found, not fixed (not this branch's): a
photo opened while its original is offline keeps the Adjust tab's offline
state after the volume returns until it is opened again
(`AdjustmentEditor.follow` returns early for the same version); the loupe's
picture and badge recover (C1). Proposed as a follow-up below.

Determinism of the new tests: structural. They render fixed synthetic files
and compare against tolerances 10 to 100 times half-float rounding, or test
pure values (`supersedes`, the badge, `hdrIsOn`, `GainMap.exists` on fixed
files); no shared state, timing or pool order. The outcome test's stale case
depends only on the service's stack closure, not on timing.

## Review round 2 (2026-11-25)

Fixes for the open findings of `review.md`'s second pass (F1's rest, F11; design
§19.2, §19.4) and `code-review.md`'s Follow-up (C8, C9), commits `c629de3`
(F1, F11), `1215ef4` (C8), `033458e` (C9). Each was reproduced first on code
without its fix. Debug-script runs: a copy of the bundle with identifier
`me.sesser.gus.debugtest.hdrreview282b`, scratch libraries in the session
scratchpad (copies of the owner's three HEICs, the photo with HDR on is
IMG_0561; for offline, the same copies on a FAT32 disk image detached and
attached again while the app ran), shell-started, on the DELL U2723QE
(potential 4.18; the inactive app reads 1.0 now, so `allowed 1.00` unless
`hdr display` overrides it).

| Finding | Outcome | Test or check |
| --- | --- | --- |
| F1 (rest: at 100%, Show HDR left the histogram an empty frame) and F11 (at 100%, a live frame didn't follow the headroom) | Reproduced, fixed (one cause, as the review said). A frame and a tile now record the display headroom they were asked for (`requestedHeadroom`, nil for SDR), and the editor's two skips in `requestRender` count a frame as current only when it shows the same values and overlay **and** was asked for the same thing now: SDR, or HDR at the same headroom within `GainMapHeadroom.tolerance` (`LiveFrameRules.isCurrent(…frameHeadroom:…headroom:)`, `rendered(for:wanted:)`). So Show HDR or a display move at 100% renders the whole frame that gives the HDR counts, and a headroom change with live frames up renders the tile again. The caption's sharp-frame spinner still ignores the headroom: following the display is no wait (design §6.3). | `GainMapHDRTests` "Review F1, F11: a frame is current only for what it was asked for…" (the rule both ways, the tolerance, values and overlay still count; both renderers record the request, an SDR file's frame too; only the HDR frame carries HDR counts). Script F1 (the review's: `hdr off`, open, `zoom`, wait, `hdr on`, wait 5 and 8 s): without the fix `live frame sdr tile hdr 1.00 … histogram none … inspector histogram hdr empty` at both waits (reproduced); with it `live frame hdr 1.00 tile hdr 1.00 … histogram hdr above white 0.381 … inspector histogram hdr`. Also at 100% from `hdr display sdr` to `system` (a move to an HDR display): `inspector histogram hdr`. Script F11 at 100% (`print hdr` now prints the tile): with Show Original, `hdr display 3` then `2`: without the fix the tile stayed `hdr 1.00` (reproduced); with it `tile hdr 3.00`, then `hdr 2.00`; with a radial mask's overlay, `2` then `3`: without, `tile hdr 2.00` both times (reproduced); with, `hdr 2.00` then `hdr 3.00`. By eye: M16 (below). |
| C8 (an unreadable original remembered as "no gain map" for the run) | Reproduced, fixed. `GainMap.read` tells a file read without a gain map (nil) from one that can't be read now (`GainMap.ReadFailure.unreadable`, when the header or gain-map reads fail and the file isn't readable); `PreviewGenerator.gainMapHDRImage` and `gainMapHDRHistogram` use it, so `PreviewService` remembers only the first. The second is a failure of that opening (`.failed`, not `.superseded`: a share that stops answering while mounted must not leave the badge loading), and the next opening, or a remount's reload, asks again, as the help tag says. `GainMap.load` keeps its meaning for the live renderers (per session). | `GainMapHDRTests` "Code review C8: an original that can't be read fails without being remembered…" (file moved away: `read` throws, the outcome is `.failed`; moved back: the same request gives the HDR version; a plain JPEG is still a failure twice): without the fix it failed at the second request (reproduced). Script (the HDR-on photo's file renamed before launch, renamed back 9 s in, the photo opened again at about 14 s): without the fix `sdr failed` both times (reproduced); with it `sdr failed`, then `shown hdr badge 'hdr fitted' failed false`. |
| C9 (the possibility reload recentred the loupe) | Real at zoom steps other than 100%, not at 100% itself. At exactly 100% `applyZoom` asks `NSScrollView` for the magnification it already has, which moves nothing (run: panned to a corner, `hdr display flat`, then `system`: `visible 0.6148,0.0000` throughout). At 200% (`zoomstep`) it set the zoom back to 100% (`magnification 2.000` then `1.000`, reproduced). Fixed: the loupe begins a new visit of the same version where it is (`beginsVisitInPlace`), as a pane does: it clears the tile and loads the renditions again, but sets no size and no zoom. | Script at 200%, panned to a corner: `hdr display flat` then `system`: `magnification 2.000 visible 0.8074,0.0000` before, under **SDR: No HDR Display** and back in HDR (`inspector histogram hdr`). Offline at 200% (disk image detached, then attached, photo open): `sdr offline`, then `shown hdr`, `failed false`, same magnification and position throughout. |
| §19.4 (HDR returns in place; a photo opened while offline keeps an empty HDR histogram) | Accepted as built by the designer; the proposed follow-up bug now says so and asks for the histogram to be checked (below). | n/a |

Determinism of the two new tests: structural. The F1/F11 test checks a pure
rule with fixed values and renders fixed synthetic files; the C8 test moves a
file in its own temporary folder between two awaited requests to a service of
its own (distinct memory keys per case). No shared state, timing or pool order.

The user guide needed no change: it already says HDR returns when the volume is
connected again, "open the photo again to retry" (now true after an unreadable
moment, C8), and that the histogram may show only its frame "for a moment"
(now true at 100% too, F1).

SDR output: no SDR path changed. The F1/F11 rule compares nil with nil for every
SDR frame (a photo without the choice, or HDR not shown), so SDR live frames
skip as before; previews, exports and `photocli render` are untouched (AC11's
byte-equality test and every golden pass).

## QA round 1 (2026-11-25)

Fixes for `qa.md`'s first pass (`60b95bd`), commits `c3f21e7` (Q1, Q4),
`21e4782` (Q5), `6ebce7a` (Q2), `60af4cc` and `4b1523e` (Q3). Each was
reproduced first on code without its fix. Debug-script runs: a copy of the
bundle with identifier `me.sesser.gus.debugtest.qafix282`, scratch libraries in
the session scratchpad (copies of the owner's IMG_0546 and IMG_0561 and of
Apple-only copies of them, made as QA did: every `tmap` code renamed; for
offline, two of them on a FAT32 disk image detached and attached again while
the app ran), shell-started, `hdr display` overriding the screen.

**Correction (Q4).** Earlier versions of this file, and the spike, called
IMG_0561 a file with only Apple's kind of gain map. It is not: all three of the
owner's files carry both an ISO 21496-1 and an Apple gain map, and ImageIO
reports the ISO one for each. Every figure below that says "Apple-only" is for a
copy with the ISO map hidden. (`spike.md` is not this file's to change; its
wording stands there.)

| Finding | Outcome | Test or check |
| --- | --- | --- |
| Q1 (Apple-only gain map: labeled HDR, SDR brightness) | Reproduced and the cause confirmed by a probe: Core Image takes an Apple gain map's headroom from the **receiving** image's Apple maker dictionary (tags 33 and 48), not from the map. On a copy of IMG_0546 with only Apple's map: the file's own image brightened 0.2740 to 0.4947 (the system's decode), the same image with its properties emptied gave 0.2740 (none), with only the maker dictionary set 0.4947; the white image `GainMap.ceiling` used came out 1.0 against 2.52. Fixed: `GainMap` keeps the file's maker dictionary (`receiverProperties`) and sets it on the picture it brightens and on the ceiling's white image (`receiving`). Every path that makes an HDR picture or reads the ceiling goes through `GainMap.hdr`, `fullHDR` and `read` (settled renders at fit and 100%, comparison panes, crop session, live frames, region tiles, the photo refinement, both histograms, `placed` geometry with Distortion and spots), so one change covers them. An ISO map's render is unchanged (an image with no maker dictionary is passed through untouched; on files with both maps the maker dictionary changes nothing, measured equal). | Opt-in sample test (`HEIC_GAINMAP_SAMPLE`) on the Apple-only copies: +0.006, +0.001, −0.000 stops against the system's HDR decode (QA measured −0.84 to −0.94); the files with both maps unchanged (+0.006 for IMG_0546). Script: HDR on for the Apple-only copies of IMG_0546 and IMG_0561: `histogram hdr above white` 0.132 and 0.199 (QA: 0.000), rendered 2.62 and 4.67, `hdr display 2` fits to 2.00. The always-run tests below fail without the fix (10 tests, every failing case the Apple kind) and pass with it. |
| Q4 (no Apple-only coverage; drift can't fail for an unapplied map; no Color Fringes; no identity table) | Fixed. `HDRTestImages.writeAppleGainMap` (also `writePatternedGainMap(kind: .apple)`) writes a HEIC or JPEG with only Apple's gain map through ImageIO: maker tags 33 = 1, 48 = 1 (headroom exactly 4), a half-size 8-bit map, any EXIF orientation. Every gain-map test that makes an HDR picture now runs on both kinds (`HDRTestImages.GainMapKind`): loading and ceiling, the system decode in 8 orientations × 2 containers, fitting (now also against Core Image's own rule for the file at each headroom, AC5's second clause, for both kinds), edits, live and settled, the 100% region, the photo refinement, the service, both histograms, AC6, Distortion, spots, AC11's byte equality and AC13. AC6 checks that the unedited HDR version is the system's decode (so an unapplied map fails), adds a **Color Fringes** case, and uses an **identity look-up table** (installed in the test store, applied at 100%) as the smallest look-up table; the opt-in real-file test checks the system decode, values above white, and each smallest value too. | Without the Q1 fix: 10 of 29 tests in the HDR suites fail, 0 ISO cases among them. With it: all pass (5 runs). AC6 on Apple-only maps below. |
| Q5 (AC8 for a few stacks only) | Fixed: `GainMapAdjustmentTests` "AC8: for every adjustment…", 29 stacks (each adjustment's strong value, the identity table, crop with a turn and Straighten, Distortion, a healed spot) × both kinds: the frame a drag shows (`interactive`, drafts allowed) and the settled-size frame against the settled render at fit (headroom 2), and a 100% region tile against the same quarter of the full-resolution render (headroom 1.8), by mean and by each cell of a 6 × 4 grid. | Measured (macOS 27.2.1, M4 Pro): settled-size frame at most 0.0015 stops of mean, 0.002 in a cell; drag frame (draft decode) 0.0042 and 0.027; 100% tile 0.0015 and 0.0021. Limits: 0.005/0.02, drag frame 0.01/0.05 (AC8's "match" is 0.05 stops). Drafts reduced in scale (draft levels 1 and 2, chosen by frame time) are not forced; each case is a fresh session whose first frame is level 0. |
| Q2 (choice changeable after the original goes offline while open) | Reproduced (box enabled, `adjust hdr off` turned it off), fixed. `AdjustmentEditor.canSetHDR` (gain-map photo, not cropping, original online) now gates the check box (dimmed), Adjust ▸ Turn On / Off HDR (`LibraryMenuContext.canSetHDR`) and `setHDR` itself, so the debug script's `adjust hdr` is refused too; it returns with the volume. `print hdr` prints `can set`. | Script (disk image detached with IMG_0561 open, HDR on): online `can set true`, box enabled; offline `can set false`, `button 'HDR' … disabled … state on`; a click on the box and `adjust hdr off` change nothing (`choice true`, no undo step); after the attach `can set true`, the box enabled, `adjust hdr off` gives **Turn Off HDR**. Menu item: by reading (two activated runs stayed `key nil`, as QA's). Not changed: Undo, Redo, a History revert and the ⋯ menu's Reset All still act on the whole stack, the choice included, while the Adjust tab stays up after the volume goes (older than this branch; RI-8 below). |
| Q3 (stars over the version badge at the minimum width) | Reproduced (760 pt, sidebar and inspector shown: the loupe is 240 pt wide; ⚠ **SDR** under the fifth star, **Copy** an empty box). Fixed in `LoupeCaption`: the first arrangement that fits, by ideal widths (`ViewThatFits` over a `CenteredCaptionRow` layout): marks centered with the full badges; centered with the version badge's short form; marks after the position; marks without the position. The badge row is never squeezed, and badges and position keep 8 pt from the marks. Wider windows lay out as before. Waits on the designer (DQ-2): it moves the marks off center at the narrowest widths, which design §4 says a badge change never does. | Snapshots (content area, 760 pt unless said; looked at only for overlap, no visual result claimed): unrated plain JPEG: centered; 5 stars with **HDR**: marks after "4 of 4", 8 pt or more from the badge; with **View ▸ Hide HDR**: the same arrangement, ⚠ **SDR** whole; a copy, hidden or HDR: marks at the left, position dropped, ⚠ **SDR** and **Copy** whole; a copy with a pick flag: the row a few points wider than the caption, nothing overlapping. 900, 1000 and 1300 pt: marks centered as before (short form at 900 and 1000, the full reason at 1300). |

### AC6 on Apple-only gain maps (after the fix)

Synthetic (`GainMapAdjustmentTests` "AC6…", 600 px, Apple kind): unedited
−0.004 stops off the system's decode (ISO kind −0.001); every smallest value
within 0.013 stops (Black & White, a switch, follows SDR within 0.002); the
identity table −0.002; the strong values' drift at most 0.0038 stops RMS
(Shadows), Color Fringes 0.0001.

Real files, opt-in (`GAINMAP_SAMPLES`, 1024 px), the three Apple-only copies:
unedited −0.025, −0.032, −0.018 stops off the system's decode (the same files
with both maps: −0.025, −0.032, −0.014; downscaling of the system's full-size
decode, not the gain map); smallest values within 0.011 stops (identity table
−0.0007, +0.0005, −0.0022; Color Fringes 0.0000); strong values at most
**0.0038 stops RMS** (largest: Shadows 0.0038, Highlights 0.0029, Dehaze 0.0022;
Color Fringes 0.0002 or 0.0003). AC6's 0.05 limit is met for Apple-only maps
with room. The spike's "0.04 stops for a file with only Apple's" was IMG_0561's
ISO map: with both maps, IMG_0561 still shows Contrast 0.0458 and Tone Curve
0.0403 (its ISO map), under 0.05.

Determinism of the new and widened tests: structural. Each renders fixed
synthetic files written in its own temporary folder (Apple-only files by
ImageIO, byte for byte the same each run) through a fresh generator, session
or region renderer, and compares against tolerances at least twice the
measured value (the drag-frame mean: 0.0042 against 0.01); the AC8 drag frame is
the first of a fresh session, so its draft level is 0 and no frame time enters.
No shared state, timing or pool order. Five consecutive runs of the HDR suites
passed (not offered as a rate bound).

SDR output: nothing that renders SDR changed. `GainMap.receiving` is used only
inside `hdr` and the ceiling; AC11's byte-equality test passes for both kinds,
and every golden passes.

## Stage 1 (history): what it was for

Only what E1 to E4 need: one gain-map file shown and edited in HDR in the
loupe, with the gain map loaded, turned by the file's orientation and applied
last; fitted to what the display can give now and following it; live frames
and the settled render agreeing; at most one SDR-to-HDR change on opening from
the grid. Written as the foundation the rest builds on (PhotoCore pieces with
tests, in the spike's order). Not built: the stored per-photo choice and its
UI, version badges and reasons, the HDR histogram, overlays and maps in HDR,
the crop session in HDR, comparison panes, the export notice, `photocli`, the
user guide.

## The temporary switch: removed

Stage 1's `--gain-map-hdr on` is gone: `LaunchOptions.gainMapHDR`,
`TemporaryGainMapHDR` and its test, `LibraryModel.showsGainMapsInHDR`,
`LoupeController.gainMapSetting` and the debug script's `gainmaphdr`. The
stored choice replaces it. `LaunchOptions.swift` is back to `develop`'s text.

## Stage 1 (history): what was built

PhotoCore:
- `Preview/GainMap.swift`:
  - `GainMap`: loads a non-raw, non-video, not HLG/PQ file's gain map (ISO
    21496-1 or Apple's), turns it by the file's EXIF orientation (spike trap
    1), knows the file's headroom (the HDR decode's `contentHeadroom`) and the
    photo's *ceiling* (SDR white through the whole gain map at full weight: the
    brightest any HDR version of the photo can be; 2.62, 3.74 and 4.57 on the
    owner's three files, equal to their headroom within 0.5%). `placed(over:crop:)`
    stretches it over a decode of any size and takes it through the stack's
    turns, straightening and crop. `hdr(_:placed:displayHeadroom:)` clips the
    edited SDR render to SDR white in Display P3 (the SDR picture as shown),
    applies the gain map weighted for the display (`applyingGainMap(_:headroom:)`,
    the gain map's own rule) and limits the result to the tag.
  - `GainMapHeadroom`: weighting = min(file, display); tag = min(display,
    ceiling), so every frame of a visit has the same tag whatever an edit does
    to its brightest pixel, and no value is above what the display can show;
    when to render again (0.02 stops).
  - `GainMapVisit`: the loupe's R8 rule. Arrival may show SDR then HDR (one
    change); once HDR is on screen no SDR picture replaces it; maps are neither
    version; following the headroom is not a change.
  - `DisplayHeadroomReading`: what the display can give now, learned from
    settled screen readings (see Findings).
  - `TemporaryGainMapHDR` (see above).
- `RenderEngine.makeHDRCGImage(_:contentHeadroom:)`: half float, a given tag,
  no pixel scan. The existing `makeHDRCGImage(_:)` is unchanged in behavior
  (refactored to share the render).
- `PreviewGenerator.gainMapHDRImage(source:stack:longEdge:displayHeadroom:)`:
  the same decode as the SDR renditions, the stack, the gain map last.
- `PreviewService.gainMapHDRImage(for:displayHeadroom:fullResolution:)`, its
  memory lookup (by the tag the display wants), `insertGainMapHDRIntoMemory`
  and `gainMapHeadroom(for:)`; its own lane beside the HDR lane.
- `LiveRenderSession.render(…, hdrHeadroom:)` and
  `LiveRegionRenderer.render(…, hdrHeadroom:)`: with a headroom, a gain-map
  photo's frame is its HDR version (`Frame.headroom`); maps and other files
  are unchanged. An HDR frame's histogram is, for now, the SDR frame's
  (counted from a 256-pixel SDR reduction), until the HDR histogram (design §7)
  is built.
- `HDRTestImages.writePatternedGainMap` (PhotoFixtures): a gain map that
  brightens one part of the picture more, with any EXIF orientation.

PhotoApp:
- `LoupeController`: for a gain-map photo, the settled rendition at fit and at
  100% is `gainMapHDRImage` (neighbors preloaded too); live frames and region
  tiles are HDR (`AdjustmentEditor.hdrDisplayHeadroom`); `display` and
  `showLiveFrame` go through `GainMapVisit`, so the cached SDR preview, the SDR
  full rendition and SDR tiles never replace HDR once it is on screen; the
  layer asks for the photo's ceiling (`CALayer.contentsHeadroom`) while it
  shows a gain-map photo's HDR version; a 0.25 s poll and
  `NSApplication.didChangeScreenParametersNotification` follow the display's
  headroom and render the settled rendition again when it moves (one render at
  a time, latest wins). The caption's existing HDR badge shows, with the
  headroom the picture is shown at (min of the fitted tag and the file's) in its
  tooltip; the designed badges are later work.
- `AdjustmentEditor`: passes the headroom to both renderers; an HDR frame of
  the saved values goes into memory as the new edit's HDR version, never as its
  SDR preview.
- Debug script: `hdr display <h>|system` (override the display headroom),
  `gainmaphdr on|off` (temporary), and `print hdr` now also prints the screen's
  current reading and the visit (`LoupeGainMapReport`: version changes and their
  order, rendered tag, fitted display headroom, known limit, request, file
  headroom, refits, the live frame's kind).

SDR output: no SDR code path changed except `LiveRenderSession`'s final
lines, rewritten to the same calls in the same order (`scaledToFit`, then
`makeCGImage`, then `Histogram`). No golden moved; no
`PreviewCacheKey.currentPipelineVersion` bump; no migration; no package.

## Stage 1 (history): findings

### The display's headroom (design §13's note, verified)

Measured on macOS 27.2.1, M4 Pro, with a probe app in the scratchpad and the
app's debug script (`print hdr`). Two screens were seen, as the owner's setup
changed during the session: the built-in Retina display (potential 16.0) and
the DELL U2723QE (potential 4.18).

- With nothing asking for extended range, the current reading
  (`maximumExtendedDynamicRangeColorComponentValue`) was **1.20, not 1.0**,
  on both screens. The note's direction holds: it does not show what the
  display can give until a layer asks.
- A layer with `preferredDynamicRange = .high` showing an untagged image, or
  one tagged 1.0, did **not** raise it. An image tagged above 1 did: the
  reading ramped (about 1 to 2 s, `didChangeScreenParameters` posted about
  120 times a second meanwhile) to exactly the tag (2.0, then 6.0) when that was below what the
  display could give. Tagged 16 on the built-in display, it stopped at 9.82.
- The potential reading stayed at 16.0 (4.18 on the Dell) throughout. So the
  potential is **not** what the display can show now; a settled current
  reading below the request is. On the built-in display at the brightness of
  the moment that was 9.82; on the Dell it was 1.29 (a probe asking for 16 got
  1.29 too), so on the Dell as set up then every one of the three photos is
  brighter than the display.
- `CALayer.contentsHeadroom` (macOS 26) above the image's tag raises the
  request: an image tagged 1.5 with `contentsHeadroom` 16 took the reading to
  9.82. The loupe uses that: it asks for the photo's ceiling and tags the
  picture with the fitted headroom, so the reading settles at what the display
  can give up to the ceiling and can follow a brightness change both ways.
  (The deprecated `wantsExtendedDynamicRangeContent` also raises it to 9.82
  with `.standard`; not used.)
- In an app that is not frontmost the request was not always granted: a probe
  that lost activation got no ramp for a 6.0 tag until it was active again, and
  a shell-started (inactive) run on the Dell stayed at 1.20 and fitted to it.
  This is macOS 26's background HDR suppression (#287), not handled here.

What this means for E4: the first gain-map photo shown on a screen is rendered
for the potential headroom capped at the photo's ceiling, because nothing
better is known yet. Where the display gives at least the ceiling (the built-in
display at that brightness), nothing more happens. Where it gives less (the
Dell at 1.29), the reading settles about 1.5 s later and the picture is
rendered again for it: a second, smaller change, and between the two Core
Animation fits the picture to the display itself. The known limit is kept for
later photos on the same screen, which open directly at it. See DQ-1.

Not observed (no way to here): a real brightness change, so whether the
reading follows the brightness keys is unverified (E3 is that check); how any
of it looks.

### Rendering (from tests; no screen involved)

Owner's files, opt-in test (`HEIC_GAINMAP_SAMPLE=… swift test --filter
"GainMapHDRTests/sample"`), means of linear Display P3 luminance at a quarter of
2560 px; no personal metadata recorded:

| File | File headroom | Ceiling | Ours vs system HDR decode, unedited | Live vs settled at headroom 3 (identity, Exposure −1, Contrast +20) | Warm HDR frame, 2560 px |
| --- | --- | --- | --- | --- | --- |
| IMG_0546 | 2.62 | 2.62 | +0.006 stops | −0.0005, −0.0005, −0.0005 | 16 to 17 ms |
| IMG_0542 | 3.74 | 3.74 | +0.001 | −0.0005 each | 12.5 to 13 ms |
| IMG_0561 | 4.55 | 4.57 | +0.000 | −0.0005, −0.0005, −0.0004 | 9.6 to 17 ms |

The first frame of a session took 77 to 128 ms (gain map load, decode). SDR
frame times for the same stacks were not measured in this stage (AC10 is
later work).

## Acceptance criteria

PRD as revised 2026-11-25 (RI-6, RI-7, AC18). Tests are Swift Testing suites
in `Tests/PhotoCoreTests`; "script" is a debug-script run on a copy of the
bundle (identifier `me.sesser.gus.debugtest.hdrchoice282`, a scratch library
of copies of the owner's three photos in the session scratchpad,
shell-started unless said).

| AC | How it is checked | Result |
| --- | --- | --- |
| AC1 (R1) | `GainMapHDRTests` "A gain-map HEIC or JPEG has a gain map…" (HEIC, JPEG: yes; plain JPEG, PQ with and without a gain map: no) and "AC1: only a HEIC or JPEG, by name and content…" (a gain map under a TIFF or PNG name, or in an AVIF, gives no choice); `GainMap.exists` takes HEIC and JPEG names and content types only; `HDRChoiceTests` "Off is the default…"; script: a newly imported HEIC shows **SDR**, choice off, check box shown (`has choice true`) | Pass |
| AC2 (R2) | `HDRChoiceTests`: stack round trip, catalog column and History snapshot revert, virtual copy independence and Undo of Duplicate's removal, Reset All; script: on, relaunch still on, undo off, redo on, History lists **Turn On HDR**, revert to an entry with it off shows SDR, Reset All (menu, activated run) off, its undo on | Pass |
| AC3 (R3) | `HDRChoiceTests` "presets and Paste Adjustments neither carry nor change the choice" (both directions, all items and one group) | Pass |
| AC4 (R4, R5) | `HDRChoiceTests` badge reasons and order, offline with choice off (RI-3), fitted at 1.29 and 1.0 is **HDR** (RI-7); script: **SDR: HDR Hidden**, **SDR: No HDR Display** (`hdr display sdr`), **SDR: HDR Failed** (`hdr fail on`), allowance 1.29 and 1.0 read **HDR** with the fitted help tag; comparison panes each state their version; the stored choice unchanged under every reason; QA round 1: a photo whose original goes offline while open can't have its choice changed (Q2), and at 760 pt the caption keeps ⚠ **SDR** clear of the marks (Q3, snapshots) | Pass (offline by script: disk image detached and attached; the menu item by reading; Q3's layout waits on DQ-2) |
| AC5 (R6) | `GainMapHDRTests` system decode in every orientation and both containers, smaller headroom by the gain map's rule (against Core Image's own rule for the file too), each for ISO and Apple-only gain maps (QA Q1, Q4); opt-in sample test on Apple-only copies within 0.006 stops; script: `hdr display 2`, `1.5`, `system` refit without reopening, version unchanged; at 100% with live frames up the tile follows too (review round 2, F11) | Pass |
| AC6 (R7) | `GainMapAdjustmentTests` "every adjustment…" (25 cases × ISO and Apple-only gain maps: every group and control, Color Fringes, an identity look-up table as the smallest, masks; Black & White as a switch; the unedited version checked against the system's decode); opt-in `GAINMAP_SAMPLES` on the owner's three files (both kinds of gain map) and on Apple-only copies of them, below and under "QA round 1" | Pass |
| AC7 (R8) | `GainMapHDRTests` "Once HDR is on screen…" (the visit rule); script: arrival `versions sdr,hdr changes 1`, then an Exposure change, Exposure −3 (nothing above white), crop begin and done, sharpening map on and off (no badge, HDR back), comparison and back, grid and back: still HDR, no further change; Undo of Turn On HDR, Reset All and a revert to an entry with it off show SDR | Pass (drags, zoom and hover by stage 1's scripted runs and the code path) |
| AC8 (R9) | `GainMapAdjustmentTests` "AC8: for every adjustment…" (29 stacks × both kinds, at fit and at 100%, QA Q5); `GainMapHDRTests` "A live HDR frame and the settled HDR render… agree" and "A region frame at 100%…" | Pass in values; by eye with the owner |
| AC9 (R10) | `HDRChoiceOutputTests` "the HDR histogram counts values above white…" (same at headroom 1.3 and 16, draft and settled share within 0.05, dark edit keeps the axis) and its bins test; script: histogram kind and share in `print hdr` and `print compare`; at 100% after Show HDR the counts come (review round 2, F1, `GainMapHDRTests` "Review F1, F11…") | Pass |
| AC10 (R11) | `GainMapTimingTests` (`GAINMAP_TIMING`), table below | Measured: within 1.5× |
| AC11 (R12, R14) | `HDRChoiceOutputTests` "previews and photocli render are the same bytes with the choice on and off"; `HDRChoiceTests` render hash; every golden passes unchanged | Pass |
| AC12 (R13) | `HDRChoiceTests` "the export notice counts…"; script: `export` prints "1 photo has HDR on. Exports are SDR." | Pass |
| AC13 (R15) | `HDRChoiceOutputTests` Auto Exposure, Auto White Balance and Color Alignment measure the same | Pass |
| AC14 (R16) | the existing HLG, PQ and floating-point DNG tests (`GainMapRenditionTests` for HLG and PQ, with and without a gain map; `PreviewTests` and the DNG merge suites `HDRMergerTests` and `HDRMergeJobTests`) pass unchanged; user guide states the limit | Pass |
| AC15 (R17) | `HDRChoiceTests` "develop sets and resets the choice…" (sets, reads back through `query images`, refuses a plain JPEG with `invalidEdit` and an unreadable original with `fileNotFound`) | Pass |
| AC16 (R18) | Every check above ran on macOS 27.2.1; nothing checks macOS 15 | n/a |
| AC17 (R19) | `GainMapHDRTests` every orientation, crop with turn and Straighten; `GainMapAdjustmentTests` Distortion with a crop and a turn (and a check that an unwarped gain map would be caught), heal and clone over a small bright object | Pass |
| AC18 (R6) | `GainMapHDRTests` "Design §18.1…" and "AC18: each screen's allowance…" (lower request keeps, more replaces, inactive not kept, per screen, survives requests stopping); structural: the memory lives in `LibraryModel`, outside the loupe; script: grid and comparison and back open with `refits 0` | Pass; by hand on a low-allowance screen, below |

"Fails without the fix": with the spot step left out of the gain map's
geometry (run and reverted 2026-11-25), both spot cases failed (2.0 stops at
the spot against 0.59 at its source). The Distortion test checks within itself
that an unwarped gain map is caught (more than 0.2 stops and four times the
warped error).

### AC6 on the owner's files (opt-in, 1024 px, stops RMS of ratio drift)

`GAINMAP_SAMPLES=…IMG_0546.HEIC:…IMG_0542.HEIC:…IMG_0561.HEIC swift test --filter "GainMapAdjustmentTests/everyAdjustmentOnRealFiles"`.
All below 0.05. All three files carry both kinds of gain map and are rendered
with their ISO map (corrected in QA round 1; this paragraph first called
IMG_0561 Apple-only). Largest: IMG_0561 (its ISO map, applied with a small
dependence on the base's level) Contrast 0.046, Tone Curve 0.040, Exposure
0.026, Clarity 0.025. IMG_0546 and IMG_0542: every adjustment 0.004 or less.
Apple-only copies: under "QA round 1". Every value on IMG_0561 (before QA round
1's identity table and Color Fringes cases): white balance 0.0007, exposure 0.0258, contrast 0.0458, highlights
−80 0.0058, highlights +80 0.0008, shadows 0.0206, whites 0.0007, blacks
0.0218, clarity 0.0253, dehaze 0.0201, vibrance 0.0050, saturation 0.0034,
tone curve 0.0403, color mixer 0.0049, black and white 0.0106, color grading
0.0005, look-up table 0.0052, vignette 0.0208, grain 0.0048, sharpening 0.0000,
noise reduction 0.0171, lens vignetting 0.0131, color alignment 0.0080, mask
0.0083.

### AC10: frame times (opt-in, medians of 15 interactive frames, M4 Pro, macOS 27.2.1)

`GAINMAP_TIMING=…IMG_0546.HEIC:…IMG_0542.HEIC:…IMG_0561.HEIC swift test --filter GainMapTimingTests`.
Stack: Exposure (moving), Contrast +20, Highlights −30, Vibrance +15, an S
curve, Sharpening 40. Fit: 2560 px frames with both histograms; 100%: a
2560 × 1440 region of the full-resolution decode.

| File | Fit SDR | Fit HDR | Ratio | 100% SDR | 100% HDR | Ratio |
| --- | --- | --- | --- | --- | --- | --- |
| IMG_0546 | 22.1 ms | 24.7 ms | 1.12 | 12.6 ms | 10.9 ms | 0.87 |
| IMG_0542 | 21.0 ms | 24.3 ms | 1.16 | 11.7 ms | 10.7 ms | 0.91 |
| IMG_0561 | 16.6 ms | 23.8 ms | 1.44 | 18.7 ms | 18.5 ms | 0.99 |

Before the single-render change, fit HDR was 2.48 to 3.17 times SDR.

## Tests

QA round 1: every gain-map test that makes an HDR picture runs on an ISO and an
Apple-only synthetic file (`HDRTestImages.GainMapKind`); AC8's every-adjustment
test is new.

New or changed suites: `HDRChoiceTests` (11 tests), `HDRChoiceOutputTests` (4),
`GainMapAdjustmentTests` (24 adjustment cases, Distortion, two spot modes,
the opt-in real-file run), `GainMapTimingTests` (opt-in), `GainMapHDRTests`
(stage 1's, plus the §18.1 and AC18 tests; the temporary switch's test
removed; its pixel reader now renders in the app's working space),
`CatalogTests` (v17 listed), `CommandTests` (`adjustments` lists `hdr`).

Determinism: the new tests compare renders of fixed synthetic files against
tolerances 10 to 100 times above half-float rounding, or compare pure values
(`HDRVersionBadge`, `DisplayHeadroomReading`, `DisplayHeadroomMemory`,
`HDRHistogram.bin`, `ExportTargets.hdrCount`) fed fixed inputs and times.
The byte-equality test renders the same stack twice through one generator and
compares whole files; renders with identical graphs and inputs are identical
here (as the existing "Rendering the same file with the same edits gives the
same bytes" test relies on). No shared state, timing or pool order enters.
The timing test asserts nothing about time.

## Build and test results

- Baseline at `2903ea7` (2026-11-25): `swift build` clean; `swift test`
  1546 tests in 217 suites passed, 83.4 s.
- At the end of stage 2 (2026-11-25): `swift build` clean, no warnings;
  full `swift test`: **1568 tests in 221 suites passed**, 86 s. Goldens
  unchanged; no `PreviewCacheKey.currentPipelineVersion` bump.
- CI toolchain: `DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer swift build --build-tests --scratch-path .build-xcode26.3`:
  **Build complete**, no errors, no warnings.
- After review round 1 (2026-11-25, `d5e2486`): `swift build` clean, no
  warnings; full `swift test`: **1572 tests in 221 suites passed**, 78 s.
  Goldens unchanged; no `PreviewCacheKey.currentPipelineVersion` bump; SDR
  output untouched (AC11's byte-equality test passes). CI toolchain command
  as above: **Build complete** (31.9 s), no errors; its only warnings are
  `VirtualCopiesTests.swift`'s, from `develop` (#62).
- After QA round 1 (2026-11-25, `4b1523e`): `swift build` clean, no
  warnings; full `swift test`: **1575 tests in 221 suites passed**, 97.6 s
  (parametrized cases not counted separately). Goldens unchanged; no
  `PreviewCacheKey.currentPipelineVersion` bump; AC11's byte-equality test
  passes for both kinds of gain map. CI toolchain:
  `DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer swift build --build-tests --scratch-path .build-xcode26.3`:
  **Build complete** (34.0 s), no errors; its only warning is
  `VirtualCopiesTests.swift`'s, from `develop`. `Scripts/build-app.sh`: built
  and signed.
- After review round 2 (2026-11-25, `033458e`): `swift build` clean, no
  warnings; full `swift test`: **1574 tests in 221 suites passed**, 81.8 s.
  Goldens unchanged; no `PreviewCacheKey.currentPipelineVersion` bump; AC11's
  byte-equality test passes. CI toolchain:
  `DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer swift build --build-tests --scratch-path .build-xcode26.3`:
  **Build complete** (18.6 s, incremental), no errors, no warnings.
- `Scripts/build-app.sh`: bundle built and signed.

Debug-script results (2026-11-25) are in the AC table. Screens seen: the
DELL U2723QE (potential 4.18; the shell-started app read 1.0 to 1.2, an
activated one 1.29) and earlier the built-in display.

## For a person

On an HDR display, with a copy of the bundle on a scratch library (the
owner's three photos are copied in `/Users/randy/gus-qa/gain-map-hdr-editing/photos`
from the early check):

```zsh
cd /Users/randy/Projects/Gus && Scripts/build-app.sh && Q=/Users/randy/gus-qa/gain-map-hdr-editing && rm -rf $Q/Gus-gainmap282.app && cp -R build/Gus.app $Q/Gus-gainmap282.app && plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest.gainmap282 $Q/Gus-gainmap282.app/Contents/Info.plist && codesign --force --deep --sign - $Q/Gus-gainmap282.app && open -n $Q/Gus-gainmap282.app --args --library-root $Q/library
```

The early check's `--gain-map-hdr on` is gone: turn HDR on per photo with the
Adjust tab's **HDR** check box.

1. The **HDR** check box after **Original** and **Adjust ▸ Turn On / Off HDR**:
   look, spacing, that the box doesn't appear for a raw or a plain JPEG.
2. Turning it on: the badge and check mark respond at once, the picture
   changes once to HDR; turning it off returns to SDR at once.
3. Brightness while dragging and on release, at fit and 100% (AC8 by eye),
   including Exposure, Contrast, a curve, a mask, and Show Original.
4. Handles (crop, mask, spot) over bright highlights stay findable; the mask
   overlay's red reads clearly over highlights; the crop session's picture is
   HDR and Done and Esc go straight back to HDR.
5. Sharpening and fringe maps: no flash of SDR around them; HDR returns.
6. The HDR histogram's look in Light and Dark appearance and with Increase
   Contrast: the line, fill, dashed lines and the **HDR** mark; the Tone
   Curve's backdrop staying SDR.
7. Narrow captions: shrink the window until a reason badge
   (**SDR: HDR Hidden**, via View ▸ Hide HDR) takes its short form, triangle
   and **SDR**; in comparison, that the version badge never drops.
8. On a screen that allows less than the photo needs (the Dell): the first
   photo changes at most once more about 1.5 s after HDR appears; later
   photos, also after the grid, a video, comparison and moving the window
   away and back, do not (AC18 by hand). The badge's help tag names the
   file's number and the display's.
9. The Export sheet's notice line under the subtitle.
10. Comparison with an HDR photo beside an SDR one: each pane's badge, the
    histogram following the active side.
11. Review round 1: in comparison, a pane whose HDR version takes longer than
    half a second shows the mini spinner beside its **SDR** badge (F4; best on
    a large file, the first time it is shown); at 100%, picking a filled fringe
    slot again sharpens in HDR (F5); while HDR counts are made the histogram
    shows its empty HDR frame, never an SDR curve under an HDR picture (F2).
12. Review round 2 (the review's M16): at 100%, **View ▸ Hide HDR**, wait,
    **Show HDR**: the HDR histogram fills within a moment (F1). With the mask
    overlay on, and again with Show Original, lower and raise the screen's
    brightness on a screen that allows less than the photo needs: the picture
    follows at 100% as it does at fit (F11). At 200%, panned to a corner,
    eject and reconnect the photo's volume (or turn the display's HDR off and
    on): the zoom and the place shown stay (C9).
13. QA round 1: at the minimum window width (760 pt, sidebar and inspector
    shown), a gain-map photo rated 5 stars, with **View ▸ Hide HDR**, then as a
    copy: no badge over the stars, ⚠ **SDR** and **Copy** whole, and how the
    stars sitting off center looks (DQ-2). If you have a photo with only
    Apple's kind of gain map (older iPhone photos may be; not verified), turn
    HDR on for it: it should brighten as the owner's three files do, not stay
    at its SDR look. A copy of one of the three with each `tmap` code renamed
    stands in (QA's method in `qa.md`, Q1).

Covered by CI only, per the owner's standing ruling: VoiceOver, macOS 15 and
macOS 26.

## Open questions

### Design questions (for apple-ui-designer)

DQ-1 is ruled (design §18.1) and accepted by the owner.

**DQ-2 (QA Q3): what gives way in the loupe caption when the version badge's
short form can't fit beside the centered marks.** At the minimum window (760
pt, sidebar and inspector shown) the loupe is 240 pt wide: with five stars,
about 52 pt is left right of the centered marks, and ⚠ **SDR** with the strip
toggle needs about 75 pt (with **Copy**, about 120). So design §4 ("changing the
badge never … moves the culling marks"), §5 ("the badges never run into the
culling marks"), R4/AC4 (the mark and **SDR** stay visible) and the Copy badge
staying (virtual-copies §6.3) can't all hold there. Options:
- (a) *As built:* the first arrangement that fits: centered with full
  badges, centered with the short form, marks after the position, marks
  without the position. Cost: none further. At the narrowest widths the marks
  sit off center, and at a width where only one form fits, a badge change
  (Hide HDR) can move them; at 760 pt both the **HDR** and the ⚠ **SDR** photo
  take the same arrangement, so it doesn't there. Before this branch an
  **HDR** badge at 760 pt sat centered but 7.5 pt into the 18 pt gap; now any
  arrangement keeps 8 pt, so that photo's marks are off center too.
- (b) The arrangement chosen from the width and the photo's widest short badge
  (⚠ **SDR** for any gain-map photo, plus Copy and Offline), not the current
  badges, so no badge change moves the marks. Cost: a hidden measuring row or
  a custom layout reading fixed widths, about a day; marks off center more
  often (HDR photos at widths where ⚠ **SDR** wouldn't fit).
- (c) Keep the marks centered and drop something else first: the film strip
  toggle (also View ▸ Show Film Strip, ⌥⌘B), then Copy (the window title says
  "copy"). Cost: small; loses a control and an identity badge at the narrowest
  widths, and still fails with a color label.
- (d) Raise the library window's minimum width. Cost: small; a change for
  every view, outside this feature.
Recommendation: (a), as built: nothing is ever covered or dropped, and the move
happens only where centering is impossible.

Noted, not a question: the comparison panes follow the screen's headroom with
a 0.25 s poll like the loupe's; while comparing, the panes' layers make the
request the screen's reading answers (the largest ceiling of the two photos).

### Requirements issues (for the product manager)

RI-6 and RI-7 are in the revised PRD.

**RI-8 (QA Q2's remainder): does AC4's "the loupe offers no way to change the
choice" cover Undo, Redo, a History revert and Reset All while the original is
offline?** After Q2's fix the check box, the menu item and the debug route
refuse. But a photo opened while online keeps its Adjust tab when its volume
goes (older than this branch, the proposed follow-up bug below), so Undo of
**Turn On HDR**, a History revert to an entry with another setting, and the
loupe's Reset All still change the whole stack, the choice with it. Options:
(a) leave it to the follow-up bug, which would put the Adjust tab (and History)
into its offline state when the volume goes; (b) refuse those for the choice
alone now, which splits undo steps and reverts in two (costly, and Reset All
from the grid already turns the choice off for offline photos by RI-2).
Recommendation: (a): read AC4 as the HDR controls, and fix the rest with the
follow-up bug.

### Follow-ups proposed (not fixed here)

- Bug: "The Adjust tab stays offline after a photo's volume returns, until the
  photo is opened again". A photo opened while its original is offline keeps
  `AdjustmentEditor.state == .offline` when the volume is mounted again,
  because `follow` returns early for the same version and nothing reloads it
  on `libraryAvailabilityChanged`. Seen while checking C1 (any photo, not only
  gain-map ones; older than this branch). Per design §19.4, the issue should
  also say: a gain-map photo with HDR on that was opened while offline keeps
  an empty HDR histogram (the frame with no curve) after the volume returns,
  because its counts come from the Adjust tab's editor; the fix should check
  that the HDR histogram fills once the tab leaves its offline state.

## README

- Catalog: migration v17 adds the column `version.hdr` (the HDR choice's copy
  of the stack's value). CLAUDE.md's Catalog rule lists tables only; the edit
  stack rule may want "the `hdr` operation is left out of the render hash".
- New opt-in test variables: `GAINMAP_SAMPLES=a.HEIC:b.HEIC swift test --filter "GainMapAdjustmentTests/everyAdjustmentOnRealFiles"`
  and `GAINMAP_TIMING=a.HEIC swift test --filter GainMapTimingTests` (the
  owner's files, never committed), for CLAUDE.md's command list. The owner's
  iPhone files carry both kinds of gain map; for an Apple-only run, pass copies
  with each `tmap` code renamed (QA round 1).
- The View menu item is now **Show / Hide HDR** (CLAUDE.md's Scope still says
  "Show / Hide HDR Highlights" in the #277 entry).
- `photocli develop --set hdr.on=true|false`.
- Debug script (CLAUDE.md lists none of these one by one): `hdr display flat`
  (review round 1) beside `hdr display <h>|sdr|system`, `hdr fail on|off`,
  `adjust hdr on|off`; `print hdr` also prints the 100% tile's version
  (`tile hdr <h>|sdr|none`, review round 2).

## User guide

Updated in its own commit: the HDR passage (gain-map photos, the choice, the
badges and reasons, fitting, the first photo's second adjustment, what stays
SDR, the HLG/PQ/DNG limit naming the adjustments), the histogram passage, the
Export passage, the Adjust tab header, and `photocli develop`.
