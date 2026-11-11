## Issues

Every feature and every bug is a GitHub issue before any work on it starts. The issue is the one record of what the work is and whether it is done; `docs/roadmap.md` only orders the open ones (see the **Roadmap** bullet below). Specs, designs, status and reviews stay in `docs/features/<slug>/`.

- **Who creates it.** The main session, with `gh issue create`, as soon as the owner names a feature or a bug. Agents without a shell (product-manager, apple-ui-designer) return the title, labels and body they propose, and the main session files them. Look for an existing issue first (`gh issue list --search`); never open a second one for the same thing.
- **Labels.** Exactly one of `enhancement` (feature) or `bug`. `on-roadmap` while the item is in Now, Next or Later in `docs/roadmap.md`. `needs-prd` on a feature until its PRD is approved; the main session removes it then. Bugs never carry `needs-prd`: a bug fix has no PRD (see **Bug fixes**).
- **Body.** The problem in a few sentences, where it came from, and the slug. The slug is the kebab-case name of its folder `docs/features/<slug>/`; the issue links the folder once it exists, and `prd.md` and `status.md` name the issue number on their first lines (`Issue: #N`).
- **Closing.** The pull request description says `Closes #N`, so the merge closes the issue. After the merge the main session removes `on-roadmap` if it is still there. Dropped work is closed as not planned with the `wontfix` label and a comment giving the reason.
- **Roadmap.** `docs/roadmap.md` is the vision, principles and three lists, Now, Next and Later, each item a line linking its issue, in priority order, plus the Dropped table. It carries no per-item narrative and no Shipped list: the closed issues are that record. A change in order or in what is on it is a roadmap change by the product manager, and the issue's `on-roadmap` label follows it. The roadmap as it stood before issues is kept in `docs/archive/ROADMAP_2026-11-10.md`.
- **Follow-ups.** A follow-up named by a review, QA or Ship is a new issue (a bug or an enhancement, `on-roadmap` if it is going on the roadmap), not a row in a file. The agent that names it gives the main session its title and body.
- **Checks left open at sign-off** stay in `qa.md`'s "For a person" list and are named in the pull request; they are also added to the standing manual-checks issue (#82, slug `ui-redesign-onscreen-check`).

## Workflow

Features move through the agents in order. Do not skip steps other than those a bug fix or a docs and process change skips (see **Bug fixes** and **Docs and process changes** below), and do not do one agent's job from another.

