# Library launch guard: designer review

Owner: apple-ui-designer. Date: 2026-11-07. Step 4 of `docs/WORKFLOW.md`,
for a bug fix that changes the UI (it adds an alert).

**What was reviewed.** `bug/library-launch-guard` at `09ad984`. A bug fix
has no `prd.md` or `design.md`, so the review is against:

- the **Bug** section of [`status.md`](status.md), the owner's rulings of
  2026-11-07 (rulings 2 and 4 decide what is on screen);
- the HIG, [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)
  (read on 2026-11-07);
- the app's alert conventions (`QuitGuard`, the preset delete alerts, the
  catalog failure view in `PhotoApplication.swift`);
- the terms in `docs/USER_GUIDE.md`, "Development options".

**How.** I read the code; I did not run it. Verdicts come from
`Sources/PhotoApp/AppLauncher.swift`, the String Catalog, the user guide and
the debug-script results recorded in status.md (D2–D4). Items marked
"on screen" need a person at the bundled app.

## Verdict

**The alert is the right control, in the right form, shown to the right
people. One low fix: the message (DQ2, ruled below). Nothing blocks the
merge.**

**Update, 2026-11-07: F1 is fixed (`fa7a67a`) and confirmed; see "Fix
confirmation". No open findings. The manual checks M1–M3 remain for a
person.**

The alert is a standard `NSAlert`, app-modal, before any window exists. It
has a title-style fragment as its title, the reason and the remedy in the
message, and one verb button that says what happens. Scripted launches get
standard error only (ruling 4). It keeps the default style, so it shows the
app icon and no caution badge, which is correct: nothing is at risk, because
the guard has already protected the library.

## DQ2 ruling: the alert's copy

| Part | As built | Ruling |
|---|---|---|
| Title | Can't Open the Library | **Keep.** |
| Message | Test copies of %@, and launches with --debug-script or --benchmark-scroll, must be started with --library-root <folder>. Nothing was opened. | **Change** to: `Test copies of %@ must be started with --library-root <folder>. Your library wasn't opened.` |
| Button | Quit | **Keep.** |
| Style | default (`.warning`) | **Keep.** Don't set `.critical`. |

Why:

- **Drop the scripted flags.** Since ruling 4, nobody who passed
  `--debug-script` or `--benchmark-scroll` sees this alert. The clause is
  still true, but it lengthens the one sentence the reader needs and points
  to cases that aren't theirs. HIG: "Include informative text only if it
  adds value… keep it as short as possible." Scripted launches already have
  the standard-error line and the user guide.
- **"Your library wasn't opened" instead of "Nothing was opened."** The
  reader's real worry is the incident this fix exists for: did a test copy
  just touch my library? "Nothing was opened" can be read as "no window
  opened", which the reader can already see. Naming the library answers the
  question they have. Straight apostrophe, as in every other string in the
  catalog.
- **"Test copies"** is the guide's own term ("without this a test copy would
  open your library"). It covers a re-identified bundle exactly and a
  `swift run` executable well enough; the standard-error line gives the
  precise reason (identifier or no identifier) to anyone in a shell.
- **The title stays.** It is a fragment in title-style capitalization with
  no ending punctuation, as the HIG asks. It states the outcome in the same
  words the app already uses when the library isn't open. A deliberate
  refusal is not a catalog failure, but the message says why at once, and a
  second, near-synonymous title would give translators two strings for one
  meaning. "Can't" for a refusal by policy is ordinary macOS usage.
- **Quit stays.** It is a one-word verb that says what the button does
  ("describes the result of selecting the button"), and the alert has no
  other outcome, so it is not "OK" (which the HIG reserves for purely
  informational alerts) and not "Cancel" (nothing is cancelled). As the only
  button it is the default, so Return answers it.
- **Default style.** The HIG says to use a caution symbol only "when extra
  attention is really needed, as when confirming an action that might
  result in unexpected loss of data". Nothing here can lose data.
  `.warning` and `.informational` look the same on current macOS (the app
  icon), so leaving the default is right.
