Issue: #160

# Export overwrites masters: design review

Owner: apple-ui-designer. Bug fix with a UI change (`docs/WORKFLOW.md`, "Bug
fixes"): reviewed against the **Bug** section of `status.md`, the export
sheet's design (`docs/UI_REDESIGN.md` §8, `docs/features/ui-redesign/design.md`
I3 and E-rulings) and the HIG (Alerts, Writing). Branch
`bug/export-overwrites-masters`, uncommitted working tree on `cd992f9`, read
2026-11-12. Code was read, not run; I build nothing.

## Verdict

**Approved (fourth pass, 2026-11-13): the owner's sign-off finding P1 is
fixed and the new wording is ruled in R5; no open findings, manual checks M1
(updated for the new text) to M4 remain.** R5's text supersedes R1's
wording; R1 stays below as the record of the earlier decision.
Third note (2026-11-13): N1 ruled
in R4. The wording stays and nothing changes; M4 has been added. Second pass
(2026-11-12): F1 fixed and confirmed. First pass: approve with one fix
(F1). The behavior is right and the alert stays the
alert people already know: same title, same four buttons in the same order,
Keep Both still the default, Cancel still Esc. Only the message changed. Its
wording leans on the title for its subject ("2 are originals") and does not
tell people when Replace and Keep Both have become the same choice; F1 gives
the message three cases instead of two. DQ2 and DQ3 are ruled below with no
code change.

## Rulings

### R1 (DQ1): the alert's message

**Superseded by R5 (owner, sign-off P1, 2026-11-13).** The case structure
below (four cases, the plural on the partial case, no number in the "all"
cases) still holds; the exact English of the three cases with originals is
R5's.

Built: "2 are originals in the library. Originals are never replaced: with
Replace, those photos are written under numbered names. Keep Both writes every
new file under a numbered name."

What is wrong with it:

- "2 are originals" has no subject of its own. An alert's message is read
  after the title, but VoiceOver and a quick glance both meet it as a sentence
  on its own; "2 of them" ties it to the title's count in two words.
- When every file in the way is an original, the message reads as if Replace
  still did something different from Keep Both. That is exactly the case DQ2
  asks about, and the message is the place to settle it (R2).
- Three clauses joined by a colon is long for an alert. The HIG asks for a
  short message in complete sentences that helps the person choose; the colon
  sentence can become a plain "so".

Ruling: `conflictMessage` takes the clash count as well as the masters
(`conflictMessage(count:masters:)`) and has three cases. Exact English:

| Case | Message |
|---|---|
| `masters == 0` | unchanged: "Keep Both writes the new files under numbered names." |
| `0 < masters < count`, plural on `masters` | one: "1 of them is an original in the library. Originals are never replaced, so Replace writes that photo under a numbered name. Keep Both gives every new file a numbered name." other: "%lld of them are originals in the library. Originals are never replaced, so Replace writes those photos under numbered names. Keep Both gives every new file a numbered name." |
| `masters == count == 1` | "It is an original in the library. Originals are never replaced, so Replace, like Keep Both, writes the new file under a numbered name." |
| `masters == count > 1` | "They are all originals in the library. Originals are never replaced, so Replace, like Keep Both, writes the new files under numbered names." |

The two "all" cases are separate keys with no number in them (the title
already gives it), so no plural variant has to drop its argument. "Originals"
and "the library" are the terms `USER_GUIDE.md` and the other strings use;
"numbered names" matches the existing Keep Both message. Naming the buttons in
the message is fine: they are on screen beside it.

### R2 (DQ2): Replace when every file in the way is an original

**Keep Replace, keep its destructive role, change nothing but the message
(option a).**

- *Consistency.* The alert keeps one shape for every export into an occupied
  folder. Hiding Replace (b) makes the button set depend on something the
  person cannot see before the alert opens, and moves Skip Them into Replace's
  place for anyone who chooses by position or habit.
- *Safety.* The destructive role overstates the risk in this one case; it
  never understates it. Dropping it (c) would make the same button look safe
  in one export and dangerous in the next, which teaches people to ignore the
  styling. Keep Both stays the default button, so Return is the safe choice
  either way.
- *Clarity.* R1's "all" message said plainly that Replace now does what Keep
  Both does, so no one chooses Replace expecting a file to be replaced. Since
  R5 the message states the outcome instead ("Originals are never replaced,
  so the new files are written under numbered names"), which settles the same
  question without comparing buttons. R2's decision (keep Replace and its
  role) is unchanged.