1. **product-manager** turns an idea into requirements. It writes `docs/features/<slug>/prd.md` and maintains `docs/roadmap.md`. For a thin idea it returns questions first. The GitHub issue exists before it starts (see **Issues**); the PRD names it.
2. **apple-ui-designer** designs against the PRD, following Apple's Human Interface Guidelines. It writes `docs/features/<slug>/design.md`.
3. **swift-macos-engineer** implements against the PRD and design, writes tests for the acceptance criteria, and keeps `docs/features/<slug>/status.md` current. Its last state is **Done**: every criterion built and tested, nothing blocked.
4. **Review**, on the feature branch, on this Mac. There is no pull request yet: pushing the branch is fine (it runs no CI), and the reviewers build, test and read the diff against `develop` locally. Code review and design review can run together; QA runs last, after both, so that `qa.md` is the one list of what a person still has to check.
   - **code-reviewer** reviews the branch's diff against `CLAUDE.md`'s rules and the PRD, and writes `code-review.md`.
   - **apple-ui-designer** reviews the result against `design.md` and the acceptance criteria, and writes `review.md`.
   - **qa-tester** maps every acceptance criterion to a test or a check, runs the tests and the checks the debug script can make, and writes `qa.md`. What only a person can check (including the designer's manual checks it could not script) is listed there for the owner.
   - When the diff adds or changes a parser of outside files, a subprocess, file writing outside the library, or network code, the main session also runs `/security-review` on the branch (code-reviewer says when).

   Findings go to the engineer, who fixes them and updates `status.md`. The reviewer that raised a finding confirms the fix in its own file. Any commit that changes source or tests after a review, including one after Ship such as a CI fix, goes back to code-reviewer for a second pass, to the designer when it changes the UI, and to qa-tester when it changes behavior. A merge of `develop` into the branch (before Ship, say) is not such a commit when nothing in `Sources/`, `Tests/`, `Scripts/` or `Package.swift` conflicted: the full run before Ship and CI cover it. When code conflicts were resolved by hand, the second pass reviews only the resolution (`git show --remerge-diff <merge>`).
5. **Sign-off**, once the reviews have no open findings. The main session gives the owner `qa.md`'s "For a person" list and an exact command that builds the bundle and runs it with `--library-root` on a scratch library from `photobench`. The owner may use a copy of their own photos, or their real library, by choice; a branch's migrations can't be undone on it. The owner does the checks they want, and either signs off or sends back what they found. They may sign off with checks left open by naming them. Nothing goes further without the owner's explicit go-ahead.

   What the owner finds goes to the engineer, who records it in `status.md` and fixes it; it takes step 4's second pass, and comes back to the owner to sign off that change. New scope isn't added to the branch: it goes to the product manager as a Requirements issue. The main session relays the final result to **qa-tester**, which records the sign-off, the commit signed off, its date and any checks left open in `qa.md`'s Follow-up, and commits nothing itself; the main session commits it.
6. **Ship**, the last commit on the feature branch, after the sign-off. The main session first merges `develop` into the branch and runs the full `swift test` and `Scripts/build-app.sh all` on the result, so Ship writes against the current roadmap and the branch is known to work here. A failure there goes to the engineer as a finding, and code conflicts resolved by hand take step 4's second pass, before Ship runs. The full run repeats after any such fix, and a fix that changes behavior goes back to the owner. The main session then runs **product-manager** in Ship mode. The product manager takes the feature off the roadmap's lists (the issue closes with the pull request), sets the PRD's status, and brings `README.md`, `docs/features/_inventory.md` and the "Scope so far" and "Not yet" sections of `CLAUDE.md` in line with what the branch delivers. The record carries the date of the Ship pass and a link to the feature folder; the pull request does not exist yet, and its number stays findable from the merge commit. Checks left open at sign-off are recorded as "Shipped, checks pending" in the PRD's status line, with a link to `qa.md`, and added to the standing manual-checks issue, never dropped. Follow-ups the product manager names go back to the main session as proposed issues. The main session commits these changes to the feature branch.

   The record describes what the feature does, not a commit, and becomes true when the pull request merges; if the branch never merges, the record never reaches `develop`.
   - **Run Ship again** when a later commit changes anything Ship wrote from: what the feature does or its scope, a check opened or closed in `qa.md` or `review.md`, or a follow-up the reviews or `status.md` name. A build or CI fix that changes none of these leaves the record standing (it still gets its second code review, step 4).
   - **Another PR shipped first.** Merge `develop` into the branch again. Where the conflicts are in what the product manager wrote at Ship (its roadmap edits, the PRD's status, the inventory, its README lines, and `CLAUDE.md`'s "Scope so far" and "Not yet"), don't merge the two by hand: take `develop`'s side of those conflicting parts only, keep the branch's side everywhere else (the owner's other edits to `CLAUDE.md` or the README included), and run Ship again.
