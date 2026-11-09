# Review order: code review

Owner: code-reviewer. Date: 2026-11-09. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/review-order` (PR #50), dfa0d5c..f51400c (one commit).
Build and tests: not run, as instructed. The diff is documentation and agent
prompts only (`docs/WORKFLOW.md`, the agent table in `CLAUDE.md`,
`.claude/agents/{code-reviewer,product-manager,qa-tester,swift-macos-engineer}.md`);
nothing under `Sources/`, `Tests/`, `Scripts/` or `Package.swift` changed.

No feature folder, PRD or design: the owner's four decisions, as relayed by
the main session, are the spec, and were not reviewed.

## Verdict

Not ready to merge, though nothing is a blocker. The new order is stated the
same way in every place that states it, and no sentence still says QA runs
last or that a merge can leave checks open. What needs fixing is at the end of
the new path. Ship's gate looks at a file nobody updates after a person's
checks, a check that can't be done has no way to close, and the qa-tester and
product-manager prompts don't yet cover two things the new order asks of them.
Five Should fix, five Nits.

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|----------|-------|---------|---------|------|
| C1 | Should fix | `.claude/agents/product-manager.md:47`; `docs/WORKFLOW.md:8`, `:13`, `:17`, `:23` | Ship's gate is wider than the workflow's. `product-manager.md:47`: "If a check is still open in `qa.md` or `review.md`, stop and say so: Ship waits for it." Everywhere else the list is `qa.md` alone: `WORKFLOW.md:8` "`qa.md` is the one list of what a person still has to check", `:17` "a person has done the checks `qa.md` lists", `qa-tester.md:38` "`qa.md` is the one list of what is still open". A person's results are recorded only in `qa.md` (`WORKFLOW.md:13`), qa-tester writes only that file (`qa-tester.md:8`), and no step or prompt has the designer close its M checks (`apple-ui-designer.md:80` only creates them). `:23`'s "no check left open" doesn't say which file it means. Gate on `qa.md` alone. | library-launch-guard is the case. The owner passed P1–P4 and `qa.md` maps P1–P3 to review M1–M3, in a commit that touched only `qa.md` (bf509da). Its `review.md:28-30` still reads "The manual checks M1–M3 remain for a person." Under this gate the product manager stops there, and no step in the workflow clears it. chromatic-aberration's M table reads "Confirmed by the owner" only because the Ship record commit (deda5f6) edited it, which no step asks for. M checks QA closes by script stay open in `review.md` the same way. | `WORKFLOW.md:8`; Ownership table |
| C2 | Should fix | `docs/WORKFLOW.md:13`, `:17`, `:23`; `.claude/agents/qa-tester.md:38`, `:65` | There is no way to close a check that can't be done, or one QA marks optional. Merge needs "no check left open" (`:23`) and Ship needs "a person has done the checks `qa.md` lists" (`:17`). `qa-tester.md:38` still gives "real cameras and cards, other displays, the macOS 15 path" as typical person checks, and Follow-up records only "each P item when the owner reports it done" (`:65`). | `docs/roadmap.md:111-112`: "the owner has no macOS 15 Mac". Past lists contain exactly that check (`ml-denoise/qa.md:465` P6, `sharpen-mask-preview/qa.md:194` P8, `ui-redesign/qa.md:371` P10), so a feature with one can never reach Merge. Optional checks exist too (`editor-follow-edit-drop/qa.md:325` P1, `stale-preview-after-save/qa.md:302` P2, `library-launch-guard/qa.md:220` P4), and the owner has already accepted shipping without one (`ml-denoise/prd.md:3`, P8). Each of these now either blocks the merge or is dropped with no record. "Nothing merges with checks open" is settled; what counts as a check that must be closed is not. See Question 1. | Owner's decision 4; `WORKFLOW.md:23` |
| C3 | Should fix | `docs/WORKFLOW.md:12`, `:13`, `:14`; `.claude/agents/product-manager.md:26` | The gates before the last two stages leave out design review. `WORKFLOW.md:12` and `product-manager.md:26`: "once code review and QA have no open findings"; `WORKFLOW.md:13`: "once the product manager's review has no open findings". QA only "runs after" design review (`:8`), which doesn't require its findings closed. `/security-review` (`:14`) also has no place in what `:8` calls "this order". Name design review in `:12` and `product-manager.md:26`, and say where `/security-review` falls. | Design review leaves a fix open (chromatic-aberration's had F1–F5) while code review and QA close. `:12` lets the product manager run and `:13` lets the owner do the checks. The design fix then lands, goes through `:16`, and the owner repeats the checks it affects, which is the rework that putting a person last is there to avoid. Step 5's "the reviews have no open findings" still stops the merge, so what is lost is the owner's time. | `WORKFLOW.md:8` |
| C4 | Should fix | `.claude/agents/qa-tester.md:3`, `:65`, `:70`; `docs/WORKFLOW.md:16` | The frontmatter gained the new duty ("to record a person's checks when the owner reports them"), the body did not. `WORKFLOW.md:16`: "QA's second pass says which of a person's checks the commit affects, and those are done again." Nothing in `qa-tester.md` asks for that. Follow-up (`:65`) is "each finding Fixed or Not fixed, and each P item when the owner reports it done": no failed or reopened state. The report's next step (`:70`) is always "the product manager's review and then the P list for a person … then Ship (step 5) if it applies". | (a) A fix for a failed check reaches QA's second pass. Filling in the template marks the finding Fixed while the P items the commit affects still read done from the earlier commit, so Ship's gate sees nothing open. (b) qa-tester records the owner's results, all passing, and its report names the product manager's review and the P list as next, both already done, instead of Ship. | `WORKFLOW.md:13`, `:16` |
| C5 | Should fix | `.claude/agents/product-manager.md:26`, `:35`, `:38`; `docs/WORKFLOW.md:12`, `:13` | Review mode runs before a person's checks but has no way to treat a criterion only a person can verify. It checks "every requirement and acceptance criterion" and must "Write only what the files show", with a `Delivered?` column and a verdict of "Delivers what was asked, or not". At that point QA reports those criteria as Open (`qa-tester.md:53`). Allow a third value, such as "Awaiting a person (P3)", that is not a finding. | `ml-denoise/prd.md:3`: "AC13 is P9"; `sharpen-mask-preview/qa.md:8`: "the 3 still open (AC4's drag, AC5's speech, AC13) need a person". For such an AC the product manager either writes "delivered" with no evidence, against `:26`, or records a shortfall. A shortfall is "a finding for the engineer", and `WORKFLOW.md:13` holds a person's checks until the review "has no open findings", while the only evidence that could close it is that person's check: a cycle. | `product-manager.md:26` |
| C6 | Nit | `docs/WORKFLOW.md:20`; `.claude/agents/product-manager.md:47`, `:57` | A leftover from the old Ship. "Run Ship again when a later commit changes anything Ship wrote from: … a check added or reopened in `qa.md` or `review.md`", repeated at `product-manager.md:57`. Ship no longer writes anything about checks; that sentence was removed from `:17` and from the mode's bullets. | A commit after Ship reopens P2 (`:16`). `:20` says run Ship again; `product-manager.md:47` makes it stop, since P2 is open. Once P2 is done the pass has nothing to change. The check must still be redone before the merge, but `:16` and `:23` already say so. Drop the clause in both files. | `WORKFLOW.md:17`, `:23` |
| C7 | Nit | `docs/WORKFLOW.md:57`; `.claude/agents/product-manager.md:26`, `:41`, `:138` | `WORKFLOW.md:57`: "The product manager, reviewing the result, returns **Findings** for the engineer and **Design questions** for the designer." Review mode knows only the first half: "What falls short is a finding for the engineer" (`:26`), "For the engineer" (`:41`), and the next step (`:138`) names only the engineer and the person's checks. | The build matches `design.md` but the product manager sees that `design.md` doesn't serve the requirement. The prompt offers only an engineer finding, which the engineer can't act on (`swift-macos-engineer.md:32` forbids inventing behavior the spec doesn't define). | `WORKFLOW.md:57` |
| C8 | Nit | `.claude/agents/product-manager.md:26`, `:32`; `docs/WORKFLOW.md:12`, `:17` | The `pm-review.md` header needs "`<branch>` at <commit>", and the agent has no shell. It is told to ask for the diff only: "ask the main session for the branch's diff if it did not give it to you". Step 5 tells the main session what to pass ("with the PR number (the product manager has no shell)"); step 4's bullet doesn't. | The product manager copies the commit from `qa.md`'s "Tested:" line, which can predate the head after a second pass, or leaves it out. A later "changes what the feature does" decision (`:16`) then has no reliable record of what was reviewed. Have the main session pass head commit and diff. | Agent tools |
| C9 | Nit | `.claude/agents/swift-macos-engineer.md:37` | Not updated: "Code review and QA check against it." `WORKFLOW.md:25` now says "Code review, QA and the product manager's review check against it". | The engineer writes the Bug section without knowing it is also the product manager's standard. | `WORKFLOW.md:25` |
| C10 | Nit | `docs/WORKFLOW.md:25` | The old "QA still runs last" became "QA follows code review, then the product manager's review, then a person's checks". For a bug fix that changes the UI, this leaves out the design review; `:8`, `:80`, `qa-tester.md:3` and `code-reviewer.md:79` all put QA after it. | Read alone, the paragraph lets QA run before the design review on a UI fix, so `review.md`'s M checks miss `qa.md`'s list. | `WORKFLOW.md:8` |

## Questions

1. **For the owner (from C2).** How does a check close when it can't be done
   before the merge, or QA marks it optional? For example, the macOS 15 path,
   with no macOS 15 Mac. Two ways, and the choice is yours: QA leaves such
   items out of "For a person" and they become follow-up rows, or the owner
   can waive one, with the reason recorded in `qa.md`'s Follow-up, and a
   waived check counts as closed.
2. **For the owner: Ship after the person's checks (flagged in the PR body).**
   I found no contradiction. qa-tester's record of the results (`WORKFLOW.md:13`)
   is itself a commit, so Review, checks, Ship is the order that keeps "the
   last commit on the feature branch" (`:17`) true. It agrees with all four
   decisions. Checks are made before Ship's final merge of `develop`, the same
   as every other review, and `:16` covers hand-resolved conflicts. It also
   makes C6's clause unnecessary. Yours to decide.

## Checked and fine

- **The order** reads the same in `WORKFLOW.md:8`, `:12`, `:13`, `:17`, `:23`,
  `:25`, `:78`, `:80`, `CLAUDE.md:133-134` and `:138`, the frontmatter and
  report lines of `code-reviewer.md`, `product-manager.md` and `qa-tester.md`,
  and `swift-macos-engineer.md:73`, apart from the items above. "Code review
  straight away, nothing between" is stated at `:8`, `:78`, `:80`, in
  `code-reviewer.md:3` and in `swift-macos-engineer.md:73`.
- **`apple-ui-designer.md`**, unchanged: "Your review comes before QA's" still
  holds.
- **Who records a person's results:** qa-tester, in `qa.md`'s Follow-up
  (`WORKFLOW.md:13`). That agrees with `qa-tester.md:3`, `:8` and `:65`, and
  with `product-manager.md:117`. It does not break "the only file you write".
- **A failed check:** a finding for the engineer (`:13`), then the second-pass
  chain (`:16`), and the affected checks are done again. The path is complete;
  C4 is only about the prompt carrying it out.
- **`qa.md` lists nothing for a person:** `:13`, `:17` and `:23` hold with
  nothing to do, and `:25` and `:80` say "if `qa.md` lists any" and "any
  checks". The next step is then Ship, or the merge.
- **Review mode and tools:** apart from C8, it needs only Read and Write. The
  diff request follows the same pattern as reconcile's `git log` request.
  `pm-review.md` has an Ownership row (`WORKFLOW.md:41`), the engineer's
  prompt lists it (`swift-macos-engineer.md:39`), and the reviewer-confirms
  rule (`WORKFLOW.md:16`) covers it.
- **Mode numbering:** Ship moved from 4 to 5 and nothing refers to a mode by
  number. Step numbers 1–6 are unchanged, as the PR body says.
- **"Shipped, checks pending" for existing features** holds together.
  `product-manager.md` no longer writes it, `WORKFLOW.md:23` keeps the existing
  ones, `qa-tester.md:3` still works them down, and `product-manager.md:117`
  still clears them from `qa.md`'s Follow-up. The four features that read that
  way, and `ui-redesign-onscreen-check` that holds their checks, need no edit.
- **`CLAUDE.md`:** the changed sentence and table row agree with the rest of
  the file. There are still five agents, and `docs/features/<slug>/` is still
  described as holding "reviews".
- **Stale references elsewhere:** none in `README.md` (`:147` only links the
  workflow), `.github/`, or `docs/` outside the excluded folders. The older
  step citations in `docs/roadmap.md` are dated log entries.
- **`/security-review`:** not needed. No parser, subprocess, file writing or
  network code.

## Follow-up

Second pass, 2026-11-09: `f51400c..503e57c` (one commit), this file excluded.
Build and tests: not run, as instructed. The diff is documentation and agent
prompts only.

All ten findings are fixed, and the owner's ruling on C2 is consistent
everywhere it has to be. One new Nit, C11, is the only thing still open.

| # | State | Commit | What I confirmed |
|---|---|---|---|
| C1 | Fixed | 503e57c | `product-manager.md:47` now reads "If a check is still open in `qa.md`, the one list of them, stop". No gate in `WORKFLOW.md` or the agent files names `review.md` any more (grep). |
| C2 | Fixed, by the owner's ruling | 503e57c | `WORKFLOW.md:13` and `qa-tester.md:65` carry it; see the waiver check below. Question 1 is closed. |
| C3 | Fixed | 503e57c | "once code review, any design review and QA have no open findings" in both `WORKFLOW.md:12` and `product-manager.md:26`. `/security-review` runs "before QA" (`WORKFLOW.md:14`). |
| C4 | Fixed | 503e57c | `qa-tester.md:65` says which P items new commits affect and gives Passed, Failed or Waived. `:70` is now "the first of these still to do". Trace (a): an affected P item is named and done again. Trace (b): with the owner's results all in, the first still to do is Ship or the merge. An empty P list falls through the same way. |
| C5 | Fixed | 503e57c | `product-manager.md:26`: "What only a person can verify is not a finding: mark it `Awaiting a person` with its P-number". `:38` has the column value. Such a row no longer holds up `WORKFLOW.md:13`, so the cycle is gone. |
| C6 | Fixed | 503e57c | The clause is gone from `WORKFLOW.md:20` and `product-manager.md:57`; no "reopened" remains in either (grep). |
| C7 | Fixed | 503e57c | `product-manager.md:26`: "A doubt about the design goes back as a **Design question** for the designer." The report's **Questions** line (`:137`) carries it to the main session. |
| C8 | Fixed | 503e57c | `WORKFLOW.md:12`: "the main session gives it the branch's diff and head commit". `product-manager.md:26` asks for both if they are missing. |
| C9 | Fixed | 503e57c | `swift-macos-engineer.md:37` matches `WORKFLOW.md:25`. |
| C10 | Fixed | 503e57c | `WORKFLOW.md:25`: "QA follows code review and any design review". |

**The waiver.** Consistent in all four places, with no contradiction:

- Step 4 (`WORKFLOW.md:13`) states it: only the owner waives, qa-tester records
  the waiver and the owner's reason in Follow-up, and "a waived check counts as
  done".
- Step 5 (`WORKFLOW.md:17`) and the first sentence of the Ship gate
  (`product-manager.md:47`) require that "a person has done the checks `qa.md`
  lists". That holds through "counts as done".
- The Ship gate's stop ("If a check is still open in `qa.md`") and step 6
  (`WORKFLOW.md:23`, "with no check left open") do not apply to a waived check,
  which is not open.
- A later commit that affects a waived check: `WORKFLOW.md:16` and
  `qa-tester.md:65` say affected items are done again, and only the owner
  waives, so qa-tester can't carry the waiver over. The owner does the check or
  waives it again, which is the right result.

The one place the waiver doesn't reach is `qa.md`'s acceptance table, C11.

**New finding.**

| # | Severity | Where | Finding | Failure | Rule |
|---|----------|-------|---------|---------|------|
| C11 | Nit | `.claude/agents/qa-tester.md:53`, `:70` | Follow-up now has Waived (`:65`), but the acceptance table's values are still "Result is Pass, Fail or Open." and the report's counts are still "passed by test, by script, open for a person, failed". Add a waived value to both. | An AC that depends on a waived P item, such as ml-denoise AC6 and AC7 with P6 (`ml-denoise/qa.md:465`, a Mac on macOS 15 or 26). When the owner reports, QA moves the row (`chromatic-aberration/qa.md:463`, "moved to passed by the owner's check"), but a waived row has no value to move to and stays Open. The Ship gate then finds Follow-up saying Waived and the table saying Open under "still open in `qa.md`", and the product manager has to guess which wins. | `WORKFLOW.md:13` |