- **Audience.** Only developers and testers see this alert, so the
  command-line option in the message is the actionable content, not jargon.
  The `<folder>` placeholder is a common convention for them.

## Design checks

| # | Requirement | Source | Result |
|---|---|---|---|
| R1 | A test launch without `--library-root`, started by a person, shows an alert saying `--library-root` is required, then quits | Ruling 2 | Pass (code: `refuse` shows the alert, then `exit(EX_USAGE)`); on screen: M1 |
| R2 | A scripted refused launch (`--debug-script`, `--benchmark-scroll`) shows no alert, writes to standard error, exits 64 | Ruling 4 | Pass (code: `guard showsAlert else { exit(EX_USAGE) }`; D3, D4 in status.md) |
| R3 | The alert appears before any library window or menu bar of the app; nothing of the app shows behind it | Ruling 2 | Pass (code: `PhotoApplication.main()` is never reached); on screen: M1 |
| R4 | The alert comes to the front when started from Finder or `open` | HIG, Alerts (people must see it); D2 | Pass (code: `.regular` policy and `activate()` before `runModal`); on screen: M1, M3 |
| R5 | Title: a specific fragment, title-style capitalization, no ending punctuation | HIG, Alerts, Content | Pass |
| R6 | Message: short, complete sentences, says what to do | HIG, Alerts, Content | Was **Fail, low: F1** (the scripted-flags clause and "Nothing was opened"); **Pass** after `fa7a67a` |
| R7 | One button, a verb that describes the result, default (Return) | HIG, Alerts, Buttons | Pass |
| R8 | No caution symbol or critical style | HIG, Alerts, macOS | Pass |
| R9 | Startup alert is a justified exception | HIG: "Avoid showing an alert when your app starts" | Pass as a conscious tradeoff: no window will ever exist, the app must quit, a Finder launch has no visible standard error, and the alert is actionable. It is the only signal a person who double-clicked the copy would get |
| R10 | Strings in the catalog; the product name only through `%@` from `AppBranding.displayName` | `CLAUDE.md`, Naming rules | Pass (both new keys present; title key reused) |
| R11 | Catalog comments give translators the context they need | `CLAUDE.md`, Naming rules | Was **Fail, low: part of F1** (the reused title's comment names only the catalog failure view; the message comment doesn't say the option name stays as is); **Pass** after `fa7a67a` |
| R12 | Terms match `docs/USER_GUIDE.md` "Development options" | WORKFLOW step 4 | Pass: "test copy", "test launch", "alert", status 64 and "before it opens or creates anything" all agree with the alert and the code. The guide needs no change for F1 |
| R13 | The alert is read correctly by VoiceOver | HIG, Accessibility | Needs manual check: M2 (a standard `NSAlert`, so expected to pass) |
| R14 | Clean room: no borrowed names, strings or layout | `CLAUDE.md` | Pass |

## Fixes for the engineer

- **F1 (low). Alert message and catalog comments.** Fixed in `fa7a67a`;
  confirmed below.
  1. Replace the message key and value in
     `Sources/PhotoUI/Resources/Localizable.xcstrings` and the literal in
     `AppLauncher.refuse` with:

     `Test copies of %@ must be started with --library-root <folder>. Your library wasn't opened.`

     In Swift: `"Test copies of \(AppBranding.displayName) must be started with --library-root <folder>. Your library wasn't opened."`
     Remove the old key.
  2. Message comment: `Alert when a test copy is started without --library-root; the app quits after it. Keep --library-root <folder> as is: it is a command-line option.`
  3. Title `Can't Open the Library`: change its comment, in the catalog and at
     both call sites (`AppLauncher.refuse` and `LibraryErrorView`, which uses
     the key without one), to `Title when the library isn't opened: the
     catalog failure view, and the alert when a test copy is started without
     --library-root`. Keep the key and value. If the catalog compiler or
     `LocalizationTests` require one comment per key, the catalog's comment
     is the one that counts.
  4. Update the M1 wording in `status.md` if it quotes the message.

