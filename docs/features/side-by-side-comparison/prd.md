Issue: #63

# Side by side comparison

Status: Shipped, checks pending 2026-11-12, including the merge with develop (#155, #62), which the owner acknowledged the same day ([`qa.md`](qa.md): AC7's hitch count (P3), animations (P1), real mouse and trackpad (P2), menus with a key window and alert keys (P4), looks (P5) and Full Keyboard Access (P6), P7 (a copy beside its photo in a narrow window, D15) and P8 (Duplicate while comparing, D14))
Slug: side-by-side-comparison
Roadmap: none (shipped)

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
R2 (Must): Entered from a selection of two photos in the grid, or of one
photo (compared with its partner: the photo it was last compared with, else
the next comparable photo in the source). From the loupe it is entered with
the loupe's photo and its partner; the second photo is then chosen by
walking or clicking the film strip (no new gesture on the strip). Entered
with the new bare key `S` (View ▸ Compare Side by Side). Also available in
review mode. The two halves of one RAW+JPEG pair (shown as two items) are
refused with an alert, as are videos and offline photos.
R3 (Must): Exactly one photo is active, clearly marked. Culling keys (rating,
flag, label, reject) apply to the active photo only; the bare key `A`
switches the active photo (cycling to the next pane). Changes are saved and undoable as in the loupe.
R4 (Must): Zoom (fit and 100%) and pan are linked: moving one moves the
other to the same image position. Must be switchable to independent.
R5 (Must): A way to leave comparison (`S` again) back to the single loupe on
the active photo, with the rest of the window (source, view) as it was. The
grid selection on leaving is the current pair on screen, not the pair
selected when comparison began (owner decision, 2026-11-11).
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
After walking a side, leaving leaves the pair last on screen selected in the
grid; the source and view are unchanged.
AC5 (R2): Review mode can enter, use and leave comparison.
AC6 (R2): Selecting an offline photo or a video with a second photo does not
enter comparison and says why, in an alert.
AC6a (R2): With Group RAW+JPEG Pairs off, selecting the RAW and the JPEG of
one pair and choosing Compare shows an alert and does not enter comparison.
With them grouped, a pair is one photo and compares normally.
AC6b (R2): From the loupe, `S` shows the loupe's photo and its partner;
walking the right side with the arrow keys or clicking a film strip
thumbnail replaces the right photo. With one photo selected in the grid, `S`
compares it with its partner.
AC6c (R3): `A` makes the other pane active and marks it; `S` is a toggle:
pressed again it leaves comparison, and `S` once more brings back the same
pair.
AC7 (R8): Accepted by the owner 2026-11-12 (the hitch count itself is not yet
measured: the display was asleep during QA, so AC7 stays open, check P3): on the reference Mac (Apple M4 Pro, 24 GB,
60 Hz display), with two raws of 24 MP (assumed to be the owner's usual size)
at 100% and both sharp, `compare panbench 6` reports 0 hitches (a hitch is a
frame over 1.5 refresh intervals), linked and not linked. Until a picture is
sharp each pane shows its preview enlarged and panning still works. The
frames on which a full-resolution picture arrives (zooming in, walking a side
at 100%) are outside this number: measured at 99 to 155 ms, two per arrival,
input is not blocked (Proposed, pending owner; see Assumptions and Open
questions).

## Non-goals
- A comparison built for versions of one photo: no command that makes a copy
  and compares it, no listing of a photo's copies, no side-by-side of edit
  stacks. An original and its copy (#62) are two items and compare like any
  two photos (Decision 16).
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

## Decisions
Approved by the owner on 2026-11-11, accepting the proposed defaults.
1. Compares different photos, two at a time. Versions of one photo wait for #62.
2. Lives in the library window's loupe and in review mode.
3. Culling while comparing: yes, on the active photo only.
4. Zoom and pan linked by default, with an unlink switch.
5. No editing while comparing.
6. Two photos is the minimum slice; more is a Could (R9).
7. Picking: select two in the grid; walking one side against the other is a
   Should (R6).

Approved by the owner on 2026-11-11, accepting everything the designer
proposed (`design.md` §14 and §15):
8. New bare keys: `S` (Compare Side by Side / Stop Comparing) and `A`
   (switch the active side).
9. RI-1: leaving comparison keeps the current pair selected in the grid.
10. RI-2: the second photo is chosen by entering with a partner, then walking
    or clicking the film strip; no new gesture on the strip.
11. RI-3: comparing the two halves of one RAW+JPEG pair is refused with an
    alert.
12. Design assumptions accepted: other photo commands (keywords, albums,
    export, Show in Finder) act on the active photo; Remove from Album and
    Remove from Library are off while comparing; Advance After Rating
    advances the active side; the link switch is remembered across launches;
    one selected photo in the grid compares with its partner.

13. Owner, 2026-11-12, at sign-off (`qa.md` Follow-up): AC7's target is
    accepted as written (zero hitches while panning two sharp raws at 100%,
    linked and not linked, on the reference Mac); the owner's usual raw size is
    24 MP; the long frames when a full-resolution picture arrives (99 to 155 ms)
    stay outside AC7 for this slice.
14. Owner, 2026-11-12: known limitation #153 accepted. The attempt to fix it
    (design D12) was reverted because it broke linked gestures on equal
    photos. Linked, after zooming in twice with ⌘= and dragging the zoomed
    photo beside a photo at its fit, the fitted photo's zoom state can flip and
    `Z` then goes to fit instead of 100%; the next step or `Z` puts both right.
15. Design rulings D1 to D13 (`design.md` §16) are built, except D12 (reverted).
    AC6b holds as written: from the loupe, `S` makes the partner on the right
    active (D3).

16. Product manager, 2026-11-12, from Decision 1 and virtual-copies R5 (no
    new owner decision: Decision 1 deferred versions only until #62 existed,
    and #62 made a copy its own item in the grid, loupe and film strip). A
    photo and its copy enter comparison like any two photos: R1 to R7 apply
    unchanged, and a copy is never half of a RAW+JPEG pair, so R2's refusal
    does not touch it. Each side must be told apart: a copy is named as
    everywhere else in the app (its name, Copy badge) and in VoiceOver, as
    R7 asks, so the choice is clear (the designer rules on the form, review
    C15). Duplicate while comparing is not decided here: it is a design
    ruling (review C14), the requirement being that the comparison and the
    active photo never disagree (R3). Built as design D14 and D15
    (`design.md` §16): Duplicate is dimmed and absent from the pane menu while
    comparing; undo or redo of a Duplicate never moves the focus off the panes
    (an undo that removes a compared copy ends the comparison on the remaining
    photo, or on the active copy's original if both go; redo never changes a
    comparison); a copy shows its own name and the Copy badge in the caption
    and in VoiceOver (D15). Not built, not promised: any
    shortcut to compare a photo with its own copy. If the owner wants one,
    it is a new issue.

## Assumptions
None outstanding. The earlier ones (AC7's number, the 24 MP size, the arrival
frames, AC6b's active side) are decided: Decisions 13 and 15.

## Open questions
None for the owner. Checks only a person can do are open in `qa.md`
("For a person") and in issue #82.

## Revisions
- 2026-11-11: approved; owner intake defaults recorded as Decisions.
- 2026-11-11: owner approved the designer's keys `S` and `A` and RI-1 to
  RI-3 defaults (Decisions 8 to 12). R2 and R5 reworded; AC4 and AC6
  extended, AC6a to AC6c added. Open question to the designer on the switch
  key is closed.
- 2026-11-11: engineer's RI-E1 and RI-E3 answered as proposals (AC7 now
  carries the measured number and states what it excludes; both marked
  pending owner). RI-E2 left open pending DQ-3.
- 2026-11-12: Ship. Owner signed off with checks left open; Decisions 13 to 15
  record AC7's acceptance, the 24 MP size and #153; Assumptions closed. R9 (three
  or four photos) was not built.
- 2026-11-12, merge with #62: the first non-goal reworded and Decision 16
  added (a photo and its copy compare as two photos; reviews C14 and C15
  go to the designer and engineer). No requirement or criterion changed.
- 2026-11-12, Ship again: D14 and D15 built (Decision 16 now says so); the
  owner acknowledged the merged result with P1 to P8 left open (P7 and P8
  are new). No requirement or criterion changed.
