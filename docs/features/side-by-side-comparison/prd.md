Issue: #63

# Side by side comparison

Status: Draft (defaults pending the owner's answers to intake; see Assumptions)
Slug: side-by-side-comparison
Roadmap: Next

## Problem
A photographer with several near-identical shots (a burst, a bracket, three
frames of one pose) has to pick the best. The loupe shows one photo at a time,
so they flip back and forth with the arrow keys and hold the difference in
memory. Show Original (`\`) compares a photo only with its own unedited
render, never with another photo. Sharpness, expression and exposure are
exactly the things that are hard to judge from memory.

## Goal and success
Look at two photos next to each other in the loupe, at the same zoom and
position, and cull them there. Worked if the owner can take a set of similar
shots, compare pairs at 100% to check focus, and rate or reject from the
keyboard without leaving the comparison.

## Users and scenarios
- Primary: the owner selects two similar photos in the grid, enters
  comparison, zooms both to 100% on the face (one zoom moves both), decides,
  rejects the weaker one, and moves on.
- Edge: one of the two is offline, a video, or a RAW+JPEG pair. Offline and
  videos cannot be compared; a pair counts as one photo.
- Edge: window is narrow (13" laptop); two photos still have to be usable.

## Requirements
R1 (Must): Two different photos shown side by side in the loupe area, each
with its normal rendering (saved edits applied, as in the loupe).
R2 (Must): Entered from a selection of two photos in the grid, and from the
loupe by choosing a second photo. Also available in review mode.
R3 (Must): Exactly one photo is active, clearly marked. Culling keys (rating,
flag, label, reject) apply to the active photo only; a way to switch the
active photo from the keyboard. Changes are saved and undoable as in the loupe.
R4 (Must): Zoom (fit and 100%) and pan are linked: moving one moves the
other to the same image position. Must be switchable to independent.
R5 (Must): A way to leave comparison back to the single loupe on the active
photo, with the rest of the window (grid selection, source) as it was.
R6 (Should): Replace either photo with another without leaving (for
example, advance one side through the source with the arrow keys while the
other stays).
R7 (Should): Each side shows the caption values the loupe shows (name,
rating, flag, label) so the choice is clear without the inspector.
R8 (Should): Comparing never makes the window unresponsive: two photos at
100% stay scrollable. (Engineer to state what is feasible; see Open
questions.)
R9 (Could): Three or four photos at once at fit zoom.

## Acceptance criteria
AC1 (R1): With two photos selected, entering comparison shows both, each
matching what the single loupe shows for it.
AC2 (R3): Pressing a rating key changes only the active photo's rating; the
other is unchanged; undo reverts it.
AC3 (R4): Zooming to 100% on one side puts the other side at 100% on the
same relative point; turning the link off lets them differ.
AC4 (R5): Leaving comparison returns to the single loupe on the active photo.
AC5 (R2): Review mode can enter, use and leave comparison.
AC6 (R1): Selecting an offline photo or a video with a second photo does not
enter comparison and says why.
AC7 (R8): At 100% on two raws of the owner's usual size, panning stays
responsive (a number to be proposed by the engineer, marked as assumption).

## Non-goals
- Comparing versions of one photo (depends on virtual copies, #62, not yet
  specified). Design must not make it impossible later.
- Editing in the comparison. Adjust and the inspector's edit tabs are not
  offered while comparing; edit in the single loupe.
- Survey or lightbox grids of many photos, auto-grouping similar shots, or a
  "best of" suggestion.
- A second window or second display (that is #102).
- Before/after of one photo (Show Original already does that).

## Dependencies and impact
- Touches the loupe, review mode, film strip, culling commands, menus
  (`LibraryMenuContext`) and the debug script's `print`/`key` commands.
- Rendering: the loupe renders the saved edits through the preview and
  100% region paths, not live edit frames, so no new render path is
  expected; two decoded masters at 100% double the memory held for it
  (CLAUDE.md: the full-resolution copy has no cap).
- No catalog or edit-stack change; no migration. No `PreviewCacheKey` bump.
- Edit history is unaffected: comparison makes no edits.
- The film strip: needs a rule for what it shows while comparing.

## Assumptions
Unconfirmed; each is a proposed default for the owner's intake answers.
1. Compares different photos, two at a time. Versions of one photo wait for #62.
2. Lives in the library window's loupe and in review mode.
3. Culling while comparing: yes, on the active photo.
4. Zoom and pan linked by default, with an unlink switch.
5. No editing while comparing.
6. Two photos is the minimum slice; more is a Could.
7. Numeric performance target is not yet set.

## Open questions
Owner:
- Q1 What is compared: different photos, versions of one photo, or both?
  Default: different photos only.
- Q2 How many at once? Default: two.
- Q3 Where: library window, review mode, or both? Default: both.
- Q4 Cull while comparing? Default: yes, on the active photo only.
- Q5 Zoom and pan linked? Default: linked, with a switch.
- Q6 Edit while comparing? Default: no.
- Q7 How do you pick the two: select two in the grid, or pin one and walk
  the rest against it? Default: select two; walking one side is a Should (R6).
Designer: entry points, active marker, key to switch the active photo (note
bare keys such as C, Z and `\` are taken), film strip behavior, narrow windows.
Engineer: memory and speed of two 100% views on large raws, and how a
RAW+JPEG pair resolves.
