## Workflow

Features move through the agents in order. Do not skip steps other than those a bug fix skips (see **Bug fixes** below), and do not do one agent's job from another.

1. **product-manager** turns an idea into requirements. It writes `docs/features/<slug>/prd.md` and maintains `docs/roadmap.md`. For a thin idea it returns questions first.
2. **apple-ui-designer** designs against the PRD, following Apple's Human Interface Guidelines. It writes `docs/features/<slug>/design.md`.
3. **swift-macos-engineer** implements against the PRD and design, writes tests for the acceptance criteria, and keeps `docs/features/<slug>/status.md` current. Its last state is **Done**: every criterion built and tested, nothing blocked.
4. **Review**, on the feature branch before merge, in this order: code review (with design review alongside it), QA, the product manager's review, a person's checks. When the engineer reports Done, the main session opens the pull request into `develop`, so CI runs on it, and starts code review straight away: nothing else comes between Done and code review. QA runs after code review and design review, so that `qa.md` is the one list of what a person still has to check.
   - **code-reviewer** reviews the branch's diff against `CLAUDE.md`'s rules and the PRD, and writes `code-review.md`.
   - **apple-ui-designer** reviews the result against `design.md` and the acceptance criteria, and writes `review.md`.
   - **qa-tester** maps every acceptance criterion to a test or a check, runs the tests and the checks the debug script can make, and writes `qa.md`. What only a person can check (including the designer's manual checks it could not script) is listed there for the owner.
   - **product-manager**, in Review mode, once code review and QA have no open findings, checks the result against `prd.md` (for a bug fix, the **Bug** section of `status.md` and its roadmap row, if any) and writes `pm-review.md`: whether the branch delivers what was asked, and what falls short.
   - **A person** (the owner) does the checks `qa.md` lists, last, once the product manager's review has no open findings and before the merge. The owner gives the main session the results and qa-tester records them in `qa.md`'s Follow-up. A check that fails is a finding for the engineer.
   - When the diff adds or changes a parser of outside files, a subprocess, file writing outside the library, or network code, the main session also runs `/security-review` on the branch (code-reviewer says when).

   Findings go to the engineer, who fixes them and updates `status.md`. The reviewer that raised a finding confirms the fix in its own file. Any commit that changes source or tests after a review, including one after Ship such as a build fix, goes back to code-reviewer for a second pass, to qa-tester as well when it changes behavior, and to the product manager's review when it changes what the feature does. QA's second pass says which of a person's checks the commit affects, and those are done again. A merge of `develop` into the branch (before Ship, say) is not such a commit when nothing in `Sources/`, `Tests/`, `Scripts/` or `Package.swift` conflicted: CI covers it. When code conflicts were resolved by hand, the second pass reviews only the resolution (`git show --remerge-diff <merge>`).
5. **Ship**, the last commit on the feature branch, once the reviews have no open findings, a person has done the checks `qa.md` lists, and CI is green. The main session first merges `develop` into the branch, so Ship writes against the current roadmap, then runs **product-manager** in Ship mode with the PR number (the product manager has no shell). It moves the feature to Shipped on the roadmap, sets the PRD's status, and brings `README.md`, `docs/features/_inventory.md` and the "Scope so far" and "Not yet" sections of `CLAUDE.md` in line with what the branch delivers. The date it records is the date of the Ship pass. The main session commits these changes to the feature branch and pushes them, so the record reaches `develop` with the merge itself and needs no pull request of its own.

   The record describes what the feature does, not a commit, and becomes true when the pull request merges; if it is closed unmerged, the record never reaches `develop`.
   - **Run Ship again** when a later commit changes anything Ship wrote from: what the feature does or its scope, a check added or reopened in `qa.md` or `review.md`, or a follow-up the reviews or `status.md` name. A build or CI fix that changes none of these leaves the record standing (it still gets its second code review, step 4).
   - **Another PR shipped first.** Merge `develop` into the branch again. Where the conflicts are in what the product manager wrote at Ship (its roadmap entries, the PRD's status, the inventory, its README lines, and `CLAUDE.md`'s "Scope so far" and "Not yet"), don't merge the two by hand: take `develop`'s side of those conflicting parts only, keep the branch's side everywhere else (the owner's other edits to `CLAUDE.md` or the README included), and run Ship again.
   - **CI on the Ship commit.** A red run gets one rerun. If it fails again it blocks the merge like any red run.
6. **Merge.** The owner merges the pull request into `develop`, with no check left open. No agent step follows the merge. Features that shipped before checks had to be done first may still read "Shipped, checks pending": those are worked down later (qa-tester, or the owner), and the product manager clears them on the roadmap and in the PRD at its next reconcile.

