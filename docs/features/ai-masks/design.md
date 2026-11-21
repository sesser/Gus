# AI masks (Subject, People, Background): design

Owner: apple-ui-designer. Date: 2026-11-20. Issue: #88 (slug `ai-masks`).
Status: Designed. No rulings recorded yet (§19 holds them as the engineer
returns Design questions).

**Inputs.**

- Requirements: the issue body (the PRD, revised 2026-11-20 after the spike),
  cited as R1–R16 and AC1–AC14. This document answers its designer open
  questions: how the add action, the Detecting state, the reasons (missing
  raster included) and Update appear, and whether Background is a kind of its
  own.
- Spike findings: [`status.md`](status.md) (sizes, timings, People limit and
  false positives, determinism, storage).
- Earlier records followed: `docs/UI_REDESIGN.md` (UIR §4 inspector, §6
  menus, §10 accessibility), [`../ui-redesign/design.md`](../ui-redesign/design.md)
  (N7 mask overlay item, N8 limits, N10 component controls stay in the
  inspector, D-Q5), [`../chromatic-aberration/design.md`](../chromatic-aberration/design.md)
  (the measuring spinner and state captions), [`../healing/design.md`](../healing/design.md)
  (bare keys in use, one on-photo tool at a time, the paste note),
  [`../side-by-side-comparison/design.md`](../side-by-side-comparison/design.md)
  (no editing while comparing), [`../edit-history/design.md`](../edit-history/design.md),
  `docs/archive/PHASE6_PLAN.md` (masks).
- Code read on `feature/ai-masks`: `Views/MasksSection.swift`,
  `Model/MaskEditing.swift`, `Loupe/MaskOverlayView.swift`,
  `Views/LibraryCommands.swift` (the Adjust menu), `Views/LibraryMenuContext.swift`,
  `Views/AdjustView.swift`, `Views/LensControls.swift` (the spinner row),
  `Edits/Masks/LocalAdjustments.swift`, `Commands/MaskCommands.swift`,
  `LibraryModel.report` and `AccessibilityText.announce`.
- HIG pages read on 2026-11-20 (markdown versions): Pull-down buttons,
  Progress indicators. The Menus, Inspectors, Accessibility and Segmented
  controls readings in the earlier records are relied on where cited. Where
  the HIG is silent I say "judgment".

**Clean-room note.** The words (Subject, People, Background, Detecting,
Update) say what the person gets and are common nouns and verbs. The layout
(a button beside the five shape buttons, a component row with a caption
under it) extends this app's own Masks heading. Nothing is taken from
another photo application's mask panel.

## Summary of rulings

| # | Ruling |
|---|---|
| A1 | The five shape buttons stay as they are. Detection gets **one more control in the same row: a pull-down button** (symbol `wand.and.stars`) whose menu lists **Subject, People, Background**. The same control sits in the "Add to Mask:" row (§2) |
| A2 | **Background is a kind of its own** in the menu, the row and VoiceOver. It is Subject's raster with the inversion built into the kind; the row's Invert toggle starts off and stays independent (§3) |
| A3 | A new detection shows **one transient status line** under the add row: a mini spinner, "Detecting…" and Cancel. The component is **written to the stack only when the result lands**, as one undo step and one History entry (§5) |
| A4 | Every AI component row carries a **state caption** in the slot where shape sliders sit: found (with a count), empty, failed, unavailable, missing (§4) |
| A5 | A component with no usable result (pending, empty, failed, unavailable, missing) **is skipped**: it contributes nothing, whatever its operation or Invert, so the photo renders as without it. Background with no subject selects nothing, not everything (§8) |
| A6 | **Update** is a per-component button, shown only where it is the remedy (failed, unavailable, missing), plus **Adjust ▸ Update Detection** and an item in the mask's ⋯ and context menus for every state. One undo step; an unchanged result does nothing (§7) |
| A7 | No shortcuts, no bare keys, no new toolbar item (§11) |
| A8 | The red mask overlay already shows the whole combined mask, so it shows AI components with no new drawing; a new AI result **flashes the overlay once for 1.5 s** so the person can judge the edge (§9) |
| A9 | Adding and Update are dimmed while cropping, while comparing and while a detection is pending; a pending detection is cancelled when the editor leaves the photo (§10) |
| A10 | Inline for state, Activity for diagnosis: failed and unavailable also post a warning to Activity; empty and missing never do (§6) |

## 1. Terms

| Term | Meaning | Why this word |
|---|---|---|
| **Subject** | What stands out in the photo, every instance of it as one region | The PRD's word; plain |
| **People** | Every person found, at most four | The PRD's word |
| **Background** | Everything except the subject | The PRD's word; the person's goal ("darken everything behind them") |
| **Detecting…** | The state while the Mac looks | The PRD's word (R4). A specific verb, not "Loading" (HIG Progress indicators: avoid vague terms) |
| **Update** (button, `Update Detection` in menus) | Look again and replace the saved result | The PRD's word (R5). One word for the command everywhere (P5) |
| **component** | One shape, range or detection inside a mask | In the user guide and docs only. In the app, rows are named by what they are ("Subject") and sentences say "It selects nothing" |

In sentences and the user guide: "subject", "people", "background",
"detection" in lowercase as common nouns.

## 2. Where the add action lives

**Today** (`ShapeButtons`): the heading shows "New Mask:" and five 26 pt
icon buttons; a selected mask shows "Add to Mask:" and the same five. The
inspector's narrowest content width is 256 pt.