## Fix confirmation (2026-11-07, `fa7a67a`)

Read in the source, the String Catalog and `status.md`; not run (the
engineer's third run in status.md shows the bundle's `Localizable.strings`
has the new message and not the old one).

| Fix | Result |
|---|---|
| F1.1 Message | **Confirmed.** `AppLauncher.refuse` and the catalog key and value both read `Test copies of %@ must be started with --library-root <folder>. Your library wasn't opened.` (the Swift literal interpolates `AppBranding.displayName`). The old key is gone from the catalog and from `Sources/`. |
| F1.2 Message comment | **Confirmed.** Catalog and call site carry the comment as written in F1.2. |
| F1.3 Title comment | **Confirmed.** The catalog, `AppLauncher.refuse` and `LibraryErrorView` all carry the shared comment; key and value unchanged. |
| F1.4 Status wording | **Confirmed.** status.md's "The fix" and M1 quote the new message, and its DQ2 entry records the ruling. My M1, M2 and M3 are its M1, M3 and M4, worded as here. Its M2 (release identifier with `--debug-script`) is the engineer's own optional check. |

**`LibraryErrorView` change.** To carry the comment, `Label("…",
systemImage:)` became `Label { Text("…", comment:) } icon: {
Image(systemName:) }`. The two forms build the same `Label`: the same
localized title, looked up in the main bundle as before, and the same
`exclamationmark.triangle` symbol, which `ContentUnavailableView` styles the
same way. Nothing on screen changes, so this needs **no on-screen check**.
(The view shows only when the catalog fails to open, which is hard to bring
about safely, and a check would show nothing a reading doesn't.)

**I1** was not taken, by the owner's main session decision (status.md,
"Review findings"). That is fine: it was a judgment call, not a finding.

## Improvements (judgment, not required)

- **I1. Escape.** With one button titled Quit, `NSAlert` gives Escape to no
  button, so only Return or a click answer the alert. The HIG suggests
  other ways to dismiss an alert "when it makes sense", and here every
  answer means quit. `QuitGuard` already maps Escape with a local monitor;
  the same few lines would work here. Low value for a developer-only alert,
  so leave it unless the code is being touched anyway.

## What's working

- Reusing the system `NSAlert` rather than a custom window: it gets the app
  icon, VoiceOver, layout and the current design for free.
- The alert appears only for launches a person started. A shell script can't
  answer an alert, and standard error is where it would look.
- Activating the app before `runModal` means a double-clicked copy doesn't
  hide its alert behind Finder.
- No caution badge, no destructive styling, no "OK": the alert tells the
  reader what happened and what to do, and stops.

## Manual checks

Each runs a `.debugtest` copy (or `swift run`) **without**
`--library-root`, which is what the guard refuses. To be doubly safe, note
the modification times of `~/Library/Application Support/<app folder>/Library`
before and after, as status.md M1 suggests. Run them after F1.

- **M1.** (Same as status.md M1, with the new copy.) `open -n <copy>` with
  no `--args`. Expect the alert in front of other windows, with the app's
  icon, the title "Can't Open the Library", the message from F1 on two or
  three lines without truncation, and one accent-colored Quit button.
  Return quits; clicking Quit quits. No library window and no app menus
  appear; the Dock icon goes away after Quit.
- **M2.** With VoiceOver on (⌘F5), repeat M1. VoiceOver should read the
  title, then the message, and land on Quit. Turn VoiceOver off after.
- **M3.** From Terminal, `swift run PhotoApp` (no bundle identifier) with no
  arguments. Expect the standard-error line in Terminal, the alert visible
  (in front, or reachable from its Dock icon if macOS declines to activate a
  process started from a shell), and exit status 64 after Quit
  (`echo $?`).
