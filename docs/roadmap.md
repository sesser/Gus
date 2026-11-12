# Roadmap

Owned by the product-manager agent. Every feature and bug is a GitHub issue
(`docs/WORKFLOW.md`, Issues); this file only orders the open ones. An item's
problem, history and outcome are in its issue, and a closed issue is a shipped
(or dropped) one. Its stage is read from its labels (`needs-prd`) and from
`docs/features/<slug>/`.

Moved from a file-based roadmap to issues on 2026-11-10. The earlier roadmap,
with its change log and Shipped table, is kept in
[`archive/ROADMAP_2026-11-10.md`](archive/ROADMAP_2026-11-10.md). Specs for
work shipped before that are in `docs/features/<slug>/`, and the phase plans
(`docs/archive/PHASE1_PLAN.md` … `PHASE6_PLAN.md`) and `docs/UI_REDESIGN.md` stay
as the historical record.

## Vision and principles

Accepted by owner 2026-11-04.

The app is a native Mac photo library and RAW editor for photographers who
keep their files in their own folders and drives. It catalogs photos where
they already are, never changes them, and makes culling, organizing, editing
and exporting fast from the keyboard. It is not a cloud service, a sync
engine or a copy of another app's interface.

Principles (drawn from `README.md` and `CLAUDE.md`):

1. **Originals are sacred.** Masters are referenced, never moved, copied or
   written; edits are a list of steps applied at render time.
2. **The library is the source of truth, but other apps' work is never
   overwritten.** Outside changes to sidecars wait for review.
3. **On the Mac, private by default.** Analysis (keyword suggestions) runs on
   device; nothing leaves the Mac unless the user sends it.
4. **Native first.** System components and Apple's HIG before custom chrome;
   macOS 15 stays supported.
5. **Keyboard-first culling**, with every command also in a menu.
6. **Few dependencies, checkable output.** GRDB only; renders pinned by
   goldens and CPU references; everything scriptable through `photocli`.

## Now (maximum three)

