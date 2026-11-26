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

(After the engineer's fixes: each finding with Fixed, Not fixed (and why) or
Withdrawn, and the commit.)
