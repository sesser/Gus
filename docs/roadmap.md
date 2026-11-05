# Roadmap

Owned by the product-manager agent. Statuses are reconciled from `docs/features/<slug>/`.

Seeded 2026-11-04 from `CLAUDE.md` (Scope so far, Not yet), the phase plans,
`docs/UI_REDESIGN.md`, open GitHub issues and git history. At seeding no
feature folder existed, so every open item started as `Idea`. What already
exists is listed in [`features/_inventory.md`](features/_inventory.md).

2026-11-04: triaged the seven requirements issues (RI-1 … RI-7) from
[`features/ui-redesign/design.md`](features/ui-redesign/design.md) §5. Rulings
are in [`features/ui-redesign/prd.md`](features/ui-redesign/prd.md); new
scope is below as `Idea` rows citing the RI.

Where specs live: new features get `docs/features/<slug>/`. The phase plans
(`docs/PHASE1_PLAN.md` … `PHASE6_PLAN.md`) and `docs/UI_REDESIGN.md` stay
where they are as the historical record (owner, 2026-11-04).

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

## Status key

Idea, Specified (has prd.md), Designed (has design.md), In progress, Shipped, Dropped

## Now (maximum three)

Both items chosen by owner 2026-11-04. One slot is free since the film strip
shipped; filling it is the owner's choice.

| Slug | Problem | Status | Folder | Source |
|------|---------|--------|--------|--------|
| publishing-engine | Getting edited photos into Apple Photos or Immich means exporting to a folder and uploading by hand | Idea | none yet | Issue #28; `PHASE4_PLAN.md` out of scope ("export to services") |
| ui-redesign-onscreen-check | Parts of the shipped redesign and the film strip were only checked by tests, never seen on screen (glass panes, VoiceOver speech, macOS 15 path, 13" Export sheet; film strip steps, height cap, show/hide, resize drag, crop session, Increase Contrast) | Idea | none yet | `UI_REDESIGN.md` status, "Not yet checked on screen"; §11 "Implementation status", last item |

## Next

Order is my proposal, not owner-confirmed.

| Slug | Problem | Status | Why this order | Source |
|------|---------|--------|----------------|--------|
| ui-redesign-reconcile | Shipped UI has wrong enablement (Export on videos), a wrong empty state for empty albums, inconsistent field names and missing menu items (E1–E27) | Designed | Jumps the queue: already designed, and its three High changes fix wrong behavior people hit today. Pairs with ui-redesign-onscreen-check, which should run after it. Folder is [`features/ui-redesign/`](features/ui-redesign/) (design.md §6; prd.md addendum) | `ui-redesign/design.md` §3, §6 |
| edit-history | No way to see or jump back to an earlier state of a photo's edits | Idea | Intake before any spec (owner, 2026-11-04). Need: see a photo's edit steps and return to an earlier one. Open for the owner: does history survive relaunch. Placement and keys belong to design, not the PRD: issue #26's ⌘Y redo and left-sidebar placement are proposals, and they conflict with the shipped ⇧⌘Z (the HIG's standard redo) and a sidebar that holds sources (UIR §3). RI-6 | Issue #26; `ui-redesign/design.md` RI-6 |
| viewport-render-1to1 | At 100% zoom, sliders show a stretched 2560 px frame until the edit is saved | Idea | Named on the phase 6 roadmap; affects every edit at 1:1 | `PHASE6_PLAN.md` "Roadmap" |
| dehaze-above-white | Dehaze and local tone estimates jump on extended-range (above white) input | Idea | Named on the phase 6 roadmap; a rendering change with a pipeline bump | `PHASE6_PLAN.md` "Roadmap", finding 4 |
| remove-from-library | A wrong or unwanted import can never be taken out of the library; nothing removes photos or projects from the catalog (files are never touched) | Idea | Placed after the owner's queued items. Every library collects mistakes, and the catalog already has `deleteProject` (cascade, tested), so effort is moderate. Intake: what happens to edits, albums, pairs, sidecar files and undo; whether offline photos can be removed (the "never delete rows because a volume is missing" rule covers automatic removal, not a person's choice) | `ui-redesign/design.md` RI-2 |
| rename-project | Projects keep the folder or template name they were imported with | Idea | Small: `Catalog.renameProject` exists with no UI. Could ship with remove-from-library | `ui-redesign/design.md` RI-2 |
| show-in-finder | No way to reveal a photo's original or a project's folder in the Finder | Idea | Small and frequent for people who keep their own folders (the vision). Intake: offline originals, which file of a RAW+JPEG pair, projects with no single folder (`project.sourcePath` is not always set). Export already reveals its own output | `ui-redesign/design.md` RI-3 |

## Later

Roughly ordered by dependency, then by how often a photographer would hit
the gap. Ordering below the first row is judgment.