7. **Pull request.** The main session pushes the branch and opens the one pull request into `develop`, with everything already on it and `Closes #N` in its description. CI runs here, on macOS 26 and on macOS 15, which nothing before this step has covered. `swift test` retries itself once when it dies on signal 11, the known runner crash (issue #77). A red run that remains gets one rerun. If it fails again it blocks the merge: the fix goes to the engineer and through step 4's second pass, and back to the owner only if it changes behavior.
8. **Merge.** The owner merges the pull request into `develop` once CI is green. No agent step follows the merge. Checks left open are worked down later (qa-tester, or the owner), and the product manager clears them in the PRD and the standing manual-checks issue at its next reconcile.

**Bug fixes.** A bug fix has no PRD or design, so it skips steps 1 and 2, but it still starts as a GitHub issue (label `bug`). It still gets a folder, `docs/features/<slug>/`, for `status.md` and the reviews. In place of acceptance criteria, `status.md` opens with a **Bug** section: steps to reproduce, expected and actual behavior, the root cause, and the test that fails without the fix. Code review and QA check against it, and against the bug's issue. Step 4 runs in full except the design review, which runs only when the fix changes the UI (against the Bug section, the design of the feature it touches, and the HIG); QA still runs last. A bug fix is not ready for a pull request until code review, QA and the owner's sign-off are done. Step 6 runs when the fix is on the roadmap or changes what the README or `CLAUDE.md` says; a fix that skips Ship still takes step 6's merge of `develop` and full run before its pull request, and is recorded at the product manager's next reconcile.

**Docs and process changes.** A change with no app behavior (the roadmap, docs, `.claude/`, CI) has no PRD, design, QA, sign-off or Ship. It goes on a branch and straight to a pull request, and the owner's merge is the sign-off. It gets code review only when it touches `.claude/agents/`, `docs/WORKFLOW.md` or CI. When a change touches only `docs/`, Markdown files or `.claude/`, CI reports success on both required checks without building.

### Ownership

| File | Owner | Others |
|------|-------|--------|
| `docs/roadmap.md` | product-manager | read-only |
| GitHub issues (titles, labels, bodies) | main session, from what the agents propose | agents read them with the issue number; never edit them |
| `README.md` | product-manager, updated at Ship | the engineer notes changes to requirements, build commands or repository layout in `status.md` under **README**; others read-only |
| `CLAUDE.md` "Scope so far" and "Not yet" | product-manager, updated at Ship | the rest of `CLAUDE.md` belongs to the owner; agents propose changes in their report |
| `docs/features/_inventory.md` | product-manager | read-only |
| `docs/features/<slug>/prd.md` | product-manager | read-only |
| `docs/features/<slug>/design.md` | apple-ui-designer | read-only |
| `docs/features/<slug>/review.md` | apple-ui-designer | read-only |
| `docs/features/<slug>/status.md` | swift-macos-engineer | read-only |
| `docs/features/<slug>/code-review.md` | code-reviewer | read-only |
| `docs/features/<slug>/qa.md` | qa-tester | read-only |
| `docs/USER_GUIDE.md` | swift-macos-engineer, updated in the same change as the behavior it describes | apple-ui-designer checks its terms at review; others read-only |

Slugs are kebab-case. A whole-app redesign is a feature: `docs/features/ui-redesign/`.

Statuses: an issue's state is its labels and whether it is open (`needs-prd` is Idea; a PRD, design and `status.md` in the folder say how far it has come; closed is Shipped). `status.md` uses Not started, In progress, Done, Blocked, Deferred; Shipped is recorded in the PRD's status line, by the product manager at Ship, and by closing the issue.

The phase plans in `docs/archive/` and `docs/UI_REDESIGN.md` are the historical record of work done before this workflow. Link to them by their real path (`docs/archive/PHASE6_PLAN.md`); do not add to them.

### Questions go back to the owner

Agents cannot call each other, so the main session relays.

- The engineer returns **Design questions** for the designer and **Requirements issues** for the product manager.
- The designer returns **Requirements issues** for the product manager.
- The code reviewer and QA tester return **Findings** for the engineer, and **Design questions** or **Requirements issues** when a finding is really about the spec.
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
- Keep the roadmap's Now list to three items or fewer. A feature In progress is in Now: to start one, move something out.
- Treat `.claude/agents/` files like source code: changes go through review.

### Typical session

Start a feature by filing its GitHub issue (`enhancement`, `needs-prd`), then asking the product-manager agent to take the idea. After the PRD exists, ask apple-ui-designer to design it. When `design.md` is done, ask swift-macos-engineer to implement. When `status.md` says Done, run code-reviewer and the designer review, then qa-tester, and send their findings back to the engineer. When the reviews are closed, give the owner the list of checks and wait for their sign-off. Then merge `develop` into the branch, run the full tests and the bundle build, run product-manager in Ship mode and commit its changes to the branch. Only then push and open the pull request; the owner merges when CI is green.

For a bug fix, file the issue (`bug`), then ask swift-macos-engineer to fix it. When `status.md` says Done, run code-reviewer (and the designer review if the UI changed), then qa-tester, and get the owner's sign-off. Then merge `develop` into the branch and run the full tests and the bundle build, whether or not Ship applies. Run Ship if the fix is on the roadmap or changes what the README or `CLAUDE.md` says. Then push and open the pull request; the owner merges when CI is green.
