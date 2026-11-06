## Workflow

Features move through the agents in order. Do not skip steps, and do not do one agent's job from another.

1. **product-manager** turns an idea into requirements. It writes `docs/features/<slug>/prd.md` and maintains `docs/roadmap.md`. For a thin idea it returns questions first.
2. **apple-ui-designer** designs against the PRD, following Apple's Human Interface Guidelines. It writes `docs/features/<slug>/design.md`.
3. **swift-macos-engineer** implements against the PRD and design, writes tests for the acceptance criteria, and keeps `docs/features/<slug>/status.md` current. Its last state is **Done**: every criterion built and tested, nothing blocked.
4. **Review**, on the feature branch before merge. Code review and design review can run together; QA runs after the design review, so that `qa.md` is the one list of what a person still has to check.
   - **code-reviewer** reviews the branch's diff against `CLAUDE.md`'s rules and the PRD, and writes `code-review.md`.
   - **apple-ui-designer** reviews the result against `design.md` and the acceptance criteria, and writes `review.md`.
   - **qa-tester** maps every acceptance criterion to a test or a check, runs the tests and the checks the debug script can make, and writes `qa.md`. What only a person can check (including the designer's manual checks it could not script) is listed there for the owner.
   - When the diff adds or changes a parser of outside files, a subprocess, file writing outside the library, or network code, the main session also runs `/security-review` on the branch (code-reviewer says when).

   Findings go to the engineer, who fixes them and updates `status.md`. The reviewer that raised a finding confirms the fix in its own file.
5. **Merge.** The owner merges the pull request into `develop`.
6. **Ship**, after the merge. The main session runs **product-manager** in Ship mode, giving it the PR number and merge commit (the product manager has no shell). It moves the feature to Shipped on the roadmap, sets the PRD's status, and brings `README.md` and the "Scope so far" and "Not yet" sections of `CLAUDE.md` in line with what shipped. Checks still open in `qa.md` or `review.md` are recorded as "Shipped, checks pending" with a link, never dropped.

A bug fix without a feature folder skips steps 1, 2 and 6 unless it changes what the README or `CLAUDE.md` says; it still gets code review.

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
| `docs/USER_GUIDE.md` | swift-macos-engineer, updated in the same change as the behavior it describes | apple-ui-designer checks its terms at review; others read-only |

Slugs are kebab-case. A whole-app redesign is a feature: `docs/features/ui-redesign/`.

Statuses: the roadmap uses Idea, Specified, Designed, In progress, Shipped, Dropped. `status.md` uses Not started, In progress, Done, Blocked, Deferred; Shipped is recorded only on the roadmap and in the PRD, because the engineer does not run after a merge.

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
- UI checks run the bundle with `--debug-script` (see `CLAUDE.md`), against a copy of the bundle with its own bundle identifier and a scratch library from `photobench`, so they never touch the owner's library or preferences.

### Rules

- Requirements live in `prd.md`, UI decisions in `design.md`, progress in `status.md`. Not in code comments or chat.
- Every acceptance criterion maps to a test or an explicit manual check, and `qa.md` says which.
- Prefer system components. Custom chrome needs a written justification in `design.md`.
- Keep the roadmap's Now column to three items or fewer. A feature In progress is in Now: to start one, move something out.
- Treat `.claude/agents/` files like source code: changes go through review.

### Typical session

Start a feature by asking the product-manager agent to take the idea. After the PRD exists, ask apple-ui-designer to design it. When `design.md` is done, ask swift-macos-engineer to implement. When `status.md` says Done, run code-reviewer and the designer review, then qa-tester, and send their findings back to the engineer. After the owner merges, run product-manager in Ship mode.