| Slug | Problem | Status | Notes | Source |
|------|---------|--------|-------|--------|
| publishing-plugins | Destinations beyond the built-ins need app changes | Idea | Depends on publishing-engine settling `PublishTarget` | Issue #29 |
| dng-export | No DNG output | Idea | ImageIO cannot write DNG; needs a writer of our own | CLAUDE.md Not yet; `PHASE4_PLAN.md` Formats; issue #6 (asked, closed without it) |
| healing | No spot removal or healing | Idea | Phase 5's test loop was built with healing and lens corrections in mind | CLAUDE.md Not yet; `PHASE5_PLAN.md` intro; `PHASE6_PLAN.md` out of scope |
| lens-corrections | No distortion, vignetting or chromatic aberration correction | Idea | Interacts with the decoder's own lens correction on camera-cropped raws | CLAUDE.md Not yet; `PHASE6_PLAN.md` finding 1 |
| ai-masks | No subject, sky, object or people masks | Idea | | CLAUDE.md Not yet; `PHASE6_PLAN.md` out of scope |
| ml-denoise | Noise reduction is classical only | Idea | | CLAUDE.md Not yet; `PHASE3_PLAN.md` out of scope |
| dcp-profiles | Adobe `.dcp` camera profiles not supported | Idea | | CLAUDE.md Not yet; `PHASE3_PLAN.md` out of scope |
| stacks | No hand-made or burst stacks | Idea | `stack` / `stackMember` tables and `Catalog.createStack` exist, no UI | CLAUDE.md Not yet; `PHASE2_PLAN.md` out of scope |
| virtual-copies | No second version of a photo with different edits | Idea | `Catalog.duplicateVersion` exists, no UI | Issue #26 ("future feature") |
| hierarchical-keywords | Keywords are flat | Idea | `keyword.parentId` exists, always NULL | CLAUDE.md Not yet; `PHASE2_PLAN.md` |
| masks-in-presets-and-paste | Presets, paste and sync leave masks out; no mask presets | Idea | | `PHASE6_PLAN.md` out of scope |
| whole-mask-invert | Inverting a whole mask takes a first Subtract component | Idea | Owner: "no for now" | `PHASE6_PLAN.md` Answers, E |
| local-dehaze-exact | Soft-edged local dehaze is much stronger mid-edge than the slider | Idea | Needs a per-pixel amount (kernel or 2-D table) | `PHASE6_PLAN.md` decision 5 |
| local-tone-edge-margin | On macOS 26 an Apple filter bug moves edge pixels between renders | Idea | Our-side workaround with a pipeline bump; only if Apple does not fix it | `PHASE6_PLAN.md` finding 6; `docs/feedback/edge-preserve-upsample/` |
| ptp-camera-import | Cameras that do not mount as disks cannot be imported | Idea | | CLAUDE.md Not yet |
| second-backup-destination | Card imports copy to one place only | Idea | | CLAUDE.md Not yet |
| export-extras | No text watermarks, export of originals, or more than one destination per export | Idea | Overlaps publishing-engine for destinations | `PHASE4_PLAN.md` out of scope |
| photo-pasteboard | Photos can't be copied (⌘C) or dragged into other apps or the Finder; grid drags carry a private type that only the sidebar accepts | Idea | Export covers the need with more steps, so Later. Separate from publishing-engine (no destination or account) but shares export's rendering; "copy the original file" overlaps export-extras' export of originals. Until it ships, Edit ▸ Copy stays text-only in the grid and loupe (design X5). Intake: rendered image or original file, size, pairs, videos, offline photos | `ui-redesign/design.md` RI-7 |
| video-editing-export | Videos can be catalogued and played but not trimmed, edited, exported or published | Idea | | `PHASE2_PLAN.md`, `PHASE4_PLAN.md`; issue #28 out of scope |
| avchd-video | MTS/M2TS files are not catalogued | Idea | Left out until tried on real files | `PHASE2_PLAN.md` As built |
| second-loupe-display | No loupe on a second display | Idea | | `UI_REDESIGN.md` decision 9 |
| cli-writes-while-open | `photocli` cannot write while the app has the library open | Idea | App would need to notice outside writes | `PHASE5_PLAN.md` "Not surprising the app" |
| mcp-server | No MCP access to the command registry | Idea | Registry was designed so one could dispatch it | `PHASE5_PLAN.md` out of scope |
| people-recognition | No way to find photos of a person | Idea | On-device face detection and recognition (Vision, Core ML); parked by the owner 2026-10-31 | Owner decision 2026-10-31 (not in repo docs) |
| metadata-reader-status | When ExifTool isn't installed, metadata silently comes from ImageIO, which changes what the Info tab, smart albums and sidecar comparisons see | Idea | Ruling on intent: if built, it is a passive statement of which reader is in use, never an alert (design P4: information that needs no action gets no alert). Whether to also suggest installing ExifTool is an intake question. Later because the effect is invisible to most people | `ui-redesign/design.md` RI-4; README "ExifTool is used… when it's installed" |
| in-app-help | The app has no help; the dead "‹app› Help" item is removed meanwhile (ui-redesign prd.md R1) | Idea | Intake: form (bundled Help Book, the guide shown in the app, or a web page, whose URL is a brand value), and whether it covers `photocli`. `docs/USER_GUIDE.md` is kept by the engineer, with the designer reviewing its terms (owner ruling, 2026-11-04, RI-5); if help is built from the guide, that stays its owner | `ui-redesign/design.md` RI-1, N13, I28 | `ui-redesign/design.md` RI-1, N13, I28 |

