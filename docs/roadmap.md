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
was at the top of Next and the candidate for the empty Now slot (it shipped
the same day; next entry). The PRD Status lines of the three features now
point to their qa.md.

2026-11-06: Ship pass for stale-preview-after-save, a bug fix with no PRD
(status.md, code-review.md and qa.md in its folder). Merged in PR #40
(merge commit 986131a, on `develop`). Moved from Next to Shipped as
"Shipped, checks pending": qa.md's optional P2 (a real slider drag on real
raws) is open for a person and joins ui-redesign-onscreen-check as (f). The
owner accepted the cost of pipeline version 7 (qa.md P1, recorded in
status.md). Follow-ups: editor-follow-edit-drop (top of Next, data loss) and
reload-items-stale-hash (with the small fixes); qa.md O2 (no test target for
the app-side ordering) added to qa-test-gaps. Now still has two items; the
owner's rule on the third slot stands.

2026-11-06: Ship and reconcile pass. editor-follow-edit-drop and
reload-items-stale-hash merged as one bug fix with no PRD in PR #43
(`bug/editor-follow-edit-drop`, merge commit 520d479, on `develop`; records
in [`editor-follow-edit-drop/`](features/editor-follow-edit-drop/)). Code
review: ready to merge, no findings. QA: all 13 items pass, and each route
reproduces on `develop` and none on the branch. Both moved from Next to
Shipped. editor-follow-edit-drop is "Shipped, checks pending": qa.md's
optional P1 (real keys on real raws) joins ui-redesign-onscreen-check as (g).
I corrected reload-items-stale-hash's wording as I closed it. The row said
"display only", which was wrong for culling: on `develop`, after a stale
reload, the next rating, flag or label key saved the stale values (qa.md Q1).
QA O1 (the Adjust tab shows loading for about 3 s behind a batch of about
30,000 photos) is recorded as the expected cost of the rule. QA O2 joins
qa-test-gaps. New Idea row reads-beside-write-chain (code-review.md Q1),
second in Next. Reconciled two merges nobody had recorded. PR #41
(`chore/project-cleanup`, d56580b) holds the agent-workflow changes, the three
qa.md files, `--library-root` required on every scripted launch, a CLAUDE.md
note on bringing a scripted app forward, and the roadmap entries for
stale-preview's ship. PR #42 (`bug/ci-crash-capture`, 14dc0c1) makes CI record
backtraces and crash reports when the tests crash. Neither changes the app.
PR #41 puts the `--library-root` rule in the docs and agent prompts only, so
library-launch-guard (a safeguard in the app) still stands. The comment PR #42
added to `.github/workflows/build.yml` says the test process has crashed with
signal 11 on `develop` since PR #39 and never reproduced locally. That became
the Idea row ci-test-crash, for the owner to confirm. Issues #35, #29, #28 and
#26 are each cited by a row. There are no unmerged branches besides master.
Now still has two items; the owner's rule on the third slot stands.

