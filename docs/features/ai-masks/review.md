# AI masks: design review

Owner: apple-ui-designer. Date: 2026-11-20. Issue: #88 (slug `ai-masks`).
Branch `feature/ai-masks` (worktree `/Users/randy/Projects/Gus-ai-masks`).
Against: [`design.md`](design.md) (with the rulings DR-1 to DR-3 this review
added to its §19.1), the acceptance criteria as `status.md` and design §18
record them, `docs/USER_GUIDE.md`, and the HIG.

**How this was done.** From code, `status.md` and the debug-script outputs it
records. I did not run the app (no shell, and the inspector is glass, which
`snapshot` cannot draw). I did not re-read the issue body: the criteria below
are AC2, AC3, AC4, AC6, AC13 and AC14 as `status.md` words them. Looks,
tooltips, wrapping at 256 pt and keyboard focus are manual checks (M1 to M7).
Per the standing ruling, VoiceOver, macOS 15 and macOS 26 are not asked of the
owner; where I judged accessibility it is from code only.

## Verdict

**Pass with fixes.** The structure is as designed: one pull-down beside the five
shapes in both rows, Background as its own kind, the pending line with Cancel,
captions in the shape sliders' slot, Update as a button only where it is the
remedy plus menu paths, one undo step per landing. The engineer's one
deviation (the pull-down dims as a whole) is better than what I specified.
Three things must change before QA: the pull-down looks enabled while
cropping and then does nothing (F1), the caption after a failed Update says
"It selects nothing" when the earlier result still applies, a mistake in my own
design (F2, DR-1), and a failed request in a mixed Update is attributed to the
wrong request (F3). The rest are small.

## Requirements by design section