## Shipped

Dates are from git history (first commit of the work) or the phase document.

| Slug | Shipped | Notes |
|------|---------|-------|
| library-core | 2026-10-23 | Phase 1: catalog, import in place, offline volumes, previews, grid, loupe, culling, sidebar filters, profiling. `PHASE1_PLAN.md` |
| grid-labels-and-pairs | 2026-10-23 | Phase 2 steps 1–2: file names, type badges, RAW+JPEG pairs. `PHASE2_PLAN.md` |
| keywords-and-suggestions | 2026-10-23 | Phase 2 steps 3–4: keywords, inspector, undo, on-device suggestions |
| albums-and-smart-albums | 2026-10-23 | Phase 2 step 5: albums, smart albums, Dates tree, more metadata |
| xmp-sidecars | 2026-10-23 | Phase 2 step 6: write sidecars, review outside changes |
| card-import | 2026-10-23 | Phase 2 step 7: copy, verify, delete from card, eject |
| videos | 2026-10-23 | Phase 2 step 8: MOV/MP4/M4V catalogued and played |
| hdr-display | 2026-10-25 | HDR sources on EDR displays. CLAUDE.md Rendering; git |
| standalone-importer | 2026-10-26 | Copy cards without a library. CLAUDE.md; git |
| global-adjustments | 2026-10-26 | Phase 3 first pass. `PHASE3_PLAN.md` |
| look-up-tables | 2026-10-26 | LUT browser and intensity; Effects heading with collections, vignette, grain on 2026-10-27; refinements from issue #1 (closed) on 2026-10-28 |
| folder-drop-import | 2026-10-27 | Folders dragged from Finder import in place. `PHASE3_PLAN.md` As built |
| presets | 2026-10-28 | Color Mixer, partial presets, collections, preset files, Lightroom import. `PHASE3_PLAN.md` second pass |
| export | 2026-10-28 | Phase 4 first pass; issue #6 (closed). `PHASE4_PLAN.md` |
| crop-rotate-straighten | 2026-10-29 | CLAUDE.md Scope; git |
| info-metadata-fields | 2026-10-30 | IPTC Core/Extension fields in the Info tab, migration v13. CLAUDE.md Scope; git |
| goldens-and-references | 2026-10-31 | Phase 5. `PHASE5_PLAN.md` |
| photocli | 2026-10-31 | Phase 5: command registry, `photocli`, library lock; mask commands added in phase 6 |
| local-adjustments-masks | 2026-11-01 | Phase 6 first pass, with stage caching and drafts. `PHASE6_PLAN.md` |
| import-keep-picks | 2026-11-02 | Bug, issue #19 (closed); UI_REDESIGN step 10 |
| ui-redesign | 2026-11-04 | Steps 1–15 incl. review mode; PRs #20, #21. Not everything checked on screen (see ui-redesign-onscreen-check). Reconciled design in [`features/ui-redesign/`](features/ui-redesign/); its follow-up changes are ui-redesign-reconcile (Next) |
| loupe-film-strip | 2026-11-04 | Issue #25 (closed); merged via PR #27. Spec stayed in `UI_REDESIGN.md` §11 (owner, 2026-11-04). Its on-screen checks are under ui-redesign-onscreen-check. §11's checklist still shows 7 build items open that the code appears to implement; the engineer should tick them |

## Dropped

| Slug | Date | Reason |
|------|------|--------|
| film-strip-size-slider | 2026-11-04 | Owner revision: the slider pushed the centered thumbnail off the photo's center; replaced by a drag handle with fixed steps. Issue #25 still asks for a slider. `UI_REDESIGN.md` §11 decision 3 |
| write-metadata-to-originals | 2026-11-04 | Owner: conflicts with the referenced-masters principle (originals are never written). Sidecars carry the library's metadata. Was on CLAUDE.md "Not yet" and README "Not there yet" |
| film-strip-left-anchor | 2026-11-04 | Owner decision: the focused photo is centered in the strip, not at the left edge as issue #25 asks. `UI_REDESIGN.md` §11 decision 2 |