**Three more icon buttons do not fit.** "New Mask:" at caption size is
about 55 pt, five buttons are 130 pt, three more 78 pt, plus spacing:
roughly 275 pt against 256. A second row would split one idea ("make a
mask") across two rows, and would repeat for "Add to Mask:".

**Ruling A1.** Keep the five buttons and add **one pull-down button** at the
end of both rows:

```
New Mask:  ▭ ◌ 🖌 ☀ 💧  [✨▾]          ← Linear, Radial, Brush, Luminance, Color, Detect
Add to Mask: ▭ ◌ 🖌 ☀ 💧  [✨▾]
```

| Part | Spec | Basis |
|---|---|---|
| Control | `AppKitMenuButton` (an `NSPopUpButton` that pulls down), symbol `wand.and.stars`, borderless like its neighbours, about 34 pt with its chevron, tooltip "New mask from the photo: Subject, People or Background" (in the Add row: "Add to this mask from the photo: …"), VoiceOver label "Detect" | Fits: about 55 + 130 + 4×2 + 34 = 227 pt. The engineer confirms `print inspectorwidth` reports `fits` at the narrowest inspector |
| Menu | **Subject**, **People**, **Background**. No icons in the items (the row icons in §4 carry the meaning once chosen), no section header. The pull-down dims **as a whole** (not item by item; DR-2, §19.1), as the shape buttons do, with the reason as its tooltip and VoiceOver help: the mask or component limit (same tooltips), "Wait for the current detection to finish." while one is pending, "Finish cropping to detect in the photo." while cropping (§10) | HIG Pull-down buttons: "An Add button could present a menu that lets people specify the item they want to add"; three items is the length the HIG says makes a pull-down worth opening |
| Symbol | `wand.and.stars` (SF Symbols 3 and later). The engineer confirms it in the SF Symbols app and otherwise uses `sparkles` | Says "automatic" without saying "AI" |

**Why a pull-down and not three buttons, and the HIG cost.** Width is the
first reason. The second is that detection kinds will grow (Sky is its own
issue) and a menu takes a fourth item with no layout change. The HIG's
warning is real: "avoid putting all of a view's actions in one pull-down
button" because primary actions should be discoverable. Here the pull-down is
*one action among six* in the row, not all of them, and the same three
commands are in **Adjust ▸ New Mask ▸** with their words visible (§11). I
judge detection discoverable enough; if the owner's eye at sign-off says
people miss it, the answer is a text label on the button, not a second row.

**Do not add the kinds to `MaskShapeKind.allCases`.** `ShapeButtons` and the
New Mask submenu iterate it, so the row would overflow and the menu would
list detections as shapes. Detection kinds are a separate type
(`MaskDetectionKind`: `subject`, `people`, `background`, with `title`,
`symbol`). `ComponentRow` handles both.

**Why not the toolbar.** Masks are inspector content in the loupe; a toolbar
item for one kind of component would be a command with no target when no
photo is open in the loupe, and the toolbar is for navigation and
every-photo commands (UIR §6).

## 3. Background: its own kind

**Ruling A2.** Background is a kind of its own in the menu, the component's
title and VoiceOver, **not** "Subject with Invert switched on".

Why. The person's goal is stated as "the background"; a row reading
"Subject" with a lit Invert button makes them translate. Storage allows
either (status.md §6), so this is presentation, and plain words win.

How it behaves:

- A Background component stores kind `background` and a digest; the digest
  may be Subject's row (no second detection, R5).
- The kind carries its own inversion: its alpha is 1 − raster. The row's
  **Invert** button is a separate toggle, off when added, and means what it
  means on every component: Background with Invert on selects the subject.
  Two inversions cancelling is correct and needs no special case in the UI.
- Update on a Background component runs the Subject request and replaces its
  digest. It never changes a sibling Subject component's digest: each
  component owns its reference, as after Duplicate.
- With no subject found, Background selects nothing (§8).

## 4. The component row and its states

Same `ComponentRow` as every component: icon, title, operation pop-up,
Invert, Remove from Mask. What changes is the slot below it, where shape
sliders sit. For a detection it is a **state caption**: 11 pt secondary, wraps,
inset to the title, with an `exclamationmark.triangle` where the state is a
problem. There is no feather or refine control (R3).

```
[◎] Subject                  [Add ▾] [◐] [⊖]      ← icon, title, operation, Invert, Remove
    1 subject found.
```
```
[◎] People                   [Add ▾] [◐] [⊖]
    ⚠ Detection failed on this photo. It selects nothing.
      Choose Update to try again.                [ Update ]
```

Row icons (judgment; the engineer confirms each in the SF Symbols app):
Subject `dot.viewfinder`, People `person.2`, Background `rectangle.dashed`.
The default mask name is the kind's title ("Subject", "People",
"Background") rather than "Mask N": a mask made by detection has one obvious
noun, and "Mask 3" tells nothing in the list. It renames like any mask.

### States and captions

