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

2026-11-05: specified sharpen-mask-preview (owner's idea, follow-up to issue
#35 / PR #36) and placed it at the top of Next. Now is full, so I did not move
anything out. The owner answered its four questions the same day, and the
PRD is approved. The owner also ruled on the designer's RI-1 and RI-2 for it.
RI-2 became the Idea row local-sharpen-group-off, placed right after it in
Next. After implementation, the owner ruled on the engineer's finding and
made it the Idea row sharpen-masking-scale. It merged in PR #37 the same day
and moved to Shipped. Its manual checks M1–M9 are still open, by the owner's
choice ("Shipped, checks pending").

2026-11-05: specified ml-denoise (owner accepted every intake default) and
moved it to the top of Next; added classical-noise-strength. Both come from
issue #35.

2026-11-06: Ship pass (`docs/WORKFLOW.md` step 6) for two merges nobody had
recorded. ui-redesign-reconcile merged in PR #34 (merge commit 1e89a7b,
2026-11-05) and ml-denoise in PR #39 (merge commit 334312c, 2026-11-05); both
commits are on `develop`. Both moved to Shipped as "Shipped, checks pending",
with links to where the open checks are listed. ml-denoise's PRD had said
AC13 keeps it short of Shipped; under the workflow as changed, a merge is
what ships, and AC13 is recorded as a pending check instead (PRD Revisions).
Added follow-up Idea rows appkitbutton-enablement (from
`ui-redesign/status.md`) and ml-denoise-missing-model (from
`ml-denoise/status.md`, RI-E6). Also fixed the in-app-help row's duplicated
Source cell. Now has two items; I did not move anything in (candidate in my
report to the owner).

2026-11-06: QA pass and owner rulings. qa-tester ran step 4 after the merge
for the three features shipped with checks pending and wrote
[`ml-denoise/qa.md`](features/ml-denoise/qa.md),
[`sharpen-mask-preview/qa.md`](features/sharpen-mask-preview/qa.md) and
[`ui-redesign/qa.md`](features/ui-redesign/qa.md). Every criterion a test or
script can reach passed, except ml-denoise's M9: the "Machine Learning Not
Applied" badge draws over the loupe caption's rating and flag at narrow
widths. What only a person can check is now each qa.md's "For a person"
list. The QA run found a cache bug outside those features (a saved edit can
keep its old preview under the new hash), and during it a copy of the app
started without `--library-root` opened the owner's real library for about
3 minutes (nothing changed). Owner rulings, the same day: (1) Now's third
slot stays empty until the manual checks are done; (2) ml-denoise ships
without the RI-E6 (d) check, which stays pending, and ml-denoise-missing-model
stays in Later; (3) every person-only check, including ml-denoise's AC13, is
done in one sitting under ui-redesign-onscreen-check. The findings became
seven Idea rows in Next, citing `<feature>/qa.md Qn`. The stale-preview bug
is at the top of Next and is the candidate for the empty Now slot. The PRD
Status lines of the three features now point to their qa.md.

Where specs live: new features get `docs/features/<slug>/`. The phase plans
(`docs/archive/PHASE1_PLAN.md` … `PHASE6_PLAN.md`) and `docs/UI_REDESIGN.md`
stay as the historical record (owner, 2026-11-04). Bare `PHASE<n>_PLAN.md`
names below refer to `docs/archive/` (the plans moved there; path corrected
2026-11-05).

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