| Requirement | Result | Evidence and notes |
|---|---|---|
| A1, §2: one pull-down at the end of both rows, `wand.and.stars`, borderless, chevron, tooltip, VoiceOver label "Detect", Subject / People / Background | Pass | `DetectionButton` in `ShapeButtons` (`MasksSection.swift:82`, `:74`); `AppKitMenuButton(showsArrow:)`; items are plain text. Width 34 pt: arithmetic ~236 pt of 256 (M1 confirms) |
| A1: detection kinds not in `MaskShapeKind.allCases` | Pass | `MaskDetectionKind` is its own type (`LocalAdjustments.swift:299`, `MaskEditing.swift:43`) |
| A1: items dim with the limit's tooltip, and while pending or cropping | **Fail for cropping** (F1); pass for limit and pending | Dimmed as a whole, reason in the tooltip (below). Cropping gives `dimmed == nil`, so the control is enabled and the action's `guard` drops the click |
| A2, §3: Background its own kind, Invert independent, off when added | Pass | Kind `background`, `isInverted` in the kind; row's Invert untouched. VoiceOver state of Invert: F5 |
| A3, §5: pending line (mini spinner, "Detecting…", Cancel) under the row that started it, or in the component's slot for Update; one undo step on landing | Pass | `DetectingLine`; `land`/`landUpdate`; debug script recorded one step, Cancel and leaving add nothing |
| A3: new mask selected on landing only if the selection is unchanged; default +0.3 / −0.5 EV; names "Subject" etc. | Pass | `selectionAtStart`; `values.exposure`; `Mask(name: kind.title)` |
| A4, §4: state captions | **Fail for one state** (F2); wording otherwise as designed | Table below |
| A5, §8: unusable component skipped | Pass (engineer's tests, goldens); not re-judged | `idleComponentsRenderAsWithout` |
| A6, §7: Update button only in Failed, Unavailable, Missing; Adjust ▸ Update Detection; mask ⋯ and context menu; enabled in every state; unchanged result writes nothing | Pass | `state.offersUpdate`; `LibraryCommands.swift:654`; `MaskRow` menu entries. Placement judgment: I2 |
| A7: no shortcuts, bare keys, toolbar item | Pass | None added |
| A8, §9: flash 1.5 s, hard cut, ends early on eye, slider drag, selecting another mask, leaving | Pass, two changes (F4, I1) | `flashOverlay`, `endOverlayFlash`, `showsMaskOverlay.didSet` |
| A9, §10: dimmed while cropping, comparing, pending; cancelled on leaving | **Fail for cropping** (F1); rest pass | Comparing tears the loupe down (status); `finishSession` cancels |
| A10, §6: Activity for failed and unavailable only | Pass, one attribution bug (F3) | `reportFailures` |
| §11: three items under a divider in New Mask; Update Detection after Show / Hide Mask Overlay; no shortcuts | Pass | `LibraryCommands.swift:636-657`. The New Mask submenu title stays enabled while pending (D-Q5); only the three items dim |
| §12: AppKit wrappers in the inspector; announcements; focus not moved | Pass, F5, F6, M5 | |
| §14: localization keys, plurals | Pass | Plural variations present in the catalog for the four count captions |
| §16: captions at the title inset, same slot, no dividers | Pass | `.padding(.leading, 22)` is the design's 18 + 4; text uses the `.caption` role like the neighbouring captions (design said 11 pt; the role matters, not my number) |
| AC14, §17: user guide | Pass with edits | G1 to G4 |
| AC2, AC4, AC6, AC13 (the parts a designer judges) | Pass | Recorded in `status.md`; Missing shows Update, Update restores Found |
| AC3, the window staying responsive | Needs manual check | M6 |

### Captions against §4

| State | Built text | Verdict |
|---|---|---|
| Found, Subject / People / Background, four-person | As designed | Pass |
| Empty (three kinds) | As designed, no triangle, no Update, no Activity entry | Pass |
| Failed | "Detection failed on this photo. It selects nothing. Choose Update to try again." | Pass for a component with no result; **wrong after a failed Update of a Found component** (F2) |
| Unavailable | "Detection isn't available on this Mac. It selects nothing." with Update | Pass. It does not say "Choose Update", and need not: the button is beside it |
| Missing | As designed | Pass |
| Loading (row being read) | Nothing shown | Acceptable: for a moment after opening a photo the row has no caption, then it appears and the list moves down a few lines. Not worth a placeholder |
| Detecting | Mini spinner, "Detecting…", Cancel | Pass |

## The five judgments you asked for

**1. The pull-down dims as a whole, the reason as its tooltip. Accepted, with
F1.** My §2 had the items dimming one by one with the same tooltips. That
cannot be built (`AppKitMenuButton` items carry none), and it was not the better
design: all three items always share one reason, and a pull-down that opens
onto three dimmed items is worse than one that is dimmed and says why on
hover. It matches the five shape buttons, which dim with the limit as their
tooltip. The HIG's rule is to dim a control that cannot act and let the
person find out why; this does. Two costs, both fine: while dimmed the
tooltip stops saying what the button does (as for the shape buttons), and
the reason is also the VoiceOver help (`AppKitMenuButton` sets it from `help`),
so it is not hover-only. Condition: the cropping gap. Recorded as DR-2.

**2. Caption wording and states.** The wording is right and every state has the
plain-words, "it selects nothing" form the PRD's R6 asks for. One state is
wrong (F2). At 256 pt the Failed and Missing captions will take three to four
lines beside the Update button (about 150 pt of text width); that is heavy but
legible, and the Update button stays top-aligned. If M2 shows it is ugly, put
the button on its own line under the text at narrow widths rather than
shortening the words. "Choose Update" is correct for both the button and the
menu item.

**3. Update command placement. As specified, but I would now move it (I2,
optional).** It is where I put it: Adjust ▸ after Show / Hide Mask Overlay, and
in the ⋯ and context menus between Move and Delete. In the menu, though, it
now sits between the overlay item and the two map items, splitting three
"look at the mask" toggles with a command that changes data. It belongs beside
its sibling New Mask ▸. Moving it above Show / Hide Mask Overlay is a
one-line change and would need §7 and §11 amended; I leave it to the owner's
eye because nothing breaks either way.

**4. The overlay flash. Right idea, built as designed, two corrections.**
It starts only when a result lands, ends on the eye, a slider drag, selecting
another mask, or leaving, is a hard cut and is not shown when a mask is merely
opened. (F4) It also runs when the result is empty, failed or unavailable,
where the overlay shows nothing: a blank red state change, a pointless
re-render and a moment of "did it work?". Only a Found result flashes (DR-3).
(I1) The eye: touching it during the flash toggles the overlay off, because
`showsMaskOverlay` is the eye's own state and reads "on". Someone who reaches
for the eye while a red shape is on screen most likely wants to keep looking.
I recommend that touching the eye (or the menu item) during a flash ends the
flash and keeps the overlay on. This is judgment; decide it at M4.

**5. Inspector width. Not yet shown at 256 pt.** `print inspectorwidth` said
`fits` with 283 pt visible and controls reaching 275: that is the default width,
and 275 is the existing 276 pt Tone Curve, Color Grading and Spots mode
controls `CLAUDE.md` already records as overflowing the narrowest inspector, so
the reading says nothing about this row. By arithmetic the new row is about
60 (prompt) + 5 x 26 + 34 + 6 x 2 = 236 pt, inside 256. M1 checks it.

**Accessibility announcements.** Landing, update, cancel and failure each
announce at medium priority, focus is never moved, the spinner has the label
"Detecting", the triangle is hidden because the caption says the same, and the
pull-down's name is "Detect" with the reason as help. Gaps: a failed landing
speaks twice (F6) and the Invert button has no on/off value (F5). Keyboard
focus on the pull-down while it dims is M5.

**User guide.** The Masks and Masks-from-the-photo text is the wording I
proposed, accurate to the build, and `userGuideLimits` pins the two limits. Edits:

- G1. "The wand button at the end of the shape buttons (**Detect**; …)": "Detect"
  is the VoiceOver name; nobody sees it. Drop the bold name, or say "its
  tooltip reads 'New mask from the photo…'". The terms list in design §17 loses
  "Detect".
- G2. The four-person caption is quoted as "4 people found, the most that can
  be selected." The caption continues "Others in the photo may be left out."
  Quote it whole.
- G3. Say what Invert does on Background: it selects the subject (design §3).
  Two inversions cancelling is correct and a person will try it.
- G4. After F2, add that an Update that fails keeps the earlier result and says
  so. One sentence, and "the row says why and shows **Update**" stays true.

Terms checked against the UI: Subject, People, Background, Detecting…, Update,
Update Detection, Cancel, "1 subject found." all match. Optional: add that a
new mask is not selected if you chose another mask while it looked.

## Findings for the engineer

Most severe first.

- **F1 (must). The Detect pull-down is enabled while cropping and does
  nothing.** `MasksSection.swift:33` and `:295` pass `dimmed: canDetect…
  ? nil : limit ?? DetectionButton.dimmedHelp(editor)`; while cropping there is
  no limit and nothing pending, so `dimmedHelp` returns nil, the control is
  enabled, the person picks Subject and `addDetectionMask`'s `guard
  canDetectMask` drops it with no message. The Masks heading stays on screen
  during a crop session. The Update button has the same hole (its help falls
  back to the normal tooltip). Why it matters: a control that looks live and
  silently refuses breaks the HIG's feedback expectation and the "dim what
  can't act" rule the five shape buttons follow in the menu bar. Fix: give
  `dimmedHelp` a cropping case (DR-2: "Finish cropping to detect in the photo."
  for the pull-down, "Finish cropping to detect again." for Update), add both
  strings to the catalog, and add a debug-script check (`adjust crop`, then
  `buttons`: the Detect pull-down and any Update button are disabled).
- **F2 (must). A failed Update of a Found component reads "It selects
  nothing".** `detectionState` returns `.failed` for any key in `failedUpdates`,
  but the old result keeps applying (design §7, and the engineer built it that
  way). The caption then contradicts the picture. This is my error in §4 and §7.
  Fix per DR-1: when the underlying state is Found, show a new state with
  "Detection failed on this photo. The earlier result still applies. Choose
  Update to try again." (triangle, Update; new catalog key; the VoiceOver
  announcement after a failed Update uses it). Empty, Failed and Missing keep
  the present caption.
- **F3 (should). A mixed Update attributes a failure to the wrong request.** In
  `land`, `unavailableRequests.insert(pending.kind.request)` and
  `reportFailures` both use `pending.kind` (the first component's kind), but
  `results` is keyed by request. A mask with Subject and People whose People
  request fails says "Couldn't detect a subject" and can mark Subject
  unavailable. Iterate `(request, result)` and name the kind of the request
  that failed.
- **F4 (should). Flash only a Found result** (DR-3). `flashOverlay` is called
  for every landing. Skip it when the landed component's state is not Found.
- **F5 (should). Invert has no on/off for assistive technology.** Design §12
  asked the engineer to check that a Background row reads "Invert, off"; the
  button carries the state only in its symbol and tint, and nothing says it was
  checked. With Background and its built-in inversion, "Invert" without a state
  is a trap. Set `accessibilityValue` ("On" / "Off", existing keys if any) on
  `ComponentRow`'s Invert button for every component kind.
- **F6 (should). A failed landing speaks twice.** `reportFailures` announces
  the warning text, then `land` announces "Subject mask added. Detection failed
  …" at the same priority; the second can cut the first. One announcement per
  outcome: let the "added" or "updated" sentence carry the failure (it contains
  the caption) and post the Activity warning without `announcing:`.

Minor, no fix required: the overlay flash also lights the eye for 1.5 s with
Show Original on (nothing shows; harmless).

## Improvements (judgment)

- **I1.** Touching the eye during a flash keeps the overlay on (above).
- **I2.** Move Update Detection above Show / Hide Mask Overlay so the three
  "look at" toggles stay together (above). Amend design §7 and §11 if taken.
- **I3.** Update on a healthy component shows "Detecting…" for a fraction of a
  second and nothing else (design §7 chose this over a message). If M7 says it
  reads as no response, announce and show nothing more than VoiceOver already
  gets; do not add a message. For VoiceOver only, "Detection unchanged." before
  the caption would be clearer than the caption alone.

## What's working, do not change

- One pull-down, not three more icons; the row still fits; the same control and
  wording in both rows; the tooltip names the three kinds.
- The pending line replacing the caption in the same slot, with Cancel and a
  reason-giving tooltip, and the pull-down dimmed with "Wait for the current
  detection to finish." beside it.
- Captions that say "It selects nothing" and a triangle only where Update is the
  remedy; Empty with no triangle, no button, no Activity entry.
- The new mask selected only if the selection has not moved; default +0.3 and
  −0.5 EV; default names Subject, People, Background.
- Failed and unavailable in Activity with the system's own words; missing never.
- Using `AppKitMenuButton` and `AppKitButton` in the inspector, per the
  `ScrollView` rule.
- A user guide that states both limits verbatim and says detection stays on the
  Mac.

## Requirements issues

None. R4/AC3's wording (RI-1) and R9's `--shape` (RI-2) were taken as designed
and are in the PRD's Revisions.

## Manual checks for the owner

Built from the main session's scripted launch with `--library-root` on a scratch
library. The debug script can hold the app open on a state:
`adjust mask detector disc` (or `fail`, `empty`, `unavailable`, `hang`), then
`adjust mask detect subject`, then a long `wait`. These supersede and group
`status.md`'s M1 to M8. VoiceOver, macOS 15 and macOS 26 are not asked.

- **M1. The row at the narrowest inspector.** Drag the inspector to its minimum
  width. In both "New Mask:" and "Add to Mask:" the five shapes and the wand
  with its chevron fit with no clipping; hover shows the tooltip; the menu lists
  Subject, People, Background. (Status M3, first half; design A1.)
- **M2. Captions at 256 pt.** With `detector fail`, `unavailable` and `empty`, and
  `raster delete` for Missing: each caption wraps, the triangle and Update line
  up, nothing reaches the inspector's edge. Also the four-person caption on a
  crowd photo (status M6). Judge whether Update beside three or four lines of
  text looks right.
- **M3. Dimmed pull-down and its reason.** With `detector hang`: the pull-down
  is dimmed in both rows and hover shows "Wait for the current detection to
  finish."; Cancel adds nothing. With a crop session open (after F1): dimmed,
  "Finish cropping to detect in the photo." Confirm the tooltip shows on a
  dimmed borderless pull-down.
- **M4. The flash on a real portrait.** Does 1.5 s of red help you judge the
  edge or annoy? Click the eye while it flashes: does the overlay vanish (as
  built) or should it stay (I1)? Background on a portrait at −0.5 EV, and Invert
  on it (status M4, M5).
- **M5. Keyboard only (Full Keyboard Access).** Tab to the pull-down, open it
  with Space, choose Subject. The pull-down dims while detecting: where does
  focus go, can you Tab to Cancel and press it, and where is focus after the
  result lands and Cancel disappears? If focus is lost to the window, tell the
  engineer.
- **M6. Responsive while detecting.** On a large raw (the first detection after a
  launch is the slowest), scroll the inspector and drag a slider while the line
  says "Detecting…". Cancel; move to another photo mid-detection (status M2).
- **M7. Update on a healthy mask, from the menu.** Adjust ▸ Update Detection on
  a Found mask: does the brief "Detecting…" read as a response when nothing
  changes?
- **M8. The Adjust menu.** Adjust ▸ New Mask ▸ (the divider and three items),
  Adjust ▸ Update Detection (dimmed with no detection mask, with a Subject
  mask selected, enabled; dimmed while detecting). A scripted run could not
  activate the window, so the menu bar rows were never seen (status M1).
- Also still open from `status.md`: M7 export beside the loupe and M8 edge
  quality at 100% on the owner's raws. They are QA's and the owner's, not
  design checks.

## Summary for the issue

Design review, #88: **pass with fixes.** The build follows the design (pull-down
beside the shapes in both rows, Background its own kind, pending line with
Cancel, state captions, Update as a button where it is the remedy plus menu
paths). Accepted: the pull-down dims as a whole with the reason as its tooltip.
Must fix: F1 the pull-down and Update look enabled while cropping and then do
nothing; F2 the caption after a failed Update says "It selects nothing" while
the earlier result still applies (my design error, ruled in DR-1). Should fix:
F3 failure attributed to the wrong request in a mixed Update, F4 flash only a
Found result, F5 Invert has no on/off value, F6 a failed landing is announced
twice; four user guide edits. 256 pt fit not yet shown (M1). No requirements
issues. Manual checks M1 to M8 for the owner (no VoiceOver, macOS 15 or 26).
Full review: `docs/features/ai-masks/review.md`.

## Confirmation (2026-11-20)

Owner: apple-ui-designer. Against commits `b56d44c` (code), `88d1c43` (user
guide) and `2abdd18`, read in the worktree `/Users/randy/Projects/Gus-ai-masks`;
`status.md` ("Review findings" and its scripted re-check) and `design.md`.

**How this was done.** By reading the code, the catalog, the user guide and
`status.md`. I could not run the app and did not run the tests; "scripted" below
means `status.md` says the debug script showed it, which I take as reported.
Looks, tooltips and keys stay with M1 to M8.

### Verdict

**Confirmed, one small gap.** Every must and should finding is fixed as
asked, and the design is amended. One thing I missed the first time and found
now (N1) is a caption that flips from Unavailable to Failed after a second
failed Update. It is small and not a blocker for QA; fix it with the next
change to this file.

### Findings

| # | Finding | Result | Evidence |
|---|---|---|---|
| F1 | Pull-down and Update look enabled while cropping | **Confirmed** | `DetectionButton.dimmedHelp` returns `croppingHelp` while `cropSession != nil` (`MasksSection.swift:97`); both rows pass `maskLimit ?? dimmedHelp` / `componentLimit ?? dimmedHelp`, and `dimmed != nil` disables the control. The Update button's help is wait, then cropping, then the normal tooltip, and `isEnabled` is `canUpdateDetection`, which already requires no crop session. Both strings are in the catalog ("Finish cropping to detect in the photo.", "Finish cropping to detect again."), worded as DR-2 and as "Finish cropping to show the sharpening map." Scripted: `adjust crop begin`, `buttons` shows both pull-downs and Update disabled |
| F2, DR-1 | Caption after a failed Update of a Found result | **Confirmed** | New `MaskDetectionState.failedUpdate(instances:)` (PhotoCore), `offersUpdate` true (triangle and Update), caption "Detection failed on this photo. The earlier result still applies. Choose Update to try again." in the catalog with its comment. `detectionState` returns it only when the underlying state is Found, else `.failed`, as DR-1 says. `landUpdate` clears the entry on a later success and the announcement uses the same caption. `failedUpdates` is reset on leaving the photo (`AdjustmentEditor.swift:588`). One gap: N1 |
| F3 | Failure attributed to the wrong request | **Confirmed** | `land` iterates `(request, result)`; Unavailable is remembered for that request and `reportFailure` names `pending.kind(for: request)`, the first component that uses it. Background's request is Subject's, so a Subject-or-Background failure says "a subject", People's says "people". Update with two requests renders once (C7) |
| F4, DR-3 | Flash only on Found | **Confirmed** | New mask and component: `if found { flashOverlay }`, where `found` is the instance count of the pending kind's request. Update: `flashes` only when a landed result has instances, and only when `changed`. Empty, failed and unavailable never flash. Scripted: empty People landing, `flash false` |
| F5 | Invert on/off for assistive technology | **Confirmed** | `ComponentRow`'s Invert passes `accessibilityValue` "On" or "Off" (existing catalog keys); `AppKitButton.updateNSView` applies it on every update, not only at creation, so it follows a toggle. Applies to every component kind. Not read by VoiceOver (standing rule) |
| F6 | One announcement | **Confirmed** | `reportFailure` calls `library.postActivity`, which posts to Activity with no announcement (`LibraryModel.swift:614`); the landing's single `announce` carries the caption. Design §12 amended to say so. `report(... announcing:)` is no longer used here |
| I2 | Update Detection above Show / Hide Mask Overlay | **Confirmed** | `LibraryCommands.swift:636-658`: New Mask ▸, Update Detection, then the overlay item, the sharpening map and the fringe map. Design §7, §11 and a new DR-4 amended |
| G1 | No bold "Detect" | **Confirmed** | The guide says "The wand button at the end of the shape buttons"; design §17's terms list no longer names "Detect" (the VoiceOver name only) |
| G2 | Four-person caption quoted whole | **Confirmed** | "4 people found, the most that can be selected. Others in the photo may be left out." matches the catalog |
| G3 | Invert on Background | **Confirmed** | "Invert on a Background component selects the subject again." |
| G4 | A failed Update keeps the earlier result | **Confirmed** | "If Update fails, the earlier result keeps applying and the row says so, with Update to try again." True of the build and of F2 |

Terms in the guide against the UI: Subject, People, Background, Detecting…,
Cancel, Update, Update Detection, the "1 subject found." example and the
"4 people" caption all match; "Adjust ▸ Update Detection" is where the menu now
puts it.

### Design amended

`design.md`: §2 (the pull-down dims as a whole), §4 (a row for the failed Update
of a Found result), §7 (placement, the Update button's states, the failed
Update text), §9 (Found only), §11 (placement), §12 (Invert's value, one
announcement), §17 (G1 to G4 note, terms list), and §19.1 (DR-4, the open
judgments I1 and I3, this confirmation). DR-1 to DR-3 were already there.

### Remaining findings

- **N1 (should, small). A second failed Update turns Unavailable into
  Failed.** `detectionState` (`MaskDetectionEditing.swift:389-394`) returns
  `.failed` for any component in `failedUpdates` whose state is not Found.
  A component that already shows Unavailable (no stored result, the request
  can't run on this Mac) and whose Update fails as unavailable again goes
  from "Detection isn't available on this Mac. It selects nothing." to
  "Detection failed on this photo. …", which names the wrong cause and flips
  the text on a retry. Fix: leave `.unavailable` alone, so
  `if case .unavailable = state { return state }` before the override. Test
  with `detector unavailable`, add, `Update`, and compare the caption.
  A Found component whose Update fails as unavailable shows the DR-1 caption,
  which is acceptable (it does not claim a cause).
- **I1 (judgment, unchanged).** The eye still turns the overlay off during a
  flash. Decided at M4; not a finding.
- **I3 (judgment, unchanged).** No "Detection unchanged." for VoiceOver. Not
  needed unless M7 says the brief "Detecting…" reads as no response.
- **Manual checks M1 to M8 stand**, with M3 now covering the crop-session
  tooltip (F1) and M8 the new menu order (Update Detection before the overlay
  item). Cannot be confirmed from code: F1's tooltip showing on a dimmed
  borderless pull-down, and the 256 pt fit.

Not re-opened: the engineer's code-review items (C1 to C8) are code-reviewer's
to confirm. I read C3 only as far as F3 needs it.

No requirements issues.

### Summary for the issue

Design review confirmation, #88 (`b56d44c`, `88d1c43`, `2abdd18`): **confirmed.**
F1 (dimmed with a cropping tooltip), F2 and DR-1 (a failed Update of a Found
result says the earlier result still applies), F3, F4 and DR-3 (flash only for
Found), F5 (Invert On / Off), F6 (one announcement), I2 (Update Detection
before the overlay item) and G1 to G4 (user guide) are built as asked; read
from code and `status.md`, the app not run. `design.md` amended (§2, 4, 7, 9,
11, 12, 17, 19.1 with DR-4). One small open finding, N1: a second failed Update
of an Unavailable component shows Failed instead of Unavailable. I1 and I3
stay judgment calls for M4 and M7. Manual checks M1 to M8 for the owner (no
VoiceOver, macOS 15 or 26). Full text: `docs/features/ai-masks/review.md`.
