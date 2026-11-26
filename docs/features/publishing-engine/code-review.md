# Publish to Immich: code review

Owner: code-reviewer. Date: 2026-11-26. Step 4 of `docs/WORKFLOW.md`.
Reviewed: `feature/publishing-engine`, a58d943..b244b48 (12 commits). Build and
tests: `swift build --build-tests` clean; `swift test` 1620 tests in 226 suites
passed (95.4 s); the five connection and publishing suites (`Publishing runs`,
`Publishing boundaries`, `Immich check and allowlist`, `Immich connections`,
`Remote session…`, 41 tests) passed 30 of 30 runs with `--skip-build`.

## Verdict

Not ready for QA yet. The engine's core (allowlist, the four writes, the album
and stack rules, records, the ending rule) is sound and well tested, but six
should-fix findings remain: a person's Stop loses its "ending" state as soon as
another photo reports progress (C1), a second run can start while Retry Failed
is connecting (C2), Export's watermark issue no longer clears (C3, a regression
in a feature this PRD says is unchanged), a virtual copy of a paired raw stacks
on the JPEG's asset rather than its original's (C4), a scripted test launch
deletes the real app's in-flight publish files (C5), and AC10's "either order"
is not forced by any test (C6).

## Findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C1 | Should fix | `Sources/PhotoApp/Model/PublishModel.swift:615-619`, `Sources/PhotoCore/Remote/PublishJob.swift:238-271` | `cancel()` sets `progress?.phase = .ending`, but the job's `ProgressCounter` only learns of `.ending` from a fault (`counter.report(.ending)` at line 126), never from the person's Stop. Every later report (`counter.finished()` in each photo's `defer`, `report(.waiting)`, a hop already queued) carries the counter's own phase, and the closure assigns it over `.ending`. | Two photos, concurrency 2: A fully sent and waiting for its answer, B mid-upload. Stop: B is cancelled at once and its `defer { counter.finished() }` reports `phase: .uploading`, so `isEnding` is false for up to the 10 s bound while A waits. During that time File ▸ Stop Publishing and Activity's Stop are enabled again, the row shows a progress bar and "Uploading…" instead of "Stopping…", and ⌘Q asks "Quit While Publishing?" when design §9 says an ending run asks nothing (`PhotoApplication.swift`: `isPublishing && !isEnding`). Status.md's AC23 check was a one-photo run. Fix: keep `.ending` once set in the closure (or tell the counter on cancellation). | Design §9; R17, AC23 |
| C2 | Should fix | `Sources/PhotoApp/Model/PublishModel.swift:679-703` (`retry`), `:605-623` (`execute`) | `retry` checks `retryRefusal(run)` (which tests `isPublishing`) before `await loadServers()` and `await Self.connect(…)` (three requests, plus a Keychain read that may prompt), then calls `execute` with no second check. `isPublishing` stays false all that time, and `execute` has no guard. | (a) Retry Failed, then reopen Publish Results from Activity's Show Results… before the connect returns: Retry is enabled again (`retryRefusal` is nil), and both retries run `execute` on the same run. The second overwrites `task`, `runningID` and `started`, so Stop cancels only one. The photos are uploaded and stacked twice at once (R14: one stack at a time per original), and the run's record is whichever finishes last. (b) The same with File ▸ Publish… and Publish on another server during the retry's connect: two runs at once (R21: one publish at a time). The first to finish sets `started = nil` while the other still runs, so the quit question is skipped and Stop and Quit's wait doesn't cover it. Fix: a starting flag set before the first await that `isPublishing`, `canPublish` and `retryRefusal` all read, and a guard in `execute`. | R21, R14 |
| C3 | Should fix | `Sources/PhotoApp/Views/ExportSettingsForm.swift:150, 153`; `Sources/PhotoApp/Model/ExportModel.swift:149-172` | Choose Image… in the shared form now calls `editor.chooseWatermark`, whose pick goes to `ExportSettingsEditor.useWatermark`, not `ExportModel.useWatermark`. Before the refactor, a good pick cleared `ExportModel.issue` (`issue = nil`). Now it doesn't, and the form shows `watermarkIssue ?? editor.watermarkIssue`, so Export's own issue comes first. | In the Export sheet, press Export with a watermark whose image was deleted: "The watermark image is missing. Choose it again." appears under Image. Choose a valid PNG with Choose Image…: the watermark is set, but the message stays until Export is pressed again. Picking a non-PNG at that point also shows the stale "missing" text, not "is not a PNG image". The debug script's `export watermark` path goes through `ExportModel.useWatermark` and still clears it, so scripted checks don't see this. | PRD Dependencies: "Export behaviour does not change" |
| C4 | Should fix | `Sources/PhotoCore/Remote/PublishOriginals.swift:242-243`, used at `:279` | `linkedAssetIDs` is built as [own link, pair partner's default, own image's default], and `OriginalFinder.find` uses only `.first`. A virtual copy has no link of its own, and copies never join a pair, yet the partner is looked up by the copy's image. So a copy of a paired raw takes the JPEG's link before its original's. | Pair IMG_1.RW2 + IMG_1.JPG, both imported from Immich (assets R and J; #271 pairs them by stem). Duplicate the raw (copy C) and publish the raw and C. The raw's edit stacks on R (its own link), and C's edit stacks on J (the partner's link comes first). The two edits of one photo end in two different stacks. AC7 says "a linked photo, its pair partner and its virtual copy stack on the linked asset". Fix: for a copy, try the default version it was copied from before the partner (see Q1). | R11, AC7 |
| C5 | Should fix | `Sources/PhotoCore/Remote/PublishJob.swift:40-43, 64-66`; `Sources/PhotoApp/Model/LibraryModel.swift:846` | Every app launch runs `PublishJob.removeLeftovers()`, which deletes `$TMPDIR/<AppBranding.bundleIdentifier>.publish` whole. `AppBranding.bundleIdentifier` is the constant `me.sesser.gus`, not the running bundle's identifier, so the real app and every scripted copy (re-signed with its own identifier for QA) share that folder. | The owner publishes a large selection in the real app. Meanwhile an agent launches a scripted copy with `--debug-script` (as QA does), and that launch deletes the real run's folder mid-run. The photo being rendered or having its body written fails with a misleading render or permission error (its folder is gone: `createFile` fails, or the render can't write). That breaks the isolation `docs/WORKFLOW.md` asks scripted copies to keep from the owner's work. Fix: one folder per process (for example under the running bundle's identifier, or a pid or launch subfolder), with leftover removal limited to folders whose process is gone. | R24; WORKFLOW Build ("never touch the owner's…") |
| C6 | Should fix | `Tests/PhotoCoreTests/PublishJobTests.swift:186-210` (`linkAndCopy`) | AC10: "With two edits of one original in a run, the later in grid order is primary and both are in the stack, with uploads finishing in either order." The only test runs the two uploads at concurrency 2, and nothing forces the later photo's upload to finish first. No test uses `holdUploadAnswer` with two photos, and nothing tests `StackSequencer` directly. | Remove the `await sequencer.turn(…)` at `PublishJob.swift:692` and `linkAndCopy` still passes whenever the first photo's upload happens to finish first, so it is not a test that fails without the behaviour. Hold the first upload's answer (the fake server can) until the second photo has uploaded, then release it and expect the second as primary. | Tests: AC10 must have a test that fails without it |
| C7 | Nit | `Sources/PhotoCore/Catalog/CatalogSchema.swift:471-485` | The new migration's doc comment was inserted inside `addHDRChoice`'s. That comment now runs straight into the publishing paragraph and documents `addPublishing`, and `addHDRChoice` (v17) has none. The v17 code is unchanged, so no migration was edited. | Reading only: the v17 rationale is now attached to v18. | Migrations (comment only) |

## Questions

- **Q1 (product manager, with C4): which link wins for a virtual copy?** R11
  lists "itself, its pair partner, or for a virtual copy the photo it was
  copied from". The code takes them in that order. But a copy never joins a
  pair (virtual copies, #62), so a copy arguably has no pair partner. Proposed:
  for a copy, the photo it was copied from comes before the partner, so a copy
  stacks where its original does. If the literal order is meant, C4 becomes a
  documented limit.

## Checked and fine

- **Allowlist and writes (R9, AC6).** Exactly four write patterns plus
  `GET /assets/{id}`, checked in `makeRequest` before a request exists. Server
  ids are gated twice: by `isPlainFileName` and by the `[0-9A-Za-z-]{1,64}`
  path pattern. `/albums/assets` (bulk) and `/albums/{id}/users` don't match.
  Content-Type now goes on non-GET requests only, so GETs are unchanged.
- **`exchange` and `MemorySink`.** A non-2xx body is capped at 64 KiB, an
  overlong or chunked error body keeps its status, and an encoded body is still
  refused at its head. The `data()` path (import) behaves as before.
  `serverMessage` is cut at 200 characters.
- **Streamed upload (R17).** `uploadTask(fromFile:)` with
  `RemoteUploadEnding.end`: "fully sent" is read from the task's counters at
  cancel time. A body not fully sent is cancelled at once, and a fully sent one
  is cancelled at a deadline set once per run. A call cancelled before
  `resume` is cancelled immediately. The 64 KiB answer cap fits the upload's
  JSON answer.
- **Multipart body.** Field values and the filename go through `headerSafe`
  (no quote, backslash or control character, so no header injection). The
  boundary is a UUID. Only the four fields and the file are sent. The file is
  copied in 1 MiB chunks. `safeFileName` keeps the temporary file inside its
  photo's folder.
- **Capture date (R4, RI-V1).** Floating capture times are stored as UTC
  (`MetadataReader.swift:49`), so `captureDate + offset` is the wall-clock time
  labelled UTC in both cases. With no capture date, the modification time is
  converted to local wall-clock time.
- **Album coordinator (R22, AC24).** A create is never repeated through
  `retrying`. The set of albums is read before each create, and a lost or
  cancelled answer becomes `.unknown(before:first:)`, resolved by
  `albums?assetId=first` minus the set read before. Retry Failed resumes from
  `.unknown`. A "duplicate" add counts as done.
- **Stack step (R14).** It reads the original's primary just before the create
  and sends `[edit, primary?, original]`, leaving out the primary when it is
  the original or the edit (the duplicate case). A refusal is
  `.stackRefused`, a failure and not "no original". A repeated create is
  harmless (status.md item 8).
- **`StackSequencer`.** Every child task calls `ended`, and a photo waits only
  on earlier ones, so no wait cycle is possible with the album lock (taken
  before the stack step, never held across `turn`). Retry candidates keep grid
  order.
- **Records (R17).** Written from a detached task so a cancelled run still
  records. A failed write is kept and re-tried first on Retry Failed.
  `ON DELETE CASCADE` from `version` (foreign keys are on,
  `Catalog.swift:50`), `SET NULL` from `remoteService`. The settings row
  cascades with its service. Tested in `records` and `rememberedChoices`.
- **Original rules (R13, R15).** `OriginalRules` follows R13's order of faults
  and counts only the account's own assets. NFC/NFD forms are compared by
  scalars, case counts, a partner's asset gives "another account's" only with
  no own asset, and the combine and ladder order is as design §7.1. A finder
  request that fails is a stacking failure, never a reason.
- **Retry Failed (R23).** `retryCandidates` follows the latest ending.
  `versionsPublished(after: startedAt)` removes photos a later run published.
  Photos are rendered as saved at the retry start. Accepted photos skip the
  upload. A step's earlier failure is re-run.
- **Migration v18** is a new numbered migration. No existing migration's code
  changed (C7 is comment-only). Table and column names hold no product name
  (`schemaNamesDoNotEmbedTheProductName` passes). No key is stored.
- **Quit (R21).** `QuitConfirmation.publishing`. Stop and Quit cancels and waits
  up to 15 s, so its waits overlap the others. An ending run waits with no
  question (but see C1).
- **Server sheet hosts (R1, AC25, R26).** The required permissions follow
  `ServerSheetPurpose`. A Publish-hosted check doesn't read the account, and
  `ownerID` isn't persisted (import still reads it in its own check). Remove
  Server… is offered from Import only. Edit and Remove are dimmed for the
  server being published to. The address warning uses the normalized address
  and `hasRecordsOrLinks`.
- **Import window (R20).** `publishedRemoteIDs` marks assets In Library, with
  their own tooltip, updated in place after a run.
- **Main actor.** No image decoding or large file reads on the main actor; the
  catalog and the Keychain (`connect` is `nonisolated`) are read off it. Renders
  run in the job's task group, like `ExportJob`.
- **No new package.** No `Process`, no `URLSession` outside
  `RemoteHTTPSession.swift`, no logging of keys (the publish loggers log
  nothing). `FakeImmichServer` stays linked as ruled for #271 (C10).
- **Strings.** New UI strings are in the catalog (`LocalizationTests` and
  `BrandingTests` pass). The R27 texts named in the PRD are changed. The
  README's "only reads from the server" line (README.md:66) is the product
  manager's, at Ship.
- **Proposed `CLAUDE.md` Network rule (status.md).** Checked against the code:
  every type it names exists and does what it says (`RemotePublishDestination`,
  `RemoteRequestAllowlist.writes` with the four writes, `StackSequencer`,
  `AlbumCoordinator`, `PublishUploadBody`, `RemoteUploadEnding` with a 10 s
  default bound, the 64 KiB error cap). Nothing in it is wrong. It could add
  that rendered files go to a temporary folder under the system's temporary
  directory, removed when the run ends and at launch (see C5).
- **Determinism.** 30 of 30 runs of the five suites rule out a per-run flake
  rate of about 1 in 10 or more (at about 95%), not rarer ones. The structural
  argument in status.md holds for `personsStop` (it cancels on whichever of
  the callback and the assignment comes second) and for the no-answer half of
  `endingWaitsForFullySent` (the deadline is set after `stoppedAt`). Two
  timing assumptions remain:
  - The answered half expects the whole ending within the 2 s bound on
    loopback. That is generous, but a loaded CI runner is its one risk.
  - `notFullySentCancelledAtOnce` relies on socket buffers far smaller than
    48 MB. Its 200 ms sleep only lets bytes flow and doesn't decide the
    outcome.

## Follow-up

Second pass, 2026-11-26: b244b48..a382a7b (666b6fe review files, 8b12a6b
engine, 0759b74 app, a382a7b status). Build and tests: `swift build
--build-tests` clean; `swift test` 1634 tests in 226 suites passed (99.8 s);
the connection and publishing suites (`--filter "PublishJobTests|PublishRulesTests|PublishBoundaryTests|RemoteConnectionTests"`,
63 tests in 5 suites) passed 30 of 30 runs with `--skip-build`, which rules out a
per-run flake rate of about 1 in 10 or more (at about 95%), not rarer ones (see C9).
I did not revert fixes to re-run the "fails without" checks; status.md records
that the engineer did (C1, C4, C5, C6, F6, F15, N1), and each test below
reads as one that would fail without its fix.

**Verdict, second pass: ready for qa-tester.** C1 to C7 are fixed, and the
security review's L1 and N1 with them. The new code (the publish slot, the
retry inside the run's task, per-launch temporary folders, awaited-answer
counting, the whole-path allowlist, the id rule, the sheet's sessions) is
sound. Three new nits (C8 to C10) and one question (Q2) remain; none blocks QA.

### First-pass findings

| # | Result | Commit | Checked |
|---|---|---|---|
| C1 | Fixed | 8b12a6b, 0759b74 | `ProgressCounter` now holds `ending` as a flag that nothing clears, and `withTaskCancellationHandler { … } onCancel: { counter.stopping() }` around the task group tells it of the person's Stop, so every later report (`finished`, `step`, `waiting`) says ending. In the app, `isEnding` is `slot.isStopping \|\| progress?.phase == .ending`; `cancel()` sets `slot.stop()` first, and `followed(by:)` keeps a report sent before the stop but delivered after it at ending. The quit rule (`PhotoApplication.swift:111-112`), Activity's Stop (`stopDisabled: ending`) and File ▸ Stop Publishing (`publishIsEnding`) all read `isEnding`. `stopKeepsEndingInEveryReport` runs two photos at concurrency 2 and checks every report after the first ending one. |
| C2 | Fixed | 8b12a6b, 0759b74 | `PublishSlot` is claimed in `start` (refused with "A publish is already running.") and in `retry` right after `loadServers()`, with no await between the check and the claim. `isPublishing` is `slot.isBusy`; `canPublish`, `begin`, `retryRefusal` and the menu read it. The retry's connect now runs inside `task` (`retryRun`), so Stop, ⌘Q's wait (`task != nil`) and Activity cover it. `isRetryPending` blocks a second Retry during `loadServers()`. A Publish that starts during that read can only come from a sheet, and the results sheet is still up (`LibraryModal`); if one did, the retry's `claim` fails and the results sheet stays open showing `.running`. Both of my first-pass traces now end in a refusal. |
| C3 | Fixed | 0759b74 | `ExportSettingsEditor.onWatermarkPicked` sends Choose Image… to `ExportModel.useWatermark`, which clears `issue` on a good pick and sets the "not a PNG" text on a bad one. Publish's editor has no handler and uses `useWatermark` (separate editor instances, `PublishModel.swift:170`, `ExportModel.swift:91`). The debug script's `export set watermark=` now takes the same route (`watermarkPicked`), so scripted checks follow the real path. |
| C4 | Fixed | 8b12a6b | `publishSources` orders links as own, then the copy's original's (`ownDefault`), then the pair partner's (`PublishOriginals.swift:248-249`), as PRD revision 6 rules (Q1). `pairBothLinkedAndCopy` checks both the source order and that no request names the JPEG's asset; `pairJPEGLinkedAndCopy` checks the fallback. |
| C5 | Fixed | 8b12a6b | See L1 below. |
| C6 | Fixed | 8b12a6b | `stackOrderWhicheverUploadFinishesFirst` holds both answers, releases them one at a time by file name, and waits for `onRecorded` of the first before releasing the second, in both orders. It checks the primary, the members and the exact create bodies (`[[earlier, original], [later, earlier, original]]`), so a missing `sequencer.turn` fails it whichever upload finishes first. |
| C7 | Fixed | 8b12a6b | The v17 comment is back on `addHDRChoice` and v18's on `addPublishing`. Comment only; no migration code changed. |
| Q1 | Ruled | PRD revision 6 | R11 and AC7 now say own, the copy's original, then the partner. C4 implements it. |

### Security review

| # | Result | Checked |
|---|---|---|
| L1 | Fixed (8b12a6b) | `PublishTemporaryFolders` gives each launch `<base>/<uuid>/` and takes an exclusive lock on `<uuid>.lock` as it creates the file (`O_CREAT \| O_EXCL \| O_EXLOCK \| O_NONBLOCK`), before the folder exists, holding it for the life of the process. `removeLeftovers` removes a launch folder only when it can take that lock itself (`O_EXLOCK \| O_NONBLOCK`), plus folders with no lock file. On macOS a `flock` held through one open file description refuses a second `open` with `O_EXLOCK`, even from the same process, so this launch's folder is safe too (`temporaryFoldersPerLaunch` relies on that and passes). A launch's folder is made lazily, when the first `PublishJob` is built, and every run and item folder is created with `withIntermediateDirectories`. So a cleanup's `readdir` that sees a brand-new folder before its lock (both created during the listing) costs at most an empty folder that is made again. Two cleanups at once can't both take a lock. A scripted copy no longer touches the owner's run. |
| N1 | Fixed (8b12a6b) | `permits` compiles each pattern with `NSRegularExpression` and requires `match.range == whole`, so a trailing `\n`, U+2028 or U+2029 never passes. If a pattern fails to compile, the request is refused, which is the safe side. `RemoteAsset.isServerID` (1 to 64 ASCII `[0-9A-Za-z-]`) guards `asset(id:)` and `addToAlbum` before a request exists. In import, it now drops any listed asset whose id fails, before the id can reach the thumbnail or original path. The only id that still reaches the server unchecked is `ownAlbums(holding:)`'s, and that goes in a query item, which `URLComponents` encodes. Tests: `serverIDsAndAnchoredAllowlist` (ids, and paths ending in each terminator) and `strangeIDsNeverRequested` (no request reaches the fake server). |

**Import's behavior change (N1).** An asset whose id is not 1 to 64 ASCII
letters, digits or hyphens is now left out of the import listing, the same
way as an unsafe file name. Before, it was listed and its thumbnail or
download failed at the allowlist. Immich ids are UUIDs, so no real server is
affected, and no import test changed. No test pins this drop in the listing;
the allowlist is the backstop either way. Fine as it is.

### Design review fixes I read (F1 to F18)

- **F1 (confirming Publish).** `confirm()` keeps the confirming task. Closing
  the sheet any way (`showsPublishSheet` didSet → `sheetClosed`) bumps
  `session` and cancels it. Closing for the Server sheet does neither.
  `requestPublish` checks `!Task.isCancelled, session == opened` after each
  await, and calls `start` with no await after the last check. The run's
  `Task` is unstructured, so cancelling the confirm task can't reach it. The
  question carries its own service, client and check.
- **F4, F5, F8, F9, F11, F18.** `serversChanged` from both Server sheet hosts.
  `choose(keepingChoices:)` keeps the form when returning to the same server.
  `endedRuns` leaves out the slot holder, including a run being retried.
  `begin` and `choose` reset the check and client before any await.
  `resetOriginals` runs everywhere design §7 names. `rememberMadeAlbum`
  rewrites only the album, in one transaction, gated by `mayRememberItsAlbum`.
  All correct. C10 below is a corner of F4.
- **F6.** The field binds the text as typed. `serverPath(volumeIdentity:…)`
  matches on `keptServerPath`, and Done saves `.kept`. A changed map resets
  Check Originals.
- **F15, D-1, D-2, D-5.** `retrying` reports waiting on its first wait and
  stops reporting it however the request ends, so the waits balance (the
  album create's `defer` too). The `.checking` phase is indeterminate, with
  Stop on. `PublishStop.checkFailed` is a fault, so a retry stopped by its
  check keeps every candidate. `PublishStop` lost `Codable`; nothing encoded
  it (the build is clean and runs are not persisted).
- **F12, F13, F16, F17.** View code: the inline `Picker` tag for New Album…
  is normalized both ways, and the hints and announcements follow
  `AnnouncedIssue`. I read the strings in `PublishText` and they are in the
  catalog (`LocalizationTests` passes).

### New findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C8 | Nit | `Sources/PhotoCore/Remote/RemoteHTTPSession.swift:239-259` | The cancellation handler moves `wait` from `.running` to `.awaiting` under the lock, but calls `ending.beganAwaiting()` after releasing it. The returning path reads `.awaiting`, sets `.over` and calls `endedAwaiting()`. When the answer arrives just as Stop is pressed, `endedAwaiting` can run first: the count is clamped from -1 to 0 and reports false. Then `beganAwaiting` raises it to 1 and reports true. Nothing lowers it again. | One fully sent photo, Stop pressed as its answer lands, a second photo still rendering. Activity reads "Stopping. Waiting for “Home” to answer…" until the run ends, though nothing is awaited (D-1 wants **Stopping…**). The count belongs to the run, so the next run starts clean. Cosmetic, in a window of a few instructions. Fix: call `beganAwaiting()` and `endedAwaiting()` inside the `wait.withLock` closures. The lock order would be wait → awaiting → counter state, and nothing takes them in the reverse order. | Design §9, D-1 |
| C9 | Nit | `Sources/PhotoCore/Remote/PublishJob.swift:280-287` (`ProgressCounter.change`) | Each report is computed under the counter's lock but delivered (`reportTo(progress)`) after releasing it. Two threads can therefore deliver in the reverse order of their states. In the app, `followed(by:)` repairs only the phase. `done` can step back by one and `awaitsAnswer` can be left inverted until the next report. In `stopKeepsEndingInEveryReport`, a step computed just before `stopping()` but appended just after it puts a non-ending phase after the first ending report, which fails `after.allSatisfy { $0.phase == .ending }`. | The window is a few instructions, so the test is not structurally deterministic as status.md's argument says. The runs below make a frequent flake unlikely, not a rare one. Fix: call `reportTo` inside the lock. It is non-blocking in both callers: the app's closure only creates a `Task`, and the tests' appends to another `Mutex`. | Determinism claims (WORKFLOW) |
| C10 | Nit | `Sources/PhotoApp/Model/PublishModel.swift:380` (`canPublish`), `:639` (`requestPublish`), `:230` (`serversChanged`) | F4 now reloads `servers` while the Publish sheet is open. If the chosen server is removed in the Import window meanwhile (Remove Server… is dimmed there only for a running publish), `service` becomes nil. `client` and `check` stay set, so `canPublish` is still true. Pressing Publish runs `confirm()`, and `requestPublish` returns at `guard … let service` with no message. | With two servers, open Publish on Home (check passed). In the Import window, choose Home, then Remove Server…. Back in the sheet, nothing in the Server list is ticked, Publish N Photos is enabled, and pressing it does nothing. Fix: require `service != nil` in `canPublish`, or have `serversChanged` clear the check and client (or choose another server) when the chosen one is gone. | Design §3.8 (Publish enabled only when it can run) |

### Questions (second pass)

- **Q2 (product manager): a Stop during a retry's check.** Status.md's Known
  and left: Stop pressed while a retry checks its server, before anything is
  sent, ends the run as the person's Stop. Under R23 ("the latest ending
  decides"), the photos the earlier fault left unreached then drop out of
  Retry Failed for good: the results say they are left out, and nothing
  offers them again. That matches R23's wording, but here the Stop interrupted
  only a check. Should a Stop before anything is sent keep the run's previous
  ending? If the literal rule is meant, the user guide should say so.

### Proposed `CLAUDE.md` Network rule (status.md, review-round version)

Checked again against a382a7b. Every type and claim holds:

- `RemoteRequestAllowlist` is matched against the whole path, with the four
  writes in `writes`.
- `RemoteAsset.isServerID` holds for every id that goes into a path. The one
  other server-given id that reaches a request, `ownAlbums(holding:)`'s, goes
  in a query, and the rule says "into a path".
- `PublishSlot`, `StackSequencer`, `AlbumCoordinator`, `PublishUploadBody`
  and `RemoteUploadEnding` (10 s) do what the rule says.
- `PublishTemporaryFolders`: a launch's folder is locked for the life of the
  process; each run removes its own.

Two wording points, neither wrong enough to block:

- The rule writes `<bundle id>.publish` with the same notation as the
  Keychain's `<bundle id>.servers`. The temporary folder uses the constant
  `AppBranding.bundleIdentifier`, so every copy shares the base folder, which
  is why the locks exist. The Keychain service takes the identifier its
  caller passes in.
- "A launch removes only those of launches that have ended" leaves out
  folders with no lock file, which it also removes.

### `/security-review`

Run it again, but scoped to the changed parts, not the whole branch.
`PublishTemporaryFolders` is new file writing and deletion outside the
library, with `flock`. The allowlist matcher and the id rule are new
request-building gates, and the id rule also changes import's listing. I
found nothing wrong in either, but WORKFLOW names both kinds of change.

### Third pass, 2026-11-26: a382a7b..41f6d0f

Commits: cbbbc24 (review files, D-10, D-11), 452db62 (engine), 15d3a92 (app),
eb34859 (status), b16e129 (design D-12, D-13), e58b8a2 (engine), 5b83b3d (app),
41f6d0f (status). No merge of `develop`. Build and tests: `swift build
--build-tests` clean; `swift test` 1642 tests in 226 suites passed (101.5 s);
the connection and publishing suites (`--filter "PublishJobTests|PublishRulesTests|PublishBoundaryTests|RemoteConnectionTests|RemoteSessionTests"`)
(77 tests in 6 suites) passed 30 of 30 runs with `--skip-build`. That rules out a per-run
flake rate of about 1 in 10 or more (at about 95%), not rarer ones. For
`stopKeepsEndingInEveryReport`, C9's fix now gives a structural argument as well. I did not revert fixes to re-run the
"fails without" checks; status.md records that the engineer did (F22, F23,
D-10, D-12, D-13), and each test reads as one that would fail without its fix
(but see C12).

**Verdict, third pass: ready for qa-tester.** C8, C9 and C10 are fixed, and Q2
is ruled (PRD revision 7) and built. The new code (`PublishRetry` and
`PublishConnection` in PhotoCore, delivery inside locks, the shared retry rule
and its catalog read, the sheet's reaction to a removed or changed server, the
observation changes) is correct; I found no deadlock or re-entrancy. Two new
nits (C11, C12); neither blocks QA.

#### Second-pass findings

| # | Result | Commit | Checked |
|---|---|---|---|
| C8 | Fixed | 452db62 | `beganAwaiting()` runs inside the cancellation handler's `wait.withLock`, and `endedAwaiting()` inside the returning path's, so for one upload the raise is always before the lower. `onAwaitingChange` is told inside the count's lock, and `endedAwaiting` no longer clamps (it ignores a lower at 0, which can't happen now). My trace (answer lands as Stop is pressed) now ends with the count at 0 and "waiting" false. |
| C9 | Fixed | 452db62 | `ProgressCounter.change` calls `reportTo` inside `state.withLock`, so reports reach the listener in the order of their states. The listeners are the app's `report(for:)` (creates a main-actor `Task`, takes no lock) and the tests' appends under a separate `Mutex`. With this, `stopKeepsEndingInEveryReport` has a structural argument (status.md), not only run counts. |
| C10 | Fixed | 15d3a92, 5b83b3d | `canPublish` and `canCheckOriginals` require `service != nil` (PublishModel.swift:417, :574). D-13 then goes further: `chosenServerWasRemoved()` clears the server, check, client, albums, map and links, gives up sheet work and the Skip or New Copy question, and leaves the folder map page. My trace now ends with Publish dimmed and the line **This server was removed.** |
| Q2 | Ruled and built | PRD revision 7, design D-10, D-11; 452db62, 15d3a92 | See **Retry stopped during its check** below. |

#### Lock order and re-entrancy (C8, C9)

The locks are taken only in this order: an upload's `wait`, then
`RemoteUploadEnding.awaiting`, then `ProgressCounter.state`, then the listener
(which takes no publishing lock). Nothing holding a later lock takes an earlier
one:

- `counter.stopping()` (the job's `onCancel` and the fault path) takes only the
  counter's lock.
- `group.cancelAll()` runs the children's handlers after `stopping()` has
  returned.
- `task.cancel()` comes from the main actor, holding nothing.
- `RemoteUploadEnding.end(task, by: ending.deadline())` runs before the
  `wait` lock.

These are non-recursive `Mutex`es. A cancellation handler would deadlock only
if it ran on a thread that already held the counter's lock, which requires a
listener that cancels the task. Neither listener does. `ProgressCounter`'s
doc comment states that rule. `RemoteUploadEnding`'s public `onAwaitingChange`
is now called inside its lock and doesn't say so; its only caller is the
job's `counter.awaiting`, so that is not a finding.

#### Retry stopped during its check (R23 revision 7, AC21, D-10, D-11)

- `PublishRetry.perform` checks `Task.isCancelled` after the check, after
  `makeJob`, and (through `PublishJob.retry`, which returns nil) after the
  job's own reads, until the first photo is started. Each of these is
  `calledOff`. `PublishRetryOutcome.ended(stopAsked:)` lets a Stop asked on
  the main actor before `retryRun` resumes win over a `checkStopped`.
- `retryRun` then only calls `release`: no `finish`, no message, and `runs`,
  `endedAt` and the ending are untouched. A late progress hop is dropped by
  `slot.holder == id`. `cancel()` sets `slot.stop()` and `.ending` first, so
  the job shows **Stopping…** with Stop dimmed until the check returns.
- `job(...) == nil` can no longer reach the old "person's Stop" path for a
  retry.
- `isBeingRetried` dims Show Results… on that run's row, and `showResults(id)`
  no longer falls back to another run.
- `stopDuringRetryCheck` covers a Stop during a real held check, during a
  check that then fails, and during `makeJob`. `retryCheckFailsOrRuns` and
  `retryOutcomeRule` cover the outcome rule.

#### Retry rule and its catalog read (D-12)

- `PublishRun.retryVersionIDs(laterPublished:)` is the one rule. The job uses
  it (PublishJob.swift:97-98), and the results sheet's `offersRetry` and
  `retrySentByLaterRuns` use it through `PublishModel`.
- `Catalog.laterPublications(of:)` asks only about `notUploadedVersionIDs`, so
  the run's own records (made after `startedAt` too) never count. The SQL
  filters by provider, address and `publishedAt > startedAt`.
- The model reads it on appear, on a change of `resultsRunID` (`didSet`), and
  after `finish` while the sheet is open. `laterReads` drops all but the
  newest read, and `retry()` bumps it so an older read never lands over its
  own.
- `retry()` reads it again after `loadServers()` and claims the slot in the
  same main-actor turn as `isRetryPending = false`, so the C2 property holds.
  The claimed total equals the job's own count.
- A read that fails leaves nothing out, in the app and in the job alike.
- `retryNothingLeftAfterLaterRun` checks the catalog read against a real
  sequence of runs.

#### The sheet after its server is removed or changed (D-13, F28)

- `PublishServerChange.after` compares the record held before the reload
  with the one after it, by id. A person choosing another server during the
  reload gives `before.id != chosenID`, which is `.unchanged`. A rename alone
  is `.unchanged`.
- `.connectionChanged` re-runs `choose(_, keepingChoices: true)` only while
  the sheet shows. `begin` resets `chosenServerRemoved` for a sheet that was
  closed. The folder-map row, the "no original" line and
  `showFolderMapPage` all require a server. See C11 for the one thing
  `.connectionChanged` leaves.

#### Observation

- `client` and `session` are observed now. `canPublish` and
  `canCheckOriginals` read only observed state (and the watermark's presence,
  as before).
- `laterPublished` is observed and `laterReads` is not, so the results
  sheet's button and caption follow each read.
- `chosenServerRemoved` is observed.
- `debugChecksStarted` is ignored (debug only).

#### Other changes read

- D-6, D-7: the new strings are in the catalog, and the old keys are gone
  (`LocalizationTests` passes).
- D-8: the first report is the first photo's own step, and an accepted photo
  reports Uploading.
- D-9: `byEnding` is a stable sort by end time.
- The Failed list now has one id per photo and failure. The old nested
  `ForEach` with offset ids drew the first photo's row for each photo.
- F26: `ReasonGroup` alignment.
- F27: File Settings shows the editor's issue first.
- `ExportSettingsEditor.useWatermark` now calls `loadWatermark()`, so Export's
  preview shows an image chosen again under the same identifier. This is the
  only Export change, and it brings the preview in line with what Export
  writes.

#### New findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C11 | Nit | `Sources/PhotoApp/Model/PublishModel.swift:261-263` (`serversChanged`, `.connectionChanged`), `:677-719` (`requestPublish`), `:723-731` (`answer`) | F28 re-runs `choose(_, keepingChoices: true)`, which cancels the sheet's check but not `confirmTask`, and leaves `question` as it was. `requestPublish` captured the old record and connected with it. Its guard (`serviceID == service.id`) passes because the id is unchanged, and the Skip or New Copy `Question` carries the old record and client. D-13's removal path gives both up (`cancelSheetWork()`, `question = nil`). | Publish pressed on Home with some photos already published, so the Skip or New Copy alert is up. In the import window, Edit Server sets Home's address to its new one (the R26 warning accepted). Answer New Copy: the run starts with the old record and the old address's client. Edit Server is dimmed only for a running publish, not a pending confirm, so nothing stopped this. The records go under the old address, so the next Publish to the new address doesn't ask Skip or New Copy for them. That run's Retry Failed reads "This server's address has changed since this run." straight away. The same happens if the address changes during `requestPublish`'s own connect or records read. Rare: the person has to edit the server in the other window during those seconds or while the alert is up. Fix: on `.connectionChanged`, call `cancelSheetWork()` and set `question = nil` before `choose`, as the removal path does. Whether the alert should go is the designer's to confirm (design §3.3 says so only for removal). | Design §3.3 (D-13, F28); R26 |
| C12 | Nit | `Sources/PhotoCore/Remote/PublishJob.swift:163`; `Tests/PhotoCoreTests/PublishJobTests.swift` (`stopDuringRetryCheck`) | `PublishJob.retry`'s own "called off" (`stop == nil && Task.isCancelled && sequence == 0`) has no test. `stopDuringRetryCheck`'s "before any photo" case cancels inside `makeJob`, so `PublishRetry.perform` returns at its `guard … !Task.isCancelled` before the job runs. | By reading: no test calls `PublishJob.retry`, and every other test that cancels does so outside it. So if line 163 were `let calledOff = false`, every test would still pass. With that change, a Stop pressed while the job does its own reads (`laterPublications`, `exportJob.items` and `publishSources`, which take a while for a large run) would end the run as the person's Stop and drop its unreached photos from the next retry (AC21). The code is right; only the test is missing. Fix: hold the job before its first photo (a test-only hook, or a catalog read the test can block) and cancel there, expecting `job.retry` to return nil and no write request. | Tests: AC21 |

`/security-review`: this round adds no parser, subprocess or new network
path. The request gates, the allowlist and the temporary folders are
unchanged. `PublishConnection` moved into PhotoCore `Remote/` unchanged, and
the new catalog read is local. A security re-review is already running in
parallel; nothing here needs more than that.

`CLAUDE.md` Network rule (status.md): both of my second-pass wording points
are taken, and nothing this round changes what the rule describes.
`PublishConnection` and `PublishRetry` are now PhotoCore `Remote/`, which
matches "All of it is PhotoCore `Remote/`".

### Fourth pass, 2026-11-26: 41f6d0f..f5d5f09

Commits: 9773e03 (design D-15, D-16, reviews, security addendum), e603c77
(engine), cd55215 (app), f5d5f09 (status). No merge of `develop`. Build and
tests: `swift build --build-tests` clean; `swift test` 1651 tests in 226
suites passed (95.8 s); the connection and publishing suites (`--filter
"PublishJobTests|PublishRulesTests|PublishBoundaryTests|RemoteConnectionTests|RemoteSessionTests|RemoteCheckTests"`,
86 tests in 6 suites, the nine new ones included) passed 30 of 30 runs with
`--skip-build`. That rules out a per-run flake rate of about 1 in 10 or more
(at about 95%). For rarer ones I accept status.md's structural argument, which
I checked: the D-16 tests put the other window's change at a fixed point
through a key store hook called synchronously inside the save or removal; the
folder tests use their own folders, descriptors and `now`; C12's test cancels
only after the hook has yielded, and the hook waits for that cancellation. I
did not revert fixes to re-run the "fails without" checks (I don't edit
`Sources/`); status.md records that the engineer did, and each test reads as
one that would fail without its fix.

**Verdict, fourth pass: ready for qa-tester.** C11 and C12 are fixed. D-15,
D-16, N5, N6 and the N2 addendum are built as ruled, and I found no case that
loses a key or a folder that should be kept. One new nit (C13, a doc comment).

#### Earlier findings

| # | Result | Commit | Checked |
|---|---|---|---|
| C11 | Fixed (as D-15, with security L2) | cd55215, e603c77 | `serversChanged`'s `.connectionChanged` now gives up a Publish being confirmed and the question (`cancelSheetWork()`, `question = nil`) before the recheck, as removal does. The rule is also enforced where a run starts: `requestPublish` (after connect and the records read) and `answer(skip:)` (before `start`) call `stillSaved`, which compares the saved row's address and fingerprint with the record checked. My C11 trace (question up, the import window moves Home, New Copy) now ends with the question closed by the reload, or, if New Copy came first, with `answer`'s read finding `.connectionChanged`: no run, the line shown. While `answer` reads, `confirmingSession` is set, so `isConfirming` dims Publish and a reload landing then cancels `confirmTask`. A rename or a new key alone is `.unchanged` (`after` compares address and fingerprint only). |
| C12 | Fixed | e603c77 | `PublishJob.beforeFirstPhoto` (internal) is awaited after the job's reads and before the task group. `stopInsideRetryJobBeforeFirstPhoto` cancels there and expects `retry` to return nil, no write and still one upload; with `calledOff = false` the run would come back `.stopped(.stopped)` and the `#expect(stopped == nil)` fails. |

#### D-16: Keychain and catalog writes (`RemoteServices.swift`, `ServerSheet.swift`)

- `saveRemoteService(_:)` now inserts only a record with no id and otherwise
  `update`s, which throws `RecordError.recordNotFound` when the row is gone
  (GRDB's `save` inserted). Its only callers are the keyed save and the tests.
  SQLite counts a matched row as changed even when no value differs, so an
  unchanged update and `renameRemoteService`'s `changesCount > 0` behave.
- Save (S) and Remove (R) interleaved. S is: check the row (s1), write the key
  (s2), update the row (s3). R is: delete the key (r1), delete the row (r2),
  delete the key again (r3, new). I traced every order. Each ends with no row
  and no key once R has run:
  - s3 before r2: r1 or r3 deletes S's key.
  - s3 after r2: s3 throws `recordNotFound`, and S deletes its key.
  - s1 after r2: S returns `.removed` before touching the key store.
- No key that should be kept is deleted. Accounts are the record's `uuid`,
  made fresh by `RemoteServiceRecord.init` (the sheet's Add is the only
  `init` in `Sources/`). No row ever reuses another's uuid, and after D-16 no
  save recreates a removed row, so a key deleted for a gone row has no owner.
  r3 runs only after r1 succeeded (a Keychain refusal returns before the row
  goes) and is `try?`. On the real Keychain it either finds nothing
  (`errSecItemNotFound` counts as deleted) or finds an item this process just
  wrote, so it adds no prompt. Both run off the main actor (`Catalog` is a
  `Sendable` class; no `NonisolatedNonsendingByDefault`).
- One residue, not a finding: with s2 done and s3 failing for some reason
  other than `recordNotFound` after r2 (a database error), S puts the
  previous key back, so a key can stay with no row. It needs a write error on
  the app's own serialized writer at that instant. That is the existing F2
  rollback, unchanged.
- Name-only Save calls `renameRemoteService`, which writes `name` only, and
  hands the host the row as saved now. With one window this gives the same
  result as before. With two, an address or certificate saved in the other
  window is kept, and the host's `choose`/`chooseServer` gets the current
  record. A failed write still leaves the sheet as it was (`catch {}` in place
  of `try?`).
- A checked Save, and Trust Certificate (which calls `submit()`), read the row
  before the Keychain and the network; a removed server reaches
  `serverSheetFoundRemoved`. The save's own check catches a removal after
  that. Add (no `existing`) skips both checks.
- Import's Server sheet is otherwise unchanged. When its server still exists,
  the only differences are one extra catalog read before the check, and a
  failure of that read shown as the sheet's error. The import host's
  `serverSheetFoundRemoved` does what `removeServer` does after a removal:
  `closeServer()` if it was the source, `loadServers()`,
  `remoteServersChanged()`.
- Publish host: `serverSheetFoundRemoved` sets `serverSheet = nil`, so
  `sheetDidClose` (`returnsAfterServerSheet`) brings the publish sheet back,
  and `chosenServerWasRemoved()` runs unless the import window's reload did it
  first (`serviceID == service.id`). `chosenServerRemoved = !servers.isEmpty`
  reads the reloaded list, so the last server gives No saved server.

#### N5, N6: `PublishTemporaryFolders`

- `prepare` makes the base 0700 and requires `lstat` to find a directory owned
  by `getuid()`, then sets 0700. `lstat` follows `/var` → `/private/var` in
  `$TMPDIR` but not the last component, which is what's wanted.
  `removeLeftovers` checks the same before listing.
- Removals: `FileManager.removeItem` on a symbolic link removes the link, and
  both `open` calls carry `O_NOFOLLOW`, so nothing outside the base is
  removed or locked. `temporaryFoldersNoLinks` covers a linked base and a
  linked `.lock`.
- Kept folders. A running launch's folder keeps its held lock and is skipped.
  A launch folder seen without its lock (a `readdir` that misses the lock
  file, which is made first, or a lock file removed by a person or a temp
  cleaner) is kept for a day by its own `lstat` mtime. Run folders are made
  with `withIntermediateDirectories: true` (PublishJob.swift:104), so a launch
  whose folder was removed after that day still runs.
- `Launch.make` no longer returns an unlocked folder in the base. It tries 8
  names, then falls back to `<bundle id>.publish-<UUID>` beside the base,
  which no cleanup removes. status.md accepts that leftover with a reason.
- C13 below: one doc line still says the lock is taken atomically.

#### D-15 residue (not a finding)

`stillSaved` reads the row, then `start` runs when the main actor resumes. A
Save in the import window that commits in that gap (well under a millisecond,
unless the main actor is busy) lets the run start with the record checked a
moment earlier. The reload that follows finds neither a confirm nor a question
and only rechecks. The key still goes only to the address it was checked with,
and the effect is the one C11 described (records under the old address),
within a window a person can't reach by clicking two windows. I don't ask for
more.

#### Other changes read

- N2 addendum: `ImmichClient.refusals` puts each per-photo error through
  `RemoteAnswer.shownText` (trim, cut at `shownTextLimit`, empty to none).
  `serverMessage` uses the same function. `albumAddErrorCut` pins both.
- Strings: one new key with its catalog entry (`LocalizationTests` passes).
  The line shows as `AnnouncedIssue` and as the Server pop-up's hint, and
  clears where design §3.3 says (`requestPublish`, `choose` unless
  `keepingLine`, `chosenServerWasRemoved`, `begin`).
- Debug script: `publish answer` polls `isConfirming` with a 25 ms sleep for
  up to 5 s. It's a script command, not a test, and the poll ends as soon as
  the state is reached.
- USER_GUIDE: both new paragraphs match the code.

#### New findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C13 | Nit | `Sources/PhotoCore/Remote/PublishTemporaryFolders.swift:12-13` | The type's doc comment still says the lock is "taken atomically as the file is made (`O_EXLOCK`)". `lockAttempts`' comment (:36-37) and security N6(a) say the opposite: another process can lock the new name between its creation and its locking. | No wrong behavior. The retry loop exists only because creation and locking are not atomic, and the comment says they are. A later reader who trusts it could remove the loop as dead code, and the race N6(a) describes would come back. Fix: say the lock is taken in the same `open` that makes the file, and that another process can still take it first, hence the retry. | Correctness of documentation that guards a rule |

#### `/security-review`

Yes, scoped, not the whole branch. This round changes credential deletion
(`saveRemoteService`'s `.removed` path and `removeRemoteService`'s second
delete) and file deletion outside the library (`PublishTemporaryFolders`'
`lstat`, `O_NOFOLLOW`, mode and age rules), both kinds WORKFLOW names. The
reviewer should confirm L2, N5 and N6 against these commits (e603c77, cd55215)
and look at the two credential paths above. I found nothing wrong in either.
No new parser, subprocess or network path. The request gates and the
allowlist are unchanged. The one new request-adjacent read, `stillSaved`, is
local.

#### `CLAUDE.md` Network rule (status.md)

The fourth-round sentence matches the code: base 0700 and the user's own; only
ended launches' folders and day-old lock-less ones are removed; no link is
followed; nothing at all is removed unless the base is the user's real folder;
a launch that can't lock uses a folder beside the base. Nothing else in the
rule changed this round, and it still holds.

### Fifth pass (2026-11-26, f5d5f09..ce41e92)

Read only `git diff f5d5f09..ce41e92 -- Sources Tests`; no build or tests
(comment-only change).

| # | Result | Commit | Note |
|---|---|---|---|
| C13 | Fixed | ce41e92 | The diff under `Sources/` and `Tests/` is the doc comment of `PublishTemporaryFolders` (:12-17) and nothing else. It now says the lock is asked for in the same `open` that makes the file (`O_EXLOCK`), that making and locking are not atomic, and that a launch whose lock fails tries a new name (`lockAttempts`). That matches `Launch.make` (:58-80: `O_CREAT \| O_EXCL \| O_EXLOCK \| O_NONBLOCK`, `continue` on failure, up to `lockAttempts` names) and `lockAttempts`' own comment (:38-40). |

### Sixth pass, 2026-11-26: bc54ded..586cfd2

Commits: 1c84496 (N7 for publishing), a04d1ee (Q1), 82339ab (Q2), 35ec122
(Q3, Q4), 944982c (status, CI toolchain fix to the N7 tests), aa3216e (design
D-17 to D-19), e840ec9 (the import window and the Server sheet), 586cfd2
(status). ce41e92..bc54ded is docs only (QA's file and the fifth pass). No
merge of `develop`. Build and tests: `swift build --build-tests` clean; `swift
test` 1667 tests in 228 suites passed (98.2 s); `ServerKeyPairingTests`,
`PublishKeyPairingTests`, `PublishJobTests` and `RemoteConnectionTests` (62
tests in 5 suites) passed 30 of 30 runs with `--skip-build`. That rules out a
per-run flake rate of about 1 in 10 or more (at about 95%). For rarer ones I
accept status.md's structural argument, which I checked. The sheet tests put
the other window's Save at a fixed point in one task (`key`, `check` and
`save` called in turn). The two "waits for the row" tests hold the gate
themselves and spin on `Task.yield()` only until the check either waits
(`waiters`) or has finished, so without the gate they fail rather than hang.
Each test uses its own uuid on the shared `RemoteKeyGate`, so parallel tests
never meet on one account. I did not revert fixes to re-run the "fails
without" checks (I don't edit `Sources/`). status.md records that the engineer
did, and each test reads as one that would fail without its fix.

**Verdict, sixth pass: ready for qa-tester.** N7 is closed on both sides, and
D-17 to D-19 are built as ruled. I found no deadlock, no lost wake-up, no path
that blocks the main actor, and no order that loses a key or leaves one with
no row. #271's import behaviour is unchanged when only one window saves. One
new nit (C14: the publish sheet can be left at "Checking…") and two wording
points on the proposed Network rule.

#### `RemoteKeyGate` (`Remote/RemoteKeyPairing.swift`)

- **Correct as a lock.** `acquire` inserts into `held` or queues its
  continuation in one critical section, so a release can't fall between the
  test and the queueing (no lost wake-up). `release` hands the gate straight
  to the first waiter without clearing `held`, so a newcomer queues behind it
  (FIFO). Continuations are resumed outside the `Mutex`. `holding` releases on
  both the return and the throw path, and a cancelled body still releases.
- **Never on the main actor.** `holding` runs its body in the caller's
  isolation (`#isolation`). Its three callers, `RemoteSavedKey.read` and the
  two keyed `Catalog.saveRemoteService`, are nonisolated `async` functions on
  a `Sendable` enum or class. The package sets no `NonisolatedNonsendingByDefault`
  and no default isolation (Package.swift has neither), so they run on the
  global executor. App code reaches them only through `PublishConnection.connect`,
  `RemoteImportConnection.connect` and `RemoteServerSheetCheck.run`, which are
  also nonisolated. The Keychain call and its possible prompt block a pool
  thread, as before (C8), never the main thread.
- **No deadlock or re-entrancy.** No body takes the gate again: bodies call
  only the key store and `Catalog` reads and writes. `KeychainKeyStore` never
  calls back, and the tests' hooks that start a check do it in a new `Task`.
  GRDB's write closures are synchronous, so no database work can wait on the
  gate while a holder waits on the database. `removeRemoteService` doesn't
  take the gate, and doesn't need to: a reader that races it gets no key or no
  row, never a key beside another address.
- **Across a Keychain prompt.** The gate is held until the person answers it.
  Meanwhile only key reads and saves of the same server wait, suspended, not
  blocking a thread: the import window shows Connecting…, and the publish
  sheet shows Checking…. Documented in the type and in status.md. Nothing that
  Quit waits for waits on the gate. The import window's Quit wait is for
  `importTask`, which reads no key, and publishing's is for a run, bounded by
  its timeout.
- **Waiters can't be cancelled** (residue, not a finding): `acquire` has no
  cancellation handler. A check cancelled while queued behind a prompt runs its
  own Keychain read once it gets the gate, which can prompt once more if the
  person picked Allow rather than Always Allow. The old code had the same
  read, unordered, and dropped the result the same way (`guard
  !Task.isCancelled` at each caller), so nothing regressed. A `guard
  !Task.isCancelled` after `acquire` in `RemoteSavedKey.read` would avoid that
  extra read.

#### Saves and rollback (`Catalog/RemoteServices.swift`)

- **F2's order is kept inside the gate:** read the previous key, write the new
  one, write the row; if the row fails, put the previous key back, or delete
  the new one when there was none; `recordNotFound` deletes the key (D-16).
  D-16's removal check still runs before the gate. It needn't be inside: my
  fourth-pass trace of S against r1, r2 and r3 still holds, since only S's
  steps moved under the gate, in the same order.
- **Guarded save (D-19).** The key read, the row read, the comparison (stored
  key against the one the check used, plus address and certificate through
  `PublishServerChange.after`, the same rule `RemoteSavedKey` uses) and the
  write all happen under the gate. A keyed save of the same account can't land
  between them, in either order:
  - G before S: S writes over G (the last save wins with its key).
  - S before G: G sees the other key or address, and `.changed` writes
    nothing.

  A removal: if the row is gone, G deletes the key and returns `.removed`. If
  r1 ran but not r2, G sees no key, returns `.changed`, and the host chooses a
  server whose next check ends `.removed`. The reload that follows the removal
  then clears it. The guarded save never writes a key, so it can't leave one
  behind. A rename racing G loses to G's form name: the design accepts that
  (only the address, the certificate and the key are compared).
- **No caller passes `key: nil` to the keyed save any more.** `save` uses the
  guarded save whenever `enteredKey` is nil and the sheet was opened on a
  server, and `submit` refuses Add without a key.

#### Every key read

`grep -rn "\.key(account:" Sources` finds three, as status.md lists:
`RemoteSavedKey.read` (gated, returns a key only with a row that has the
caller's address and certificate) and the two saves (gated, never sent). Every
check goes through `RemoteSavedKey`: publishing's sheet check, Publish and
Retry Failed (`PublishConnection.connect`), the import window's choose, Rescan,
Try Again and reconnect (`RemoteImportConnection.connect`), and the Server
sheet with an empty key field (`RemoteServerSheetCheck.key`). The deleted
`CardImportModel.check` and `ServerSheetModel.storedKey` were the last reads by
uuid alone. `setKey` and `deleteKey` appear only in `RemoteServices.swift`.
Runs already under way use their check's client and read no key.

#### Import window (#271 behaviour, D-18)

- **One window, nothing changed.** The import check reads the same key and
  contacts the same address, now with the row's pin and plain-http flag,
  which `RemoteSavedKey` has just shown to equal the window's. The error
  results and focus handling (`focusesGridWhenShown = false` on failure) are
  as before. The new failure (catalog unreadable) shows as the Keychain title
  with the catalog's message, as the Server sheet already did. `takeSaved`
  acts only when the name differs, which a single window never causes: its own
  Save goes through `serverSheetSaved` and `chooseServer`, as before.
- **Running import.** Nothing can rechoose the server during an import:
  `chooseServer`, album, range, Rescan, Edit and Remove are all guarded by
  `!isImporting`. `connectServer`'s `.changed` branch puts `failure` and
  `albumGone` back while importing. `loadServersAfterPublish` gives
  `.afterImport`, which does nothing. The importer keeps the client and
  `RemoteLinkTarget` it was started with, so links stay under the source
  address.
- **Reconnect after an import.** `importTask` is set to nil before
  `finishServerImport`, so `isImporting` is false when the reconnect lands.
  A rename is taken (`takeSaved`), and a move follows (`chooseAgain`). That
  goes through `chooseServer`, which clears `doneText`, and `follow` puts it
  back when `keepingSubtitle`. This matches scripted check C.
- **Rename.** In place: `browse.service` updates, and the project prefill
  follows unless the person typed a name. Selection, pages, album and range
  stay.
- **Removal.** `.leave` does what `removeServer` does after a removal
  (`closeServer`, `loadServers`). A removal can't start during an import: the
  import window's Remove is guarded, and publishing's `serverSheetRemove` is a
  no-op.
- **Following while the window is closed.** Closing the import window keeps
  `browse`, so a Save from Publish with the window closed reconnects there
  (check, albums, first page). design §11.1 rules this ("in front, behind,
  minimized or closed"). Noted only so QA expects the requests.
- **Residue, not a finding.** A Rescan cancels any page in flight
  (`browse.cancel()`), and that page task returns before resetting
  `isLoadingPage`. The old `.ready` path cleared the flag with
  `reloadPhotos`. Suppose Import is pressed while that Rescan connects (the
  old client is still set), and the Rescan then finds `.changed`. The flag
  stays true, so no further page loads until the import ends and the
  reconnect reloads. That takes a page in flight, a Rescan, Import pressed
  during it, and a Save in the other window, all within one check.

#### Server sheet (D-19)

`submit` builds the record before the task, from the same values as before,
and `RemoteServerSheetCheck.run` keeps the old steps in order: the D-16
removal check, the cancel check, the key, the cancel check, the check, the
cancel check, then the save. Page 2, the permissions note (`keyCanPublish`),
the error results and Cancel behave as before. A typed key and a name-only Save
take the old paths. On `.changed`, both hosts call `serverSheetSaved(now)`:
publishing returns to its sheet and rechecks with choices kept, and import
chooses the server as saved. That matches §11.2. In Edit with a new address
typed and the key field empty, the stored key still goes to the typed address,
as in #271. `RemoteSavedKey` compares the row with the opened record, not with
the form, so that case is unchanged.

#### Publishing (N7, Q1 to Q4)

- `PublishConnection.connect` uses the row's pin and flag. On `.changed`, the
  sheet check waits for the reload, Publish shows D-15's line or leaves the
  removal to D-13, and Retry Failed is called off silently (D-17). On
  `.unreadable`, the sheet and Publish show the start issue, and the retry is
  called off. C14 below covers the one case where the reload doesn't come.
- Q1 (`stepsFollowEachUpload`) and Q2 (`OriginalsTally`). The tally keeps the
  old loop's rules: offline photos are counted and not looked for, a photo
  with no source is counted in neither found nor a group, the first failure
  throws, and a cancel gives nil. The one change, progress counting a photo
  with no source, is the one status.md names. `==` now compares the reasons
  too.
- Q3: `closeSheetsForQuit` is debug-script only. Q4: the sheet and `publish
  print` draw from the same `checkTitle` and `checkDetail`, with the same
  styles.

#### New findings

| # | Severity | Where | Finding | Failure | Rule |
|---|---|---|---|---|---|
| C14 | Nit | `Sources/PhotoApp/Model/PublishModel.swift:365-369` (`runCheck`, `case .changed: break`), with `:266` (`serversChanged` rechecks only `if library?.showsPublishSheet == true`) and `:1112-1116` (`serverSheetCancelled`) | The sheet check's `.changed` leaves `check` at `.checking` and relies on the reload to check again. But that reload rechecks only while the publish sheet is showing, and the sheet is hidden while its own Server sheet is up. | (1) In the import window, Edit Server… saves Home with a new address and key, and the Keychain asks (an ad-hoc build): the Save holds Home's gate. (2) File ▸ Publish… opens on Home, and its check queues behind the gate. (3) Edit Server… in the publish sheet: the publish sheet hides. (4) The person answers the Keychain prompt. The Save writes its row, `serversChanged` finds `.connectionChanged`, but the sheet is hidden, so there is no `choose`. The check then gets the gate and returns `.changed`, and `break` leaves it there. (5) Cancel in the publish Server sheet: `serverBeforeSheet == serviceID`, so there is no `choose`. The publish sheet comes back showing the spinner and "Checking Home…" for good, with Publish off and no Try Again. Recovery: close and reopen the sheet, or Save in Edit Server…. Before this round the check went ahead, which was N7 itself, so this is new but much narrower. Fix: on `.changed(.connectionChanged(let now))`, call `choose(now, keepingChoices: true)` when the sheet is hidden. Or have `sheetDidClose` rerun a check left at `.checking` with no task. | Correctness (a state with no way forward in the sheet); design §3.3 |

#### `/security-review`

Yes, scoped to this round. A security review is already running in parallel.
This round changes every credential read and the checked save: the
`RemoteKeyGate` ordering, `RemoteSavedKey.read`, the guarded
`saveRemoteService(_:checkedWith:opened:keys:)`, and the import window's and
Server sheet's key paths (`RemoteServerChecks.swift`). It should confirm N7's
import side against e840ec9. I found nothing wrong there. No new parser,
subprocess, request kind or file writing. The allowlist, the request gates and
the temporary folders are unchanged. The fake server only records `Host` as
well.

#### `CLAUDE.md` Network rule (status.md)

The new sentence matches the code, with two wording points (neither blocks
anything):

1. "every write of a key with its row go through the account's
   `RemoteKeyGate`" is true of the two saves. Remove Server… also deletes keys
   (key, row, key again), outside the gate, and that is safe. To keep a later
   reader from adding a gate there, or from assuming one exists, write "every
   save of a key with its row".
2. "only a row with the address and trusted certificate the caller holds is
   contacted" is right for publishing and the import window. For the Server
   sheet, the read passes only while the row still has the address and
   certificate the sheet opened on, and the check then goes to the address the
   form shows. That can be a new address the person typed, which takes the
   stored key with it, as in #271. Suggested: "...and a key is given only
   while the row still has the address and trusted certificate the caller
   opened or holds, so a key saved for a new address never reaches the
   previous one".

Everything else in the rule is unchanged this round and still holds.