2026-11-06: triage, on `chore/roadmap-reprioritize` (from `develop` after
PRs #44 and #45; #45 moved Ship onto the feature branch and gives every bug
fix a folder and QA). Owner rulings, the same day: (1) publishing-engine
moves from Now to Later; issue #28 stays cited. (2) ui-redesign-onscreen-check
moves from Now to Later, nothing dropped. Item (c) is done: "I've checked
all the P1-P10 of the ui-redesign", all passed, no findings. That was all
ui-redesign-reconcile had open, so its Shipped row and the ui-redesign PRD's
Status line no longer say "checks pending" (PRD Revisions). qa.md's
Follow-up does not record the owner's check yet; that file is qa-tester's.
The row keeps (a) the older redesign, incl. the macOS 15 path (the owner has
no macOS 15 Mac), (b) the film strip, (d) sharpen-mask-preview P1–P8, (e)
ml-denoise P1–P9 incl. AC13, and the optional (f) and (g). (3) Now is
exactly library-launch-guard, viewport-render-1to1 and edit-history, three
items. This supersedes the earlier ruling that the third slot stays empty
until the manual checks are done. Under Now: library-launch-guard can go as
a bug fix once the owner picks the mechanism; viewport-render-1to1 needs a
short PRD after a few intake answers; edit-history needs intake, then a PRD
and design. (4) The top of Next is remove-from-library, rename-project,
show-in-finder, in that order, with their intake notes. (5) Then
virtual-copies, up from Later (`Catalog.duplicateVersion` exists; issue #26),
then a new Idea row, side-by-side-comparison, which needs intake (the owner
gave only "side-by-side comparison"; no open issue covers it, issue #26
mentions it as a future idea with virtual copies). (6) The rest of Next
keeps its order, so the whole of Next is now owner-set. reads-beside-write-chain
goes from second to sixth by that ruling. I also brought the bug-fix rows'
wording in line with PR #45 ("as a bug fix", not "without a feature
folder"). Still open for the owner: whether the CI test crash still
happens (ci-test-crash).

2026-11-07: Ship pass for library-launch-guard, a bug fix with no PRD
(status.md, code-review.md, review.md and qa.md in
[`library-launch-guard/`](features/library-launch-guard/)), PR #47 on
`bug/library-launch-guard`. The owner picked the mechanism the same day
(status.md, rulings 1–4). Code review: two passes, closed. Design review:
F1 fixed and confirmed. QA: passes, no findings. Moved from Now to
Shipped. P1–P3 and the optional P4 in its qa.md were for a person and
were recorded as ui-redesign-onscreen-check (h) (owner ruling 3 of
2026-11-06: every person-only check in one place); they passed the same
day (next entry). Follow-ups: QA O1 (`LocalizationTests` misses
multi-line `String(` calls) and O2 (the launcher's wiring has no
automated test) added to qa-test-gaps. Now has two items,
viewport-render-1to1 and edit-history; I did not move anything in
(owner's call).

2026-11-07: Ship pass again for library-launch-guard (PR #47). The owner
made P1–P4 ("P1-P4 pass visual testing"), no findings; qa-tester recorded
it in [`library-launch-guard/qa.md`](features/library-launch-guard/qa.md)
Follow-up: 16 of 16 pass, nothing open. "Checks pending" cleared on its
Shipped row, and ui-redesign-onscreen-check (h) marked done.

2026-11-07: owner's request. Chromatic aberration and fringing
correction comes out of lens-corrections (Later) as a new row,
chromatic-aberration. The owner said: "make it the next item". Owner's
reason: "Most raw files already have geo corrections and vignetting baked
in but the fringing usually isn't". Now had one free slot, so the row
goes into Now as the first item, the next one to start, and Now is full
again. Nothing moved out. lens-corrections stays in Later, now covering
distortion, lens vignetting and lens profiles only, which are lower
priority because the raw decoder usually applies them. The new row is an
Idea and needs intake first: which corrections "and others" covers,
automatic or manual, which file formats, and presets and paste. The
questions are with the owner. Feasibility: the stitchable-kernels spike
(`docs/PROFILING.md` "Stitchable kernels"; branch
`feature/stitchable-kernels-spike`, not merged) shows that custom
per-pixel and warp kernels can run without a Metal build step, at the
cost of a stock filter. Until now, the lack of such kernels was why lens
corrections were held back.

2026-11-07: specified chromatic-aberration as a Draft
([`features/chromatic-aberration/prd.md`](features/chromatic-aberration/prd.md)).
The owner answered two intake questions. For fringe halos: "a color
picker that will turn the fringe gray. And a slider to widen or narrow
the color range". For test photos: none on hand, so QA uses synthetic
scenes, and a real-photo check (M1) waits without blocking. The other
answers are proposed defaults in the PRD's Assumptions, not confirmed.
These include whether lateral color-edge correction is still in scope
(Q1), plus one or more picks, near edges only or everywhere, and an
amount control (OQ1 to OQ3). The row moves to Specified, with the PRD
still Draft until the owner confirms. The same day, the owner answered
"Defaults are good", accepting every proposed default: lateral
correction in scope, a second pick, near edges only, no amount control,
and A1 to A7. The PRD is approved, and those answers are recorded as its
Owner rulings 3–13.

2026-11-07: apple-ui-designer wrote
[`features/chromatic-aberration/design.md`](features/chromatic-aberration/design.md).
I ruled its two requirements issues (PRD Revisions). RI-1: a paste,
preset or batch that carries automatic lateral correction leaves
offline or unreadable photos unchanged, with the existing Activity
warning, as batch automatic exposure does. RI-2: fine-tuning makes the
correction hand-set, and paste copies it as it is. Both match what the
design applied, so the row moves to Designed. The designer's two groups
satisfy R12. One owner question from the design is open: a way to fill a
fringe slot without pointing at the photo. Proposed: not in this feature,
and a Later Idea row `fringe-color-presets`, not added until the owner
answers.

2026-11-07: the owner answered that question: "It should go into this
feature now." Filling a fringe slot from a short list of common fringe
colors (at least purple and green), usable by keyboard and VoiceOver, is
now PRD R1a–R1c. A listed color behaves exactly like a picked one. The
`fringe-color-presets` row is not added. The PRD stays approved. The
design needs revising for the list, so the row goes back from Designed
to Specified until design.md is updated.

2026-11-08: chromatic-aberration was built (R1–R18, PR #48 open, CI green,
reviews not started). The owner tried it on a raw ("it works well") and added
a pixel magnifier tied to the pointer while picking a color (PRD ruling 16,
R19–R36). Six owner questions are open (OQ6–OQ11), each with a default. The
row is In progress: it stays in Now. Whether Pick Colors adopts the
magnifier is OQ6; a row for it is added only once that is answered.

2026-11-08: the owner accepted all six defaults ("Defaults are fine."), and
R19–R36 are Approved (PRD rulings 17–22). The magnifier serves the fringe
eyedropper only for now, so Pick Colors' adoption is the new Later row
pick-colors-magnifier. The row stays In progress, next with the designer.

2026-11-08: Ship pass for chromatic-aberration (PR #48). Moved from Now to
Shipped. Code review, design review and QA have no open findings against the
feature, and the owner confirmed every person check in qa.md, so no checks
are pending. QA's three low follow-ups were not fixed; the owner was told and
chose to ship. Q1 joined qa-test-gaps, Q3 joined debug-script-undo-groups, and
Q2 is the new row debug-resignkeyboard-inactive. pick-colors-magnifier now
says what shipped. Now has two items; I did not move anything in.

2026-11-09: specified viewport-render-1to1. The owner accepted all seven
intake defaults ("Defaults are fine"); the rulings are in
[`features/viewport-render-1to1/prd.md`](features/viewport-render-1to1/prd.md).
The owner then confirmed its assumptions A1–A9 the same day ("Yes, as
written"), so the PRD is approved. The row moved from Idea to Specified, and its
problem text now also names the 1280 px decode (4.7×) used while RAW white
balance, profile or noise reduction move. Design is next. Now has two items;
I did not move anything in.

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

Set by the owner 2026-11-06: library-launch-guard, viewport-render-1to1 and
edit-history. This superseded the owner's earlier rule (2026-11-06) that
the third slot stays empty until the manual checks are done.
publishing-engine and ui-redesign-onscreen-check moved to Later.
library-launch-guard shipped 2026-11-07 (PR #47), and that freed a slot.
The owner filled it the same day with chromatic-aberration, which is the
next item to start ("make it the next item"). It shipped 2026-11-08 (PR
#48), which frees that slot; the owner has not filled it.

| Slug | Problem | Status | Folder | Source |
|------|---------|--------|--------|--------|
| viewport-render-1to1 | At 100% zoom (and other zooms past fit), a control that is moving shows a stretched live frame until the change is saved, so fine detail can't be judged while editing: the 2560 px frame for most controls (2.3× for a 6000 px photo), and a 1280 px decode (4.7×) while RAW white balance, profile or noise reduction move | Specified | [`features/viewport-render-1to1/`](features/viewport-render-1to1/) | `PHASE6_PLAN.md` "The loupe at 100 %" and "Roadmap" |
| edit-history | No way to see or jump back to an earlier state of a photo's edits | Idea | none yet | Issue #26; `ui-redesign/design.md` RI-6 |

How each starts:

- **viewport-render-1to1** has a PRD (not a bug fix: today's behavior is as
  designed and documented in `PHASE6_PLAN.md`). The owner answered intake on
  2026-11-09 ("Defaults are fine"), which settled which zooms, what a pan
  during a drag may show and how fast is fast enough. The owner also
  confirmed its assumptions A1–A9 ("Yes, as written"), so the PRD is
  approved. Design is next; no new UI is expected, so that step should be
  brief.
- **edit-history** needs intake, then a PRD and design. Placement and keys
  stay out of the PRD (issue #26's ⌘Y redo and left-sidebar placement are
  proposals that conflict with the shipped ⇧⌘Z, the HIG's standard redo,
  and a sidebar that holds sources, UIR §3; RI-6). The intake questions are
  with the owner (2026-11-06 entry).

## Next

Order set by the owner 2026-11-06: the library and project operations
first, then virtual-copies, then side-by-side-comparison; the rest keeps
the order it had. The small fixes and tooling rows can each go as a bug fix
(`docs/WORKFLOW.md` "Bug fixes": no PRD or design, but a folder with
`status.md`'s Bug section, code review and QA), so their place in the queue
doesn't hold them back.

| Slug | Problem | Status | Why this order | Source |
|------|---------|--------|----------------|--------|
| remove-from-library | A wrong or unwanted import can never be taken out of the library; nothing removes photos or projects from the catalog (files are never touched) | Idea | Owner, 2026-11-06: top of Next, first of the library and project operations. Every library collects mistakes, and the catalog already has `deleteProject` (cascade, tested), so effort is moderate. Intake: what happens to edits, albums, pairs, sidecar files and undo; whether offline photos can be removed (the "never delete rows because a volume is missing" rule covers automatic removal, not a person's choice) | `ui-redesign/design.md` RI-2 |
| rename-project | Projects keep the folder or template name they were imported with | Idea | Owner, 2026-11-06: second. Small: `Catalog.renameProject` exists with no UI. Could ship with remove-from-library | `ui-redesign/design.md` RI-2 |
| show-in-finder | No way to reveal a photo's original or a project's folder in the Finder | Idea | Owner, 2026-11-06: third. Small and frequent for people who keep their own folders (the vision). Intake: offline originals, which file of a RAW+JPEG pair, projects with no single folder (`project.sourcePath` is not always set). Export already reveals its own output | `ui-redesign/design.md` RI-3 |
| virtual-copies | No second version of a photo with different edits | Idea | Owner, 2026-11-06: moved up from Later, right after the library and project operations. `Catalog.duplicateVersion` exists (copies a version's stack and culling) with no UI or command. Intake before a spec: whether a copy shares keywords, albums and culling with its original or keeps its own; RAW+JPEG pairs (edits are per file); what the sidecar and an export say for a copy; how a copy is removed (overlaps remove-from-library) | Issue #26 ("future feature"); `_inventory.md` "Duplicate a version" |
| side-by-side-comparison | No way to look at photos next to each other to compare them. The loupe shows one photo at a time, and Show Original (`\`) compares a photo only with its unedited self | Idea | Owner, 2026-11-06: right after virtual-copies. **Needs intake** before anything else; the owner gave only "side-by-side comparison". Intake: what is compared (different photos, versions of one photo, or both); how many at once; where (a view in the library window, review mode, or both); culling while comparing; zoom and pan linked or not; editing while comparing. If it compares versions of one photo, it depends on virtual-copies (and perhaps edit-history) | Owner, 2026-11-06. No open issue covers it; issue #26 mentions comparing "two of the same images side by side" with virtual copies as a future idea |
| reads-beside-write-chain | Five reads still take a photo's edits from the catalog without waiting for pending saves, so right after a change they can get the older values. Worst: paste onto a photo, then Copy Adjustments from it before the paste's write lands; the copy holds the values from before the paste, and the next paste silently gives other photos the wrong edits. The others: Save as Preset from the grid (the preset can get older values), batch Auto Exposure's measurement (measures from older values of other modules; its write drops nothing), the preset preview's base and the offline machine learning badge (display only) | Idea | Was second; now after the owner's five (2026-11-06). Same family as the two bugs PR #43 fixed, and the fix is known (each read moves onto `writes.read`, one line each per code review). Nothing is lost on the photo read and the wrong values are visible and undoable where they land. Can go as a bug fix. The window is one write's latency, longer behind a large batch (see editor-follow-edit-drop qa.md O1) | `editor-follow-edit-drop/code-review.md` Q1; `editor-follow-edit-drop/status.md` "Notes (not fixed here)": `copyAdjustments` (`AdjustmentActions.swift:18`), `focusedAdjustments` (`PresetActions.swift:52`), `PresetPreviewModel.baseAdjustments` (`PresetPreviewModel.swift:69`), `AdjustmentEditor.loadOfflineMachineLearning`, batch Auto Exposure (`BatchActions.swift:93`) |
| loupe-caption-narrow | At narrow window widths the loupe caption's items collide. The "Machine Learning Not Applied" badge draws over the rating and pick flag (overlaps at 760 pt, touches at 820 pt, clear at 900 pt), the sharpening map badge truncates to "Shar…", and the position text wraps | Idea | A failed design check (ml-denoise M9) on shipped work, seen at the window's minimum size. Needs a designer ruling first: what gives way when the caption is too narrow, one rule for every badge. Then a small fix; recheck with `ml-denoise/qa.md` S-12/S-13 | `ml-denoise/qa.md` Q1 (M9); sharpen-mask-preview QA run 2026-11-06, design note (reported to the main session, not written in its qa.md) |
| classical-noise-strength | The classical noise sliders (RAW decoder and Core Image filter) are mild at 100; the non-RAW filter runs after the vignette and ignores preview scale | Idea | Owner, 2026-11-05: split out of ml-denoise. The only noise fix for JPEG/HEIC. Changes existing edits' rendering (pipeline bump, goldens); intake must decide whether existing stacks keep their look | Issue #35; `PHASE6_PLAN.md` finding 6; `ml-denoise/prd.md` Non-goals |
| local-sharpen-group-off | Turning the Sharpening group off makes local Sharpness use the default Radius 1, Detail 25 and Masking 0 instead of the user's values, so it starts sharpening noise (`Adjustments.effective` resets the group) | Idea | Next to sharpen-mask-preview because it concerns the same code and changes saved renders unexpectedly. Owner to decide the intent: should local Sharpness keep the user's Radius, Detail and Masking, or turn off with the group? Any fix is a rendering change that needs a `PreviewCacheKey.currentPipelineVersion` bump and golden updates | Designer RI-2 on sharpen-mask-preview; owner ruling 2026-11-05 ("Roadmap item to decide"). `AdjustmentRenderer.swift:193-194` |
| sharpen-masking-scale | Masking holds back much more noise at fit than in a full-size export: on a noisy flat area at Masking 30, about 50% of the sharpening at fit (scale 0.43) against about 93% at full size. So the loupe at fit understates the sharpened noise an export gets | Idea | Placed after local-sharpen-group-off: same sharpening code, and both are rendering changes, so one pipeline bump could cover both. Any fix is a rendering change that needs a `PreviewCacheKey.currentPipelineVersion` bump and golden updates. Not urgent, because once input pauses the sharpening map already shows the full-size result | Engineer's finding on sharpen-mask-preview (PRD Q5: M4 Pro debug build, synthetic noisy 6000 × 4000 DNG); owner ruling 2026-11-05 ("Add Idea row") |
| dehaze-above-white | Dehaze and local tone estimates jump on extended-range (above white) input | Idea | Named on the phase 6 roadmap; a rendering change with a pipeline bump | `PHASE6_PLAN.md` "Roadmap", finding 4 |
| slider-field-shift-step | ⇧↑ / ⇧↓ in an adjustment slider's value field likely don't step by 10 as the design asks. Plain ↑ / ↓ work (`SliderRow` handles only `moveUp:` / `moveDown:`) | Idea | Small fix, on the keyboard path (principle 5). It affects every slider, not one feature. Confirm by hand first, since a scripted key isn't a held Shift: sharpen P1 step 3 under ui-redesign-onscreen-check | `sharpen-mask-preview/qa.md` Q2; `sharpen-mask-preview/design.md` §8 |
| export-missing-file-reason | An export whose original is missing from a connected volume says "the volume … is not connected". Since E14 that Activity warning is the only report the person gets | Idea | Small fix, made more visible by E14. Product intent (mine; owner may overrule): the reason tells a disconnected volume apart from a missing file, because the person fixes them differently. The wording belongs to the designer. Intake: whether the grid and loupe's Offline state should draw the same line (not checked) | `ui-redesign/qa.md` Q3; `ui-redesign/design.md` E14 |
| appkitbutton-enablement | Some inspector buttons look enabled when they should be dimmed (the mask eye button and other Adjust tab buttons are likely affected): `AppKitButton(isEnabled: false)` doesn't reliably dim | Idea | A defect, small, and against principle 4; it may go as a bug fix (workflow: bug fixes skip steps 1 and 2). Placed with the small fixes only because a workaround covers the buttons the reconcile changes touched | `ui-redesign/status.md` "Found, not fixed" |
| ci-test-crash | The test process sometimes crashes on CI (signal 11), so that run reports nothing about the tests that had not finished. Per the comment PR #42 added to the workflow, it has happened on `develop` since PR #39 (ml-denoise) and never reproduced locally. PR #40's CI passed on both runners, so it is intermittent | Idea | Tooling first, but it moves up if the backtraces point into app code: the crash started with ml-denoise, so it could be a real crash in shipped code rather than in a test. For the engineer, as a bug fix: the next crashing run now leaves a backtrace of every thread and the system crash reports as artifacts (PR #42); read them, then fix or report. Owner to confirm it still happens | `.github/workflows/build.yml` Test step comment (PR #42, `bug/ci-crash-capture`, merge 14dc0c1); no other record in `docs/` |
| debug-script-undo-groups | Debug-script commands that change nothing (`ml wait`, `ml ready`, `ml override`, a `key` with no effect, `adjust crop show`, `adjust crop begin`) open undo groups and leave empty undo steps, so scripted undo checks misread. `ml override` also reloads before the last save lands, and a frame still in flight can override the new state. The opposite case: a posted click that completes a fringe pick saves in a Task after the command returns, so nothing groups its undo step and `registerUndo` raises (`DebugScript.swift:118`; it blocks any posted-event check of a completed pick) | Idea | Tooling only; people using the app don't see it. Ahead of qa-test-gaps because the loupe-caption-narrow recheck uses `ml override` (the workaround until then: `wait` before an override, `ml override clear` between two). For the engineer, as a bug fix | `ml-denoise/qa.md` Q2, Q3; `sharpen-mask-preview/qa.md` Q4; `ui-redesign/qa.md` Q2; `chromatic-aberration/qa.md` Q3 |
| debug-resignkeyboard-inactive | The debug command `magnifier resignkeyboard` can silently do nothing in a process that isn't active: it uses `NSApp.mainWindow`, which is nil there, so a following Esc check proves nothing (`DebugLensCommands.swift:74`) | Idea | Tooling only; correct with the app active. For the engineer, as a bug fix | `chromatic-aberration/qa.md` Q2 |
| qa-test-gaps | Three tests don't check what they are named for. ml-denoise AC10's "Reset All clears it" asserts the Details reset. Nothing observable shows that the sharpening map after a pause is the refined frame (AC7, R6). `FolderImportQueueTests` passes without E13's change. Also: the app-side half of the stale-preview fix (a hash shown only after its write, batch undo, the grid cell's silence on a refused render) has no automated test, because there is no test target for the app module. Likewise, nothing automated fails if the loupe's load or the library reload stops reading through the write chain (`writes.read`); QA's scripts S2, S3b, S3c, S4 and S5b, which reproduce on `develop`, are the only regression check. Nothing automated fails if the app's launcher stops asking the launch guard before it opens the library, or if `LibraryModel.open`'s backstop goes; the rule is unit-tested in PhotoCore, the wiring only by QA's scripted launches. `LocalizationTests` reads `String(localized: "` on one line only, so a `String(` call with `localized:` on the next line is never checked against the catalog (8 calls in 3 files, older than library-launch-guard). From chromatic-aberration: no automated test for four review fixes, C2's replacement race, C3, C7/C13 and C9/F1, which were checked by reading, by script or by a person, because no test target reaches the app module | Idea | For the engineer, as a bug fix. All these behaviors passed by script, so no defect is known; the risk is a regression nobody notices. The first three fixes are an assertion, a rename, a testable rule, or more detail in `print sharpenmap`. editor-follow-edit-drop (PR #43) moved the ordering rule into PhotoCore (`WriteChain`, tested there), so what stays untested is that the app uses it; the launch guard is the same case. The scanner gap is a matter of reading the call across lines. Whether to add an app test target is the engineer's call | `ml-denoise/qa.md` Q4; `sharpen-mask-preview/qa.md` Q3; `ui-redesign/qa.md` Q1; `stale-preview-after-save/qa.md` O2; `editor-follow-edit-drop/qa.md` O2; `library-launch-guard/qa.md` O1, O2 (and `code-review.md` second pass); `chromatic-aberration/qa.md` Q1 |

## Later

Roughly ordered by dependency, then by how often a photographer would hit
the gap. The first two rows came down from Now (owner, 2026-11-06):
ui-redesign-onscreen-check first because it holds open checks on work that
has already shipped, then publishing-engine, which publishing-plugins
depends on. Ordering below them is judgment.

| Slug | Problem | Status | Notes | Source |
|------|---------|--------|-------|--------|
| ui-redesign-onscreen-check | Shipped work that only a person can check. (a) The older redesign: glass panes, VoiceOver speech, macOS 15 path, 13" Export sheet. (b) The film strip: steps, height cap, show/hide, resize drag, crop session, Increase Contrast. (c) ui-redesign-reconcile: **done** (owner, 2026-11-06: "I've checked all the P1-P10 of the ui-redesign"; all passed, no findings): P1–P10 in [`ui-redesign/qa.md`](features/ui-redesign/qa.md) "For a person", incl. AC2. (d) sharpen-mask-preview: P1–P8 in [`sharpen-mask-preview/qa.md`](features/sharpen-mask-preview/qa.md) "For a person", incl. the ⇧↑ check for its Q2. (e) ml-denoise: P1–P9 in [`ml-denoise/qa.md`](features/ml-denoise/qa.md) "For a person", incl. AC13 (P9, your raws: ML vs classical at 100). (f) stale-preview-after-save, optional: P2 in [`stale-preview-after-save/qa.md`](features/stale-preview-after-save/qa.md) "For a person" (drag Exposure three times on a real raw, back to the grid, relaunch; the thumbnail shows the last value and never goes blank). (g) editor-follow-edit-drop, optional: P1 in [`editor-follow-edit-drop/qa.md`](features/editor-follow-edit-drop/qa.md) "For a person" (a scratch library with a few real raws and a few thousand photos: drag Exposure, → then ← at once, drag Contrast, three times; paste onto a few thousand photos and open one at once; relaunch. Every drag survives, the Adjust tab shows the pasted values once it stops loading, and how long it shows loading is acceptable to you, qa.md O1). (h) library-launch-guard: **done** (owner, 2026-11-07: "P1-P4 pass visual testing"; no findings; recorded in qa.md's Follow-up): P1–P3 and the optional P4 in [`library-launch-guard/qa.md`](features/library-launch-guard/qa.md) "For a person" (a `.debugtest` copy opened from the Finder or `open` shows the alert in front and quits on Return or a click; VoiceOver reads it; `swift run PhotoApp` shows it and exits 64; optionally, the release bundle with `--debug-script` and no `--library-root` exits 64 with no alert). Items that need another Mac (macOS 15, which the owner doesn't have: (a)'s macOS 15 path; macOS 15 or 26: ml P6, sharpen P8; a Mac without the RAW 9 model: ml P8, the RI-E6 (d) check) stay open here until one is available | Idea | Owner, 2026-11-06: moved from Now to Later, holding (a), (b), (d), (e), (f) and (g); nothing dropped. (h) added at library-launch-guard's Ship, 2026-11-07, and done the same day. The checks stay pending on each feature's Shipped row until done. Every person-only check is gathered here (owner, 2026-11-06, earlier ruling 3) | `UI_REDESIGN.md` status, "Not yet checked on screen"; §11 "Implementation status", last item; the five qa.md files above (2026-11-06) |
| publishing-engine | Getting edited photos into Apple Photos or Immich means exporting to a folder and uploading by hand | Idea | Owner, 2026-11-06: moved from Now to Later | Issue #28; `PHASE4_PLAN.md` out of scope ("export to services") |
| publishing-plugins | Destinations beyond the built-ins need app changes | Idea | Depends on publishing-engine settling `PublishTarget` | Issue #29 |
| pick-colors-magnifier | The Color Range mask's Pick Colors doesn't use the Pixel Magnifier, so the person can't see which pixel a click takes or read its values | Idea | The Pixel Magnifier shipped in chromatic-aberration (PR #48) and is built for other tools to use (`PixelMagnifierTool`; AC29 proves it with a test tool). So far only the fringe eyedropper uses it. Pick Colors needs its own answers to R22 and R25: it samples the on-screen frame, after edits, at that frame's resolution, has no snap and stays on for several clicks | `chromatic-aberration/prd.md` OQ6, owner, 2026-11-08 |
| dng-export | No DNG output | Idea | ImageIO cannot write DNG; needs a writer of our own | CLAUDE.md Not yet; `PHASE4_PLAN.md` Formats; issue #6 (asked, closed without it) |
| healing | No spot removal or healing | Idea | Phase 5's test loop was built with healing and lens corrections in mind | CLAUDE.md Not yet; `PHASE5_PLAN.md` intro; `PHASE6_PLAN.md` out of scope |
| lens-corrections | No correction of geometric distortion or lens vignetting, and no lens profiles. Chromatic aberration and fringing moved to chromatic-aberration (Now, owner, 2026-11-07) | Idea | Lower priority, owner, 2026-11-07: the raw decoder usually applies distortion and vignetting already. Interacts with the decoder's own lens correction on camera-cropped raws | CLAUDE.md Not yet; `PHASE6_PLAN.md` finding 1 |
| ai-masks | No subject, sky, object or people masks | Idea | | CLAUDE.md Not yet; `PHASE6_PLAN.md` out of scope |
| dcp-profiles | Adobe `.dcp` camera profiles not supported | Idea | | CLAUDE.md Not yet; `PHASE3_PLAN.md` out of scope |
| stacks | No hand-made or burst stacks | Idea | `stack` / `stackMember` tables and `Catalog.createStack` exist, no UI | CLAUDE.md Not yet; `PHASE2_PLAN.md` out of scope |
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
| sharpen-mask-preview | 2026-11-05 | Merged via PR #37 (merge commit 64334b7). Shows where Sharpening's Masking lets sharpening through: a live estimate while the value changes, recomputed at full resolution when input pauses. **Shipped, checks pending** (owner's choice, 2026-11-05). QA on 2026-11-06 passed everything a test or script reaches (M7, M8 closed); what is left for a person is P1–P8 in [`sharpen-mask-preview/qa.md`](features/sharpen-mask-preview/qa.md), done under ui-redesign-onscreen-check. Follow-ups: local-sharpen-group-off, sharpen-masking-scale, and from QA slider-field-shift-step, debug-script-undo-groups, qa-test-gaps (Next). Its QA also found stale-preview-after-save, which this feature didn't cause (fixed in PR #40, Shipped 2026-11-06). [`features/sharpen-mask-preview/`](features/sharpen-mask-preview/) |
| ui-redesign-reconcile | 2026-11-05 | **Shipped.** Merged via PR #34 (merge commit 1e89a7b). All 28 changes E1–E28 from `ui-redesign/design.md` §6 are Done: empty states per source, Export enabled only for photos, export results in Activity only, one ⌘. Stop and one ⇧⌘A Deselect All, Play / Pause and a video context menu, new Adjust menu items, one set of field labels, preset delete confirmations, the dead Help item removed. QA on 2026-11-06 found nothing failing in E1–E28 and closed most of status.md's "Pending manual checks" by script. What was left for a person, AC2 included, was P1–P10 in [`ui-redesign/qa.md`](features/ui-redesign/qa.md), under ui-redesign-onscreen-check (c). The owner checked all of them on 2026-11-06: all passed, no findings (owner's word; qa.md's Follow-up does not record it yet). "Checks pending" cleared the same day. No separate review.md. Follow-ups: appkitbutton-enablement, and from QA export-missing-file-reason, debug-script-undo-groups, qa-test-gaps, library-launch-guard (Shipped 2026-11-07, PR #47). [`features/ui-redesign/`](features/ui-redesign/) |
| ml-denoise | 2026-11-05 | **Shipped, checks pending.** Merged via PR #39 (merge commit 334312c). Opt-in machine learning noise reduction for raw files through the macOS 27 RAW decoder's version 9; off unless chosen, says why when it can't apply. QA on 2026-11-06 passed every criterion this Mac can run, but the designer's M9 failed: the caption badge overlaps the rating and flag at narrow widths (loupe-caption-narrow, Next). What is left for a person is P1–P9 in [`ml-denoise/qa.md`](features/ml-denoise/qa.md), done under ui-redesign-onscreen-check. That includes AC13 (P9, the owner's check on 2–3 of their own high-ISO raws that it beats classical at 100) and the RI-E6 (d) check (P8, a Mac without the model), which the owner accepted shipping without (2026-11-06). Follow-ups: classical-noise-strength, and from QA loupe-caption-narrow, debug-script-undo-groups, qa-test-gaps (Next); ml-denoise-missing-model (Later). [`features/ml-denoise/`](features/ml-denoise/) |
| stale-preview-after-save | 2026-11-06 | **Shipped, checks pending.** Bug fix, no PRD or design (folder has status.md, code-review.md, qa.md). Merged via PR #40 (merge commit 986131a); CI passed on macOS 26 and 15. Saving an edit no longer caches the old look under the new edit's hash: the preview service refuses to keep a rendition under any hash but that of the stack it rendered, and the editor and batch undo show a new hash only after its write lands. Pipeline version 6 to 7 drops every rendition cached since the race began (2026-10-26); no rendering changed and no golden moved. **Owner accepted the cost** (2026-11-06, status.md; qa.md P1, code-review.md Q1): every thumbnail and preview regenerates once, and photos on volumes offline at the first launch show empty cells and a blank loupe until their volume is reconnected. Code review: approve with nits (C1 fixed; its confirmation is not yet written in code-review.md's Follow-up). QA: passes; reproduced on `develop` 6 of 6, not on the branch. Open for a person: P2 (optional, real slider drags on real raws) in [`stale-preview-after-save/qa.md`](features/stale-preview-after-save/qa.md), done under ui-redesign-onscreen-check (f). Follow-ups: editor-follow-edit-drop and reload-items-stale-hash (both Shipped 2026-11-06, PR #43), and qa.md O2 under qa-test-gaps (Next). Found by `sharpen-mask-preview/qa.md` Q1. [`features/stale-preview-after-save/`](features/stale-preview-after-save/) |
| editor-follow-edit-drop | 2026-11-06 | **Shipped, checks pending.** Bug fix, no PRD or design (folder has status.md, code-review.md, qa.md), one change with reload-items-stale-hash. Merged via PR #43 (`bug/editor-follow-edit-drop`, merge commit 520d479). Leaving a photo in the loupe and coming back before the last save landed, then changing something, wrote the older values back and silently dropped the earlier edit. The loupe now loads a photo's edits only after every pending save has landed, and reads again if another write was queued meanwhile; that also closes an undo or paste being lost while the photo loads. The ordering rule is in PhotoCore (`WriteChain`) with deterministic tests that fail without it; no rendering changed. Code review: ready to merge, no findings. QA: all 13 items pass; each route reproduces on `develop` and none on the branch. **Expected cost** (qa.md O1): behind a batch of about 30,000 photos the Adjust tab shows loading for about 3 s; batches of normal size take milliseconds. Open for a person: P1 (optional, real keys on real raws, and whether that loading time is acceptable) in [`editor-follow-edit-drop/qa.md`](features/editor-follow-edit-drop/qa.md), done under ui-redesign-onscreen-check (g). Follow-ups: reads-beside-write-chain (Next, code-review.md Q1), and qa.md O2 under qa-test-gaps (Next). Found by `stale-preview-after-save/code-review.md` Q2. [`features/editor-follow-edit-drop/`](features/editor-follow-edit-drop/) |
| reload-items-stale-hash | 2026-11-06 | **Shipped.** Fixed in the same change as editor-follow-edit-drop (PR #43, merge commit 520d479; records in [`features/editor-follow-edit-drop/`](features/editor-follow-edit-drop/)). A library reload that read rows before an edit's or culling key's write could apply after it and put the old values back. On screen, a grid cell showed the previous look or stayed blank. **Not display only, as the Next row had said** (corrected 2026-11-06, qa.md Q1): the same race put old ratings, flags and labels back, and the next rating, flag or label key then saved the stale values of the other two (on `develop`, a flag ended stored as rejected after `U` cleared it). Now a reload applies its rows only if no write was queued while it read; otherwise it reads again. QA: reproduced on `develop` (S3b 5 of 14 rounds, S3c 6 of 6, S4 7 of 9), not on the branch. No person check open for it. A reload waits behind a long write the same way as the loupe (qa.md O1). App-side regression gap: qa.md O2 under qa-test-gaps. Found by `stale-preview-after-save/code-review.md` "Checked and fine" |
| library-launch-guard | 2026-11-07 | **Shipped.** Bug fix, no PRD or design (folder has status.md, code-review.md, review.md, qa.md). PR #47 (`bug/library-launch-guard`). A test copy of the app could open the owner's real library (it happened once during QA on 2026-11-06, nothing changed; `ui-redesign/qa.md` "Incident in this QA run"). Now the app refuses a test launch that has no `--library-root`, before it opens or creates anything in the standard data and cache folders. A test launch is a bundle whose identifier isn't the release one (no bundle, as with `swift run`, included) or a launch with `--debug-script` or `--benchmark-scroll` (owner rulings 1–4, 2026-11-07, status.md). Refused: the reason on standard error, then an alert ("Can't Open the Library") and quit with status 64; a scripted launch exits 64 at once with no alert. The standalone importer has no library and is not guarded; `photocli` and `photobench` are unchanged (out of the rulings' scope). Code review: two passes, ready to merge, C1 and C2 fixed and confirmed. Design review: F1 (alert message and comments) fixed and confirmed; I1 (Escape) not taken. QA: passes, no findings; reproduced on `develop` (D5), not on the branch, the owner's library untouched. The person checks P1–P3 and the optional P4 in [`library-launch-guard/qa.md`](features/library-launch-guard/qa.md) "For a person" (ui-redesign-onscreen-check (h)) all passed (owner, 2026-11-07, no findings; qa.md Follow-up: 16 of 16 pass); "checks pending" cleared the same day. Follow-ups: qa.md O1 and O2 under qa-test-gaps (Next). [`features/library-launch-guard/`](features/library-launch-guard/) |
| chromatic-aberration | 2026-11-08 | **Shipped.** PR #48; folder [`features/chromatic-aberration/`](features/chromatic-aberration/). The Lens heading in the Adjust tab: Color Fringes grays up to two fringe colors near high-contrast edges, picked from the photo or chosen from a short list (Purple, Green), with a Fringe Map; Color Alignment measures and corrects red/cyan and blue/yellow edges, stored with the edit and measured for each photo that receives it. The Pixel Magnifier shows the photo's own pixels while picking, the pixel a click takes and its values, at a level that persists; it is built for other tools to use. Off by default, no existing render changed. The owner confirmed every person check in [`qa.md`](features/chromatic-aberration/qa.md) (P1–P13). Known limitation: if the Lens kernels can't compile, the corrections are skipped with no message (RI-CR1, PRD). Follow-ups, not fixed, the owner chose to ship: QA Q1 (qa-test-gaps), Q3 (debug-script-undo-groups), Q2 (debug-resignkeyboard-inactive); pick-colors-magnifier |

## Dropped

| Slug | Date | Reason |
|------|------|--------|
| film-strip-size-slider | 2026-11-04 | Owner revision: the slider pushed the centered thumbnail off the photo's center; replaced by a drag handle with fixed steps. Issue #25 still asks for a slider. `UI_REDESIGN.md` §11 decision 3 |
| write-metadata-to-originals | 2026-11-04 | Owner: conflicts with the referenced-masters principle (originals are never written). Sidecars carry the library's metadata. Was on CLAUDE.md "Not yet" and README "Not there yet" |
| film-strip-left-anchor | 2026-11-04 | Owner decision: the focused photo is centered in the strip, not at the left edge as issue #25 asks. `UI_REDESIGN.md` §11 decision 2 |