| State | Caption (exact) | Triangle | Update button |
|---|---|---|---|
| **Found**, Subject | "1 subject found." / "2 subjects found." | no | no |
| **Found**, People, 1 to 3 | "1 person found." / "3 people found." | no | no |
| **Found**, People, 4 | "4 people found, the most that can be selected. Others in the photo may be left out." | no | no |
| **Found**, Background | "Everything except 1 subject." / "Everything except 2 subjects." | no | no |
| **Empty**, Subject | "No subject stands out in this photo. It selects nothing." | no | no |
| **Empty**, People | "No people were found in this photo. It selects nothing." | no | no |
| **Empty**, Background | "No subject was found, so there is no background to select. It selects nothing." | no | no |
| **Failed** (the photo could not be rendered for detection, or the request threw; also a result never stored) | "Detection failed on this photo. It selects nothing. Choose Update to try again." | yes | yes |
| **Failed Update of a Found result** (this visit only; DR-1) | "Detection failed on this photo. The earlier result still applies. Choose Update to try again." | yes | yes |
| **Unavailable** (this session: the request reports it cannot run on this Mac) | "Detection isn't available on this Mac. It selects nothing." | yes | yes |
| **Missing** (the digest names no row, or the row's bytes cannot be read) | "The stored result is missing or damaged. It selects nothing. Choose Update to detect again." | yes | yes |
| **Detecting** | "Detecting…" with a mini spinner and Cancel (§5) | no | replaced by Cancel |

Why these:

- **Found says how many**, so the person sees that the Mac found what they
  meant (two subjects, not one) before they look at the photo, and so the
  four-person limit can be said where it bites. The count is kept on the
  `maskRaster` row (an immutable property of the stored result, like its
  size), not in the stack; Background reads its Subject row's count. If the
  engineer cannot keep a count, the fallback is "Found." with no limit
  sentence, and that goes back to me as a Design question (§19).
- **Empty is not an error** (R6): no triangle, no button (Update would give
  the same answer on the same Mac), plain words, and no Activity entry.
- **Update is shown only where it is the remedy**: failed, unavailable,
  missing. In found and empty states the same command is in the menus (§7),
  so a row of three healthy components has no row of three buttons.
- **"It selects nothing"** answers the question the person actually has
  ("why did my slider do nothing?"). "This mask" is avoided because a mask
  can hold other components that still work.
- A wrapped caption sits to the left, the button top-aligned to the right
  (`AppKitButton`, `.push`, small control size; tooltip "Detect again on
  this photo and replace the stored result"). It is a text button, not an
  icon, so its label is the word the caption says.
- **Failed after reopening.** A component with no digest (it failed, or the
  window quit mid-failure) reads as Failed in any later session; the specific
  "unavailable" reason is kept in memory for this session only. No reason
  text is stored in the stack (R12: the stack stays small and strict).
- States are text plus, for problems, an icon, never color alone (P-color
  rule, HIG Color).

## 5. Detecting

**The reading of R4 that this design needs (A3).** R4 says the component
"shows Detecting… and renders as no mask" while it runs. I read this as
what the person sees and what renders, not as a requirement that a
digest-less component sits in the saved stack during the wait. The design
keeps the component **out of the stack until the result lands**:

- One click, one result, **one undo step** ("Add Subject Mask") and one
  History entry. If the component were saved first and filled in later, ⌘Z
  after the result would leave a digest-less component, or need two steps.
- Leaving the photo mid-detection leaves nothing behind. AC3's "leaving the
  photo stops detection" is then a plain cancellation with no cleanup.
- The photo renders unchanged during the wait because nothing has changed.

If the owner wants the component saved first, say so (Requirements issue
RI-1 below); the observable behavior is otherwise the same.

### The pending line

While a detection runs, one line appears directly under the add row that
started it ("New Mask:" row for a new mask, "Add to Mask:" row for a new
component):

```
New Mask:  ▭ ◌ 🖌 ☀ 💧  [✨▾]
◌ Detecting…                                   [Cancel]
```

| Part | Spec |
|---|---|
| Spinner | `ProgressView().controlSize(.mini)`, as in `LensControls`; shown at once (the line is the response to the click, so there is no 0.5 s delay as in the Lens row). Tooltip and VoiceOver label "Detecting" |
| Text | "Detecting…", caption style, in the same slot the result caption will take |
| Cancel | `AppKitButton` push, small, "Cancel". Cancels the detection; nothing is added; no message |

- **Cancel exists** because the HIG says to let people halt a process when
  that has no side effect (Progress indicators). It is a button, not ⌘.:
  File ▸ Stop is for jobs listed in Activity (imports, exports), and a
  detection takes 0.15 to 0.5 s here (2 s the first time after a build), so
  it is not one. This is a judgment.
- **The HIG says to avoid labeling a spinner.** The spinner is unlabeled;
  "Detecting…" is the state caption that the result replaces, the same slot
  and wording role as "1 subject found." It is not a label on the spinner.
- **One detection at a time per photo.** While one is pending, every AI add
  and Update item is dimmed with the tooltip "Wait for the current detection
  to finish." Two at once would render the input twice and compete for the
  GPU for no benefit.
- **Update's pending state** is the same line in the component's own caption
  slot ("Detecting…", mini spinner, Cancel in place of Update). The old
  result **keeps applying** until the new one lands, so the photo does not
  flicker back to unmasked; the result swaps in one render. Changing or
  removing a component the Update covers cancels it (DR-5, §19.1).

### Landing

- The mask (or component) appears in the list; for a **new mask it is
  selected only if the selection has not changed since the click**. If the
  person has moved on (selected another mask, started painting), the mask is
  added unselected, and VoiceOver and the caption still say what happened.
  Stealing selection from a mask being edited is the worse error.
- Default local values on a new detection mask follow the existing rule
  that a new mask starts with a visible effect (`addMask` gives radial and
  brush +0.3 exposure, linear −0.5): **Subject and People +0.3 EV,
  Background −0.5 EV** (the PRD's scenario is darkening what is behind). A
  mask with all-default values does not render at all
  (`LocalAdjustments.renderedMasks`), so the person would see nothing happen.
- If the 32-mask or 16-component limit was reached while waiting, nothing is
  added and the existing message appears ("That would pass the limit on
  masks, components or brush points.", Activity warning).
- The landing is announced (§12) and the overlay flashes once (§9).

## 6. Empty, failed, unavailable, missing: persistence and notification

| State | Stored | Shown | Activity |
|---|---|---|---|
| Found | kind, digest | caption, count | no |
| Empty | kind, digest of a stored result with **zero instances** (the engineer stores a 1×1 black raster; the digest is shared by all empties) | caption | no (not an error, R6) |
| Failed | kind, **no digest** | caption, triangle, Update | **yes**, a warning: "Couldn't detect a subject in IMG_1234.JPG" plus the underlying error text for diagnosis (as `reportRemovalFailure` does) |
| Unavailable | kind, no digest | caption, triangle, Update | yes, a warning, with the error |
| Missing | kind, digest (kept; Update replaces it, R14) | caption, triangle, Update | **no**: it would repeat on every visit to the photo |

- **Empty is stored as a result** so that "found nothing" survives closing
  the library and stays different from "the row is gone". The engineer may
  store it another way if it keeps both properties, and says how in
  `status.md`.
- **Missing and damaged are one state** for the person. The engineer treats
  a row whose PNG cannot be decoded exactly like an absent row.
- All of these keep the component in the mask (R6, R14), the photo editable
  and every other component working (§8).

## 7. Update

**Ruling A6.**

| Path | Where | Acts on |
|---|---|---|
| Button "Update" | The component's caption, only in Failed, a failed Update of a Found result, Unavailable and Missing | That component |
| **Adjust ▸ Update Detection** | Directly after New Mask ▸ and **before** Show / Hide Mask Overlay (I2: it changes data, so it sits with its sibling New Mask, not among the three "look at the mask" items that follow it) | Every detection component of the selected mask, as one undo step |
| "Update Detection" in the mask row's ⋯ menu and context menu | Between Rename / Move and Delete, shown only when the mask has a detection component | Same as the menu bar item |

- **Enablement** (menu, ⋯ item and button): the loupe's photo is editable
  (`canEditLoupePhoto`), not cropping, not comparing, no detection pending,
  and the mask has at least one detection component. It is **enabled in
  every state**, healthy ones included: a person who thinks the mask is
  wrong may want to look again. In the Unavailable state it stays enabled
  because the cause may be passing.
- **Why per component for the button but per mask for the menu.** Rows are
  not selectable (N10: component controls are inspector-only), so the menu
  bar has no way to name one. A mask with two detection components and one
  Update is rare, undoable, and the button covers precise use.
- **Undo and History.** One step, "Update Detection", labelled the same in
  History. Undo restores the previous digest and its mask **without
  detecting** (R5); Redo restores the new one. If the new result has the
  same digest as the old (the usual outcome on one Mac, status.md §3), no
  stack write happens: no undo step, no History entry. The row has shown
  "Detecting…" for a moment, which is the feedback; I judge that better than
  a message about nothing changing.
- **A failed Update** erases nothing: the old result keeps applying and the
  render does not change. For this visit, as in-memory state, the row says so
  (DR-1: "The earlier result still applies" when the result is Found; the
  Failed caption when it was Empty, Failed or Missing), with Update again,
  and an Activity warning is posted;
  the stored digest is untouched, so reopening the photo shows the old result's
  Found caption again.
- **No shortcut** (§11).
- Update never touches other versions or another component's reference
  (R5, R8).

## 8. Combining, Amount, and what "selects nothing" means

All of R3 is the existing machinery; this section records the three
decisions that were open.

1. **Add, Subtract, Intersect, Invert** are the row's operation pop-up and
   Invert button, unchanged. The first component's operation pop-up stays
   shown, as for shapes.
2. **A component with no usable result is skipped (A5).** Pending, empty,
   failed, unavailable and missing components contribute nothing **whatever
   their operation and Invert**: the mask renders as without that component
   (R6, R14: "the photo renders as without it"). In particular:
   - Subtract of nothing leaves the mask whole (the literal result as well).
   - Intersect with nothing does **not** zero the mask. The literal
     arithmetic would, but "as without it" is what R6 and R14 say, and a
     component that silently erases the rest of the mask is the worse
     surprise; the caption says why it is idle.
   - **Background with no subject selects nothing**, not the whole photo.
     Inverting "nothing found" into "everything" would apply the person's
     −0.5 EV to the entire frame, which is the opposite of what they asked
     for.
   - Invert on an idle component changes nothing until it has a result.
3. **Amount and the local sliders** scale and apply as for any mask. There is
   no per-component amount, feather or refine (non-goals). To correct an
   edge the person adds or subtracts a gradient, range or brush component,
   which the guide says (§17).

The guided filter's upscaling happens in the renderer (R7). It is not a
control and has no UI.

## 9. The mask overlay

- **The red overlay already draws the selected mask's combined alpha**
  (`Show the selected mask in red`). A detection component contributes its
  alpha like any other, so Show Mask Overlay, the eye, Hide Mask Overlay and
  its menu item all work with **no new drawing**.
- **No handles.** A detection has nothing to drag, like ranges.
  `MaskOverlayView` draws nothing for it and passes clicks through.
- **The overlay on a skipped component shows nothing for it**, which is
  correct and matches the caption.
- **The flash (A8, judgment, the first thing to cut if the engineer finds it
  costly).** A new detection result has no handles, and +0.3 EV on a subject
  is subtle, so the person cannot judge the edge without finding the eye.
  When a **Found** result lands on the selected mask (add or an Update that
  changed the digest; Empty, failed and unavailable results never flash, DR-3)
  with the overlay off, **the overlay turns on for 1.5 s and
  off again**. It ends early if the person touches the eye, starts a
  slider drag, selects another mask or leaves the photo, so it never fights
  an adjustment. It is not shown when a stored mask is merely opened. It is a
  hard cut, not a fade: the overlay is a render, so a fade would need a
  render per frame, and a hard cut has no motion for Reduce Motion to
  disable. It reuses `showsMaskOverlay`, so the eye button shows the state.

## 10. Cropping, comparing, review, the grid, other tools

| Situation | Behavior | Why |
|---|---|---|
| **Crop session** | New Mask and Add to Mask detection items, and every Update path, are dimmed (the menu already dims New Mask while cropping via `canAddMask`). A detection **pending when a crop session starts continues and lands normally**: the detection input does not depend on the crop (R4, R7), so nothing it computes is wrong | The loupe shows the crop frame, so the person cannot see the result; one rule for all mask adds |
| **Comparing** | The Adjust tab is replaced by "Not Available While Comparing"; menu items dim. A pending detection is **cancelled** when a comparison starts | No editing while comparing (side-by-side design §11); starting the comparison ends the editor's use of the photo |
| **Review mode (F)** | The inspector is hidden; the menu items follow `canEditLoupePhoto` as New Mask does. A pending detection continues and lands | Same photo, same editor; nothing to cancel |
| **Grid** | The Masks heading is loupe-only, so there is no detection item in the grid and no batch detection (non-goal) | |
| **Leaving the photo, switching the loupe photo, quitting** | A pending detection is cancelled; nothing is added | AC3 |
| **Other on-photo tools (Paint, Pick Colors, Edit Spots, the sharpening and fringe maps)** | Starting a detection ends the sharpening map as any new mask does (`endSharpeningMap`). It does **not** turn Paint or Pick Colors off (it does not need the photo on screen); the landing selects the new mask only if the selection is unchanged (§5), which turns those tools off as selecting a mask already does | Keeps the existing "selecting a mask ends Edit Spots" rule |
| **Show Original** | The overlay flash and landing behave as for any edit: the render is the original while it is on | |

## 11. Menus and shortcuts

| Command | Menu | Shortcut | Enabled |
|---|---|---|---|
| **Subject**, **People**, **Background** (under a divider after the five shape items) | **Adjust ▸ New Mask ▸** | none | As the shape items: editable loupe photo, not cropping, under 32 masks, **and** no detection pending. The submenu title stays enabled (D-Q5) |
| **Update Detection** (new) | Adjust, after New Mask ▸ and before Show / Hide Mask Overlay (I2) | none | §7 |
| Subject / People / Background as a component | Inspector only: the "Add to Mask:" pull-down | none | Mask selected, under 16 components, no detection pending |
| Cancel a detection | The pending line's Cancel button | none | While pending |
| Show / Hide Mask Overlay | unchanged | none | unchanged |

- **Every command is in the menu bar except adding a component to an
  existing mask**, which stays inspector-only exactly as adding a gradient
  component does (ui-redesign N10: a parameter of the selected mask, not a
  command).
- **No shortcuts.** Each is used a few times per photo; the free single
  letters are scarce (culling, `C`, `H`, `V`, `Z`, `\`, `F`, `S`, `A`), and a
  chord for a command that takes half a second to start and half a second to
  finish earns nothing. Judgment, not Apple policy. Everything is reachable
  by keyboard through the menu bar and Full Keyboard Access on the
  `AppKit` controls.
- The submenu stays one level: the three items sit under a divider beneath
  the shapes. I did not use a `Section` header: SwiftUI renders it as a
  header only on newer macOS and the app's minimum is 15; the engineer may
  try `Section` and keep it if it renders on 15.
- Titles are Title Case like their neighbours ("Linear Gradient"); no
  ellipsis because each acts at once with no further input.
- `LibraryMenuContext` gains `canDetect` (the shape items' rule plus no
  pending detection) and `canUpdateDetection`; both are published through
  focused values as the others are.

## 12. Accessibility

- **Inspector controls are the app's AppKit wrappers**, not SwiftUI buttons:
  `AppKitMenuButton` for the pull-down, `AppKitButton` for Update and
  Cancel. CLAUDE.md's rule ("No SwiftUI `ScrollView` under the toolbar") means
  SwiftUI buttons in the inspector can swallow clicks in the earlier design.
  The mini `ProgressView` is not interactive and is fine (precedent:
  `LensControls`).
- **Labels.** Pull-down: "Detect", help as §2. Menu items read their titles.
  Component row: the title is the first element ("Subject"), then the
  caption as static text, then the controls; the operation pop-up keeps its
  label; Invert keeps "Invert" and exposes its on/off state as its
  accessibility value, "On" or "Off", on every component kind (review F5: the
  button's symbol and tint alone said nothing to VoiceOver).
- **Announcements** (`AccessibilityText.announce`, medium priority), so a
  VoiceOver user whose focus stayed on the pull-down hears the outcome:
  - Landing, found: "Subject mask added. 1 subject found." / "People mask
    added. 4 people found, the most that can be selected."
  - Landing, empty: "Subject mask added. No subject stands out. It
    selects nothing."
  - Update, changed: "Detection updated. 2 people found."
  - Failed or unavailable: posted to Activity **without** announcing (review
    F6); the landing's own announcement carries the caption ("Subject mask
    added. Detection failed on this photo. It selects nothing. …"), so each
    outcome is spoken once. After a failed Update of a Found result the
    announcement carries the DR-1 caption.
  - Cancel: "Detection cancelled." Also posted when a change to a covered
    component cancels an Update (DR-5).
  Focus is **not moved** by landing: moving focus on an asynchronous result
  steals it from whatever the person was doing.
- **The pending state** has the spinner label "Detecting" and the caption
  text, both reachable.
- **Color.** Nothing depends on color: problems carry a triangle and a
  sentence; the red overlay is the existing one (Increase Contrast variants
  already in `Palette`).
- **Motion.** The only new motion is the system spinner. The overlay flash
  is a static state (§9).
- **Keyboard.** Tab reaches the pull-down, the row controls, Update and
  Cancel in reading order; Space and Return press them; the pull-down opens
  with Space or ↓. No bare key is added, so nothing can collide with the
  grid's or the loupe's.
- **Touch-display Macs.** The new controls use the same sizes as their
  neighbours; no extra hit-area work beyond what the wrappers already give.

## 13. macOS versions

- **macOS 15.** The app's minimum. Both Vision requests are declared
  available from macOS 14 (status.md §1), so **nothing is hidden or gated by
  version**: the pull-down, the three items, the captions and Update look
  and work the same. The interface never names a macOS version.
- **macOS 26 and later.** The same, in the current design; the pull-down and
  captions are system controls and text in the inspector's content layer (not
  Liquid Glass; glass is for the controls layer, and the inspector keeps its
  system treatment).
- **If a request cannot run** (a VM without a usable compute device, as on
  CI; a Mac where the request throws), the component is kept with the
  Unavailable or Failed caption (§4). No menu item is dimmed in advance,
  because "can this Mac run it" is not knowable without trying and R6 says
  the component is kept anyway.
- **A mask made on another macOS or Mac renders as stored** (R5); Vision's
  output differs across compute devices (status.md §3), so only a new or
  updated detection can differ, and the guide says that (§17).
- AC11's fixture test checks availability and mask sizes on 15 and 26 in CI;
  nothing in this design needs a person on either (project memory: owner
  does not check VoiceOver or macOS 15 and 26 by hand).

## 14. Localization keys

All through `Localizable.xcstrings`, added by hand (`LocalizationTests`
fails on a literal without an entry). Plural rows need plural variations.

| Key (English) | Use | Notes |
|---|---|---|
| "Subject" / "People" / "Background" | Menu items, row titles, default mask names | Comment: "Mask detection kind"; the same keys serve all three uses |
| "Detect" | Pull-down accessibility label | |
| "New mask from the photo: Subject, People or Background" | Tooltip | |
| "Add to this mask from the photo: Subject, People or Background" | Tooltip | |
| "Detecting…" | Pending caption | |
| "Detecting" | Spinner tooltip and VoiceOver label | no ellipsis |
| "Cancel" | Pending button | existing key |
| "Wait for the current detection to finish." | Tooltip of dimmed items | |
| "%lld subjects found." (one, other) | Found, Subject | plural |
| "%lld people found." (one: "1 person found.") | Found, People | plural |
| "%lld people found, the most that can be selected. Others in the photo may be left out." | Four people | the number is always 4; keep `%lld` so a future limit change is a code change only |
| "Everything except %lld subjects." (one, other) | Found, Background | plural |
| "No subject stands out in this photo. It selects nothing." | Empty | |
| "No people were found in this photo. It selects nothing." | Empty | |
| "No subject was found, so there is no background to select. It selects nothing." | Empty | |
| "Detection failed on this photo. It selects nothing. Choose Update to try again." | Failed | |
| "Detection isn't available on this Mac. It selects nothing." | Unavailable | |
| "The stored result is missing or damaged. It selects nothing. Choose Update to detect again." | Missing | |
| "Update" | Button | |
| "Detect again on this photo and replace the stored result" | Button tooltip | |
| "Update Detection" | Menu item, ⋯ item, undo action name, History label | one key |
| "Add Subject Mask", "Add People Mask", "Add Background Mask" | Undo action names | |
| "Add Subject to Mask", "Add People to Mask", "Add Background to Mask" | Undo action names | |
| "Couldn't detect a subject in %@." (and people) | Activity warning | the file name via `%@`; the system error text is appended on a second line and is not localized |
| "Subject mask added. %@" and the other announcements in §12 | VoiceOver | build from the caption keys |

No brand value appears in any string (CLAUDE.md naming rules).

## 15. Debug-script needs

The designer's checks, the QA tester's and AC6/AC13 all need states that
real Vision output cannot produce on a synthetic fixture. The engineer adds
(names are the engineer's; the capabilities are required):

1. `mask add subject|people|background` and `mask addcomponent <kind> [op]`
   that **wait for the result to land** (`waitfordetection`), reusing the
   `changing` undo-group rule in CLAUDE.md.
2. A **detector override** for scripted runs only: `mask detector
   real|empty|fail|unavailable|hang`. `hang` keeps a detection pending so
   the pending line, Cancel, dimmed items and leaving the photo can be
   checked. Never a setting; launch-option-only like `--demosaic`.
3. `mask raster delete` (removes the selected component's row, for AC13) and
   `mask raster corrupt`.
4. `mask update [all]`, `mask cancel`.
5. `print masks` extended: per component, `kind`, `state` (`found`, `empty`,
   `failed`, `unavailable`, `missing`, `pending`), `instances`, a short
   digest, and the **caption text exactly as shown**, so the wording in §4
   can be diffed.
6. `menuitems "Subject"`, `menuitems "Update Detection"` already work with
   the menu machinery; `buttons` lists the pull-down, Update and Cancel with
   their enabled state; `print inspectorwidth` must report `fits` with the
   pull-down in both rows at the narrowest width.
7. `mask overlayflash` state in `print masks` (on/off) so the 1.5 s flash is
   checkable without timing.
8. `snapshot` leaves glass panes blank in the current design, so the
   caption wrapping and the row layout are read from `print`, not images
   (CLAUDE.md).

## 16. macOS design details the engineer must not lose

- Captions are 11 pt secondary at the title inset (`InspectorMetrics`), the
  same role as the Lens and White Balance captions.
- The pending line and the caption are the **same slot**, so a result does
  not shift the layout by more than a line.
- The row keeps `SliderRow.height` rhythm; do not add dividers.
- Every control keeps a tooltip (`help:`) and an accessibility label; the
  existing tooltip rules apply.
- The Masks heading note "Presets and Paste Adjustments leave masks out."
  stays true and unchanged: detection components are masks (R8).

## 17. User guide text (AC14)

`docs/USER_GUIDE.md` currently has **no description of the Masks heading**
(only passing mentions). The detection text needs its context, so the
engineer adds a short **Masks** paragraph and the **Masks from the photo**
paragraph below near the Spots paragraph (which is the nearest tool
description), and does not write the full manual-mask documentation here
(follow-up for the product manager). Proposed wording; the engineer keeps the
two limits verbatim in meaning.

> **Masks** (the Masks heading, in the loupe) limit an adjustment to part of
> the photo. **New Mask** makes a mask from a shape (a gradient, a brush
> or a range of light or color) and **Add to Mask** combines more shapes
> with it: Add, Subtract or Intersect, each with an Invert button. The mask's
> **Amount** scales it, and the sliders below apply only inside it.
>
> **Masks from the photo.** The wand button beside the shape buttons (or
> **Adjust ▸ New Mask ▸ Subject, People, Background**) finds something in
> the photo on your Mac, with nothing sent anywhere, and makes a mask of it.
> **Subject** selects what stands out, every instance of it as one region.
> **People** selects every person it finds, **up to four**: in a crowd the
> others are left out, and the row says "4 people found, the most that can be
> selected." **People can also select something that is not a person.** A
> close-up of a flower was selected as a person during testing, and there is no
> setting for how sure it must be; remove the component, or subtract another
> shape from it. **Background** is everything except the subject. It is the
> Subject result turned around, and with no subject found it selects nothing
> rather than everything.
>
> These components combine and invert like any other. They have no Feather
> or refine control: to fix an edge, add or subtract a gradient, a brush or a
> range. The photo is looked at once, at a reduced size, and the result is
> sharpened to the photo's edges when it is shown, so very fine detail such as
> hair or a fence can come out rough. While it looks, the row says
> "Detecting…"; Cancel stops it.
>
> If nothing is found the row says so and the mask selects nothing, so the
> photo is unchanged. If detection fails, or the Mac can't do it, the row
> says why and shows **Update**. The result is **saved with the photo** and is
> never found again on its own, so it looks the same after you reopen the
> library, on another Mac, or after a macOS update. **Update**
> (**Adjust ▸ Update Detection**, the button, or the mask's ⋯ menu) looks
> again and replaces the saved result; it is one undo step. Masks from the
> photo are left out of Copy and Paste Adjustments and of presets; a
> duplicate starts with its original's result and is then independent. They
> are for the loupe, one photo at a time.

(The guide as built differs from this draft where the review asked: no
bold "Detect", the four-person caption quoted whole, what Invert does on
Background, and that a failed Update keeps the earlier result, G1 to G4. The
guide, not this block, is the text.)

Terms in the guide are checked against the UI at review: **Subject**, **People**, **Background**, **Detecting…**, **Update**,
**Update Detection**, **Cancel**.

## 18. How this maps to the acceptance criteria

| AC | Design answer |
|---|---|
| AC2 | §2 adds each kind; §8 combining and Amount |
| AC3 | §5: asynchronous, Cancel, leaving cancels, "Detecting…" until the result is stored |
| AC4 | §5 one write on landing; §7 Update and undo restore digests without detecting |
| AC6 | §4 empty and failed captions; §8 render as without it; §15 detector override |
| AC7 | §9 overlay shows the filtered edge; goldens are the engineer's |
| AC8 | §16 note; §17 wording |
| AC9 | `photocli`: see RI-2 |
| AC13 | §4 missing; §7 Update restores; §15 `mask raster delete` |
| AC14 | §17 |

**Manual checks for review (M-list preview).** M1: the pull-down in both
rows at the narrowest inspector (fits, tooltip, items dim at limits). M2: the
pending line, Cancel and a quick leave of the photo, with the `hang`
override. M3: each caption's wording and wrapping at 256 pt. M4: the overlay
flash on a real portrait (does it help or annoy; one eye at sign-off). M5:
Background on a portrait reads right (default −0.5 EV, Invert toggle behaves).
M6: the four-person caption on a crowd photo.

## 19. Design questions, Requirements issues, rulings

### Design questions

None for the owner or the product manager.

**For the engineer, to verify while building (not blocking):** the three row
symbols and `wand.and.stars` exist in SF Symbols on the macOS 15 SDK floor
(fallbacks given); `Section` headers inside a menu render on 15 (else keep the
divider); the 256 pt fit; and whether keeping the instance count on the
`maskRaster` row is cheap (§4). If it is not, return a Design question and I
will drop the count and the four-person sentence from the caption.

### Requirements issues (for the product manager)

- **RI-1, R4 and AC3 read as "the component enters the stack when the result
  lands".** The PRD wording ("the component shows Detecting… and renders as no
  mask") can also mean a digest-less component saved at once and filled in.
  This design takes the former (§5): one undo step, nothing to clean up on
  cancel. Confirm, or say the component must exist during the wait; the
  user-visible behavior is nearly the same, but the undo and History behavior
  differ (two steps, or an awkward one).
- **RI-2, R9 names `--kind`; the existing command's parameter is `--shape`.**
  `mask add --shape linear|radial|brush|luminanceRange|colorRange` exists
  (`MaskCommands`). Extending it with `subject|people|background` keeps one
  flag and one command; `--kind` would be a second name for the same thing,
  against P5. This design reads R9's "`--kind subject|people|background`" as
  "the kinds are accepted by `mask add`". Confirm that `--shape` carries them
  (the engineer may also accept `--kind` as an alias). `mask list` shows the
  component's kind and digest, not pixels.
- **RI-3 (information, no decision needed): R5's "component holds its kind
  and the digest" has two small extensions in this design.** A component
  whose detection failed has **no digest** (§6), and the `maskRaster` row
  carries an **instance count** (§4). Both are inside the stated impact
  (the migration and the table are in scope; the stack stays small and
  strict). Say so if either is not acceptable.

### 19.1 Rulings

(The engineer's Design questions are recorded here as numbered rulings,
DQ-1 onward, and cited from `status.md`. Corrections the design review made
to this design are DR-1 onward; the review is [`review.md`](review.md).)

**DR-1 (review, 2026-11-20): a failed Update says the earlier result still
applies.** §4 and §7 had the Failed caption ("It selects nothing") shown after
a failed Update. That is false when the component keeps a result: the old
result keeps applying (§7). A component whose Update failed and whose stored
result is **Found** shows this caption instead, with the triangle and Update:
"Detection failed on this photo. The earlier result still applies. Choose
Update to try again." One key. A component that was Empty, Failed or Missing
keeps the §4 Failed caption (it does select nothing).

**DR-2 (review, 2026-11-20): every dimmed detection control says why.** §10
dims the pull-down, the Update button and the menu items while cropping, but
gave no tooltip. The pull-down's tooltip while cropping is "Finish cropping to
detect in the photo." and the Update button's is "Finish cropping to detect
again." (the wording of "Finish cropping to show the sharpening map.").
Dimming the pull-down as a whole, with one reason as its tooltip and
VoiceOver help, replaces §2's per-item dimming: the three items always share
one reason and `AppKitMenuButton` items carry no tooltips. Accepted.

**DR-3 (review, 2026-11-20): the overlay flash shows a result only.** §9's
flash runs only when the landed component is **Found**. Empty, failed and
unavailable results have nothing to show: the red overlay would flash
nothing.

**DR-4 (review I2, 2026-11-20): Update Detection sits before Show / Hide Mask
Overlay.** §7 and §11 had it after the overlay item, which split the three
"look at the mask" toggles (overlay, sharpening map, fringe map) with a command
that changes data. It now follows New Mask ▸ directly. The ⋯ and context menu
placement (between Move and Delete) is unchanged.

**DR-5 (code review Q3 / C11, 2026-11-20): changing or removing a component
cancels the Update that covers it.** While an Update runs (the button on one
component, or Adjust ▸ Update Detection and the ⋯ item on all of a mask's
detection components), the controls stay enabled, and a change to a component
the Update covers cancels that Update. Ruling: option (a).

- **What cancels.** Any stack write, from whatever source (the row's controls,
  Remove from Mask, deleting the mask, ⌘Z, Redo, a History revert), that
  (1) changes the **operation** or **Invert** of a component the pending
  Update covers, or (2) **removes** that component or the mask holding it. The
  engineer tests this once, where writes are applied (compare the covered
  components before and after), not in each control, so undo and History are
  covered by the same rule as the buttons.
- **What does not cancel.** A change to anything the Update does not cover:
  another mask, a component of the same mask the Update does not cover (a
  per-component button covers one), sliders, Amount, renaming, reordering that
  leaves the component's kind, digest, operation and Invert as they were, a
  new component added, or the Update landing for a component that has not
  changed. Those keep landing through the existing match (C10's rule stays).
- **Whole Update, not part of it.** An Update over two components that is
  cancelled is cancelled for both: it is one undo step ("Update Detection"),
  and landing one of two would make the step mean something the person did not
  ask for and the caption, count and announcement say differently.
- **Effect.** Exactly the existing Cancel (§5): the change itself applies at
  once and is not delayed or undone; no result is written, no undo step or
  History entry for the Update; the old result keeps applying (with Invert or
  the operation now as the person set them); the "Detecting…" line goes and
  the caption returns to the component's previous state; no Activity entry (a
  cancel is not an error, as for Cancel). A result that was already running is
  discarded on arrival (C8 is unchanged: the request itself may run to its
  end). Nothing is queued to resume: the person can choose Update again.
- **Announcement.** Reuse the existing "Detection cancelled." (§12, no new
  string, no new localization key), posted at medium priority like Cancel's,
  and posted only when a pending Update is cancelled this way. Reason: a
  sighted person sees the "Detecting…" line disappear, but a VoiceOver user
  whose focus is on Invert or Remove hears only that control's own change,
  and an Update that quietly never happens is the silent loss C11 reports.
  If the cancelling change removed the row and its focus, the announcement is
  still posted. Nothing else is announced (the control's own state change is
  spoken by the control).
- **Why not (b), dimming.** It does not close the case: ⌘Z, Redo, History and
  deleting the mask are not controls on the row, so the same loss remains
  through them and would need the same fix. It also makes Invert and Remove
  go dim and return within 0.15 to 0.5 s (2 s the first time after a build),
  and a toggle that dims for a moment is worse than one that always answers.
  Judgment, not a quoted HIG rule (the HIG's User control principle points the
  same way: people change their mind while something is in progress, and
  the latest action should win). The existing dimming (§5, one detection at a time;
  DR-2, cropping) covers adding and starting detections, where there is a
  conflict between two detections, not edits to settings.
- **Why not (c), silence.** A change the person made would silently throw away
  work they started, which breaks the Cancel rule (§5: a halt is visible and
  has no side effect) and leaves a Detecting line that ends without result,
  Cancel or message.
- **For the engineer.** A test per case: Invert changes, operation changes,
  Remove from Mask and delete mask each cancel a covered pending Update (the
  line goes, `print masks` state is no longer `pending`, no undo step is added
  for the Update, the announcement is posted if the debug script records
  them); an Update over two components with one changed is cancelled whole; a
  change to an uncovered component, or a reorder, does not cancel and the
  Update lands. The `hang` detector (§15) holds the Update pending for these
  checks. A result arriving after the cancel is ignored. Update the user guide
  by one sentence next to Cancel: "Changing or removing a component while it
  looks again stops that too." (guide terms are unchanged).

**Open, judgment (review I1, I3):** whether touching the eye during a flash
keeps the overlay on (I1), and whether VoiceOver should hear "Detection
unchanged." after an Update that changes nothing (I3). Neither is ruled; I1 is
decided at manual check M4, as built (the eye turns the overlay off).

**Confirmed (2026-11-20, [`review.md`](review.md) Confirmation):** DR-1 to
DR-4 are built as written, apart from the one gap recorded there as N1.

## 20. Summary

The add action is one pull-down beside the five shape buttons, not three more
icons; Background is its own kind; a result is one undo step written when it
lands, with "Detecting…" and Cancel while it runs; every state has a caption
that says it selects nothing; and Update is a button only where it is the
remedy, with a menu item and ⋯ path always.