Items chosen by owner 2026-11-04. ui-redesign-reconcile shipped 2026-11-05
(PR #34) and left Now on 2026-11-06. The third slot stays empty by the
owner's choice until the manual checks under ui-redesign-onscreen-check are
done (owner, 2026-11-06). The candidate for it is stale-preview-after-save
(top of Next).

| Slug | Problem | Status | Folder | Source |
|------|---------|--------|--------|--------|
| publishing-engine | Getting edited photos into Apple Photos or Immich means exporting to a folder and uploading by hand | Idea | none yet | Issue #28; `PHASE4_PLAN.md` out of scope ("export to services") |
| ui-redesign-onscreen-check | Shipped work that only a person can check, done in one sitting (owner, 2026-11-06). (a) The older redesign: glass panes, VoiceOver speech, macOS 15 path, 13" Export sheet. (b) The film strip: steps, height cap, show/hide, resize drag, crop session, Increase Contrast. (c) ui-redesign-reconcile: P1–P10 in [`ui-redesign/qa.md`](features/ui-redesign/qa.md) "For a person", incl. AC2. (d) sharpen-mask-preview: P1–P8 in [`sharpen-mask-preview/qa.md`](features/sharpen-mask-preview/qa.md) "For a person", incl. the ⇧↑ check for its Q2. (e) ml-denoise: P1–P9 in [`ml-denoise/qa.md`](features/ml-denoise/qa.md) "For a person", incl. AC13 (P9, your raws: ML vs classical at 100). Items that need another Mac (macOS 15 or 26: ml P6, sharpen P8, ui P10; a Mac without the RAW 9 model: ml P8, the RI-E6 (d) check) stay open here until one is available | Idea | none yet | `UI_REDESIGN.md` status, "Not yet checked on screen"; §11 "Implementation status", last item; the three qa.md files above (2026-11-06) |

## Next

Order is my proposal, not owner-confirmed. The 2026-11-06 QA findings are
in two places. The three that are urgent or user-visible are at the top. The
small fixes are at the end, next to appkitbutton-enablement; each can go as a
bug fix without a feature folder (`docs/WORKFLOW.md`), so its place in the
queue doesn't hold it back.

| Slug | Problem | Status | Why this order | Source |
|------|---------|--------|----------------|--------|
| stale-preview-after-save | Saving an edit can cache the old look under the new edit's hash. The grid then shows the unedited photo, and it stays wrong after relaunch (3 of 4 photos in one run, with or without the sharpening map) | Idea | Jumps the queue. This is a correctness bug in a core path: every saved edit goes through it, the preview cache is keyed by render hash, and nothing regenerates a wrong entry. Likely cause, not confirmed: `AdjustmentEditor.apply` gives the grid the new hash before the async catalog write finishes. It can go as a bug fix without a feature folder. Candidate for Now's empty slot. My proposal (owner to confirm): the fix also corrects previews already cached wrong, since the owner's library may hold some; how is the engineer's call | `sharpen-mask-preview/qa.md` Q1 (runs c2, c3) |
| library-launch-guard | A test copy of the app started without `--library-root` opens the owner's real library. It happened once during QA on 2026-11-06 (about 3 minutes, nothing changed, verified). The workflow forbids it, but nothing in the app prevents it | Idea | Second: small, and the next slip could change ratings, edits or sidecars (which sit beside the originals) in the real library. The process rules are already fixed; this adds a safeguard in the app. Intake decides the mechanism, for example: a build with a non-release bundle identifier refuses to open the default library without an explicit `--library-root` | `ui-redesign/qa.md` "Incident in this QA run"; owner, 2026-11-06 |
| loupe-caption-narrow | At narrow window widths the loupe caption's items collide. The "Machine Learning Not Applied" badge draws over the rating and pick flag (overlaps at 760 pt, touches at 820 pt, clear at 900 pt), the sharpening map badge truncates to "Shar…", and the position text wraps | Idea | Third: a failed design check (ml-denoise M9) on shipped work, seen at the window's minimum size. Needs a designer ruling first: what gives way when the caption is too narrow, one rule for every badge. Then a small fix; recheck with `ml-denoise/qa.md` S-12/S-13 | `ml-denoise/qa.md` Q1 (M9); sharpen-mask-preview QA run 2026-11-06, design note (reported to the main session, not written in its qa.md) |
| classical-noise-strength | The classical noise sliders (RAW decoder and Core Image filter) are mild at 100; the non-RAW filter runs after the vignette and ignores preview scale | Idea | Owner, 2026-11-05: split out of ml-denoise. The only noise fix for JPEG/HEIC. Changes existing edits' rendering (pipeline bump, goldens); intake must decide whether existing stacks keep their look | Issue #35; `PHASE6_PLAN.md` finding 6; `ml-denoise/prd.md` Non-goals |
| local-sharpen-group-off | Turning the Sharpening group off makes local Sharpness use the default Radius 1, Detail 25 and Masking 0 instead of the user's values, so it starts sharpening noise (`Adjustments.effective` resets the group) | Idea | Next to sharpen-mask-preview because it concerns the same code and changes saved renders unexpectedly. Owner to decide the intent: should local Sharpness keep the user's Radius, Detail and Masking, or turn off with the group? Any fix is a rendering change that needs a `PreviewCacheKey.currentPipelineVersion` bump and golden updates | Designer RI-2 on sharpen-mask-preview; owner ruling 2026-11-05 ("Roadmap item to decide"). `AdjustmentRenderer.swift:193-194` |
| sharpen-masking-scale | Masking holds back much more noise at fit than in a full-size export: on a noisy flat area at Masking 30, about 50% of the sharpening at fit (scale 0.43) against about 93% at full size. So the loupe at fit understates the sharpened noise an export gets | Idea | Placed after local-sharpen-group-off: same sharpening code, and both are rendering changes, so one pipeline bump could cover both. Any fix is a rendering change that needs a `PreviewCacheKey.currentPipelineVersion` bump and golden updates. Not urgent, because once input pauses the sharpening map already shows the full-size result | Engineer's finding on sharpen-mask-preview (PRD Q5: M4 Pro debug build, synthetic noisy 6000 × 4000 DNG); owner ruling 2026-11-05 ("Add Idea row") |
| edit-history | No way to see or jump back to an earlier state of a photo's edits | Idea | Intake before any spec (owner, 2026-11-04). Need: see a photo's edit steps and return to an earlier one. Open for the owner: does history survive relaunch. Placement and keys belong to design, not the PRD: issue #26's ⌘Y redo and left-sidebar placement are proposals, and they conflict with the shipped ⇧⌘Z (the HIG's standard redo) and a sidebar that holds sources (UIR §3). RI-6 | Issue #26; `ui-redesign/design.md` RI-6 |
| viewport-render-1to1 | At 100% zoom, sliders show a stretched 2560 px frame until the edit is saved | Idea | Named on the phase 6 roadmap; affects every edit at 1:1 | `PHASE6_PLAN.md` "Roadmap" |
| dehaze-above-white | Dehaze and local tone estimates jump on extended-range (above white) input | Idea | Named on the phase 6 roadmap; a rendering change with a pipeline bump | `PHASE6_PLAN.md` "Roadmap", finding 4 |
| remove-from-library | A wrong or unwanted import can never be taken out of the library; nothing removes photos or projects from the catalog (files are never touched) | Idea | Placed after the owner's queued items. Every library collects mistakes, and the catalog already has `deleteProject` (cascade, tested), so effort is moderate. Intake: what happens to edits, albums, pairs, sidecar files and undo; whether offline photos can be removed (the "never delete rows because a volume is missing" rule covers automatic removal, not a person's choice) | `ui-redesign/design.md` RI-2 |
| rename-project | Projects keep the folder or template name they were imported with | Idea | Small: `Catalog.renameProject` exists with no UI. Could ship with remove-from-library | `ui-redesign/design.md` RI-2 |
| show-in-finder | No way to reveal a photo's original or a project's folder in the Finder | Idea | Small and frequent for people who keep their own folders (the vision). Intake: offline originals, which file of a RAW+JPEG pair, projects with no single folder (`project.sourcePath` is not always set). Export already reveals its own output | `ui-redesign/design.md` RI-3 |
| slider-field-shift-step | ⇧↑ / ⇧↓ in an adjustment slider's value field likely don't step by 10 as the design asks. Plain ↑ / ↓ work (`SliderRow` handles only `moveUp:` / `moveDown:`) | Idea | Small fix, on the keyboard path (principle 5). It affects every slider, not one feature. Confirm by hand first, since a scripted key isn't a held Shift: sharpen P1 step 3 under ui-redesign-onscreen-check | `sharpen-mask-preview/qa.md` Q2; `sharpen-mask-preview/design.md` §8 |
| export-missing-file-reason | An export whose original is missing from a connected volume says "the volume … is not connected". Since E14 that Activity warning is the only report the person gets | Idea | Small fix, made more visible by E14. Product intent (mine; owner may overrule): the reason tells a disconnected volume apart from a missing file, because the person fixes them differently. The wording belongs to the designer. Intake: whether the grid and loupe's Offline state should draw the same line (not checked) | `ui-redesign/qa.md` Q3; `ui-redesign/design.md` E14 |
| appkitbutton-enablement | Some inspector buttons look enabled when they should be dimmed (the mask eye button and other Adjust tab buttons are likely affected): `AppKitButton(isEnabled: false)` doesn't reliably dim | Idea | A defect, small, and against principle 4; it may go as a bug fix without a feature folder (workflow: bug fixes skip steps 1, 2 and 6). Placed with the small fixes only because a workaround covers the buttons the reconcile changes touched | `ui-redesign/status.md` "Found, not fixed" |
| debug-script-undo-groups | Debug-script commands that change nothing (`ml wait`, `ml ready`, `ml override`, a `key` with no effect, `adjust crop show`, `adjust crop begin`) open undo groups and leave empty undo steps, so scripted undo checks misread. `ml override` also reloads before the last save lands, and a frame still in flight can override the new state | Idea | Tooling only; people using the app don't see it. Ahead of qa-test-gaps because the loupe-caption-narrow recheck uses `ml override` (the workaround until then: `wait` before an override, `ml override clear` between two). For the engineer, no feature folder | `ml-denoise/qa.md` Q2, Q3; `sharpen-mask-preview/qa.md` Q4; `ui-redesign/qa.md` Q2 |
| qa-test-gaps | Three tests don't check what they are named for. ml-denoise AC10's "Reset All clears it" asserts the Details reset. Nothing observable shows that the sharpening map after a pause is the refined frame (AC7, R6). `FolderImportQueueTests` passes without E13's change | Idea | For the engineer, no feature folder. All three behaviors passed by script, so no defect is known; the risk is a regression nobody notices. Each fix is an assertion, a rename, a testable rule, or more detail in `print sharpenmap` | `ml-denoise/qa.md` Q4; `sharpen-mask-preview/qa.md` Q3; `ui-redesign/qa.md` Q1 |

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
| in-app-help | The app has no help; the dead "‹app› Help" item was removed (ui-redesign prd.md R1, E28, shipped in PR #34) | Idea | Intake: form (bundled Help Book, the guide shown in the app, or a web page, whose URL is a brand value), and whether it covers `photocli`. `docs/USER_GUIDE.md` is kept by the engineer, with the designer reviewing its terms (owner ruling, 2026-11-04, RI-5); if help is built from the guide, that stays its owner | `ui-redesign/design.md` RI-1, N13, I28 |
| ml-denoise-missing-model | On a Mac with macOS 27 but without the RAW 9 model, a photo that asks for machine learning noise reduction would say "could not be applied to this photo" (or, if macOS falls back silently, claim it applied) instead of "not available on this Mac" (owner ruling 9). No public API tells whether the model is present | Idea | Depends on the pending RI-E6 (d) check on ml-denoise (what a decode does without the model; `ml-denoise/qa.md` P8) or on Apple documenting a presence check. The owner accepted shipping without that check and kept this row in Later (2026-11-06). If (d) shows a silent fallback, it breaks owner ruling 3 and moves up | `ml-denoise/status.md` RI-E6; `ml-denoise/prd.md` Open questions |

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
| ui-redesign | 2026-11-04 | Steps 1–15 incl. review mode; PRs #20, #21. Not everything checked on screen (see ui-redesign-onscreen-check). Reconciled design in [`features/ui-redesign/`](features/ui-redesign/); its follow-up changes are ui-redesign-reconcile (Shipped 2026-11-05) |
| loupe-film-strip | 2026-11-04 | Issue #25 (closed); merged via PR #27. Spec stayed in `UI_REDESIGN.md` §11 (owner, 2026-11-04). Its on-screen checks are under ui-redesign-onscreen-check. §11's checklist still shows 7 build items open that the code appears to implement; the engineer should tick them |
| sharpen-mask-preview | 2026-11-05 | Merged via PR #37 (merge commit 64334b7). Shows where Sharpening's Masking lets sharpening through: a live estimate while the value changes, recomputed at full resolution when input pauses. **Shipped, checks pending** (owner's choice, 2026-11-05). QA on 2026-11-06 passed everything a test or script reaches (M7, M8 closed); what is left for a person is P1–P8 in [`sharpen-mask-preview/qa.md`](features/sharpen-mask-preview/qa.md), done under ui-redesign-onscreen-check. Follow-ups: local-sharpen-group-off, sharpen-masking-scale, and from QA slider-field-shift-step, debug-script-undo-groups, qa-test-gaps (Next). Its QA also found stale-preview-after-save (Next), which this feature didn't cause. [`features/sharpen-mask-preview/`](features/sharpen-mask-preview/) |
| ui-redesign-reconcile | 2026-11-05 | **Shipped, checks pending.** Merged via PR #34 (merge commit 1e89a7b). All 28 changes E1–E28 from `ui-redesign/design.md` §6 are Done: empty states per source, Export enabled only for photos, export results in Activity only, one ⌘. Stop and one ⇧⌘A Deselect All, Play / Pause and a video context menu, new Adjust menu items, one set of field labels, preset delete confirmations, the dead Help item removed. QA on 2026-11-06 found nothing failing in E1–E28 and closed most of status.md's "Pending manual checks" by script. What is left for a person, AC2 included, is P1–P10 in [`ui-redesign/qa.md`](features/ui-redesign/qa.md), done under ui-redesign-onscreen-check (Now). No separate review.md. Follow-ups: appkitbutton-enablement, and from QA export-missing-file-reason, debug-script-undo-groups, qa-test-gaps, library-launch-guard (Next). [`features/ui-redesign/`](features/ui-redesign/) |
| ml-denoise | 2026-11-05 | **Shipped, checks pending.** Merged via PR #39 (merge commit 334312c). Opt-in machine learning noise reduction for raw files through the macOS 27 RAW decoder's version 9; off unless chosen, says why when it can't apply. QA on 2026-11-06 passed every criterion this Mac can run, but the designer's M9 failed: the caption badge overlaps the rating and flag at narrow widths (loupe-caption-narrow, Next). What is left for a person is P1–P9 in [`ml-denoise/qa.md`](features/ml-denoise/qa.md), done under ui-redesign-onscreen-check. That includes AC13 (P9, the owner's check on 2–3 of their own high-ISO raws that it beats classical at 100) and the RI-E6 (d) check (P8, a Mac without the model), which the owner accepted shipping without (2026-11-06). Follow-ups: classical-noise-strength, and from QA loupe-caption-narrow, debug-script-undo-groups, qa-test-gaps (Next); ml-denoise-missing-model (Later). [`features/ml-denoise/`](features/ml-denoise/) |

## Dropped

| Slug | Date | Reason |
|------|------|--------|
| film-strip-size-slider | 2026-11-04 | Owner revision: the slider pushed the centered thumbnail off the photo's center; replaced by a drag handle with fixed steps. Issue #25 still asks for a slider. `UI_REDESIGN.md` §11 decision 3 |
| write-metadata-to-originals | 2026-11-04 | Owner: conflicts with the referenced-masters principle (originals are never written). Sidecars carry the library's metadata. Was on CLAUDE.md "Not yet" and README "Not there yet" |
| film-strip-left-anchor | 2026-11-04 | Owner decision: the focused photo is centered in the strip, not at the left edge as issue #25 asks. `UI_REDESIGN.md` §11 decision 2 |