Empty. The owner decides what fills it. First candidate: rename-albums-in-place (#141, top of Next).

## Next

Order set by the owner 2026-11-06 (library and project operations first, then
virtual copies, then side-by-side comparison; the rest in the order it had). HDR merge (#150) was put after
side-by-side comparison on 2026-11-11, ahead of the rest.
The small fixes and tooling items can each go as a bug fix (`docs/WORKFLOW.md`).

1. [#141](https://github.com/sesser/Gus/issues/141) `rename-albums-in-place`: Albums rename through a sheet while projects rename in place; make both in place (follow-up to library-ops; owner, 2026-11-10)
1. [#63](https://github.com/sesser/Gus/issues/63) `side-by-side-comparison`: No way to look at photos next to each other to compare them
1. [#150](https://github.com/sesser/Gus/issues/150) `hdr-merge`: No way to merge several exposures of a scene into one tone-mapped HDR image, with automatic alignment and de-ghosting (owner, 2026-11-11)
1. [#64](https://github.com/sesser/Gus/issues/64) `reads-beside-write-chain`: Five reads still take a photo's edits from the catalog without waiting for pending saves, so right after a change they can get the older…
1. [#65](https://github.com/sesser/Gus/issues/65) `full-render-main-thread-stall`: At 100%, every arrival at a photo and every change that is let go freezes the window for about 0.4 s (about 1.3 s with machine learning…
1. [#66](https://github.com/sesser/Gus/issues/66) `adjust-tab-rebuild-on-arrival`: With the inspector open on Adjust, every arrival at a photo rebuilds the whole Adjust tab (the editor goes loading, then ready) and its…
1. [#67](https://github.com/sesser/Gus/issues/67) `raw-edge-smear-stored-alignment`: Photos whose Color Alignment was measured with Align automatically before the raw-edge-smear fix may store slightly wrong values (red…
1. [#68](https://github.com/sesser/Gus/issues/68) `raw-edge-smear-os-watch`: The raw-edge-smear fix rests on undocumented Core Image behavior seen on macOS 27.2 only
1. [#69](https://github.com/sesser/Gus/issues/69) `loupe-caption-narrow`: At narrow window widths the loupe caption's items collide
1. [#70](https://github.com/sesser/Gus/issues/70) `classical-noise-strength`: The classical noise sliders (RAW decoder and Core Image filter) are mild at 100;
1. [#71](https://github.com/sesser/Gus/issues/71) `local-sharpen-group-off`: Turning the Sharpening group off makes local Sharpness use the default Radius 1, Detail 25 and Masking 0 instead of the user's values,…
1. [#72](https://github.com/sesser/Gus/issues/72) `sharpen-masking-scale`: Masking holds back much more noise at fit than in a full-size export:
1. [#73](https://github.com/sesser/Gus/issues/73) `dehaze-above-white`: Dehaze and local tone estimates jump on extended-range (above white) input
1. [#74](https://github.com/sesser/Gus/issues/74) `slider-field-shift-step`: ⇧↑ / ⇧↓ in an adjustment slider's value field likely don't step by 10 as the design asks
1. [#75](https://github.com/sesser/Gus/issues/75) `export-missing-file-reason`: An export whose original is missing from a connected volume says "the volume … is not connected"
1. [#76](https://github.com/sesser/Gus/issues/76) `appkitbutton-enablement`: Some inspector buttons look enabled when they should be dimmed (the mask eye button and other Adjust tab buttons are likely affected):
1. [#77](https://github.com/sesser/Gus/issues/77) `ci-test-crash`: The test process sometimes crashes on CI (signal 11), so that run reports nothing about the tests that had not finished
1. [#78](https://github.com/sesser/Gus/issues/78) `sharpening-map-tests-flaky`: SharpeningMapTests (and once a grain test in EffectsTests) fail now and then under GPU load:
1. [#79](https://github.com/sesser/Gus/issues/79) `debug-script-undo-groups`: Debug-script commands that change nothing (ml wait, ml ready, ml override, a key with no effect, adjust crop show, adjust crop begin)…
1. [#80](https://github.com/sesser/Gus/issues/80) `debug-resignkeyboard-inactive`: The debug command magnifier resignkeyboard can silently do nothing in a process that isn't active:
1. [#81](https://github.com/sesser/Gus/issues/81) `qa-test-gaps`: Three tests don't check what they are named for

## Later

Roughly ordered by dependency, then by how often a photographer would hit the gap.

1. [#82](https://github.com/sesser/Gus/issues/82) `ui-redesign-onscreen-check`: Shipped work that only a person can check
1. [#28](https://github.com/sesser/Gus/issues/28) `publishing-engine`: Getting edited photos into Apple Photos or Immich means exporting to a folder and uploading by hand
1. [#29](https://github.com/sesser/Gus/issues/29) `publishing-plugins`: Destinations beyond the built-ins need app changes
1. [#83](https://github.com/sesser/Gus/issues/83) `pick-colors-magnifier`: The Color Range mask's Pick Colors doesn't use the Pixel Magnifier, so the person can't see which pixel a click takes or read its values
1. [#84](https://github.com/sesser/Gus/issues/84) `apple-feedback-raw-lens-state`: Core Image's RAW decoder reuses a context's prepared lens correction regions for a different raw with the same graph digest, which…
1. [#85](https://github.com/sesser/Gus/issues/85) `dng-export`: No DNG output
1. [#86](https://github.com/sesser/Gus/issues/86) `healing`: No spot removal or healing
1. [#87](https://github.com/sesser/Gus/issues/87) `lens-corrections`: No correction of geometric distortion or lens vignetting, and no lens profiles
1. [#88](https://github.com/sesser/Gus/issues/88) `ai-masks`: No subject, sky, object or people masks
1. [#151](https://github.com/sesser/Gus/issues/151) `panorama-merge`: No way to merge overlapping photos into a panorama. Open for the PRD: approach (Core Image if it offers stitching, the Hugin libraries, or a stitcher of our own); GRDB is the only dependency (ask first) and Hugin is GPL (owner, 2026-11-11)
1. [#89](https://github.com/sesser/Gus/issues/89) `dcp-profiles`: Adobe .dcp camera profiles not supported
1. [#90](https://github.com/sesser/Gus/issues/90) `stacks`: No hand-made or burst stacks
1. [#91](https://github.com/sesser/Gus/issues/91) `hierarchical-keywords`: Keywords are flat
1. [#92](https://github.com/sesser/Gus/issues/92) `masks-in-presets-and-paste`: Presets, paste and sync leave masks out;
1. [#93](https://github.com/sesser/Gus/issues/93) `whole-mask-invert`: Inverting a whole mask takes a first Subtract component
1. [#94](https://github.com/sesser/Gus/issues/94) `local-dehaze-exact`: Soft-edged local dehaze is much stronger mid-edge than the slider
1. [#95](https://github.com/sesser/Gus/issues/95) `local-tone-edge-margin`: On macOS 26 an Apple filter bug moves edge pixels between renders
1. [#96](https://github.com/sesser/Gus/issues/96) `ptp-camera-import`: Cameras that do not mount as disks cannot be imported
1. [#97](https://github.com/sesser/Gus/issues/97) `second-backup-destination`: Card imports copy to one place only
1. [#98](https://github.com/sesser/Gus/issues/98) `export-extras`: No text watermarks, export of originals, or more than one destination per export
1. [#99](https://github.com/sesser/Gus/issues/99) `photo-pasteboard`: Photos can't be copied (⌘C) or dragged into other apps or the Finder;
1. [#100](https://github.com/sesser/Gus/issues/100) `video-editing-export`: Videos can be catalogued and played but not trimmed, edited, exported or published
1. [#101](https://github.com/sesser/Gus/issues/101) `avchd-video`: MTS/M2TS files are not catalogued
1. [#102](https://github.com/sesser/Gus/issues/102) `second-loupe-display`: No loupe on a second display
1. [#103](https://github.com/sesser/Gus/issues/103) `cli-writes-while-open`: photocli cannot write while the app has the library open
1. [#104](https://github.com/sesser/Gus/issues/104) `mcp-server`: No MCP access to the command registry
1. [#105](https://github.com/sesser/Gus/issues/105) `people-recognition`: No way to find photos of a person
1. [#106](https://github.com/sesser/Gus/issues/106) `metadata-reader-status`: When ExifTool isn't installed, metadata silently comes from ImageIO, which changes what the Info tab, smart albums and sidecar…
1. [#107](https://github.com/sesser/Gus/issues/107) `in-app-help`: The app has no help;
1. [#108](https://github.com/sesser/Gus/issues/108) `viewport-faster-frames`: At 100% on the owner's display a typical stack draws 6 to 7 sharp frames a second while a value moves (p95 about 140–160 ms);
1. [#109](https://github.com/sesser/Gus/issues/109) `viewport-large-photos`: Above 24 MP, sharp frames at 100% are slower (over 100 ms even in small windows at 54 MP) and the full-resolution copy held at 100%…
1. [#110](https://github.com/sesser/Gus/issues/110) `ml-denoise-missing-model`: On a Mac with macOS 27 but without the RAW 9 model, a photo that asks for machine learning noise reduction would say "could not be…

## Dropped

| Slug | Date | Reason |
|------|------|--------|
| film-strip-size-slider | 2026-11-04 | Owner revision: the slider pushed the centered thumbnail off the photo's center; replaced by a drag handle with fixed steps. Issue #25 still asks for a slider. `UI_REDESIGN.md` §11 decision 3 |
| write-metadata-to-originals | 2026-11-04 | Owner: conflicts with the referenced-masters principle (originals are never written). Sidecars carry the library's metadata. Was on CLAUDE.md "Not yet" and README "Not there yet" |
| film-strip-left-anchor | 2026-11-04 | Owner decision: the focused photo is centered in the strip, not at the left edge as issue #25 asks. `UI_REDESIGN.md` §11 decision 2 |

## Shipped

Closed issues: <https://github.com/sesser/Gus/issues?q=is%3Aissue+is%3Aclosed>.
Each carries its slug, its pull request and, where there is one, its folder.