### R3 (DQ3): Activity after an export that numbered photos to spare originals

**Not part of this fix.** The decision is made in the alert, and with R1 the
alert states the outcome exactly before the person chooses; the files then
appear under the names it said, and "Reveal in Finder" shows them. Activity's
existing "Exported N photos." stays true. A row would also need the policy in
the summary (under Keep Both those photos are numbered anyway and a row would
be noise), which is design and copy beyond the bug.

One case the alert never sees: a master's place that is empty (status.md
decision 1, the master deleted or moved). The export is then numbered with no
question asked. That is the right outcome and rare; it is the one argument for
an Activity note, so it goes into the follow-up below rather than this branch.

Proposed follow-up (enhancement, not on the roadmap unless product puts it
there): "Say in Activity when Replace wrote photos under numbered names to
spare originals." Body: after an export run with Replace, when
`ExportSummary.protectedMasters > 0`, add an information row before the
export's own, as `skippedMessage` does for Skip; also covers exports numbered
because a missing master's place was protected. Needs the policy carried into
`ExportSummary`.

### R4 (N1, after C5 and decision 4): exact copies counted as originals

**Keep the four messages of R1 as they are. No string, key or code changes.**
Ruled 2026-11-13 on the same uncommitted tree. (R5 has since replaced the
wording of the three messages with originals; the reasoning below applies to
R5's text unchanged: it keeps "an original in the library" and "originals in
the library", and is shorter, so the length argument holds more strongly.)

Since C5 a file whose size and SHA-256 match a catalogued master is protected
wherever it is and whatever it is called, so the alert's "originals" count
also takes in exact copies (a backup folder, say), worded "an original in the
library".

- *The app cannot tell them apart.* C5 exists because on a volume the catalog
  can't recognize, a match by content is the only way to know the master. In
  that case the master and a byte-for-byte copy look the same to the app.
  "Original or exact copy" would be a hedge that the app could never settle,
  shown in exactly the case the protection is for. A message that says "or
  maybe a copy" every time content is the evidence would muddy the case that
  matters to cover a rare one.
- *The outcome is the same, and the message is about the outcome.* An alert
  message is there to help the person choose (HIG, Alerts). Original or copy,
  Replace numbers the new file and Keep Both does too. Which category the file
  is in doesn't change that choice, so the extra words don't help anyone
  decide.
- *It is true in substance.* A file that is byte for byte identical to an
  original *is* that original's content. Calling it "an original in the
  library" can only make the app look too careful, never careless, which is the
  safe way to be wrong in a message about not destroying files.
- *Cost of changing it.* Every case would grow by about four words ("an
  original or an exact copy of one"). The partial case already has two
  sentences after the title, and the plural one/other pair would get
  awkward ("1 of them is an original or an exact copy of one"). That is four
  keys and two plural variants for each translator to redo, with a longer
  message in languages that already run 30 to 40 percent longer than English.
  The extra length also makes M1's truncation risk worse.
- *Where the detail lives.* `USER_GUIDE.md` (Export) already says that a file
  byte for byte an original is not replaced, "and it means an exact copy of an
  original (a backup) is left alone too and counted with the originals". That
  is the right place for the explanation, and it matches the UI as built.
  Requirement 9 still passes.

Revisit only if people report confusion about a backup folder (the Activity
follow-up of R3 would be the place for a fuller account, not the alert). Manual
check M4 below covers the look and the wait. It is the same check as
`status.md`'s "For a person" item 5, so QA lists it once.

### R5 (owner's sign-off finding P1): the final wording

The owner found "Replace, like Keep Both, writes…" confusing and ruled that the
comparison goes: the messages say only what happens. Replace stays on the alert
with its role (R2 unchanged). Reviewed 2026-11-13 on the uncommitted tree
(`ExportModel.conflictMessage(count:masters:)`, `Localizable.xcstrings`,
`status.md` "Owner's findings at sign-off"). **Accepted as built; no changes.**

The five messages (four keys, the partial one with two plural forms) now read:

| Case | Message | Source |
|---|---|---|
| `masters == 0` | "Keep Both writes the new files under numbered names." | unchanged |
| `0 < masters < count`, one | "%lld of them is an original in the library. Originals are never replaced, so that photo is written under a numbered name." | engineer, in the owner's style |
| `0 < masters < count`, other | "%lld of them are originals in the library. Originals are never replaced, so those photos are written under numbered names." | engineer, in the owner's style |
| `masters == count == 1` | "It is an original in the library. Originals are never replaced, so the new file is written under a numbered name." | owner |
| `masters == count > 1` | "They are all originals in the library. Originals are never replaced, so the new files are written under numbered names." | owner |

Checked against the HIG (Alerts; Writing):

- *Short, complete sentences that help the choice.* Each message with
  originals is two sentences: a fact and its consequence. That is shorter than
  R1's three-sentence partial case and drops the clause that asked the reader
  to compare two buttons. An alert's message should explain what the person
  needs to choose; the buttons (Keep Both, Replace, Skip Them) already name
  their actions, so the message no longer has to restate them. Better than R1.
- *Accuracy for every button.* "Is written under a numbered name" holds for
  Keep Both and Replace. Under Skip Them nothing is written, and under Cancel
  nothing happens; both buttons say so themselves, and the sentence reads as
  what happens when the photo is written. Acceptable: a message that hedged for
  every button would be the comparison the owner removed.
- *Subject.* "%lld of them", "It", "They" all lean on the title ("N files
  already exist in “folder”"), as R1 ruled. "It" appears only when the title
  is singular ("1 file already exists…", the title's `one` form) and "of
  them" only when `count >= 2` (`masters < count`), so the pronoun always
  agrees with the title.
- *Terms.* "original in the library", "Originals are never replaced",
  "numbered names" match `USER_GUIDE.md` (Export) and the no-originals
  message. The guide's sentence for the all case was changed in step ("the new
  files are written under numbered names") and no longer says Replace does
  what Keep Both does; nothing in `Sources/` or `Tests/` still holds the old
  wording.
- *Plural forms.* The partial key has `one` and `other` English variants on
  `%lld`, and the `one` variant keeps the argument ("1 of them is…"), which
  translators need in languages whose `one` category covers 21, 31 and so on.
  The two "all" keys carry no number. Correct.
- *Product name.* None of the five names the product. Clean-room: the
  wording is our own.
- *Comments.* Each key has a translator comment naming its case.

**Judgment, not policy: "photo" versus "file".** The partial case says "that
photo"/"those photos", the owner's two say "the new file(s)". Both are true
(the referent is the photo being exported, whose new file gets the number),
and the partial case needs "photos" to tell its subset apart from the
title's files. I would not reword it now: the difference is small and the
owner has seen the set. If it is touched again, "those new files" would match
the owner's two exactly.

**The "some" message no longer says that Keep Both numbers every new file.
Acceptable.** The message's job is to explain the surprise: some files in the
way are originals and won't be replaced. What Keep Both does is not a surprise
in this alert (it is the Finder's familiar meaning of the button, the default
action, and the no-originals message, seen on every earlier clash, says it).
The one thing a person can't infer from the buttons is that Replace won't
replace those originals, and the message still says so; the other files in the
way are replaced or numbered as their buttons say. Saying it again would bring
back the button comparison the owner ruled out. `USER_GUIDE.md` (Export) still
covers it: "keep both (the new files get numbered names)".

## Requirements checked

| # | Requirement (source) | Result |
|---|---|---|
| 1 | No original is changed whatever is chosen (Bug, Expected) | Pass (tests and S1 to S5 in `status.md`; the UI only reports it) |
| 2 | Alert title, buttons, order and roles unchanged (UI_REDESIGN §8) | Pass |
| 3 | Keep Both stays the default action, Cancel the cancel action | Pass (`ExportSheet.swift` 33 to 37) |
| 4 | With no originals in the way, the alert is exactly as before | Pass (`masters == 0` returns the old string) |
| 5 | Message says how many of the files are originals and what happens to them | Pass (F1, second pass; R5 wording, fourth pass) |
| 6 | Message is clear when every file in the way is an original (R2, R5) | Pass (R5, fourth pass) |
| 7 | Singular and plural forms in the String Catalog, through `%lld` | Pass (F1, second pass; rechecked on R5's keys) |
| 7a | No message compares Replace with Keep Both (owner, P1) | Pass (R5) |
| 8 | Results reported in Activity only, no alert after the sheet closes (ui-redesign I3) | Pass (unchanged) |
| 9 | `USER_GUIDE.md` terms match the UI ("originals", "the library", "numbered names", **Replace**, `-2`/`-3`) | Pass; after F1 the guide still reads true, no change needed |
| 10 | No borrowed strings from another photo app (clean room) | Pass |
| 11 | Message fits in the alert without truncation | Needs manual check (M1) |
| 12 | Choosing Replace with a real click writes `-2` files and leaves the originals readable | Needs manual check (M2) |

## Fixes for the engineer

- **F1.** Replace `ExportModel.conflictMessage(masters:)` with
  `conflictMessage(count:masters:)` and the four cases of R1, exact English as
  in its table. Add the new keys to `Localizable.xcstrings` by hand (the
  partial case with one/other plural on `masters`; the two "all" cases as
  plain strings), remove the built key, pass `export.conflict?.count` from
  `ExportSheet`, and have `DebugExportCommands` print the new message. A unit
  test that picks each case (0, some, all with 1, all with several) keeps the
  choice from drifting.

### F1 confirmed (second pass, 2026-11-12)

Read on the same uncommitted tree after the engineer's fix (`status.md`,
Review findings, F1). **Fixed; no open findings.**

- `ExportModel.conflictMessage(count:masters:)` switches on
  `ExportClashes.originals` (PhotoCore, `ExportNaming.swift`): `masters <= 0`
  gives `.none`, `masters < existing` gives `.some(masters)`, otherwise
  `existing == 1` gives `.theOnlyFile` and more gives `.all`. That is R1's
  four cases, with the case choice tested in PhotoCore (4 tests).
- The four English strings are R1's table word for word. `ExportSheet` passes
  `export.conflict?.count`; `DebugExportCommands` prints the message.
- `Localizable.xcstrings`: the partial case has `one` and `other` variants
  on `%lld`. The `one` variant keeps the argument ("%lld of them is an
  original…, that photo under a numbered name"), which renders R1's "1 of
  them is…" and is the better form for translators, since in some languages
  the one category also covers 21, 31 and so on. The two "all" cases are
  plain keys with no number. Every entry has a comment. None names the
  product. The built key ("…are originals in the library. Originals are never
  replaced: with Replace…") is gone from `Sources/`.
- The bundle printed all four messages from the compiled catalog (`status.md`
  T1 to T4), so the keys resolve.
- `USER_GUIDE.md` (Export) matches the UI's terms: "original in the library",
  "numbered names", **Replace** and **Keep Both** in bold, `-2` then `-3`,
  and the all-originals case ("**Replace** then does what **Keep Both**
  does"). Its "Scripting" note is consistent.

Requirements 5, 6 and 7 above now pass. 11 and 12 stay manual checks (M1 to
M3), unchanged, and already in `status.md`'s "For a person".

## Manual checks

- **M1.** Export JPEGs (Original Name) of a whole project into its own folder:
  the alert shows "They are all originals in the library. Originals are never
  replaced, so the new files are written under numbered names." under the
  title, wrapped, nothing cut off, and no mention of Replace or Keep Both.
  Repeat with one photo selected ("It is an original in the library.
  Originals are never replaced, so the new file is written under a numbered
  name."). R5's wording, which supersedes R1's.
- **M2.** In M1, click **Replace** with the mouse: new `-2` files appear in the
  Finder, the originals still open in the loupe and in Quick Look, and no
  photo shows as missing or changed. Return in the same alert chooses Keep
  Both, Esc cancels.
- **M3.** A folder with both kinds of file in the way (a template such as
  `{name}-web` exported there once, then Original Name and `{name}-web`
  together, or the photos' folder with earlier exports in it): the title
  counts all of them, the message "N of them are originals in the library.
  Originals are never replaced, so those photos are written under numbered
  names." (R5) counts only the originals, and Replace replaces the earlier
  exports and numbers the rest.
- **M4** (R4; same as `status.md` "For a person" item 5). Export with Original
  Name into a folder holding exact copies of some originals (a Finder copy of
  a project folder). The alert counts the copies with the originals using
  R5's wording. Replace writes `-2` files and leaves the copies as they were.
  With large raws, the question appears without a wait that looks like a
  hang.

## What's working

- Keeping the rule in PhotoCore so `photocli` and the app cannot disagree.
- Not adding a new alert or a new button: the protection is invisible until it
  matters, and then explained in the one place the person is deciding.
- The safe default (Keep Both) and the unchanged button order.

## Requirements issues

None. The owner's ruling (never overwrite a catalogued master) covers what the
UI says; R3's Activity row is a follow-up, not missing scope.
