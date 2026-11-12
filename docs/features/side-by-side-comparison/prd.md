Issue: #63

# Side by side comparison

Status: Approved (owner, 2026-11-11)
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
AC7 (R8): Proposed, pending owner: on the reference Mac (Apple M4 Pro, 24 GB,
60 Hz display), with two raws of 24 MP (assumed to be the owner's usual size)
at 100% and both sharp, `compare panbench 6` reports 0 hitches (a hitch is a
frame over 1.5 refresh intervals), linked and not linked. Until a picture is
sharp each pane shows its preview enlarged and panning still works. The
frames on which a full-resolution picture arrives (zooming in, walking a side
at 100%) are outside this number: measured at 99 to 155 ms, two per arrival,
input is not blocked (Proposed, pending owner; see Assumptions and Open
questions).

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

## Assumptions
Still unconfirmed.
- The numeric performance target (AC7) is the engineer's measurement, not
  yet accepted by the owner. Default: accept it as written.
- "The owner's usual size" is taken as 24 MP, the size measured. Default
  until the owner gives their cameras' size.
- AC7 leaves out the 0.1 to 0.16 s of long frames when a full-resolution
  picture arrives. Default: accepted for this slice; the single loupe does
  the same, and a fix is its own issue.
- AC6b: which side the arrows and strip change right after `S` from the loupe
  depends on design question DQ-3 (designer ruling pending). Proposed,
  pending owner: when DQ-3 is ruled, AC6b says "the active side" if the left
  stays active on entering, or keeps "the right photo" if the right pane is
  made active. Not decided here.

## Open questions
Owner: none; Q1 to Q7 are answered under Decisions.
Designer: entry points, active marker, key to switch the active photo (note
bare keys such as C, Z and `\` are taken), film strip behavior, narrow windows.
Engineer: answered in `status.md` (speed, memory, pairs); see RI-E1 to RI-E3
and Assumptions above. Owner: accept AC7's number, give the raw size, rule on
the arrival frames.

## Revisions
- 2026-11-11: approved; owner intake defaults recorded as Decisions.
- 2026-11-11: owner approved the designer's keys `S` and `A` and RI-1 to
  RI-3 defaults (Decisions 8 to 12). R2 and R5 reworded; AC4 and AC6
  extended, AC6a to AC6c added. Open question to the designer on the switch
  key is closed.
- 2026-11-11: engineer's RI-E1 and RI-E3 answered as proposals (AC7 now
  carries the measured number and states what it excludes; both marked
  pending owner). RI-E2 left open pending DQ-3.