**Bug fixes.** A bug fix has no PRD or design, so it skips steps 1 and 2. It still gets a folder, `docs/features/<slug>/`, for `status.md` and the reviews. In place of acceptance criteria, `status.md` opens with a **Bug** section: steps to reproduce, expected and actual behavior, the root cause, and the test that fails without the fix. Code review, QA and the product manager's review check against it, and against the bug's roadmap row if it has one. Step 4 runs in full except the design review, which runs only when the fix changes the UI (against the Bug section, the design of the feature it touches, and the HIG); QA follows code review, then the product manager's review, then a person's checks if `qa.md` lists any. A bug fix is not ready to merge until all of these have run. Step 5 runs when the fix has a roadmap row or changes what the README or `CLAUDE.md` says; a fix merged without Ship is recorded at the product manager's next reconcile.

### Ownership

| File | Owner | Others |
|------|-------|--------|
| `docs/roadmap.md` | product-manager | read-only (designer may set a feature to Designed) |
| `README.md` | product-manager, updated at Ship | the engineer notes changes to requirements, build commands or repository layout in `status.md` under **README**; others read-only |
| `CLAUDE.md` "Scope so far" and "Not yet" | product-manager, updated at Ship | the rest of `CLAUDE.md` belongs to the owner; agents propose changes in their report |
| `docs/features/_inventory.md` | product-manager | read-only |
| `docs/features/<slug>/prd.md` | product-manager | read-only |
| `docs/features/<slug>/design.md` | apple-ui-designer | read-only |
| `docs/features/<slug>/review.md` | apple-ui-designer | read-only |
| `docs/features/<slug>/status.md` | swift-macos-engineer | read-only |
| `docs/features/<slug>/code-review.md` | code-reviewer | read-only |
| `docs/features/<slug>/qa.md` | qa-tester | read-only |
| `docs/features/<slug>/pm-review.md` | product-manager | read-only |
| `docs/USER_GUIDE.md` | swift-macos-engineer, updated in the same change as the behavior it describes | apple-ui-designer checks its terms at review; others read-only |

Slugs are kebab-case. A whole-app redesign is a feature: `docs/features/ui-redesign/`.

Statuses: the roadmap uses Idea, Specified, Designed, In progress, Shipped, Dropped. `status.md` uses Not started, In progress, Done, Blocked, Deferred; Shipped is recorded only on the roadmap and in the PRD, by the product manager at Ship.

The phase plans in `docs/archive/` and `docs/UI_REDESIGN.md` are the historical record of work done before this workflow. Link to them by their real path (`docs/archive/PHASE6_PLAN.md`); do not add to them.

### Questions go back to the owner

Agents cannot call each other, so the main session relays.

- The engineer returns **Design questions** for the designer and **Requirements issues** for the product manager.
- The designer returns **Requirements issues** for the product manager.
- The code reviewer and QA tester return **Findings** for the engineer, and **Design questions** or **Requirements issues** when a finding is really about the spec.
- The product manager, reviewing the result, returns **Findings** for the engineer and **Design questions** for the designer.
- The main session takes each to the owning agent, which records the ruling in its own file. Then resume the agent that was blocked.
- No agent resolves another agent's question by guessing. If the owner (the human) is needed, ask them.

### Build

- `swift build` and `swift test`.
- `Scripts/build-app.sh` assembles the `.app` bundle.
- There is no Xcode project. Do not use `xcodebuild` or SwiftUI previews to verify work.
- UI checks run the bundle with `--debug-script` (see `CLAUDE.md`), against a copy of the bundle with its own bundle identifier and a scratch library from `photobench`, so they never touch the owner's library or preferences. Every launch passes `--library-root`: the identifier separates preferences only, and a launch without it (including a bare `open` of the bundle to bring it forward) opens the owner's library.

### Rules

- Requirements live in `prd.md` (for a bug fix, the **Bug** section of `status.md`), UI decisions in `design.md`, progress in `status.md`. Not in code comments or chat.
- Every acceptance criterion, and a bug fix's Bug section, maps to a test or an explicit manual check, and `qa.md` says which.
- Prefer system components. Custom chrome needs a written justification in `design.md`.
- Keep the roadmap's Now column to three items or fewer. A feature In progress is in Now: to start one, move something out.
- Treat `.claude/agents/` files like source code: changes go through review.

### Typical session

Start a feature by asking the product-manager agent to take the idea. After the PRD exists, ask apple-ui-designer to design it. When `design.md` is done, ask swift-macos-engineer to implement. When `status.md` says Done, open the pull request and start code-reviewer straight away, with the designer review alongside it, then qa-tester, and send their findings back to the engineer. Then run product-manager in Review mode, and the owner does the checks `qa.md` lists. When the reviews and those checks are closed and CI is green, merge `develop` into the branch, run product-manager in Ship mode with the PR number and commit its changes to the branch; then the owner merges.

For a bug fix, ask swift-macos-engineer to fix it. When `status.md` says Done, open the pull request and start code-reviewer straight away (and the designer review if the UI changed), then qa-tester, then product-manager in Review mode, then the owner does any checks `qa.md` lists. Run Ship if the fix has a roadmap row or changes what the README or `CLAUDE.md` says; then the owner merges.
