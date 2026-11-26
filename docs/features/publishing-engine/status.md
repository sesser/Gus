Issue: #28 · Complexity: Hard

# Publish to Immich: status

Owner: swift-macos-engineer. Branch `feature/publishing-engine` (off `develop`).
Spec: the PRD (issue #28, **revision 7**, 2026-11-26) and [design.md](design.md)
(rulings in its §16 and §17: D-1 to D-19 and the correction to §3.6).

**State: Done** (2026-11-26, the F30 to F33, C14 and N9-wording round after
D-17 to D-19). The design review's sixth pass (F30 to F33), the code review's
sixth pass (C14 and two wording points on the proposed Network rule) and the
security review's fourth pass (the library lock sentence, N9) are answered
below under **F30 to F33, C14 and the lock sentence**, with tests that failed
without their fix and scripted checks. `swift test`, `Scripts/build-app.sh all`
and the CI toolchain build are recorded under **Build and test**. Open for
others: N9 itself (the saved-for address in the Keychain item: the owner's
decision; only the wrong sentence is corrected here), N8 and N10 (left as the
security review asks), the checks **For a person** (review.md's M1 to M8), the
owner's approval of the proposed `CLAUDE.md` Network rule, and **Follow-ups
proposed**. Next: code-reviewer's second pass on this round (it changes #271's
import window and the publish sheet's check: opus), the designer's for F30 to
F33, then qa-tester.

## F30 to F33, C14 and the lock sentence (2026-11-26)

Started from this file at 586cfd2. The reviewers' sixth-pass `code-review.md`
and `review.md` and the fourth-pass `security-review.md` were committed as
they were (6587d3f).

| # | Fix | Test or check |
|---|---|---|
| F30 | A check's row is read as the check begins, so a rename taken in place while the check is out (Publish's Save, `loadServersAfterPublish`) is newer than it. The window's record is now PhotoCore's `RemoteSourceRecord` (`Remote/RemoteServerChecks.swift`): the record plus a revision bumped by every rename taken (`take`). `connectServer` notes the revision when the check begins, and a passing check's row is taken only through `afterCheck(began:saved:importing:)`: nothing when a rename was taken since, or while an import runs; otherwise the row's name in place, as before. `ServerBrowse.service` is now read from it | `ServerKeyPairingTests.checkKeepsARenameTakenMeanwhile`: a real check reads "Home"; "Cellar" is saved and taken; the check's row leaves "Cellar"; renamed back to "Home" meanwhile, a row read as "Cellar" leaves "Home"; with no rename since, a renamed row is taken, the same name and a running import give nothing. Against the old rule (the row taken whenever no import runs): 2 issues; restored, passing. Scripted F30 below |
| F31 | `ImportGridView` is given the server's name (`model.browse?.service.name`, read in the parent's body), and the grid controller refreshes the cells on screen when it changes, so a marked cell's tooltip ("Already imported from …", "Published to … from this library") follows a rename at once. No reload, no request | Scripted F30 below (`import grid` now prints each cell's tooltip). UI glue in PhotoUI with no test target; the old behaviour was shown by the script on a bundle built with the name withheld |
| F32, F33 | `docs/USER_GUIDE.md`, import section: the design review's replacement text for the two-sheets passage (a check already out finishes against its own address with that address's key and saves nothing; from Publish the publish sheet comes back and checks again; a new key saved elsewhere also stops the save), "saved again from **File ▸ Publish…** (**Edit “‹name›”…**, **Edit Server…** or **Review Certificate…**)", and "The import window contacts a server only when you choose it, press **Add**, **Save**, **Try Again** or **Rescan**, save it from **File ▸ Publish…**, or finish an import from it." | Read in place, word for word against review.md |
| C14 | The publish sheet's check that ends on a change (`.changed(.connectionChanged)`) no longer only waits for the reload, which rechecks only while the sheet shows. PhotoCore's `PublishCheckRecovery` (`Remote/PublishCheckRecovery.swift`) records a check left waiting: if the sheet shows and its server list already has the change (the reload has come and gone), the server is checked again at once; otherwise it waits, and the sheet checks again when it comes back from its Server sheet (`sheetDidClose`), unless choosing a server (the reload's own recheck included) came first. The recheck reads the servers and chooses the server as saved, keeping every choice and D-15's line (`recheckSavedServer`, run in its own task so the cancelled check task's cancellation doesn't reach its reads). Nothing is contacted while the sheet is hidden, as before. A removal is still the reload's (D-13) | `PublishKeyPairingTests.checkLeftWaitingIsRechecked`: C14's sequence (hidden, reload first, then the check's end; back from the Server sheet: checks again), the check's end before the reload, hidden at the reload and shown before the check's end (checks at once), shown with the reload still to come (left to it; its choose clears the wait), a rename alone, a removal. Against the old `break` (nothing recorded, never rechecked): 4 issues; restored, passing. Not scripted: holding the gate across a Keychain prompt has no debug word |
| N9 (sentence only) | The claim that the library lock keeps a second copy of the app off the catalog is corrected in `RemoteKeyGate`'s doc comment, this file's N7 row and the proposed Network rule: the gate is per process and pairs the key with that process's catalog only; the library lock only keeps `photocli`'s writes off a library the app has open, and `LibraryModel.open` opens a library whose lock another process holds; copies of a library name the same Keychain item. The "never reaches the previous one" doc comments (`PublishConnection.connect`, `RemoteImportConnection`, `RemoteServerSheetCheck`) now say within this process and its catalog. N9's fix (the saved-for address in the Keychain item) is not done: the owner is deciding it. N8 and N10 are left | `grep` finds no other such claim in `Sources/`, this file or the user guide (whose "never sent to the old one" is about the two windows of one app) |
| Rule wording | The proposed Network rule says "every save of a key with its row" (Remove Server… deletes outside the gate, on purpose), and that a key is given only while the row still has the address and trusted certificate the caller holds (publishing, the import window) or opened on (the Server sheet, whose check then goes to the address its form shows). `RemoteKeyGate`'s comment says the same and that Remove deletes without it. `CLAUDE.md` not edited | Reading |

**Scripted F30 and F31** (2026-11-26). The debug bundle (`CONFIGURATION=debug
Scripts/build-app.sh library`) copied with identifier
`me.sesser.gus.debugtest.round7` and signed ad hoc, and a second copy
(`…round7old`) built with the old check (`takeSaved(saved)` whenever no import
runs) and the grid given no name; a fresh copy of the `photobench` scratch
library each run; the fake server; every launch with `--library-root`, never
activated, each quit by itself (exit 0). Script: Home added, one photo
imported (so cell 0 is marked), Publish's Edit renames it Cellar, then a
Rescan whose first answer is held 5 s (`fault slowcheck 5000`, the new `import
server rescan`, which doesn't wait), and during it Publish's Edit renames it
Attic.

| | This build | Old behaviour |
|---|---|---|
| Cell 0's tooltip after Cellar (no reload) | `Already imported from “Cellar”` | `Already imported from “Home”` |
| During the held check | Attic, connecting, project `Attic - All Photos` | the same |
| After the check | Attic, photos, project `Attic - All Photos`; cell 0 `… “Attic”` | **Cellar**, project `Cellar - All Photos`, while the saved list says Attic |

Round 6's scripts A, D and E run again on this build: their prints match round
6's except for the made-up certificate's fingerprint (random per run).

New debug-script words: `import server rescan` (as Rescan, without waiting);
`import grid` adds each cell's `tip '…'`.

## D-17 to D-19 (2026-11-26)

Started from this file at 944982c; the designer's rulings committed as they
were (aa3216e). #271's import behaviour is otherwise unchanged.

| # | Built | Test or check |
|---|---|---|
| D-17 | No code change (the retry was already called off silently, and `retryRefusal` refuses only a removal or an address change). This file's wording corrected: the N7 row below and DQ-F1 now say that, reopened, the results sheet shows the run unchanged; a removal or an address change shows the existing refusal with **Retry Failed** off, and after a certificate change alone the next **Retry Failed** runs and checks the server as saved | Reading (`PublishModel.retryRefusal`: `.serverRemoved`, `.addressChanged`, nothing for a certificate) |
| D-18 | The import window's check moved to PhotoCore as `RemoteImportConnection.connect` (`Remote/RemoteServerChecks.swift`): the key is read with the row as saved now (`RemoteSavedKey.read`, under the account's gate), and only a row with the window's address and trusted certificate is contacted; otherwise `.changed`, nothing sent. A catalog that can't be read is `.keychain` with the catalog's message, as the Server sheet shows it. Every check the window makes goes through it (choosing the server, Rescan, Try Again, the reconnect after an import). The rule for following is `RemoteSourceFollow.after(held:now:importing:)`: the same address and certificate with another name, `takeSaved` (in place: title, Source pop-up, inspector, Edit Server…'s record; the Project name follows unless typed; nothing contacted); another address or certificate, `chooseAgain` (`chooseServer`, so §11.1's table: selection, pages, album, range and a typed project name go, an earlier "Imported n photos" goes, destination and templates stay); removed, `leave` (as after Remove Server…); any of these during an import from it, `afterImport` (nothing changes). `ServerBrowse.service` is now a `var` the window updates. `loadServersAfterPublish` (run after every Save from Publish, whether the window is in front, behind, minimized or closed) applies the rule at once; a check that finds the change follows it; a check during an import that finds it restores the grid's state and touches nothing; the reconnect after an import (`connectServer(keepingSubtitle: true)`) follows the server as saved then, keeping the ending subtitle. Nothing brings the window forward or moves the keyboard. The old `CardImportModel.check` (key by uuid alone) is deleted | `ServerKeyPairingTests`: `importCheckWithSavedRow` (a rename connects and returns the renamed row; a new address and key, a certificate alone, a removal: `.changed`, the previous address gets no request), `importCheckWaitsForTheRow` (a Save between its key write and its row write: the check waits, contacts nothing, sees the new row), `sourceFollowRule` (every case, importing or not). Scripted checks A, B, B2, C, F below |
| D-19 | The Server sheet's check and save moved to PhotoCore as `RemoteServerSheetCheck` (`key`, `check`, `save`, `run`), which `ServerSheetModel.submit` calls for Save with a check and Trust Certificate, from either host. At the press: D-16's removal check first, then a typed key as before, or the stored key read with the row (`RemoteSavedKey.read` against the record the sheet opened on); a row with another address or trusted certificate ends it with `.changed`, nothing sent or written. At the save with the key field empty: the new `Catalog.saveRemoteService(_:checkedWith:opened:keys:)` reads the stored key and the row and writes the row under the account's `RemoteKeyGate`, only if the key is still the one the check used and the address and certificate still the opened ones; otherwise `.changed` (or `.removed`, D-16, no key left), nothing written. `ServiceSaveOutcome` gained `.changed`. On `.changed` the sheet calls its host's `serverSheetSaved` with the server as saved now: from Publish the publish sheet returns with that server chosen and checks it again, every choice and the description kept, no D-15 line; from Import the window reads its servers, chooses the server as saved (the grid takes the keyboard when it appears) and tells the publish side. No alert, no new string. A typed key, a name-only Save and Add are unchanged. `ServerSheetModel.storedKey` is deleted | `ServerKeyPairingTests`: `sheetBehindAtPress` (another address and key saved elsewhere, then a certificate alone: `.changed`, no request, the row and key the other window's), `sheetBehindAtSave` (the Save lands after the key read and the passing check: `.changed`, row not written over), `sheetKeyChangedAtSave` (a new key alone saved meanwhile: `.changed`, the row's name not written), `sheetUpToDateAndTypedKey` (not behind: saved as before; a typed key saved with what the form shows over the other window's Save), `sheetRemovedAtSave` (`.removed`, no row, no key), `sheetSaveHoldsTheGate`. Scripted checks D and E below |

**Fails without the fix.** The new tests were run against the old behaviour
put back in the PhotoCore code (the import check reading the key by uuid alone
and connecting to the record it was given; the sheet reading the stored key
without its row; the guarded save replaced by the old row write): 6 of 9 failed
with 8 issues (`importCheckWithSavedRow` 2, `importCheckWaitsForTheRow` 2,
`sheetBehindAtPress` 1 (the old check sent the other window's key to the
sheet's address, which refused it), `sheetBehindAtSave` 1, `sheetKeyChangedAtSave`
1, `sheetSaveHoldsTheGate` 1). The three that passed are the ones that should:
`sheetRemovedAtSave` (D-16 was already right), `sheetUpToDateAndTypedKey` (the
unchanged behaviour) and `sourceFollowRule` (new code: against a mutation that
ignores the certificate and the running import, 5 issues). Restored, passing.

**Every place that reads a server key** (after this round; `grep -rn
"\.key(account:" Sources` finds three):

| Where | Reads the key | Paired with its row |
|---|---|---|
| `RemoteSavedKey.read` | for a check: publishing (`PublishConnection.connect`: the sheet's check, Publish, Retry Failed), the import window (`RemoteImportConnection.connect`: choosing, Rescan, Try Again, the reconnect after an import), the Server sheet with the key field empty (`RemoteServerSheetCheck.key`, both hosts) | Yes: under the account's gate, with the row as saved now; only a row with the caller's address and certificate is given a key |
| `Catalog.saveRemoteService(_:key:keys:)` | the previous key, only to put it back if the row write fails (F2) | Not needed: never sent anywhere; read and written under the gate with the row |
| `Catalog.saveRemoteService(_:checkedWith:opened:keys:)` | the stored key, only to compare it with the one the check used (D-19) | Yes: under the gate with the row it compares and writes; never sent |

A run already under way (an import, a publish job, a retry past its check)
reads no key: it uses the client made by its check, whose key was read with its
row. `removeRemoteService` only deletes. The debug script's `import server
keychain fail|ok` only switches the in-memory store. The standalone importer and
`photocli` have no key store.

**Scripted checks** (2026-11-26). The debug bundle (`CONFIGURATION=debug
Scripts/build-app.sh library`) copied with identifier
`me.sesser.gus.debugtest.round6` and signed ad hoc; a fresh copy of the
`photobench` scratch library (3 JPEGs and a video) for every script; the fake
server reached as `127.0.0.1` and as `localhost` (the requests now record their
`Host`, printed by `import server fake requests [since]` after `import server
fake mark`); every launch with `--library-root`, never activated, each quit by
itself (exit 0).

| | What | Seen |
|---|---|---|
| A | Import window on Home (127.0.0.1), album Trip, two photos checked, a project name typed; Publish's Edit Server… saves the address as `localhost` | The window: Home at `http://localhost:…`, All Photos, no range, 0 of 30 selected, project `Home - All Photos`; every request after the Save to `localhost` (the Server sheet's check, the publish sheet's, then the window's check, albums, first page and thumbnails), none to 127.0.0.1 |
| B, B2 | The same, Publish's Edit Server… saves only the name Cellar | The window: Cellar at 127.0.0.1, still Trip, still 2 of 5 selected; a typed project name kept (B), the prefill following to `Cellar - Trip` (B2). After the Save: only the publish sheet's own check and album list (no page or thumbnail request from the window) |
| C | Six photos importing (each original held 2 s); Publish's Edit Server… saves `localhost` during it | Right after the Save: the list has `localhost`, the window still 127.0.0.1, 6 selected, importing 1/6; originals kept going to 127.0.0.1 while the publish sheet checked `localhost`. After the run: all six originals came from 127.0.0.1, then the window's reconnect went to `localhost` (check, albums, first page); window at `localhost`, 0 selected, subtitle **Imported 6 photos** kept |
| D | The import window's Edit Server sheet open (key empty) on Home at 127.0.0.1; Publish's Edit Server… saves `localhost`; then the stale sheet's Trust Certificate (a made-up certificate, `import server sheet review`) | The sheet closed, no alert; nothing sent to 127.0.0.1 after the press; the saved server unchanged (`localhost`, no pin); the window shows it and checked it once at `localhost` |
| E | As D, but the stale sheet's check is held 3 s (`fault slowcheck`) and Publish's Save lands during it (`trust nowait`) | The stale check's requests went to 127.0.0.1 with the key read before the Save, which belongs to that address; the Save landed meanwhile; the sheet then closed with nothing written (still `localhost`, no pin, where the old code wrote 127.0.0.1 and the made-up pin); the window shows the server as saved |
| F | The in-memory key store refusing, Rescan; then working again | `cantConnect(keychain)` as before (the existing title, untouched), then passed |

The scripts ran against this round's build only; the tests above are the
evidence against the old behaviour.

**User guide.** The import section now says that the window follows a server
saved again from **File ▸ Publish…** (a rename in place, a new address or
certificate reloads as if chosen again, a key saved for a new address never
goes to the old one, a running import finishes on its address first) and that
a Server sheet behind the saved server, key field empty, sends and saves
nothing and closes. No wording for it was found in design.md or review.md, so
the sentences are the engineer's, for the designer to check at review.

New debug-script words: `import server fake mark`, `import server fake
requests since` (with each request's host), `import server sheet trust nowait`,
`publish serversheet field address fakehost`, and `import server print` adds
`importing <done>/<total>` while an import runs.

## Fix round after QA (2026-11-26)

Started from this file at bc54ded. Code: 1c84496 (N7), a04d1ee (Q1), 82339ab
(Q2), 35ec122 (Q3, Q4); the CI toolchain fix to `PublishKeyPairingTests` and the
docs in the commit after. Scripted checks: the debug bundle
(`CONFIGURATION=debug Scripts/build-app.sh library`) copied with identifier
`me.sesser.gus.debugtest.round5` and signed ad hoc (and a second copy,
`…round5old`, built without the `quit` change), a fresh copy of a `photobench
generate --jpeg 3 --dng 0 --heic 0 --videos 1` library (`photobench import`) for
every script, the fake server, every launch with `--library-root`, never
activated.

| # | Fix | Test or check |
|---|---|---|
| N7 | Two halves, both closed for publishing. (1) A record held since before a Save: `PublishConnection.connect` (now with `catalog:`) reads the key and the row as saved now and contacts only a row with the address and trusted certificate it was given (`PublishServerChange.after`); otherwise it returns the new `.changed(PublishServerChange)` and sends nothing. (2) A Save between its key write and its row write: a re-read alone can't see it (the row is still the previous one while the Keychain already has the new key), so every key read for publishing and every key-and-row write share a per-account gate, `RemoteKeyGate` (PhotoCore `Remote/RemoteKeyPairing.swift`, a `Mutex` of held accounts and waiting continuations, FIFO). `Catalog.saveRemoteService(_:key:keys:)` holds it from reading the previous key through the row write and, on a failed row, the key's restore; `RemoteSavedKey.read` holds it around the key read and the row read. F2's write order is unchanged. The gate is per process and pairs the key with that process's catalog only. (Corrected 2026-11-26, security review N9: this said the library lock keeps a second copy of the app off the catalog. It does not: the lock only keeps `photocli`'s writes off a library the app has open, and `LibraryModel.open` opens a library whose lock another process holds. A second copy of the app on one library, or a copy of a library naming the same Keychain item, is not covered; N9 is the owner's to decide.) It is never held across a request; a Keychain access prompt holds it until answered, and another Save of the same server waits meanwhile. In the app: the sheet's check ignores `.changed` (the reload the Save posts checks the server again as saved, F28, or clears it, D-13); Publish gives up with D-15's line on a changed address or certificate, or leaves D-13's reload to say a removal; Retry Failed's check is called off (no ending, the run as it was), and reopened, the results sheet shows the run unchanged: a removal or an address change shows the existing refusal with Retry Failed off, and after a certificate change alone the next Retry Failed runs and checks the server as saved (D-17); a catalog that can't be read shows its error as the start issue (sheet and Publish) or calls the retry off. Nothing new is shown, no string added | `PublishKeyPairingTests`: `staleRecordNeverPaired` (a rename still connects; a new address and key, a certificate alone, a removal: `.changed`, the previous address's fake server gets no request), `waitsForTheRow` (the test holds the gate as a Save does, with the new key written and the row not: the check waits, contacts nothing, and sees the new row), `checkDuringSave` (a check started from the key store's write hook inside a real Save sees the Save whole), `saveHoldsTheGate`. Against the old connect (key only, no gate, no row): 3 tests failed, 5 issues. Against the re-read with no gate (the review's suggestion alone): `waitsForTheRow` 3 issues and `saveHoldsTheGate` 1; `checkDuringSave` passed then, as expected (without the gate its order is the scheduler's). Restored, passing |
| Q1 | Test only (AC20, R21) | `PublishJobTests.stepsFollowEachUpload`: an existing album, stacking with a linked original, concurrency 1; every upload answer held; a's released, b's held and the run stopped there: a is `.done` in the album, stacked on its original, and the only asset filed; b got no further. Against a mutation that defers every album and stack step to the end of a run not stopped (a second pass over the photos after the group): 4 issues; `linkAndCopy`, a run that completes, still passed under it, so the mutation is the one asked about. Restored, passing |
| Q2 | Check Originals' tally moved to PhotoCore: `OriginalsTally` (`Remote/PublishOriginals.swift`: `add(_:name:)` and `check(_:offline:sources:names:find:progress:)`, run on the caller's actor through `#isolation`). `PublishModel.OriginalsResult` is now a type alias for it; the sheet and the debug print are unchanged. Behaviour as before (offline counted and not looked for, a photo with no source checked and in no group, the first failed request stops it, a cancel gives nothing), except that progress also counts a photo with no source | `PublishJobTests.originalsTallyMatchesRun` (four photos: an original found, no mapped folder, two linked to assets the server no longer has; the tally's found, groups and names equal the run's stacked photos and `noOriginal` reasons, built into a tally with the same `add`; no write; progress 1 to 4; two offline photos counted and not looked for) and `originalsTallyFailureAndCancel`. New code, so "fails without" is a mutation: `found` not counted gave 3 issues; restored, passing |
| Q3 | The debug script's `quit` calls the new `PublishModel.closeSheetsForQuit()`: the waiting Server sheet and the return to the publish sheet are dropped, the Skip or New Copy question, the publish Server sheet, the publish sheet and the results close | Scripted, a fresh copy of the library each, killed at 90 s: the publish sheet up after a run; its Add Server sheet up; its Edit Server sheet up with a name typed; the results sheet with the import window open: each quit by itself in 11 to 12 s (exit 0). The same first three against a bundle built without the change: each killed at 60 s (exit 142) |
| Q4 | `publish print` prints `PublishText.checkTitle` and the new `checkDetail`, and the sheet draws its failed check's title and detail from the same two functions (styles unchanged) | Scripted: a server added in one launch, the next launch (its in-memory key store empty) opens the sheet: `check failed keychain 'The key couldn't be read' 'The Keychain returned an error: The specified item could not be found in the keychain.'`, and the snapshot shows those words (`round5/q4-Gus.png` in the session's scratch folder, read after it was written). Before: QA's 'The key couldn't be saved' (`ServerText.result`'s title, which the print used) |
| Q6 | Docs only (#302 is the export fix, not done here): the user guide no longer gives "an unchanged photo published again" as the example of an identical file, and says such a photo with a caption or capture time may not make one after a relaunch, so New Copy adds a second copy; this file's "byte-identical for everything tried" answer is corrected (task 6 below) | Reading |

Also checked, scripted (regression of D-15 and F28 with the new connect): the
publish sheet checked against the fake server, the import window's Edit moved
Home to `localhost`: the sheet showed the new address, checked again (checks
2), and a Publish then published 1 photo.

### N7 on the import side (fixed by D-18 and D-19, above)

Found in the fix round: the import window's check read the key by uuid with
the record its `ServerBrowse` was made with, never refreshed, so after the
publish sheet's Edit Server… saved a new address and key, Rescan or Try Again
sent the new key to the previous address for as long as the window stayed
open; and the Server sheet (both hosts) checked with the stored key read
without its row. Both are closed above.

### Design questions (fix round, ruled)

All three ruled by the designer on 2026-11-26 (design §17) and built above.
None open.

- **DQ-F1: Retry Failed given up because its server changed in the instant
  after it was pressed.** The Activity job ends with no message and the results
  sheet stays closed. Ruled D-17 (option (a)): silent, as under D-10. Reopened,
  the results sheet shows the run unchanged; a removal or an address change
  shows the existing refusal with Retry Failed off; after a certificate change
  alone the next Retry Failed runs and checks the server as saved.
- **DQ-F2: the import window when its server's saved address or certificate
  changed in the other window.** Ruled D-18 (option (a), with a rename taken in
  place and a running import left alone): §11.1.
- **DQ-F3: a Server sheet submitted with the stored key after the other window
  saved that server again.** Ruled D-19 (option (a)): §11.2.

## Fourth-pass wording fixes (2026-11-26)

The fourth-pass `code-review.md` and `review.md` were committed as they were
(f5de048). Comment and user guide only, no code change.

| # | Fix | Check |
|---|---|---|
| C13 | `PublishTemporaryFolders`' type doc comment no longer says the lock is taken atomically as the file is made: it says the lock is asked for in the same `open` that makes the file (`O_EXLOCK`), that making and locking are not atomic (another copy's cleanup can lock the new file between the two), and that a launch whose lock fails tries a new name (`lockAttempts`, security N6(a)) | `swift build` clean (2026-11-26); `git diff` shows only comment lines in `Sources/` |
| F29 | `docs/USER_GUIDE.md` (publish section, D-15): "that Publish is given up: nothing is sent" now reads "nothing is uploaded or changed on the server" | Read in place |

## Fourth review round (2026-11-26)

Started from this file at 41f6d0f. The designer's and reviewers' files
(`design.md` with D-14 to D-16, `review.md`, `code-review.md`,
`security-review.md`) were committed as they were (9773e03). Engine e603c77,
app cd55215.

| # | Fix | Test or check |
|---|---|---|
| C11, L2 (D-15) | On a reload where the chosen server's address or trusted certificate changed (`PublishServerChange.connectionChanged`), a Publish being confirmed and the Skip or New Copy question are given up (`cancelSheetWork()`, `question = nil`), as removal does, and the line **This server's address or certificate changed. Nothing was published.** shows under Server, below the address and Not encrypted lines (`AnnouncedIssue`, announced, and the Server pop-up's hint; new catalog key). The recheck keeps every choice and the description (F28). The line shows only when something was given up; it goes when Publish is pressed again, a server is chosen, added or saved from the sheet, the server is removed (D-13's line instead) or the sheet is next opened. The invariant is enforced where a run starts, not only by the reload: `requestPublish`, after its check and records read, and `answer(skip:)`, before `start`, read the server as saved now (`PublishServerChange.since(_:in:)`, PhotoCore, over the new `Catalog.remoteService(id:)`) and start nothing unless the address and fingerprint are the ones checked; a change shows the line, a removal leaves D-13's reload to say so, a catalog that can't be read shows its error as the start issue. While `answer` reads, it counts as a Publish being confirmed (Publish dimmed, and a change or removal arriving then cancels it). A rename or a new key alone gives nothing up | `PublishRulesTests.destinationSinceConfirmed` (rename, address, certificate, removal, a record never saved, against a real catalog); with `since` stubbed to `.unchanged` (no check, as before) it failed with 4 issues; restored, passing. Scripted: `30-publish-address-changed-question-given-up.png` (3 photos published, Publish again asks Skip or New Copy, the import window's Edit moves Home to `localhost`: the question is gone, the line shows, the new address is checked (checks 3), the description kept; a scripted New Copy afterwards starts nothing); `31-publish-address-changed-while-confirming.png` (the fake server's check held 5 s, Publish pressed, the address changed meanwhile: confirming ends, the line shows, the new address is checked, and 6 s later no run has started: Activity none) |
| D-16 | `Catalog.saveRemoteService(_:)` inserts only a record with no id and otherwise updates, so a removed row is never recreated (GRDB's `save` inserted). `saveRemoteService(_:key:keys:)` checks the row before touching the key store and returns the new `.removed` (deleting the account's key) when it is gone, and again when the row's update finds nothing after the key was written. `removeRemoteService` deletes the key once more after the row, so a Save whose key and row landed between Remove's two steps leaves no key. `Catalog.renameRemoteService(id:to:)` changes only the name of the row as saved now (nil when gone). `ServerSheetModel.submit` (shared by both hosts): a name-only Save renames; a checked Save, and Trust Certificate (which submits), reads the row before the Keychain and the network; a removed server reaches the new `ServerSheetHost.serverSheetFoundRemoved`, with no alert and no new string. Publish: the Server sheet closes, the servers are read again, and the sheet comes back in D-13's removed state (or No saved server), no other server chosen. Import: the sheet closes, a removed source is closed as after Remove Server…, the servers are read again and the library told. A failed write of a name-only Save still leaves the sheet as it was (unchanged from #271) | `RemoteConnectionTests.saveNeverRecreatesRemoved` (typed key, no key, pinned certificate, the plain write and a rename after a removal: no row, no key; Add unaffected), `saveAndRemoveInterleaved` (a removal landing after Save's check as its key is written; Save's key and row landing between Remove's key and row), `renameKeepsWhatAnotherWindowSaved`. With `save` back, no pre-check, no `.removed` and the rename's row check dropped, the first two failed (1 issue each, at the first expectation); with only Remove's second key delete dropped, `saveAndRemoveInterleaved` failed at its key expectation; restored, passing. `renameKeepsWhatAnotherWindowSaved` pins a function that didn't exist before (the old code saved the sheet's copy, address and all, by reading). Scripted: `32-publish-name-only-save-server-removed.png` (Home and Other saved, Edit “Home” from Publish, Home removed in the import window, the name changed and Save: the Server sheet closes, the servers are Other only, the sheet shows None and **This server was removed.**, Publish dimmed); a checked Save (a key typed) after Home, the last server, was removed: the fake server's request list is the same before and after Save, the servers are none, the sheet shows No saved server (`s33`, printed); the import window's own Edit sheet after Home was removed there: Save closes it, no server and no source (`s34`, printed) |
| C12 | `PublishJob.beforeFirstPhoto` (internal, tests only) is awaited after the job's own reads and before its first photo | `PublishJobTests.stopInsideRetryJobBeforeFirstPhoto`: the job waits there, the test cancels it, `retry` returns nil, nothing was written and one upload is still the only one; the same job then retries both photos. With `calledOff` set to `false` it failed (1 issue: the run came back stopped); restored, passing |
| N5 | The base folder is made with mode 0700, and an existing one owned by the user is set to 0700. Before anything is listed or removed, `lstat` must find a real folder (not a symbolic link) owned by this user, else cleanup does nothing. Both `open` calls carry `O_NOFOLLOW`, so a lock name that is a symbolic link is never opened (its folder then stays). The launch folder is made 0700 too | `PublishRulesTests.temporaryFoldersNoLinks` (modes; a symbolic-linked base whose target keeps its file; a `.lock` link whose folder and target stay). Against the old behaviour (new signatures, old rules) it failed with 4 issues; restored, passing |
| N6 | `Launch.make` tries up to 8 new names when a lock can't be taken (`EWOULDBLOCK` when another copy's cleanup took the new name's lock first, or any other refusal) and never makes a folder in the base without its held lock. If no name locks, or the base isn't the user's own folder, the launch works in a folder of its own beside the base (`<bundle id>.publish-<UUID>`, mode 0700), which no other launch's cleanup reaches. An entry with no lock file is removed only when it hasn't changed for a day (`unlockedAge`, by `lstat`'s modification time; `removeLeftovers(in:now:)`) | `temporaryFoldersLockRetry` (the first name's lock held elsewhere: the second name is used and locked, no folder for the first; no name lockable: a folder beside the base, nothing new in it) and `temporaryFoldersLockLessOnlyWhenOld` (a running launch whose lock file was removed keeps its folder, and it goes a day later). Against the old behaviour they failed with 7 and 1 issues; restored, passing. `temporaryFoldersPerLaunch` now ages its lock-less folder by a day |
| N2 addendum | `ImmichClient.addToAlbum`'s per-photo errors go through `RemoteAnswer.shownText` (trimmed, cut at 200 characters, empty as none), the rule `serverMessage` now also uses (`ImmichClient.refusals`) | `PublishRulesTests.albumAddErrorCut` (5,000 characters to 200, the same as a top-level message; whitespace trimmed; empty and missing as none; `duplicate` and successes left out). Without the cut it failed with 5 issues; restored, passing |
| Manual checks | The checks below cite review.md's current M1 to M7 | Reading |

Left as they are, and why:

- **N6's fallback folder outside the base** is not removed by a later launch
  after a crash (nothing else knows it). It is used only when the shared base
  can't be locked 8 times running or isn't the user's own folder, both of which
  need something else interfering with the temporary folder; the alternative,
  failing every run with a new cause and string, costs more than the leftover.
- **The pre-check reads the catalog** before the Keychain on a checked Save from
  either host: a catalog that can't be read now shows its error in the sheet
  (as the save's own catalog failure already did) instead of going on to the
  check.
- **`answer(skip:)` now reads the catalog** before starting, so the run starts a
  few milliseconds after the alert closes; the button bar may show **Checking…**
  for that moment (`isConfirming`).

New debug words: `publish print` adds `changedLine` and `question up
‹address›|-`; `publish answer …` waits for the answer's read and prints
`started` or `not started` with the start issue.

### Snapshots (fourth round)

The debug bundle (`CONFIGURATION=debug Scripts/build-app.sh library`) copied
with identifier `me.sesser.gus.debugtest.round4`, signed ad hoc; a fresh copy of
a new `photobench generate --jpeg 3 --dng 0 --heic 0 --videos 1` library
(`photobench import`) for every script; the fake server with `fault permissions
all`; every launch with `--library-root`. Each PNG was read after it was written.
In
`/private/tmp/claude-501/-Users-randy--claude-spares-spare-ZSbkzm/7f274175-835d-4217-a958-c2a7b08f08df/scratchpad/round4/shots/`:

- `30-publish-address-changed-question-given-up.png`: D-15's line under the
  new address and the Not encrypted line, Home checked again, Publish enabled.
- `31-publish-address-changed-while-confirming.png`: the same after a Publish
  being confirmed was given up.
- `32-publish-name-only-save-server-removed.png`: D-16 from Publish: Server
  None, **This server was removed.**, Album dimmed, Check Originals and Publish
  dimmed.

Not captured: the Skip or New Copy alert closing (an alert is a window the
snapshot can't draw; the print shows `question -`); the announcement
(VoiceOver).

## Third review round (2026-11-26)

Started from this file at eb34859. The designer's `design.md` and `review.md`
were committed as they were (b16e129).

| # | Fix | Test or check |
|---|---|---|
| F24 (D-12) | The rule is in PhotoCore, one for the button and the job: `PublishRun.retryVersionIDs(laterPublished:)` (the candidates less the photos not uploaded that a later run published; the run's own uploads are never asked about), `offersRetry(laterPublished:)` and `retrySentByLaterRuns(laterPublished:)`; `Catalog.laterPublications(of:)` reads the later publications. `PublishJob` now takes its retry list from `retryVersionIDs`, so what R23 covers and counts is unchanged, and an empty retry started anyway still ends as before (no new non-ending). The app reads the later publications when the results sheet appears, when its run changes (`resultsRunID`) and when a publish ends with the sheet open; only the newest read lands. With nothing left the button is gone and the caption **A later publish already sent the photos left to retry.** stands in its place (new catalog key, "Publishing (issue #28)"); `retry()` reads them again after the servers and starts nothing then (no message, no ending, the sheet stays). Counts, lists, header and Activity message unchanged | `PublishRulesTests.retryNothingLeftRule` and `PublishBoundaryTests.retryNothingLeftAfterLaterRun` (a fault-stopped run, later runs publishing its photos one by one, the catalog read, the job sending nothing). With the rule stubbed as before (the candidates, `offersRetry`) they failed with 5 and 2 issues; restored and passing. Scripted: `27-results-retry-sent-by-later-run.png` (caption, no button; a scripted Retry Failed is refused, Activity still 2 messages); `23a`, `23`, `23b` below |
| F25 (D-13) | `PublishServerChange.after(reload:chosenID:before:)` (PhotoCore) tells a reload's meaning for the chosen server. Removed: `chosenServerWasRemoved()` gives up the check, albums, Check Originals and a Publish being confirmed (`cancelSheetWork`), clears the server, check, client, albums, album choice (None), folder map, links, the Skip or New Copy question and the start issue, returns from the folder map page dropping its unsaved pairs, and shows **This server was removed.** (announced, `AnnouncedIssue`; also the Server pop-up's hint) until another server is chosen or added; with no saved server left, the No saved server state and no line. The folder-map row and the "no original can be found yet" line show only with a chosen server, and `showFolderMapPage` refuses without one. Show in, stacking, the file settings and the description stay | `PublishRulesTests.chosenServerChange` (with the rule stubbed to the old "reload changes nothing", 4 issues; restored, passing). Scripted: `26-publish-chosen-server-removed.png` (Server None, the line, Album None dimmed, no folder-map row or line, Check Originals and Publish dimmed; the print shows check idle, albums empty); `26b-folder-map-before-removal.png` then `26b-folder-map-server-removed.png` (back on the main page, pairs dropped, a scripted `map open` refused); `26c-another-server-chosen.png` (the line gone, checked, Publish on); `26d-check-failed-before-removal.png` then `26e-last-server-removed.png` (No saved server, no line, check idle) |
| F26 | `ReasonGroup`'s lines in a `VStack(alignment: .leading, spacing: 4)` at full width, leading | Scripted, 12 photos, one group open: `06-check-originals-result.png` (ten lines of different widths and "And 2 more." on one leading edge) |
| F27 | File Settings shows `editor.watermarkIssue ?? settingsIssue`, so a non-PNG pick says so while the image is missing | Scripted, the watermark file deleted between two launches: `29a-file-settings-watermark-missing.png` ("The watermark image is missing."), then a non-PNG picked: `29b-file-settings-not-png-over-missing.png` ("“notpng.png” is not a PNG image.") |
| F28 | The same rule: the chosen record's address or trusted certificate changed in a reload runs `choose(_:keepingChoices: true)`, only while the sheet shows (nothing is contacted otherwise). A rename alone does nothing | `chosenServerChange` (address, certificate, rename, another id). Scripted: Trip, Archive and a description chosen, then the import window's Edit set the address to `localhost`: the sheet shows the new address, checks 2 (was 1), Trip, Archive and the description kept (`28-address-changed-checked-again.png`); a rename then: checks still 2 |
| User guide | Retry Failed is not offered when a later publish to that server already sent every photo it would cover, with the caption; the publish sheet when its server is removed or its address or certificate changed in the import window | Reading |

Also fixed, found by the snapshots: **the results' Failed list drew the first
photo's row for every failed photo** (`IMG_00001.JPG` twice where the run had
`IMG_00001` and `IMG_00002` failed; the print and the counts were right). The
section nested a `ForEach` over each photo's failures with their offsets as ids
inside a `ForEach` over photos; it is now one flat `ForEach` with an id per photo
and failure. Seen fixed in `27` and `23a` (both names).

New debug words: `publish settings watermark <file>` (as Choose Image…), `import
server sheet field address fakehost` (the fake server named `localhost`); the
publish print adds `removedLine`, `mapRow`, `checks <n>` (sheet checks started)
and the File Settings page's issue; `publish results retry` prints `refused`
when nothing starts, and the results print shows the caption.

### Snapshots (third round)

The debug bundle (`CONFIGURATION=debug Scripts/build-app.sh library`) copied
with identifier `me.sesser.gus.debugtest.round3`, signed ad hoc; a fresh copy
of a new `photobench generate --jpeg 3 --dng 0 --heic 0 --videos 1` library
(`photobench import`) for every script, and a 12-photo one for `06`; the fake
server with the publishing permissions; every launch with `--library-root`.
Each PNG was read after it was written. In
`/private/tmp/claude-501/-Users-randy--claude-spares-spare-ZSbkzm/7f274175-835d-4217-a958-c2a7b08f08df/scratchpad/round3/shots/`:

- `06-check-originals-result.png`: F26, twelve photos.
- `23a-results-older-run-one-photo-left.png`: a fault-stopped run after a later
  run published one of its photos: Retry Failed offered (two still to send).
- `23-results-newest-after-retry.png`: that run retried: it ended last, opens by
  default and is first in the Run pop-up (D-9); the photo the later run
  published still counts as Failed, so the caption shows (D-12).
- `23b-results-later-run.png`: the later run, nothing to retry.
- `27-results-retry-sent-by-later-run.png`: F24, a later run published all.
- `26-publish-chosen-server-removed.png`, `26b-folder-map-before-removal.png`,
  `26b-folder-map-server-removed.png`, `26c-another-server-chosen.png`,
  `26d-check-failed-before-removal.png`, `26e-last-server-removed.png`: F25.
- `28-address-changed-checked-again.png`: F28.
- `29a-file-settings-watermark-missing.png`,
  `29b-file-settings-not-png-over-missing.png`: F27.

Not captured: a failed check followed by removal with another server left (the
removal sets the same idle state, printed in `26e`); the announcement of the
removal line (VoiceOver).

## Second review round (2026-11-26)

Started fresh from this file at a382a7b. The reviewers' and designer's files
were committed as they were (cbbbc24).

| # | Fix | Test or check |
|---|---|---|
| F19 (blocker) | Cause confirmed: `canPublish` read `client` (`@ObservationIgnored`) before `serverInfo`; while the check ran `client` was nil, so the guard stopped there and the button's view observed nothing the passing check changed. `client` is observed now (and `session`, which `isConfirming` reads). Searched the publish, results and Server sheet code for state drawn but not observed: `client` was the only one; `canPublish` and `canCheckOriginals` now read only observed state (the watermark file's presence aside, as before). Found on the way, outside these sheets: the Import window's `ServerBrowse.client` has the same pattern (see **Follow-ups proposed**) | A/B on screen, both copies built from this tree, the sheet opened and the check waited for, nothing pressed and no page visited: `01-publish-main.png` (Publish 3 Photos enabled) and `01b-publish-main-client-unobserved.png` (the same build with only `@ObservationIgnored` put back on `client`: dimmed, while a fresh computation printed "enabled" before this round) |
| F20 (D-6) | "Originals found: ‹found› of ‹checked›." and "Publishing stopped. Photos on the server: ‹n› of ‹total›.", plain catalog entries (no plural variation); the old keys removed | `LocalizationTests`; scripted: "Originals found: 0 of 1." (`25-check-originals-one-photo.png`), "Publishing stopped. Photos on the server: 2 of 3." (`10-results-stopped.png`) |
| F21 (D-7) | One published photo: "Skip leaves it as it is on the server. New Copy publishes it again; …" (its own catalog entry); the last sentence unchanged | Scripted, one photo published then offered again: the question printed with the singular text (the alert itself is a window the snapshot can't draw) |
| F22 (D-8) | A photo whose upload is done reports Uploading with its number as it finishes its steps; the job's first report is the first photo's own step, numbered 1, never "0 of N" | `retryFinishingStepsReportsUploading` (failed without the fix: every report Rendering 0) |
| F23 (D-9) | `endedRuns` by end time (`PublishRun.byEnding`, ties keep their order); File ▸ Publish Results…, Show Results… without a run and the Run pop-up (latest first) follow it. No reason not to | `PublishRulesTests.endedRunsByEndTime` (failed in start order); scripted: two runs, the older retried: the pop-up lists it first and it opens by default (`23-results-newest-after-retry.png`) |
| C8 | The awaited-answer count is raised and lowered inside each upload's `wait` lock, and its change is told inside the count's lock (order: wait, count, progress), so an upload's end is never counted before its start and two uploads' changes arrive in the count's order | By reading (a window of a few instructions); the stop tests pass |
| C9 | `ProgressCounter` delivers each report inside its lock, so reports arrive in the order of their states; both listeners are non-blocking (the app's makes a task, the tests' appends under a lock of their own). This makes the determinism argument below hold for `stopKeepsEndingInEveryReport` | Structural, below; the publishing suites 30 of 30 |
| C10 | `canPublish` and `canCheckOriginals` need the chosen server to still be saved | Scripted: two servers, Home chosen and checked, Home removed in the import window: Server reads None, Publish and Check Originals dimmed, a scripted Publish refused (`26-publish-chosen-server-removed.png`) |
| R23, AC21, D-10 | `PublishRetry` (PhotoCore) runs a retry once it holds the slot: the check (`PublishConnection.connect`, moved from the app), then the job. A Stop during the check, or before the retry has started on any photo (`PublishJob.retry` returns nil), is `calledOff`; a Stop asked before the app acts on a check's result wins over it (`PublishRetryOutcome.ended(stopAsked:)`). Called off, the app only releases the slot: no `finish`, no message, no announcement, no sheet; the run, its end time, ending, results and retry coverage are untouched, so it rejoins the results where its end time puts it. Until the check returns the job shows the usual ending (Stopping…, Stop dimmed); the detail stays **Checking “‹name›”…** until the job's first report. Both cancellation exits of the old `retryRun` are gone with it | `stopDuringRetryCheck` (fault stop with an unreached photo; a Stop while the real check's answer is held: no write request, called off; a Stop racing a check failure: called off; a Stop after the check, before any photo: called off; the next Retry Failed publishes the unreached and failed photos). Without the fix (cancellation after the check turned into the person's Stop, as before) it failed 3 expectations. `retryCheckFailsOrRuns` (D-5's ending, and a Stop asked first wins). `PublishRulesTests.retryOutcomeRule`. Scripted (`16-activity-retry-checking.png`, `19-activity-just-after-stop-during-retry-check.png`, `21-results-after-stop-during-check.png`, `22-results-next-retry.png`): the message's post time and count unchanged, Retry Failed still offered with the unreached photo, the next retry published all three |
| `job(...) == nil` in `execute` | Reachable only if the `LibraryModel` that owns this model were gone (it lives for the app's life, held by `LibraryLoader`), so not reached. Retries no longer go through `execute`: a retry whose job can't be built is called off (no ending). A new run keeps writing the person's Stop there, as it never started | By reading |
| D-11 | Show Results… on a run's Activity row is dimmed while that run is retried, its check included (`isBeingRetried`); `showResults(id)` never opens another run in its place | Scripted: "Show Results… dimmed" during the retry's check, "enabled" after (`16-activity-retry-checking.png`) |
| Network rule wording | Both points taken in the proposed text below: the base folder is named from the fixed `AppBranding.bundleIdentifier`, shared by every copy; cleanup also removes folders with no lock file | Reading |

Also fixed, found by the snapshots:

- **Export's preview kept no watermark after the same image was chosen again**
  (its file had gone): the identifier is unchanged, so `settings` alone didn't
  reload it. `useWatermark` now loads it (`18-export-watermark-chosen.png`
  shows it; the same on `develop`, older than this branch).
- **Retry Failed on a run with nothing to retry**: the debug script could start
  one (the sheet shows no button then); `retry` now refuses it.
- **A scripted run that ends with a sheet up never quits** (AppKit ignores the
  quit, #276): explains the combined script's timeout of the first round. The
  scripts now close the sheet before `quit`.

New debug words: `publish scroll top|bottom|<points>` (the library window's
sheet, so a snapshot shows what is below the fold), `publish activity` (the
newest message, whether its Show Results… is dimmed, and when it was posted),
`publish results run <n>` (the Run pop-up's item, latest first; the results
print lists the pop-up).

### Snapshots (second round)

The debug bundle (`CONFIGURATION=debug Scripts/build-app.sh library`) copied
with identifier `me.sesser.gus.debugtest.round2`, signed ad hoc; a fresh copy
of a `photobench generate --jpeg 3 --dng 0 --heic 0 --videos 1` library
(`photobench import`) for every script; the fake server with the publishing
permissions. Each PNG was read after it was written. In
`/private/tmp/claude-501/-Users-randy--claude-spares-spare-ZSbkzm/7f274175-835d-4217-a958-c2a7b08f08df/scratchpad/round2/shots/`:

- `01-publish-main.png`: opened, check waited for, nothing pressed: **Publish 3
  Photos enabled** (F19). `01b-publish-main-client-unobserved.png`: the A/B
  copy, dimmed.
- `02-publish-new-album-taken.png`: New Album… named "Trip" (an album of that
  name exists): the Name field, the note and **Use the Existing Album**.
- `03-publish-archive-stacked.png`: Archive with stacking: the warning under
  Show in.
- `06-check-originals.png`: scrolled down, one folder mapped, Check Originals
  enabled. `06-check-originals-dimmed.png`: a key without `stack.create`: the
  Stacking issue and Check Originals dimmed. `06-check-originals-result.png`:
  "Originals found: 0 of 3." and three "Nothing at the mapped path".
- `25-check-originals-one-photo.png`: one photo: "Originals found: 0 of 1." (F20).
- `09-results-fault-stopped.png`: a run stopped by a rejected key: header line,
  counts, the 401 wording, Retry Failed.
- `10-results-stopped.png`: the person's Stop with two answers held: "Publishing
  stopped. Photos on the server: 2 of 3.", Not Finished, the caption beside
  Retry Failed.
- `13-results-retry-check-failed.png`: that fault-stopped run retried with the
  key revoked: "Publishing stopped: The server rejected this API key.". Retry
  Failed stays enabled, as designed: a check failure is a fault (D-5), so the
  unreached photo stays covered, and the server is still saved.
- `15-activity-stopping.png`: ending with an answer awaited: "Stopping. Waiting
  for “Home” to answer…", Stop dimmed, spinner.
- `16-activity-retry-checking.png`: the retry's check: "Checking “Home”…", Stop,
  spinner; the run's message below with **Show Results… dimmed** (D-11).
- `19-activity-just-after-stop-during-retry-check.png`: 100 ms after Stop during
  that check: the job gone, the run's message unchanged (posted at the same
  time, one message), Show Results… enabled. The "Stopping…" moment itself was
  over before the snapshot: the cancelled check returned at once.
- `21-results-after-stop-during-check.png`: the same run's results, unchanged.
- `22-results-next-retry.png`: the next Retry Failed: all three published.
- `23-results-newest-after-retry.png`: two runs, the older retried last: it
  opens by default and the Run pop-up shows it first (F23).
- `24-sheet-dimmed-behind-one-photo-question.png`: the sheet behind the Skip or
  New Copy alert for one photo; the alert is its own window and doesn't draw
  here (its text is in the script output, F21).
- `26-publish-chosen-server-removed.png`: C10.
- `17-export-watermark-missing.png` (after Export pressed: "The watermark image
  is missing. Choose it again."), `17b-export-watermark-not-png.png`,
  `18-export-watermark-chosen.png` (issue gone, the mark drawn in the preview):
  Export scrolled to its watermark section.

Shots 01 to 06 were taken before the last two app changes (the retry guard and
the watermark reload), which change nothing they show. Not captured: the Skip or
New Copy alert itself (above), the Stopping… moment of a Stop during a retry's
check (above), a retry that only finishes steps showing "Uploading 1 of 2" (it
ends before a print can catch it; `retryFinishingStepsReportsUploading` covers
it).

## Review round (2026-11-26)

Started fresh from this file at b244b48. The three review files were committed
as they were (666b6fe). Engine fixes and their tests: 8b12a6b; the app, strings,
user guide and this file follow it.

### Code review

| # | Fix | Test or check |
|---|---|---|
| C1 (= F2) | `ProgressCounter` learns of the person's Stop (`withTaskCancellationHandler` around the run: `stopping()`), so every later report says ending; the model holds the stop in `PublishSlot.isStopping`, and a report sent before the stop that arrives after it stays ending (`PublishProgress.followed(by:)`). Activity, File ▸ Stop Publishing and the quit rule read `PublishModel.isEnding` | `stopKeepsEndingInEveryReport` (fails without the fix: no ending report at all), `PublishRulesTests.progressCounter`; scripted D-1 run below |
| C2 (= F3) | `PublishSlot` (one publish at a time): a run takes it in `start`, a retry right after re-reading the servers and before its check; `isPublishing`, `canPublish`, `retryRefusal`, File ▸ Publish… and `begin` read it; `start` refuses with "A publish is already running." when it is held. The retry's check runs inside the run's task (D-2) | `PublishRulesTests.oneAtATime`; scripted: during a retry's slow check the reopened results say "A publish is already running." and Publish is dimmed |
| C3 (= F7) | `ExportSettingsEditor.onWatermarkPicked`: Export routes Choose Image… to `ExportModel.useWatermark` again, which clears its issue on a good pick; the debug script's `export set watermark=` takes the same route (`watermarkPicked`) | Scripted, two launches: "The watermark image is missing. Choose it again." after Export, gone after a good pick, "“notpng.png” is not a PNG image." after a bad one |
| C4 | `publishSources` orders links as PRD revision 6 says: the photo's own, then for a copy its original's (the master's default version), then the pair partner's; only the first is tried | `pairBothLinkedAndCopy` (fails without: the copy took the JPEG's link), `pairJPEGLinkedAndCopy` |
| C5 (= L1) | `PublishTemporaryFolders`: each launch has its own folder under `$TMPDIR/<bundle id>.publish/`, held by an exclusive `flock` on `<launch>.lock` taken atomically as the file is made (`O_EXLOCK`), before the folder exists, for the life of the process. `removeLeftovers` (at launch) removes only folders whose lock it can take (their process has ended) and folders with no lock file | `PublishRulesTests.temporaryFoldersPerLaunch` (fails when cleanup removes the whole base, as before) |
| C6 | Test only: the fake server releases held upload answers one by one (`releaseHeldAnswer(fileName:)`), and `PublishJob.onRecorded` tells the test when one is recorded | `stackOrderWhicheverUploadFinishesFirst`, both orders. With `sequencer.turn` removed it failed (wrong primary, wrong members, the creates not one after the other) |
| C7 | The v17 comment is back on `addHDRChoice`; v18's on `addPublishing`. Comment only | Reading |
| Q1 | Ruled by PRD revision 6 (R11, AC7) as C4 above | as C4 |

### Design review

| # | Fix | Test or check |
|---|---|---|
| F1 | Publish N Photos runs `confirm()`, a task the model keeps; the sheet closing by any route (`LibraryModel.showsPublishSheet` → `sheetClosed`) starts a new session and cancels it, the check, albums and Check Originals. After every wait `requestPublish` gives up unless the same session is open and the same server chosen, and it starts the run with the server, client and check it got (the question carries them too). The form is dimmed while confirming; Cancel is not | Scripted: Publish pressed against a 2.5 s check, Cancel: nothing uploaded, no job, Publish enabled again |
| F2 | As C1. Detail per D-1: **Stopping…**, or **Stopping. Waiting for “‹name›” to answer…** only while an answer is awaited (`RemoteUploadEnding` counts awaited answers, `PublishProgress.awaitsAnswer`) | as C1; scripted: the waiting detail twice a second apart, Stop dimmed |
| F3 | As C2. Per D-2 the retry's check is the run's: Activity job at once, indeterminate, **Checking “‹name›”…**, Stop on. Every ending sets `endedAt` (`finish`) | Scripted: the job's detail and Stop during the check; the retried run's row and results updated |
| F4 | Servers are read again when the results sheet appears and whenever a server is added, edited or removed in either window (`CardImportLibrary.remoteServersChanged`); `retry` re-reads them before deciding, and a refusal then leaves the sheet open with its reason | Scripted: Remove Server in the import window, then Publish Results: "This server was removed.", Retry dimmed |
| F5 | `choose(_:keepingChoices:)`: back from editing the server already chosen, only its folder map, links and names are read again and the check runs; remembered choices load only when the selection moves to another server (a new one included) | Scripted: Archive and a description set, Edit Server, rename, Save: both kept |
| F6 | **Not reproduced as written.** With the old binding restored in a bundle, typing `/mnt/media` a character at a time through the field editor (the path key presses take) kept every slash. Fixed anyway, as the designer ruled the transform wrong either way: the field holds the text as typed; `keptServerPath` is used for matching and the example, and Done saves `kept` | `PublishRulesTests.serverPathAsTyped` (fails without: `//` in the matched path); scripted on the old and new bundles |
| F7 | As C3 | as C3 |
| F8 | `endedRuns` (ended, not the one holding the slot) feeds File ▸ Publish Results…, `resultsRun`, `showResults` and the Run pop-up | Scripted: Publish Results dimmed during the first run, enabled after |
| F9 | `begin` and `choose` set the check to checking and drop the client before any wait; `canPublish` needs `!isLoading` and a client; the empty state shows only once servers are read (a spinner before) | Scripted: `publish sheet nowait` prints check checking, Publish dimmed, pop-up dimmed |
| F10 | Ruling D-3: the untrusted certificate's title and detail in the Server section, with Review Certificate… | By reading (the fake server is http only) |
| F11 | `resetOriginals()` cancels and clears; used by `begin`, `choose`, the stacking box, a saved folder map that changed, Publish, and the sheet closing; not by the album | Scripted: a check started, stacking turned off and on, three seconds later: not run |
| F12 | The album pop-up is a `Menu` with an inline `Picker` (None, New Album…, the albums), so the choice is ticked; **Albums need album.read on this key** and the dimmed New Album… only once the check passed without `album.read`; the pop-up dimmed until the check passes | Scripted: items printed with ✓ (None; New Album… when chosen), pop-up dimmed while checking |
| F13 (G-2) | `AnnouncedIssue`: every issue under a control is announced when it appears and when its words change, and the control takes it as its hint: the Server section (failed check, missing permission), Album (missing permission, list failed, album gone) on the pop-up, Stacking on the box, Archive on Show in, the settings issue on Edit Settings…, folder map issues on their field, the start issue on Publish, the check stopped on Check Originals | By reading; VoiceOver is left to CI |
| F14 | `PublishJob.onRecorded` → the import window marks each upload In Library as it is recorded; the Can't Import view's Edit Server… and Review Certificate… are dimmed while that server is published to | By reading; the hook is exercised by `stackOrderWhicheverUploadFinishesFirst` |
| F15 | The popover shows a small spinner for the publish job with no progress (checking, ending); the counter returns from Waiting to the step in hand when a retried request is over | `PublishRulesTests.progressCounter` (fails without: stayed Waiting); popover snapshot 16 below |
| F16 | D-4: **not published: the server didn't accept the upload (‹status›). “‹message›”**, other server causes **The server answered ‹status›.** with the message; an album add's per-photo refusal shows the server's words alone (`PublishCause.itemRefused`); Not Finished reads **already on the server, but** for an already-there photo; D-5: a retry stopped by its check says **Publishing stopped: ‹the check's title›.** (`PublishStop.checkFailed`), **The key couldn't be read** for the Keychain | Scripted: "not published: the server didn't accept the upload (400). “Status 400”", "already on the server, but not checked before publishing stopped.", "Publishing stopped: The server rejected this API key." |
| F17 | Add Folder… focuses the new section's server field (`focusedMapping`, applied when the field appears) | Scripted: `publish map focus` after `map add`: the field with the `/mnt/media/photos` prompt has the keyboard |
| F18 | `Catalog.rememberMadeAlbum` changes only the remembered album, and only when no later run to that server has started (`PublishRun.mayRememberItsAlbum`) | `madeAlbumRememberedAlone`, `PublishRulesTests.albumRememberedOnlyByTheLatest` |
| Correction to §3.6 | Noted: the missing watermark is the only settings issue (`settingsIssue`) | — |
| User guide | "It uploads no photo twice (except after a lost answer, described above)"; also the link order, the former primary per revision 5, Stopping…, the retry's check, a trailing slash dropped on Done | Reading |
| Improvements | Done: `.help` on result names; the File Settings page shows the missing-watermark issue. Not done: a separate wording for a one-photo check ("Originals found for 1 of 1 photos."), which needs new catalog keys and was a judgment call | — |

### Security review

| # | Fix | Test or check |
|---|---|---|
| L1 | As C5 | as C5 |
| N1 | `RemoteAsset.isServerID` (1 to 64 ASCII letters, digits and hyphens) guards `asset(id:)`, `addToAlbum` and, for import (#271), every listed asset's id before it can reach the thumbnail or original path. `RemoteRequestAllowlist.permits` matches with `NSRegularExpression` and requires the match to cover the whole path. Found here: on macOS 27.2 `String.range(of:options: .regularExpression)` does not let `$` match before a trailing U+2028, but ICU itself (`NSRegularExpression`) does, so the review's mechanism depends on the Foundation release; the fix answers alike on every release | `PublishRulesTests.serverIDsAndAnchoredAllowlist` (fails without the whole-path match), `strangeIDsNeverRequested` (no request made) |
| N2 to N4 | No change, as the review says | — |

### Requirements

- **RI-E1: ruled** (PRD revision 5, R14, AC10): a trashed former primary is
  named in the create and rejoins the stack (not on top) if restored, unless a
  later publication has replaced that stack while it was in the trash, which
  drops it too. Tests: `trashedPrimaryNamedAndRestored` (named in the create,
  a member once restored), `laterPublicationDropsTrashedPrimary` (the second
  create names the first edit, not it; restored, it is unstacked). User guide
  updated.

### Review round: scripted checks

The bundle built with `CONFIGURATION=debug Scripts/build-app.sh library`,
copied to the scratchpad, identifier set to `me.sesser.gus.debugtest.review28`
and signed ad hoc; a `photobench generate --jpeg 3 --dng 0 --heic 0 --videos 1`
library imported with `photobench import`; the fake server started and given
the publishing permissions (`import server fake fault permissions …`), added as
"Home". For F6 a second copy (`…review28old`) had the old binding put back. A
new fake-server fault `slowCheck` (`import server fake fault slowcheck <ms>`)
holds a check's first answer so a check can be caught running. New debug
words: `publish sheet nowait`, `publish press`, `publish cancel`, `publish map
type`, `publish map focus`, `publish originals nowait`, `publish servers`; the
`export` print shows its issue. Results are in the tables above. No crash in
any run after one found and fixed here: the retry's first build read
`progress` while modifying it (an exclusivity trap) when its check passed.

Snapshots for the designer (the window's layers; glass panes come out blank or
coloured, and the default button is drawn as in an inactive window), under
`/private/tmp/claude-501/-Users-randy--claude-spares-spare-ZSbkzm/7f274175-835d-4217-a958-c2a7b08f08df/scratchpad/shots/`:

- `01-publish-main.png`: the main page, http server.
- `02-publish-new-album-taken.png`: New Album… named like an existing album
  (taken with a key lacking publishing permissions, so the issues show).
- `03-publish-archive-stacked.png`: Archive with stacking (same key).
- `04-file-settings.png`: File Settings.
- `05-folder-map.png`: a pair typed `/mnt/media/` (as typed), its example;
  `05-folder-map-added.png`: right after Add Folder… (field focused).
- `06-check-originals.png` (dimmed, missing permissions),
  `06-check-originals-result.png`: three "Nothing at the mapped path".
- `07-server-sheet-from-publish-edit.png`: the Server sheet opened from Publish (Edit).
- `08-publish-checking.png`: Publish pressed, **Checking…** in the button bar, the form dimmed.
- `09-results-first-run.png`, `10-results-stopped.png` (Not Finished, already
  there), `11-results-failed.png` (the 400 wording),
  `12-results-while-retry-checks.png` ("A publish is already running."),
  `13-results-retry-check-failed.png`, `14-results-server-removed.png`.
- `15-activity-stopping.png`, `16-activity-retry-checking.png` (Activity
  popover: the retry's check with the spinner and Stop).
- `17-export-watermark-missing.png`, `18-export-watermark-chosen.png` (Export, C3).

Not reached by script: the untrusted-certificate state (F10; the fake server
is http), the "Stopping…" detail with nothing awaited (the small test photos
end before it can be printed; `progressCounter` covers the state and
`PublishText.detail` the words), the import window's marks appearing during a
run (F14), announcements (F13).

## Progress

Built (each step committed on the branch):

1. **Connection layer** (`Sources/PhotoCore/Remote/`): `ImmichEndpoint` gains
   `asset(id:)`, `ownAlbumsHolding`, and publishing's four writes (`upload`,
   `createAlbum`, `addToAlbum`, `createStack`); `RemoteRequestAllowlist` holds
   exactly those four writes plus `GET /assets/{id}` (`RemoteRequestAllowlist.writes`).
   `RemoteHTTPSession.exchange` returns any status with at most 64 KiB of an
   error body (the server's words, R23); `RemoteHTTPSession.upload` streams the
   multipart body from a file and ends by R17's rule (`RemoteUploadEnding`,
   which also hears URLSession's `didSendBodyData`). `ImmichClient.check(requiring:readsAccount:)`
   and `checkWithPermissions` serve both Server sheet hosts (R1).
   `ImmichPublishing.swift`: `RemotePublishDestination`, `PublishFailure`,
   `PublishStop`, `PublishUploadBody`.
2. **Catalog**: migration v18, `remotePublication` (records, R17) and
   `remotePublishSettings` (remembered choices and folder map per server, R7,
   R12; removed with the server). `Catalog/RemotePublications.swift`;
   `Catalog.publishSources` (`PublishOriginals.swift`).
3. **Rules** (`PublishOriginals.swift`, `PublishSettings.swift`):
   `OriginalRules` (R11 to R13, R15, design §7.1 as pure functions),
   `OriginalFinder` (the one function Check Originals and the run share,
   AC12), `PublishFolderMapping` (longest folder wins, by volume identity),
   `PublishPathForms` (NFC and NFD, compared by Unicode scalars),
   `PublishPermissions` (R8).
4. **Engine** (`PublishJob.swift`, `PublishRun.swift`): per photo, look for
   the original, render like an export, upload, record at once, read a
   duplicate, album, stack; `AlbumCoordinator` (R22's lost-answer rule),
   `StackSequencer` (one stack at a time per original, grid order), faults
   and the person's Stop, Retry Failed over the same `PublishRun`.
5. **Fake server** (`FakeImmichServer`): uploads with per-account duplicates,
   `GET /assets/{id}`, path search, albums (create, add with the duplicate
   answer, `assetId=` and `name=` filters), stacks as verified (merge by
   primary only, trashed members dropped, a named trashed primary kept),
   partners and unshared accounts, and faults (`refuseStack`, `loseAnswer`,
   `answer`, `holdUploadAnswer`, `stallUploadBody`).
6. **App** (`Sources/PhotoApp`): `PublishModel` (the sheet, check, albums,
   pages, Check Originals, the question, runs, results, Retry Failed, hosting
   the Server sheet), `PublishText`, `PublishSheet` (main page, File Settings,
   folder map), `PublishResultsSheet`; File ▸ Publish… (⌥⌘E), Publish
   Results…, Stop Publishing; the toolbar's Publish (`paperplane`); the
   context menu's Publish…; Activity's job row and Show Results…
   (`ActivityLog.Message.actionID`); the quit case (`QuitConfirmation.publishing`).
   Export's settings state moved to `ExportSettingsEditor` and its form to
   `ExportSettingsSections` and `ExportPresetRow`, shared by both sheets.
7. **Server sheet** (`Sources/PhotoUI/Import/ServerSheet.swift`):
   `ServerSheetHost` and `ServerSheetPurpose` (R1, design §4): required
   permissions, captions, results and Remove Server… by host; the address
   warning (R26). The Import window: published assets In Library with their
   own tooltip, updated in place (R20); "Can't Import from ‹name›"; the
   inspector captions; the Remove Server alert. `Info.plist`'s local network
   text (R27).
8. **Debug script**: `publish …` (`DebugPublishCommands.swift`) and the fake
   server's publishing faults (`import server fake fault stack|lose|answer|hold`,
   `import server fake uploads`).
9. **User guide**: the server import section's read-only wording, and a new
   section "Publishing to an Immich server".

Left: see **State** at the top and the checks below.

## Acceptance criteria

Tests are Swift Testing suites in `Tests/PhotoCoreTests` (`PublishRulesTests`,
`PublishJobTests`, `PublishBoundaryTests`, `RemoteConnectionTests`,
`CatalogTests`, `LibraryModalTests`, `LocalizationTests`). Scripted checks ran
the bundle copied with identifier `me.sesser.gus.debugtest.publish28`, a
`photobench` scratch library and the fake server (2026-11-26; commands under
**Scripted checks**); the review round's under **Review round: scripted checks**
(identifier `me.sesser.gus.debugtest.review28`).

| AC | Test or check | Result |
|---|---|---|
| AC1 | `PublishBoundaryTests.noPublishingOutsideTheLibraryApp` (no publishing code in the importer, `photocli` or the command registry; the menu item and ⌥⌘E); scripted `publish menu`, `publish sheet` (opens with saved servers), `publish serversheet add` | Pass |
| AC2 | `PublishJobTests.offlineAndArchive` (offline fails only that photo), `linkAndCopy` (a copy is its own publication), `ExportJobTests.pairsExportOnceFromTheirRAWAndVideosAreLeftOut` (the same `ExportTargets`); scripted runs: "1 video was left out." | Pass |
| AC3 | `uploadsAsExported` (pixels, name and metadata equal to an export with the typed description; no rating or label; only the four fields; library unchanged), `PublishRulesTests.captureDate` (10:20 at +02:00 sent as 10:20 labelled UTC), `uploadBody`, `description`; `ExportTests` for what each level keeps | Pass |
| AC4 | `offlineAndArchive` (visibility set by the upload), `newAlbum` (no second album), `rememberedChoices`; scripted: the Archive caption with and without stacking, a new album remembered as existing, empty description on reopening | Pass |
| AC5 | `PublishRulesTests.permissions` (each removed in turn is named; exact set; `stack.read` never), `PublishBoundaryTests.purposes`; scripted with a two-permission key: Album and Stacking name their missing permissions, Publish dimmed, then enabled with None and stacking off, and that run published | Pass |
| AC6 | `expectOnlyAllowedRequests` in the job tests, `RemoteConnectionTests.allowlist` (updates and deletes refused; `RemoteRequestAllowlist.writes` is the four) | Pass |
| AC7 | `linkAndCopy`, `stackingOffAndFallThrough` (no stack request with stacking off; a trashed linked asset falls through to the map), `PublishBoundaryTests.pairPartner`; revision 6: `pairBothLinkedAndCopy` (both halves linked: the pair and a copy of its RAW stack on the RAW's asset, nothing asks about the JPEG's), `pairJPEGLinkedAndCopy` (only the JPEG linked: both on the JPEG's asset) | Pass |
| AC8 | `PublishRulesTests` (longest folder, volume identity, NFC/NFD, case, own beside partner's, qualifying beside each non-qualifying kind, pair order), `folderMapOwnBesidePartner` | Pass |
| AC9 | `PublishRulesTests.reasonOrder`, `moreThanOne`, `linked`, `ladder`; `noOriginalReasons`; scripted Check Originals: "No mapped folder", then "Nothing at the mapped path" with the path | Pass |
| AC10 | `joinsExistingStack` (non-primary original, trashed member out, no request about it, the create names edit, primary, original), `linkAndCopy`, `stackOrderWhicheverUploadFinishesFirst` (two edits of one original, each finishing order forced: the later in grid order is primary), `trashedPrimaryNamedAndRestored`, `laterPublicationDropsTrashedPrimary` (RI-E1), `refusedStackRetried` | Pass |
| AC11 | `refusedStackRetried`; scripted: refused stack, Retry Failed, both stacked, three uploads in all | Pass |
| AC12 | One `OriginalFinder` for both (by construction); scripted `publish originals` | Pass |
| AC13 | `records` (records survive removing the server); scripted: the question once ("3 photos were already published"), Skip sent nothing ("3 were skipped."), New Copy uploaded, Cancel sent nothing | Pass |
| AC14 | `duplicateUsable` (read before album and stack, album added, recorded), `duplicateLeftAlone` (trash, hidden, locked: no album or stack request, not retried), `duplicateReadFailsThenRetried` | Pass |
| AC15 | Scripted `import grid` after publishing: the published edits are marked In Library; `records` (`publishedRemoteIDs`) | Pass |
| AC16 | `faults` (429 tried again; rejected key stops and says which), `lostConnection`, `personsStop`, `uploadsAsExported` (no temporary file; masters byte for byte), `endingWaitsForFullySent` | Pass |
| AC17 | The owner, on his own server | Open (owner) |
| AC18 | Scripted: a confirmed local http server publishes with no second question and the sheet says Not encrypted. An https server's sheet has no such line by code (`service.serverAddress?.scheme == .http`); not run, the fake server is http only | Pass (http); https by reading |
| AC19 | Scripted: Edit Server, name only: no warning; address changed on a server with records: the warning | Pass |
| AC20 | `personsStop` (the photo in progress is the only one without its album) | Pass |
| AC21 | `lostConnection` (fault: unreached included), `personsStop` (own Stop: left out; uploaded photo finished), `PublishBoundaryTests.retryAndLaterRuns` (a later run's photo left out; a re-edit renders as saved at the retry); `oneAtATime` (the slot); revision 7: `stopDuringRetryCheck` (a Stop during the check sends no write request and leaves the ending and results as they were; the next retry covers the unreached), `retryCheckFailsOrRuns`, `PublishRulesTests.retryOutcomeRule`; scripted (review round): "A publish is already running." while a retry checks, "This server was removed." after Remove Server in the import window; second round: Stop during the retry's check, message and results unchanged, the next retry published them | Pass |
| AC22 | By reading: the texts design §4.1 lists are changed (Server sheet captions and results by host, unencrypted notice, Import inspector captions, Remove Server alert, `Info.plist`); the user guide's import section and its Publishing section (trashed members and the former primary per revision 5, a lost answer, unfinished steps, the lost-answer exception to "uploads no photo twice") | Done, for the reviewers to read |
| AC23 | `endingWaitsForFullySent` (answer within the bound: recorded; none: ends at the bound, no record), `notFullySentCancelledAtOnce`, `stopKeepsEndingInEveryReport` (two photos at once: every report after Stop is ending, awaiting an answer while one is); scripted: "Stopping. Waiting for “Home” to answer…" twice a second apart with three photos, Stop and File ▸ Stop Publishing dimmed, Publish dimmed | Pass; a quit during the wait not scripted |
| AC24 | `lostAlbumCreate`, both the automatic repeat and Retry Failed, with an older album of that name holding the first photo | Pass |
| AC25 | `PublishBoundaryTests.purposes`; scripted: saved from Publish with two permissions, refused from Import with "To save a key made only for publishing…", the Import window shows "Can't Import from", a key lacking `asset.read` refused from Publish | Pass |

## Scripted checks (2026-11-26)

`Scripts/build-app.sh`, the bundle copied and re-signed with its own
identifier, `photobench generate --jpeg 3 --videos 1`, `photobench import`
into a scratch library, then `--library-root <scratch> --debug-script "…"`.
The scripts start the fake server (`import server fake start 3`), set its
permissions, add it (`import server add Home fake`, or `publish serversheet …`),
and drive `publish …` (`DebugPublishCommands.swift` lists every command). Seen:
the sheet's rows and issues, both pages, Check Originals, the question, three
complete runs, a refused stack and its retry, the ending wait, the import
window's In Library marks, both Server sheet hosts and the address warning.

One combined script (scenario 4: Publish, then the import window's Add, Edit
and Close, then Publish's Edit) did not quit within its 220 s timeout after
the import-hosted sheet steps; each part run alone passed and quit. Not
explained; QA should run it again (it may be AppKit ignoring a quit while a
sheet is up, #276).

## Live check (2026-11-26)

`PublishLiveTests` (opt-in: `PUBLISH_LIVE_SERVER`, `PUBLISH_LIVE_KEY_FILE`)
ran the real client and engine against the throwaway 3.2.0 and 3.4.2: a
multipart upload streamed by URLSession, a new album made with the first
photo, stacking on a linked original (the edit primary), and a duplicate
answer read before anything else. Passed on both. The servers were removed
afterwards; the images kept.

## Decisions on the open items

- **Trashed primary** (PRD open question 1): holds; see item A and RI-E1.
- **Archive with more than two** (task): holds; item B.
- **A lost album create** (PRD open question 2): holds with the set read
  before the create; item C and `lostAlbumCreate`.
- **Moving the connection code to a library-only target** (PRD open question
  3): **not done**, and not required. R25 and AC1 ask for no publishing path in
  the importer or `photocli`, which holds and is pinned by
  `PublishBoundaryTests`. The code is still linked into both: the importer
  links PhotoUI, whose shared import window hosts the server source
  (`ServerSource`, `ServerSheet`, `ServerText`), and PhotoCore holds
  `Remote/`. A real split needs a `Remote` target and the server parts of the
  import window moved to a library-only target with hooks in
  `CardImportModel`: #271's settled surface, and larger than this slice.
  Proposed as a follow-up.
- **Request shapes and streaming** (task): as status.md's table; the upload
  streams the multipart body from a file (`uploadTask(with:fromFile:)`), and
  "fully sent" is read at stop time from the task's counters
  (`RemoteUploadEnding.end`), as verified.
- **LibRaw-decoded exports**: not checked; there is no raw sample in the
  repository's fixtures that the system decoder refuses, and the owner's
  photos are not used.

## Proposed `CLAUDE.md` Network rule (R27; the owner approves before it is committed)

Type names checked against the code on this branch (review round: the
temporary files, the whole-path allowlist match and the id rule added; fourth
round: the temporary folders' mode, links and age, security N5 and N6; fix
round after QA: the key read with its row, security N7; D-17 to D-19: every
key read, the import window and the Server sheet included; C14 round: "every
save of a key with its row" and how the Server sheet's key is given, code review
sixth pass, and the gate's reach stated as one process and its catalog, security
review N9, whose fix is the owner's to decide).

> - **Network.** The app contacts one kind of host: an Immich server the user
>   adds, and only the library app does it (the standalone importer, About and
>   `photocli` have no path to it). All of it is PhotoCore `Remote/`: import
>   reads behind `RemotePhotoSource` and never writes; publishing goes behind
>   `RemotePublishDestination`. The key lives only in the Keychain
>   (`KeychainKeyStore`, service `<bundle id>.servers`, account the
>   connection's uuid), never in the catalog, preferences, logs, Activity or
>   debug output. Only the allowlisted requests are ever built
>   (`RemoteRequestAllowlist`, matched against the whole path), checked before
>   a request exists: GET, the one search POST, and, for publishing only, four
>   writes (`RemoteRequestAllowlist.writes`: upload an asset, create an album,
>   add assets to an album, create a stack). An id a server gave goes into a
>   path only if it is 1 to 64 ASCII letters, digits and hyphens
>   (`RemoteAsset.isServerID`). No request updates or deletes anything on the
>   server; adding another write needs the owner's approval. Creating a stack
>   makes the server replace the stack it joins, so it names the original's
>   current primary and runs one at a time per original (`StackSequencer`); an
>   album create is never sent again before the album it may have made is
>   looked for (`AlbumCoordinator`). One publish runs at a time
>   (`PublishSlot`). An upload sends only the rendered temporary file and the
>   values publishing names (`PublishUploadBody`: date, name, visibility),
>   never an original or a sidecar; it streams from disk, and a stopped run
>   cancels it at once unless it was fully sent, then waits at most 10 s for
>   its answer (`RemoteUploadEnding`). Rendered files and upload bodies go
>   under the system's temporary folder, in a folder of this launch's inside
>   one base folder every copy of the app shares, named from the fixed
>   `AppBranding.bundleIdentifier` (`PublishTemporaryFolders`:
>   `<AppBranding.bundleIdentifier>.publish/<launch>`, each launch's held by a
>   lock for the life of its process, the base the user's alone, mode 0700);
>   each run removes its own when it ends, and a launch removes only the
>   folders of launches that have ended (their lock is free) and day-old
>   folders with no lock file, never following a symbolic link and nothing at
>   all unless the base is the user's own real folder. A launch that can't lock
>   a folder there works in one of its own beside the base. The key goes
>   only as `x-api-key` and only to the connection's host. Every read of a
>   saved key and every save of a key with its row go through the account's
>   `RemoteKeyGate`, so the key is always read with the row saved with it
>   (`RemoteSavedKey`: publishing's check, the import window's check and the
>   Server sheet's with its key field empty), and a key is given only while
>   the row still has the address and trusted certificate the caller holds
>   (publishing, the import window) or opened on (the Server sheet, whose check
>   then goes to the address its form shows), so a key saved for a new address
>   never reaches the previous one. The gate is per process and pairs the key
>   with that process's catalog only: nothing keeps a second copy of the app
>   off a library (the library lock only keeps `photocli`'s writes off a
>   library the app has open), and copies of a library name the same Keychain
>   item. A Server sheet behind the saved server writes nothing
>   (`Catalog.saveRemoteService(_:checkedWith:opened:keys:)`).
>   Response bodies and downloads are capped (an error's body at 64 KiB, read only for the
>   server's message). Redirects are never followed, and there are no cookies,
>   cache or credential storage. Transport policy: `https://` by default;
>   plain `http://` only to a local-network host after the user confirms the
>   notice. An untrusted certificate is never accepted silently; the user may
>   trust one fingerprint per connection, a changed one fails, and nothing
>   turns checking off. Nothing else may use `URLSession`:
>   `RemoteHTTPSession.swift` is the one HTTP path (the fake server uses the
>   Network framework). Tests use `FakeImmichServer` and `InMemoryKeyStore`. A
>   test launch always uses the in-memory store. No package was added:
>   Foundation and the Security framework.

Also for the owner's part of `CLAUDE.md`: the catalog table list gains
`remotePublication` and `remotePublishSettings` (migration v18).

## For a person (not scriptable)

Numbered as review.md's M1 to M7 (fourth pass).

- The sheet, its two pages and the results sheet at the smallest window; their
  look in the dark library window (M1); keyboard only from ⌥⌘E to Publish (M2).
- Return in the Description field (design §13, review G-1: pressing Publish,
  inserting a line, or neither are all acceptable; note which; M2).
- Menus and the context menu by eye; the toolbar's Publish item in the default
  set (M3).
- The quit alert during a real run, and a quit while a run is ending (asks
  nothing, waits out the bound; M6).
- The album pop-up's tick and the dimmed New Album… with its line, with a real
  mouse (F12; M4); the folder map's field typed by hand (`/mnt/media/photos`, an
  edit in the middle, a pasted trailing slash) and its focus after Add
  Folder… (F17; M2).
- Stop while a large photo renders: **Stopping…** until the render returns (D-1;
  M6).
- Stop while a retry is still checking a slow or Keychain-prompting server:
  **Stopping…** until the check returns, then the job leaves Activity and
  nothing else changes, an open results sheet included (D-10; M6). The scripts
  reached only a check that returns at once when cancelled.
- Publish N Photos enabled right after the check, with no click elsewhere
  first, and Return publishing (F19; the snapshot shows the enabled button; M2).
- The Skip or New Copy alert closing by itself when the server is removed (M5)
  or its address is changed in the import window (D-15, the same check), and the
  line it leaves; with a real window, Save in the publish sheet's own Server
  sheet after its server was removed in the import window (D-16): the sheet
  closes and the publish sheet comes back with **This server was removed.**
- AC17 on the owner's server (https, a reverse proxy, the web interface), and
  there the untrusted-certificate wording if a certificate the system doesn't
  trust is met (F10, D-3; M7).

## Known and left

- Announcements and hints (design §13, F13) are by reading; VoiceOver is left
  to CI.
- A server whose permissions change after the sheet's check keeps the old
  check until Check Again or Publish (which checks again; ruling G-3).
- A Stop while a retry checks its server, or before it has started on any
  photo, is not an ending (PRD revision 7, D-10): the run stays as it was and
  the next Retry Failed still covers what it covered. A Stop after the retry has
  started on its photos is the person's Stop, so photos still not uploaded drop
  out of the next retry (R23's "the latest ending decides").
- A run's photos that a later run published are left out of its retry and
  still counted as failed or not published in that run's results (D-12: they
  record that run); when they are all its retry would cover, Retry Failed is
  not offered and a caption says why.
- A key changed for the chosen server in the import window (the address and
  certificate unchanged) is not noticed by an open publish sheet: the record
  doesn't change, so its check stands until Check Again or Publish, which
  checks again (as for permissions above).
- The chosen server removed in the import window while the publish sheet has
  handed its place to its own Server sheet (Add or Edit): that sheet is not
  closed at the moment of removal (D-14); its Cancel, or a Save (which saves
  nothing, D-16), brings the publish sheet back showing the removal as above.
- An address or certificate changed in the import window while the publish
  sheet's own Server sheet is up, and that sheet then cancelled: the earlier
  check and album list may still show until Check Again or another choice;
  **Publish** still connects to the saved address (D-14, D-15's remaining case).

## Immich verification (2026-11-25)

Checked against two throwaway Immich servers in Docker on this Mac. **3.2.0** is
the app's minimum and **3.4.2** is the current release (latest non-prerelease
on GitHub, published 2026-11-18). All data was synthetic (`photobench
generate`). There were three accounts: **A** publishes; **B** is another
account; **C** is a partner who shares with A, shown in A's timeline. **A** has
an `all` key, a **minimum key** holding import's five permissions plus PRD R8's
five, and an import-only key. Both versions gave the same results everywhere;
any difference is called out. "Observed live" means a request was sent and the
answer read. "Read from source" means `server/src` at tags `v3.2.0` and
`v3.4.2`, or `open-api/immich-openapi-specs.json` at both tags. The owner's
server was not contacted.

### How to repeat it

The compose file is our own and pulls only what the official compose file
needs to run: server, database and cache. There is no machine-learning image,
and `IMMICH_MACHINE_LEARNING_ENABLED=false` is set. 3.4.2 is the same except the
tag, the port (`127.0.0.1:2284`) and valkey digest
`418652cfb58ef879d4978c33553735d7147016032d5aefaa14c828e611eb9dfd`. The env file
holds generated `DB_PASSWORD` and `POSTGRES_PASSWORD`, plus
`DB_USERNAME=postgres`, `DB_DATABASE_NAME=immich`, `TZ=Etc/UTC` and
`IMMICH_MACHINE_LEARNING_ENABLED=false`.

```yaml
name: gusverify320
services:
  immich-server:
    image: ghcr.io/immich-app/immich-server:v3.2.0
    volumes:
      - upload:/data
      - <scratch>/external:/mnt/media/photos:ro
    env_file: [<scratch>/secrets/env-320]
    environment: { DB_HOSTNAME: database, REDIS_HOSTNAME: redis }
    ports: ['127.0.0.1:2283:2283']
    depends_on: [redis, database]
    restart: on-failure        # the server can start before postgres accepts connections
  redis:
    image: docker.io/valkey/valkey:9@sha256:70739f85ad2ee01a726a965584a0f94895f01b0c60b3cc8b0aeef11eaa6888cf
  database:
    image: ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23
    env_file: [<scratch>/secrets/env-320]
    environment: { POSTGRES_USER: postgres, POSTGRES_DB: immich, POSTGRES_INITDB_ARGS: '--data-checksums' }
    volumes: [pgdata:/var/lib/postgresql/data]
    shm_size: 128mb
volumes: { upload: {}, pgdata: {} }
```

Setup used these requests, each under `/api`:

- `POST /auth/admin-sign-up` and `POST /auth/login`, which return `accessToken`.
- `POST /admin/users`.
- `POST /partners {sharedWithId}` as C, then `PUT /partners/{C} {inTimeline: true}` as A.
- `POST /api-keys {name, permissions}`, which returns `secret`.
- `POST /libraries {ownerId, name, importPaths: ["/mnt/media/photos"]}` and `POST /libraries/{id}/scan` (admin session). Each of A, B and C got an external library over the same read-only folder.
- Locked visibility needs an elevated session, so A's session also ran `POST /auth/pin-code`, then `POST /auth/session/unlock`, then `PUT /assets {ids, visibility: "locked"}`.

The helpers are Python with only the standard library: client, setup,
libraries, and experiments by name. Afterwards the containers, volumes and
networks were removed. The images were kept.

### Request and response shapes publishing needs (same on both)

| Request | Key permission | Shape (observed live) |
|---|---|---|
| Upload | `asset.upload` | `POST /assets`, multipart. Required: `assetData` (file), `fileCreatedAt`, `fileModifiedAt`. Optional: `filename` (overrides `originalFileName`), `visibility` (`timeline`, `archive`, `hidden`, `locked`), `isFavorite`, `sidecarData`, `metadata`, `livePhotoVideoId`, `duration`. There is no `deviceAssetId` or `deviceId`. New file: **201** `{"id":"…","status":"created"}`. Identical bytes already among the account's uploads: **200** `{"id":"<existing>","status":"duplicate"}` |
| Create album | `album.create` | `POST /albums {"albumName", "assetIds"?, "description"?}`, **201**, the album. Passing `assetIds` needs no further key permission (the server checks access per asset and silently drops assets it refuses) |
| Add to album | `albumAsset.create` | `PUT /albums/{id}/assets {"ids":[…]}`, **200** `[{"id","success":true}]`. An asset already there gives `{"success":false,"error":"duplicate"}` |
| Create stack | `stack.create` | `POST /stacks {"assetIds":[…]}` (at least 2; the first becomes primary), **201** `{"id","primaryAssetId","assets":[…]}`. The server also requires every asset to be the caller's own and not locked. Otherwise **400** `Not found or no asset.update access` |
| Read stack | `stack.read` | `GET /stacks/{id}` and `GET /stacks?primaryAssetId=` |
| Read one asset | `asset.read` | `GET /assets/{id}` includes `ownerId`, `type`, `visibility`, `isTrashed`, `libraryId`, `originalPath`, `exifInfo.fileSizeInByte`, `stack: {id, primaryAssetId, assetCount}` or null. A refusal and a missing asset look the same: **400** `{"message":"Not found or no asset.read access"}` |
| Find by path | `asset.read` | `POST /search/metadata {"filter":{"originalPath":{"eq": P}} , "withExif": true}`. `eq` is exact, byte for byte: case counts, and so does Unicode normalization (NFC ≠ NFD). `"in": [nfc, nfd]` matches either form in one request. The byte size is `exifInfo.fileSizeInByte`: the file's real size for external-library assets, the uploaded size for uploads |
| Own albums | `album.read` | `GET /albums?isOwned=true`, plus `assetId=` (albums holding that asset) or `name=` (exact, case-sensitive match) |
| Key's permissions | none | `GET /api-keys/me` gives `{id, name, createdAt, updatedAt, permissions}` for any key, so the app can read its key's whole list |

A request missing a key permission gets **403**
`{"message":"Missing required permission: <name>"}`.

### design.md §15, item by item

**1. Capture date for a file with none embedded (R4).** *Holds for the date. The
time of day can shift.* Observed live, both versions.

- With no date in the file, `fileCreatedAt` becomes `dateTimeOriginal`,
  `fileCreatedAt` and `localDateTime`. `fileModifiedAt` does not date the photo:
  sent as "now", it only set `exifInfo.modifyDate`.
- An offset is kept only as an instant. `2019-06-15T10:20:30+02:00` was stored
  as `localDateTime 2019-06-15T08:20:30Z`, so Immich shows 08:20, not 10:20.
- A date embedded in the file wins over `fileCreatedAt`: EXIF 2023 against an
  upload date of 2019 gave 2023.
- Our exports at **All** and **No location** keep `DateTimeOriginal`. At
  **Copyright** and **None** there is no date in the file (checked with
  exiftool), so those levels rely on `fileCreatedAt`.
- A synthetic file with an EXIF date and no offset got `fileCreatedAt =
  localDateTime` = its wall-clock time labelled `Z`.

Consequence: RI-V1.

**2. Visibility set by the upload (R6, R9).** *Holds.* Observed live, both
versions. The multipart field `visibility=archive` gives an archived asset; no
update is needed. Even `locked` was accepted from a plain API key at upload.

**3. An archived primary and the timeline original.** *Does not hold.* Observed
live through the timeline API, both versions. After a stack of [archived edit,
timeline original]:

- The timeline with `withStacked=true` shows **neither** the edit nor the
  original: the original leaves the timeline.
- The archive with `withStacked=true` shows the edit, carrying the stack.
- With `withStacked=false` the original stays in the timeline.
- Import's listing still lists the original, because it filters on the asset's
  own visibility.

`withStacked=true` is the stacked view; the web UI itself was not looked at.
Consequence: RI-V2.

**4. Import listing includes stacked, non-primary originals.** *Holds.* Observed
live, both versions. The import search (no `withStacked`) listed the non-primary
original and its timeline edit. The web timeline (`withStacked=true`) shows only
the primary. Published edits also appear in the listing, which R20 already marks
In Library.

**5. Creating a stack keeps trashed members.** *Does not hold.* Observed live,
both versions, and read from `stack.repository.ts`.

- Once a member is trashed, it drops out of `GET /stacks/{id}` and out of every
  `stack.assetCount`, although its `stackId` stays.
- `POST /stacks` gathers members of merged stacks with `deletedAt is null`, so
  the new stack leaves the trashed member out. Its `stack` became null, and
  after restoring it from the trash it stayed unstacked.
- The app never sees trashed members unless it makes extra requests.

Consequence: RI-V3.

**6. What search and the read of a linked asset reveal (R15).** Observed live,
both versions.

| Asset | Search by path (as A) | `GET /assets/{id}` (as A) |
|---|---|---|
| Own, trashed | returned, `isTrashed: true` | 200, `isTrashed: true` |
| Own, hidden | returned, `visibility: hidden` | 200, `hidden` |
| Own, archived | returned, `archive` | 200, `archive` |
| Own, locked | **not returned** (same as nothing there) | **400**, same as a missing asset |
| Partner C's (shown in A's timeline) | **returned**, `ownerId` C | 200, `ownerId` C |
| B's, not shared | not returned | 400, same as missing |
| B's, in an album B shared with A | not returned | 200, `ownerId` B |
| A video at the path | returned, `type: VIDEO` | (not tried) |
| Nonexistent | n/a | 400 `Not found or no asset.read access` |

So trashed, hidden, "not a photo" and "another account's" can be revealed;
locked never can. For a path match, "another account's" is revealed only for a
partner's asset, and for a linked asset only for a partner's or a shared
album's. This matches §7.1's fallback rule. New finding: with a partner's
external library over the same share (a household setup), every path search
returns **two** assets, A's and C's. Consequence: RI-V4. Path matching is also
sensitive to Unicode normalization: RI-V8.

**7. Permission names (R8).** *Hold, with one permission to spare.* Observed
live, both versions.

- The names are exactly `asset.upload`, `album.create`, `albumAsset.create`,
  `stack.read` and `stack.create`. They exist in both versions' `Permission`
  enum; 3.4.2 adds only `passkey.*` and `clusterGroup.admin`.
- With the minimum key, every request publishing needs succeeded: upload,
  duplicate upload, create album (with and without `assetIds`), add to album,
  create stack, read stack, read asset, search, `GET /albums?assetId=`.
- With each of `asset.upload`, `album.create`, `albumAsset.create`,
  `stack.create`, `stack.read`, `asset.read` and `album.read` removed in turn,
  the request that needs it got 403 naming it. The import-only key got 403 on
  upload, album create and stack create.
- No extra permission is required.
- `GET /api-keys/me` lists the key's permissions; it worked with every key.

The spare permission is `stack.read`. The original's stack primary comes from
`GET /assets/{id}` (`asset.read`) and the create returns its members, so no
request in the flow needs `stack.read`: RI-V5. Detecting a lost album create
needs `album.read` even with New album: DQ-V1.

**8. A lost answer to create-album or create-stack.** Observed live, both
versions.

- **Stack:** repeating the same `POST /stacks` is harmless. It gives the same
  members and primary under a new stack id (the earlier row is replaced, see
  item 10), and `GET /assets/{edit}`'s `stack` tells whether it happened. *Holds.*
- **Album:** a repeated create makes a **second album** of the same name, and
  there is no idempotency key. It can be detected if the run creates the album
  with its first uploaded asset in the same request (`album.create` suffices),
  then on a lost answer looks for an owned album with that exact name holding
  that asset: `GET /albums?isOwned=true&assetId=<first>`. That read needs
  `album.read`. *Holds with that condition* (DQ-V1).

**9. Telling that a duplicate is trashed (R19).** *Holds through one read.*
Observed live, both versions.

- The duplicate answer is the same for a trashed asset (200
  `{"status":"duplicate","id":X}`), and the asset stays in the trash.
  `GET /assets/X` gives `isTrashed: true`.
- The read is required, because the server does not refuse later steps on a
  trashed asset. Adding a trashed asset to an album **succeeds**.
  `POST /stacks [new, trashedX]` returns 201 but leaves X out, a one-member
  stack.
- Also observed: a duplicate of a **locked** asset is answered `duplicate`, and
  the read is 400. A duplicate of a **hidden** asset reads as `hidden`. R19 says
  nothing about either: RI-V6.
- Duplicates are per account and only among uploads. Bytes identical to an
  external-library file, or to another account's upload, were `created`.

**10. A new primary by creating a stack, with no update (R9, R14).** *Holds, with
two conditions.* Observed live, both versions; read from `stack.repository.ts`.

`POST /stacks` merges only the stacks whose **primary** is in `assetIds`. It
deletes those stack rows server-side and makes a new stack, with the first id
as primary:

- `[E, P]`, where P is the primary of {P, M1}, gave {E, P, M1}, with E primary.
- `[E2, E1]`, where E1 was the current primary, gave a new primary E2 with every
  member kept.
- `[E1, O]`, where O is a **non-primary** member, moves O out alone. Its former
  stack is left with P only (P's `stack` reads null).

So the app must read the original's `stack.primaryAssetId` (`GET /assets/{id}`)
and send `[edit, currentPrimary, original]`. The server's deletion of the
replaced stack row is a server-side delete caused by a create: RI-V7.

**11. Album and stack steps right after each upload (R21, R14).** *Holds, if
stack requests are serialized per original.* Observed live, both versions.

- A stack and an album add sent immediately after the upload, while metadata
  extraction was still running, succeeded and survived the extraction.
- Two creates naming the same original sent concurrently left one edit outside
  the original's stack in 5 of 5 tries on each version. Sent one after the
  other with the original named both times, the same happens (item 10).
- The sequence that works: create, then read the original's current primary,
  then the next create names that primary. Ending primary as intended, 3
  members.

This constrains the build: one stack request at a time per original. It needs no
PRD change.

### Other items asked for

**External library, read-only (task 4).** Observed live, both versions. All 7
files of a read-only bind mount were checked:

- `checksum` was the base64 SHA-1 of `"path:" + originalPath`, never of the
  content, so the PRD's non-goal stands.
- `originalPath` is the server's path (`/mnt/media/photos/2024/Iceland/…`).
- `exifInfo.fileSizeInByte` equals the real byte count.
- `libraryId` is set and `isOffline` is false.
- A's external asset can be stacked under an uploaded edit, with the edit as
  primary. Partner C's cannot (400 `no asset.update access`).

**Can URLSession tell that the body is fully sent (R17, task 5)?** *Yes, with a
known meaning.* Observed live with a throwaway Swift program: `uploadTask(with:
fromFile:)`, the delegate's `didSendBodyData`, `countOfBytesSent`, and
`URLSessionTaskMetrics`.

- Against Immich, `totalBytesSent == totalBytesExpectedToSend` arrived 5 to 6 ms
  (27 KB JPEG) and 29 to 33 ms (48 MB DNG) before the 201's headers, on both
  versions.
- Against a local server reading 2 MB/s, "fully sent" came **2.2 s before** the
  server had read the last byte (8 MB body). About 4 MB was still in loopback
  socket buffers. `metrics.requestEndDate` was early too.
- Cancelling at "fully sent" left that server with 6.9 of 8 MB: no upload.

So the signal means "handed to the operating system". It never comes after the
server has the whole body, so:

- (a) an upload treated as fully sent but cut off during the wait leaves no
  asset, which is the safe direction;
- (b) "not fully sent, cancel" can only be wrong in the moment between reading
  `countOfBytesSent` and the cancel taking effect, when the last unsent bytes
  might still go out.

That remaining window is the gap R17 already documents. Read the count at stop
time, not a flag set by a delegate callback that may not have arrived yet. No
Requirements issue.

**Are two renders of an unchanged photo byte-identical (R19, task 6)?** *Not
always* (corrected 2026-11-26 after QA's Q6, filed as #302): QA found six
`photocli export` runs of one photo with a caption and a capture time giving
three different files of one size, differing in the order of the IPTC
`Caption-Abstract` and `TimeCreated` records. What follows was observed before
that, and holds only for what it tried. Observed with `photocli export --library-root <scratch>` on a
`photobench` library (`ExportJob`, the export path the app shares).

- Each export ran 2 or 3 times in separate processes, and every file was
  identical.
- Tried: JPEG at all four metadata levels; TIFF (full size, and long edge 800);
  ImageIO JPEG and HEIC sources; system-decoder DNGs; unedited and edited
  (`exposure.ev`) versions.

Not tried: raws LibRaw decodes, gain-map files, across a macOS update, a
pipeline-version bump or another GPU, and (QA's finding) enough runs of a photo
with IPTC fields. Consequence: publishing an unchanged photo again (New Copy)
gets the duplicate answer only when the export comes out byte for byte the
same; after a relaunch a photo with a caption or capture time may not, and New
Copy then adds a second copy (R19 speaks only of identical files, so no
criterion fails; #302 is the export fix). R19's "already on the server" is real
for identical files, not for every unchanged photo.

### Not verified

- An https server or certificate trust; a reverse proxy in front.
- The owner's server, deliberately: its version is unknown.
- The web UI itself; the timeline API it uses was read instead.
- Upload throughput on a real network.
- LibRaw-decoded exports.
- Whether a storage template changes `originalPath` for uploads. It doesn't
  matter: path matching applies only to external libraries.
- Behaviour above a few dozen assets.

### Images kept (Docker)

| Image | Disk |
|---|---|
| `ghcr.io/immich-app/immich-server:v3.2.0` | 1.62 GB |
| `ghcr.io/immich-app/immich-server:v3.4.2` | 1.6 GB |
| `ghcr.io/immich-app/postgres@sha256:bcf63357…` (14-vectorchord0.4.3-pgvectors0.2.0) | 1 GB |
| `valkey/valkey@sha256:70739f85…` (3.2.0's) | 189 MB |
| `valkey/valkey@sha256:418652cf…` (3.4.2's) | 191 MB |

### Open items verified 2026-11-26

Observed live on both 3.2.0 and 3.4.2 (`exp2.py`, synthetic data, the same
compose files; servers removed afterwards).

**A. The original's stack primary is in the trash (PRD open question 1).**
*Holds.* Stack {P primary, O, M}; P trashed. `GET /assets/O` still gives
`stack.primaryAssetId` = P. `POST /stacks [E, P, O]` returned 201 with E
primary and listed members {E, O, M}: the other members are kept and the edit
is primary. One nuance: P, named in the create, takes the new stack's id while
in the trash, and **is back in the stack when restored** (count 4). Other
trashed members, not named, stay unstacked when restored (item 5). The user
guide says so; R14's sentence ("Members in the trash drop out … and stay
unstacked if restored") is true of every member but the primary: see RI-E1.

**B. Archive with a stack of more than two (task).** *Holds.* Stack {O, M1,
M2}, all timeline; `POST /stacks [E archived, O]` gave 4 members, E primary.
Timeline with `withStacked=true` shows none of O, M1, M2; the archive shows E.
Each keeps its own visibility (`timeline`). R6's caption is right for any
stack size.

**C. A lost album create told from an older album of the same name (PRD open
question 2).** *Holds.* An older album "Trip" holds X; the run publishes X
again (answered `duplicate`), reads the account's albums named "Trip" (the
older one), creates "Trip" with X and treats the answer as lost. `GET
/albums?isOwned=true&assetId=X` gives both albums; of those named "Trip", the
one not in the set read before is exactly the run's, and the older one is
excluded. `name=` filters by exact name on both versions; album answers carry
`id`, `albumName`, `assetCount`, `createdAt`. The engine uses the set read
before the create, not dates.

## Verification requirements issues (ruled 2026-11-25: PRD revision 3, design §16.4)

Kept as raised; every one is ruled. The rulings are in the PRD's revision 3
and design §16.4.

- **RI-V1 (R4, item 1): the time of day at Copyright and None.** Immich dates a
  file with no embedded date by the upload's `fileCreatedAt`, but shows its UTC
  time: a 10:20 capture at +02:00 shows as 08:20. Options:
  - (a) Accept it and say so in the user guide.
  - (b) Send the capture's wall-clock time labelled UTC. Immich then shows the
    right time, as it does for files whose EXIF date has no offset. The instant
    is off by the offset, which matters only to sorting across zones.
  - (c) Keep the date in the file at every level. This changes what None means
    and is the owner's decision.

  Recommendation: (b). No UI change.
- **RI-V2 (R6, R14, item 3): an archived primary takes the original out of the
  timeline.** Options:
  - (a) Keep both. The Archive caption says that a stacked original leaves the
    timeline with its edit.
  - (b) Archive and Stack with original exclude each other.
  - (c) With Archive, stack but leave the original primary. This contradicts
    R14.

  Recommendation: (a), the cheapest; it keeps both capabilities and states
  Immich's rule. Product decides, the owner if product prefers.
- **RI-V3 (R14, item 5): trashed members leave the stack.** A stack the app
  creates drops members that are in the trash, and they stay unstacked when
  restored. The app can't see them without requests made only to find out
  (R15's principle). Options:
  - (a) Accept it and document it in the user guide, with no results line.
  - (b) Read each member of the original's stack to report it. Extra requests
    are made, and the stack read lists no trashed members anyway, so this does
    not work.

  Recommendation: (a). design §15.5's results line is dropped.
- **RI-V4 (R13, item 6): a partner's asset at the mapped path.** The path search
  returns partners' assets too (C's external library over the same share), so
  "the only match" would fail for every photo in a household setup. Options:
  - (a) Count only assets of the key's account. A partner's asset is used only
    for the "another account's" reason when no own asset matches.
  - (b) Count every returned asset, so these become "more than one match".

  Recommendation: (a).
- **RI-V5 (R8, item 7): `stack.read` is not needed.** No request in the flow
  needs it: `GET /assets/{id}` (`asset.read`) gives the stack and its primary,
  and the create returns its members. Options:
  - (a) Drop it from R8.
  - (b) Keep asking for it.

  Recommendation: (a), least privilege. design §4.1 and §5 follow.
- **RI-V6 (R19, item 9): a duplicate that is hidden or locked.** The server
  answers `duplicate` for an asset that is hidden (readable) or locked (the read
  fails, the same as a missing asset). R19 covers only the trash. Options:
  - (a) Treat both like the trash: report "already on the server" with the
    reason (hidden, or "couldn't be read on the server") and do nothing else.
  - (b) Album and stack anyway. A locked one fails, and a hidden primary hides
    the stack.

  Recommendation: (a).
- **RI-V7 (R9, item 10), the owner decides: a stack create replaces the stacks it
  merges.** The app sends only `POST /stacks`, but the server deletes the merged
  stack rows and makes a new one; the stack id changes, and members in the trash
  are dropped (RI-V3). Nothing else is deleted. Options:
  - (a) Accept it and reword R9: "creating a stack replaces the stack it joins".
  - (b) Don't join existing stacks: stack only an original that is unstacked,
    else publish unstacked with a reason. This loses R14's main case.

  Recommendation: (a).
- **RI-V8 (R13, item 6): Unicode normalization of paths.** Path equality on the
  server is byte for byte. A name can be NFD on one side and NFC on the other,
  depending on how files reached the share. Options:
  - (a) Treat canonically equivalent forms as equal: send both forms with `in`,
    in one request. Case still counts.
  - (b) Exact bytes only, so such photos read "nothing at the mapped path".

  Recommendation: (a). It matches the project-name rule of #271 and needs no new
  request.

## Verification design questions (ruled 2026-11-25: design §16.4)

Kept as raised; every one is ruled in design §16.4.

- **DQ-V1 (§5, §3.4; items 7 and 8): `album.read` with New album.** Retry Failed
  can avoid a second album only by finding the one a lost create made, which
  needs `album.read`. Options:
  - (a) List `album.read` under "Any album" in §5's table.
  - (b) Keep §5 as is, and accept a possible second album after a lost answer.
    R23 would then need an exception like R17's.

  Recommendation: (a). The key caption in §4.1 then names it for albums.
- **DQ-V2 (§3.4, after RI-V2's ruling): the Archive caption.** It depends on the
  ruling. If (a), it needs a sentence that a stacked original leaves the
  timeline with its edit.
- **DQ-V3 (§7.1, item 6): "Hidden or locked".** Only hidden is ever revealed;
  locked reads as not returned or nothing there, as §7.1 step 4 already says.
  Options:
  - (a) Keep the combined wording.
  - (b) Rename the group and sentences to "Hidden".

  Recommendation: (b), since nothing ever reports locked. Low priority.

## Requirements issues

- **RI-E1 (R14, AC22; verified item A): ruled** by the product manager, PRD
  revision 5 (2026-11-26), option (a) with a further fact: a trashed former
  primary is named in the create and rejoins the stack (not on top) if
  restored, unless a later publication has replaced that stack while it was
  still in the trash, which drops it too. The app's requests are unchanged.
  The user guide says so; `trashedPrimaryNamedAndRestored` and
  `laterPublicationDropsTrashedPrimary` pin both halves against the fake
  server.

None open.

## Build and test

| When | Command | Result |
|---|---|---|
| 2026-11-25, baseline | `swift build --product photocli`; `swift run -c release photobench …` | Built clean (Swift 6.4.2). No code was changed, so `swift test` was not run |
| 2026-11-26, baseline at a58d943 | `swift build --build-tests` | Built clean, no errors |
| 2026-11-26, engine | `swift test --filter "Remote\|Publish\|CatalogTests\|LibraryRemoval"` | 159 tests in 15 suites passed |
| 2026-11-26, engine | `swift test --filter PublishJobTests`, three runs | 20 of 20 each time |
| 2026-11-26, done | `swift test` | 1620 tests in 226 suites passed (100.7 s) |
| 2026-11-26, done | `Scripts/build-app.sh all` | Both bundles built and signed |
| 2026-11-26, done | `DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer swift build --build-tests --scratch-path .build-xcode26.3` | Build complete, no errors (Xcode 26.3, `/Applications/Xcode_26.3.app` a link to `/Applications/Xcode-26.3.0.app`) |
| 2026-11-26, done | `PUBLISH_LIVE_SERVER=… PUBLISH_LIVE_KEY_FILE=… swift test --filter PublishLiveTests`, 3.2.0 and 3.4.2 | Passed on both |
| 2026-11-26, review round, baseline at b244b48 | `swift build --build-tests` | Built clean |
| 2026-11-26, review round | `swift test --filter "PublishRulesTests\|PublishJobTests"` | 20 and 28 tests passed |
| 2026-11-26, review round | the three publishing suites, `--skip-build`, 20 runs | 20 of 20 passed |
| 2026-11-26, review round | each new test with its fix reverted (C1, C4, C5, C6, F6, F15, N1) | Each failed (see the tables); restored and passing |
| 2026-11-26, review round | `swift test` | 1634 tests in 226 suites passed (100.2 s), at 0759b74's sources |
| 2026-11-26, review round | `Scripts/build-app.sh all` | Both bundles built and signed (release) |
| 2026-11-26, review round | `DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer swift build --build-tests --scratch-path .build-xcode26.3` | Build complete, no errors, no warnings in the changed files (Swift 6.2.4; `/Applications/Xcode_26.3.app` a link to `/Applications/Xcode-26.3.0.app`) |
| 2026-11-26, second round, baseline at a382a7b | `swift build --build-tests` | Built clean |
| 2026-11-26, second round | `swift test --filter "PublishJobTests\|PublishRulesTests\|PublishBoundaryTests"`, three runs | 57 tests, passed each time |
| 2026-11-26, second round | each new test with its fix reverted (F22, F23, D-10) | `retryFinishingStepsReportsUploading` 2 issues, `endedRunsByEndTime` 1, `stopDuringRetryCheck` 3; restored and passing |
| 2026-11-26, second round | the publishing and connection suites (`PublishJobTests`, `PublishRulesTests`, `PublishBoundaryTests`, `RemoteConnectionTests`, `RemoteSessionTests`; 74 tests), `--skip-build`, 30 runs | 30 of 30 passed |
| 2026-11-26, second round | `swift test` | 1639 tests in 226 suites passed (90.1 s), on the final sources |
| 2026-11-26, second round | `Scripts/build-app.sh all` | Both bundles built and signed (release; the library app's executable records SDK 27.2, minimum 15.0) |
| 2026-11-26, second round | `DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer swift build --build-tests --scratch-path .build-xcode26.3` | Build complete, exit 0, no warning in the changed files (`/Applications/Xcode_26.3.app` a link to `/Applications/Xcode-26.3.0.app`) |
| 2026-11-26, third round, baseline at b16e129 | `swift build --build-tests` | Built clean |
| 2026-11-26, third round | the new tests with each rule stubbed as before (`retryVersionIDs` = the candidates, `offersRetry(laterPublished:)` = `offersRetry`; `PublishServerChange.after` = `.unchanged`) | `retryNothingLeftRule` 5 issues, `retryNothingLeftAfterLaterRun` 2, `chosenServerChange` 4; restored and passing |
| 2026-11-26, third round | `swift test --skip-build --filter "PublishJobTests\|PublishRulesTests\|PublishBoundaryTests"`, 20 runs | 20 of 20 passed (60 tests) |
| 2026-11-26, third round | `swift test` | 1642 tests in 226 suites passed (96.6 s), on the final sources |
| 2026-11-26, third round | `Scripts/build-app.sh all` | Both bundles built and signed (release; the library app's executable records SDK 27.2, minimum 15.0) |
| 2026-11-26, third round | `DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer swift build --build-tests --scratch-path .build-xcode26.3` | Build complete, exit 0, no warning in the changed files (`/Applications/Xcode_26.3.app` a link to `/Applications/Xcode-26.3.0.app`) |
| 2026-11-26, fourth round, baseline at 9773e03 | `swift build --build-tests` | Built clean |
| 2026-11-26, fourth round | each new test against its fix undone (N2 cut, C12 `calledOff = false`, N5 and N6 old rules, D-16 `save` and no check, D-16 Remove's second delete alone, D-15 `since` = `.unchanged`) | `albumAddErrorCut` 5 issues; `stopInsideRetryJobBeforeFirstPhoto` 1; `temporaryFoldersLockRetry` 7, `temporaryFoldersLockLessOnlyWhenOld` 1, `temporaryFoldersNoLinks` 4; `saveNeverRecreatesRemoved` 1, `saveAndRemoveInterleaved` 1 (and 1 with only Remove's second delete undone); `destinationSinceConfirmed` 4; restored and passing |
| 2026-11-26, fourth round | `swift test` | 1651 tests in 226 suites passed (92.1 s), on the final sources |
| 2026-11-26, fourth round | the publishing and connection suites (`PublishJobTests`, `PublishRulesTests`, `PublishBoundaryTests`, `RemoteConnectionTests`, `RemoteSessionTests`; 86 tests), `--skip-build`, 30 runs | 30 of 30 passed |
| 2026-11-26, fourth round | `Scripts/build-app.sh all` | Both bundles built and signed (release; the library app's executable records SDK 27.2, minimum 15.0, and holds D-15's string) |
| 2026-11-26, fourth round | `DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer swift build --build-tests --scratch-path .build-xcode26.3` | Build complete, exit 0, no warning in the changed files (`/Applications/Xcode_26.3.app` a link to `/Applications/Xcode-26.3.0.app`) |
| 2026-11-26, fix round after QA, baseline at bc54ded | `swift build --build-tests` | Built clean |
| 2026-11-26, fix round | the new tests against their fixes undone (N7: the old connect; the re-read with no gate. Q1: album and stack steps deferred to the end of a run. Q2: `found` not counted) | N7 old connect: `staleRecordNeverPaired`, `waitsForTheRow`, `checkDuringSave` failed (5 issues); re-read alone: `waitsForTheRow` 3, `saveHoldsTheGate` 1. Q1: `stepsFollowEachUpload` 4. Q2: `originalsTallyMatchesRun` 3. Restored and passing |
| 2026-11-26, fix round | `swift test` | 1658 tests in 227 suites passed (99.8 s), on the final sources |
| 2026-11-26, fix round | `PublishKeyPairingTests`, `PublishJobTests`, `PublishRulesTests`, `PublishBoundaryTests`, `RemoteConnectionTests` (87 tests), `--skip-build`, 30 runs | 30 of 30 passed (before the CI fix below changed `waitsForTheRow`'s flag from a captured `Mutex` to a `Sendable` class; that form passed in the full run above and alone) |
| 2026-11-26, fix round | `Scripts/build-app.sh all` | Exit 0, both bundles built and signed (release; the library app's executable records SDK 27.2, minimum 15.0) |
| 2026-11-26, fix round | `DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer swift build --build-tests --scratch-path .build-xcode26.3` | First run: 1 error in the new `PublishKeyPairingTests` (Swift 6.2.4 refused a `Mutex` captured by a `Task` inside the gate's closure: "passing closure as a 'sending' parameter risks causing data races"); the test now uses a small `Sendable` flag (same logic). Second run: build complete, exit 0, no warning in the changed files (`/Applications/Xcode_26.3.app` a link to `/Applications/Xcode-26.3.0.app`) |
| 2026-11-26, D-17 to D-19, baseline at aa3216e | `swift build --build-tests` | Built clean |
| 2026-11-26, D-17 to D-19 | `ServerKeyPairingTests` against the old behaviour put back (the import check by uuid alone, the sheet's stored key without its row, the old row write) | 6 of 9 failed, 8 issues; `sourceFollowRule` against a mutation (certificate and running import ignored) 5 issues; restored and passing |
| 2026-11-26, D-17 to D-19 | `swift test` | 1667 tests in 228 suites passed (91.8 s), on the final sources (e840ec9) |
| 2026-11-26, D-17 to D-19 | `ServerKeyPairingTests`, `PublishKeyPairingTests`, `RemoteConnectionTests`, `RemoteSecurityTests` (33 tests), `--skip-build`, 30 runs | 30 of 30 passed |
| 2026-11-26, D-17 to D-19 | `Scripts/build-app.sh all` | Exit 0, both bundles built and signed (release; the library app's executable records SDK 27.2, minimum 15.0) |
| 2026-11-26, D-17 to D-19 | `DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer swift build --build-tests --scratch-path .build-xcode26.3` | Build complete, exit 0, no error or warning in the changed files (Swift 6.2.4; `/Applications/Xcode_26.3.app` a link to `/Applications/Xcode-26.3.0.app`) |
| 2026-11-26, F30-C14 round, baseline at 6587d3f | `swift build` | Built clean |
| 2026-11-26, F30-C14 round | the new tests against their fixes undone (F30: the row taken whenever no import runs; C14: `checkFoundChange` records nothing and returns false) | `checkKeepsARenameTakenMeanwhile` 2 issues; `checkLeftWaitingIsRechecked` 4; restored and passing |
| 2026-11-26, F30-C14 round | `swift test --skip-build --filter "ServerKeyPairingTests\|PublishKeyPairingTests"`, 30 runs | 30 of 30 passed (15 tests). The two new tests are also deterministic by structure: one task, steps in a fixed order, no timing; the F30 test's one check runs to its end before the rename |
| 2026-11-26, F30-C14 round | `swift test` | 1669 tests in 228 suites passed (105.1 s), on the final sources |
| 2026-11-26, F30-C14 round | `Scripts/build-app.sh all` | Both bundles built and signed (release) |
| 2026-11-26, F30-C14 round | `DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer swift build --build-tests --scratch-path .build-xcode26.3` | Build complete, exit 0; warnings only in `SmartAlbumTests.swift` and `VirtualCopiesTests.swift` (older, not this branch's), none in the changed files (`/Applications/Xcode_26.3.app` a link to `/Applications/Xcode-26.3.0.app`) |

Determinism of the new tests: none sleeps to synchronize. The stop tests
(`personsStop`, `endingWaitsForFullySent`) stop at the client's own "fully
sent" callback (`PublishJob.onFullySent`), which the session's serial delegate
queue delivers before the answer, and `personsStop` cancels whichever of the
callback and the task assignment comes second. `endingWaitsForFullySent`'s
no-answer case measures the bound (2 s) with a 4 s margin above it.
`notFullySentCancelledAtOnce` relies on a 48 MB body not fitting the loopback
buffers (about 4 MB observed, status.md task 5). `PublishJobTests` passed 3 of
3 runs in isolation and in 3 full runs; that rules out only a frequent flake.

Determinism of the review round's tests: none sleeps to synchronize.
`stackOrderWhicheverUploadFinishesFirst` forces each order with the fake
server's held answers released one by one, and waits for the job's own
`onRecorded` before releasing the second. `stopKeepsEndingInEveryReport` waits
only for the cancellation it sends itself and for the server to hold an answer
(a fully sent body always arrives), never for the behaviour under test, so
without the fix it fails rather than hangs; its run ends within the 2 s bound.
`temporaryFoldersPerLaunch` uses its own folder and descriptors. The RI-E1 and
C4 tests run one photo or two at concurrency 1. Runs: the three publishing
suites (`PublishJobTests`, `PublishRulesTests`, `PublishBoundaryTests`, 52
tests) passed 20 of 20 times with `--skip-build`, which rules out a per-run
flake rate of about 1 in 7 or more (at about 95%), not rarer ones; the
structural argument above is the claim for those.

Determinism of the third round's tests: `retryNothingLeftRule` and
`chosenServerChange` are pure functions over values. `retryNothingLeftAfterLaterRun`
runs every job at concurrency 1 against the fake server, as `retryAndLaterRuns`
does; the fault is added from the server's own upload callback, the later runs
are awaited before each read, and `laterPublications` compares record times
with the first run's start, which every later record follows by at least one
upload's round trip. No timing or shared state decides it; the 20 clean runs
only rule out a flake of about 1 in 7 or more.

Determinism of the second round's tests: none sleeps to synchronize. C9 makes
the report order structural: every report is computed and delivered under the
counter's one lock, so the listener receives them in the order of their states,
and `stopKeepsEndingInEveryReport`'s "every report after the first ending one
is ending" follows from `ending` never being cleared. `stopDuringRetryCheck`
cancels only after an event it observes (the server has recorded the check's
request, or the test's own check or job closure has yielded), and what it
asserts doesn't depend on when the cancellation lands inside the check: before
the request, during it, or as a result returns, the outcome is called off by
`Task.isCancelled`, checked after the check returns. `untilCancelled` waits for
the cancellation, never for time. `retryFinishingStepsReportsUploading` runs at
concurrency 1 and checks every report, whatever their timing. The 30 clean runs
rule out a per-run flake rate of about 1 in 10 or more (at about 95%); the
structural argument is the claim for rarer ones.

Determinism of the fourth round's tests: none sleeps to synchronize.
`albumAddErrorCut` and `destinationSinceConfirmed` are pure or run against an
in-memory catalog in one task. The D-16 tests put the other window's change at a
fixed point with a key store hook called synchronously inside the save or the
removal, so the order is the code's, not the scheduler's. The temporary folder
tests use their own folders and descriptors, and age by passing `now` or setting
a modification date a day back. `stopInsideRetryJobBeforeFirstPhoto` cancels
only after the job's hook has yielded, and the hook waits for that cancellation
(`untilCancelled`), so the Stop always lands after the job's reads and before
its first photo. The 30 clean runs rule out a per-run flake rate of about 1 in
10 or more (at about 95%); the structural argument is the claim for rarer ones.

Determinism of the fix round's tests: none sleeps to synchronize. In
`waitsForTheRow` the test holds the gate itself and waits only until the check
either waits for it (`RemoteKeyGate.waiters`) or has finished, whichever comes
first, so without the gate it fails rather than hangs. `checkDuringSave`'s check
starts inside the Save's key write, with the gate held; it can take the gate
only after the Save has written its row and let go, so it reads the new row
whenever it is scheduled (with no gate the order is the scheduler's, which is
why it passed against that variant). `saveHoldsTheGate` reads the gate inside
the key store's own call. `stepsFollowEachUpload` runs at concurrency 1 and
waits for the fake server to hold each answer, which a fully sent body always
reaches; b starts only after a's last step returns, so a's album and stack are
done by then. The tally tests run in one task (the cancel case waits for the
`find` closure's own signal, then for its cancellation). The 30 clean runs rule
out a per-run flake rate of about 1 in 10 or more (at about 95%); the structural
argument is the claim for rarer ones.

Determinism of the D-17 to D-19 tests: none sleeps to synchronize.
`sourceFollowRule` is a pure function over values. The sheet and import tests
put the other window's Save at a fixed point in one task: before the press,
between the key read and the check, or after the passing check, by calling
`RemoteServerSheetCheck.key`, `check` and `save` in turn, so the order is the
test's, not the scheduler's. `importCheckWaitsForTheRow` holds the gate itself
and waits only until the check either waits for it or has finished, as
`waitsForTheRow` does, so without the gate it fails rather than hangs. Each test
has its own in-memory catalog, key store and fake server. The 30 clean runs rule
out a per-run flake rate of about 1 in 10 or more (at about 95%); the structural
argument is the claim for rarer ones.

## Design questions (second round, ruled)

Both ruled by the designer on 2026-11-26 (design §17: D-12 for DQ-R2-1, option
(c) with a caption; D-13 for DQ-R2-2) and built in the third round. None open.

- **DQ-R2-1: Retry Failed for photos a later run published.** R23 leaves out of
  a retry a photo not yet uploaded that a later run has since published, and the
  code does. But the run's results still count it (Failed, or Not published),
  `offersRetry` still counts it, so **Retry Failed** stays offered and, pressed,
  sends nothing and ends the run again as completed while the counts still say
  "1 failed" (seen in the second round's script: a fault-stopped run, then a
  Skip run that published its photos, then Retry Failed on the first). Options:
  (a) leave it: the button is harmless, the next press does nothing; cost none;
  (b) after a retry, show such photos under their own line ("published by a
  later run") and leave them out of `offersRetry`; cost: a new count, a section
  or reason sentence, catalog keys and a test, plus a read of the later
  publications when the results sheet opens or when the retry ends; (c) keep
  the counts but leave them out of `offersRetry`, so Retry Failed goes once
  nothing else is left; cost: a catalog read before offering the button
  (`offersRetry` is pure today), small. Recommendation: (c), with the reason
  sentence of (b) if the designer wants the photo explained. Not changed here.
- **DQ-R2-2: the publish sheet after its chosen server is removed** (C10). The
  Server pop-up reads None, Publish and Check Originals are dimmed, and nothing
  says why; the person picks another server. A line ("This server was removed.",
  the results sheet's existing words) under the Server row would explain it.
  Not added: the design doesn't place it.

## Follow-ups proposed

- **Move the server code to a library-only target** (enhancement): a `Remote`
  target and the server parts of the import window (`ServerSource`,
  `ServerSheet`, `ServerText`) in a library-only target, so the standalone
  importer and `photocli` link none of it. See **Decisions on the open items**.
- **The Import window's Date Range and Import buttons may stay dimmed after a
  server connects** (bug, #271's code, found by reading in the second round):
  `ServerBrowse.client` is `@ObservationIgnored`, and `DateRangeButton`
  (`.disabled(model.isImporting || browse.client == nil)`) reads nothing else
  that changes when the check passes, the same pattern as F19. The toolbar's
  Import button reads `selectedShots` and the Album button `albumsLoaded`, which
  do change, so those redraw. Not reproduced on screen (toolbar items are glass
  and don't draw in a snapshot); check with a real window, then drop
  `@ObservationIgnored` from `client`.
- **Publish sheet keeps an old check after its own Server sheet is cancelled**
  (bug; review.md's follow-up, narrowed by D-15 and D-16 to this one case): an
  address or certificate changed in the import window while the publish sheet's
  Server sheet is up, and that sheet then cancelled, leaves the earlier check
  and album list showing until Check Again or another choice. **Publish**
  connects to the saved address, and D-15's invariant still holds. Expected: the
  sheet checks the server as saved now when it comes back. Slug:
  `publishing-engine`.
- **A name-only Save whose catalog write fails says nothing** (bug, #271's
  code, seen while building D-16): the Server sheet stays as it was with no
  message; a checked Save shows the catalog's error. Expected: the same message.
- The first round's "combined script's timeout" is explained: the scripted
  `quit` is ignored while a sheet is up (#276). Closing the sheet first quits.
  The debug script's `quit` now closes publishing's sheets itself (QA Q3).
- The one-photo Check Originals sentence is fixed (F20); that follow-up is gone.
- The import window sending a server's new key to its previous address, and the
  Server sheet checking with the stored key without its row (security N7's
  import side), are fixed by D-18 and D-19; those two follow-ups are gone.

## README

- Publishing: File ▸ Publish… uploads to an Immich server (a Features line).
- Catalog migration v18 (`remotePublication`, `remotePublishSettings`).
- The read-only wording about servers changes (R27): the README's network
  sentence, roadmap principle 3 and `CLAUDE.md`'s Network rule (proposed
  above).
- `PUBLISH_LIVE_SERVER` and `PUBLISH_LIVE_KEY_FILE` run `PublishLiveTests`
  against a throwaway Immich (opt-in, like the other sample tests).
- No new package; no build command changed.
