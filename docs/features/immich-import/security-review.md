# Import from Immich: security review

Date: 2026-11-23. Branch `feature/immich-import` at 1deda12, reviewed by the
main session's `/security-review` (step 4 of `docs/WORKFLOW.md`: the branch
adds network code, a parser of outside data, file writing and Keychain use).
This file was written by the engineer at the coordinator's request, to record
the review and the fixes; the main session verified F1 in the code.

## What was read

The diff against `develop`: PhotoCore `Remote/` (`ServerAddress`,
`RemoteKeyStore`, `RemoteTrust`, `ImmichAPI`, `RemoteHTTPSession`,
`ImmichClient`, `RemoteImporter`, `RemoteAsset`, `RemoteBrowseRules`),
`Catalog/RemoteServices.swift` and migration v16, `CardImport/ImportTemplate`
as the importer reaches it, PhotoUI `Import/ServerSheet.swift` and
`ServerSource.swift`, PhotoApp's key-store choice and debug commands,
`Support/Info.plist`, and the fake server in PhotoFixtures.

## Findings

| # | Severity | Where | Finding | Fix | Tests (fail without the fix) |
|---|---|---|---|---|---|
| F1 | Medium (path traversal) | `CardImport/ImportTemplate.swift:85`, reached from `Remote/RemoteImporter.swift` `finish` | When the expanded file name template is empty (`{number}` on a name without digits, `{model}`, `{make}`, `{lens}`, `{serial}` without EXIF, `{job}` without a job code), `render` fell back on the original name unsanitized. For a server the original name is Immich's `originalFileName`, verbatim. A hostile or compromised server, or anyone who can upload into the account, could list `../../../../tmp/x.jpg`; `appending(path:)` and `freeName` don't resolve `..`, the kernel does at the move, `VolumeResolver.relativePath` accepted it when the volume matched, and the file was cataloged as a master outside the chosen folder | Three layers. (1) `ImportTemplate.render` sanitizes the fallback (the name's last component, without its extension) and falls back on the constant `photo` when that is empty; the extension is kept only when it is 1 to 16 ASCII letters and digits. Ordinary names render as before (card import unchanged). (2) At decode, `RemoteAsset.isPlainFileName` refuses a name with `/`, `\`, NUL or another control character, or that is `.` or `..`: such an asset is not listed. (3) `RemoteImporter.finish` refuses, before the move, a target that is not inside the destination by path components after `.` and `..` (`isInside`, resolved by text: `/a/bc` is not inside `/a/b`; not with `standardizedFileURL`, which drops `/private` only from a path whose shorter form exists, so a new file under an existing `/private/tmp` folder looked outside it, a regression the scripted run caught before commit); that photo fails ("its name on the server would have placed it outside the destination folder"), its partial file is deleted, no row | `RemoteSecurityTests.templateFallback` (`{number}`, `{model}`, `{job}`, `{serial}` × `../../x.jpg`, `a/b/../../../c.jpg`, backslashes, NUL, `../../../../../../../../tmp/f.jpg`), `namesAtDecode`, `endToEnd` (through the fake server, past the decoder, with `{job}` and `{number}`: every file inside the destination, no `..` in any catalog path), `containment` (including a new file under an existing `/private/tmp` folder); scripted: an import with the file template `{job}` names files by the original names, inside the destination |
| F2 | Low | `PhotoUI/Import/ServerSheet.swift`, the save after a passed check | In Edit with both the address and the key changed, the new key was written under the same Keychain account before the row; a failed row save rolled the key back only for Add, so the catalog kept the old address and pin while the Keychain held the key meant for the new address, and the next connection would send it to the old host | `Catalog.saveRemoteService(_:key:keys:)` saves both as one change: it reads the previous key, writes the new one, saves the row, and on a failed save puts the previous key back (or deletes the new one when there was none). The sheet uses it; the key store is called off the main actor | `RemoteSecurityTests.keyRollback` (a read-only catalog refuses the save: the old key is back; for a new connection no key is left; a refusing store changes nothing) |

Notes the review raised, no change asked:
- (a) The plain-http rule judges the name, not the address it resolves to
  (`http://nas` is local; a DNS search domain could send it elsewhere). R5 asks
  for this and the person confirms the notice. The user guide now says so.
- (b) Hosts with Unicode digits or letters (`⒏`, fullwidth digits) passed the
  local-name test as single labels. Fixed as it was cheap: the local-name test
  takes ASCII letters, digits, `-` and `.` only, so such a host is not local
  and plain http to it is refused (`RemoteSecurityTests.unicodeHosts`).

## Checked and sound

- The request allowlist is enforced before every request is built; asset ids
  are limited to `[0-9A-Za-z-]{1,64}`, so an id can't change a path; the built
  URL's host must be the connection's.
- TLS: the decision is made in the server-trust challenge for that host only,
  before the request (and the key) is sent; a pin wins over the system's trust;
  no bypass; other challenge types are rejected.
- Redirects are never followed; the session is ephemeral (no cookies, cache or
  credential storage).
- The key: only in the key store and the request header; no description,
  log line or debug print contains it; test launches keep keys in memory
  (code review C6).
- Sizes and answers are bounded (code review C3, C4); numeric hosts are read
  as the system reads them (C5).
- Verified downloads: size and SHA-1 (or size only for external libraries),
  read back around the file cache, SHA-256 dedupe; partial files removed on
  every failure; no master can be replaced (`freeName`, `moveItem`).
- Migration v16 and the link table: generic names, cascades as designed.

## Status

Both findings fixed on 2026-11-23 (the commit after 1deda12); the tests above
fail on the unfixed code (checked by reverting the three fixes locally: 43
issues in `templateFallback`, `keyRollback` and `endToEnd`) and pass with them.

## Second review: RemoteHTTPSession after the CI and C22/C23 fixes (2026-11-24)

Reviewed: `git diff 465fbec..573ef5c` (9dca22c, the delegate-driven data task
for CI on PR #278; 573ef5c, C22 and C23), mainly
`Sources/PhotoCore/Remote/RemoteHTTPSession.swift`, with
`Sources/PhotoFixtures/FakeImmichServer.swift` and the new tests for intent.
This was a read-only review (model claude-opus-5-5). It changed nothing in the
repository except this section. Probes ran under the scratchpad:
- a Python server sending chosen heads and bodies;
- standalone Swift programs that copy the sinks' head logic
  (`ContentCoding.isIdentity`, `.cancel` at the head);
- the branch's own `RemoteHTTPSession.swift`, compiled standalone with
  `ServerAddress`, `RemoteTrust`, `ImmichAPI`, `RemoteAsset` and stubs for
  three unrelated types, calling `data(.serverVersion)` over plain http to
  127.0.0.1.

# Vuln 1: Resource exhaustion (decompression bomb; C23 is not closed): `Sources/PhotoCore/Remote/RemoteHTTPSession.swift:257-273`, `:370-373`, `:457-460` (transport: `:156`, `:225`)

* Severity: Medium
* Description: The C23 fix assumes the system decodes nothing before the
  delegate's response callback. That holds only when the system has no reason
  to read the body before it hands over the head. Two conditions change that:
  - the answer has no `Content-Type`, or has `text/plain`, so the system
    sniffs the content type, and the server chooses its headers;
  - the body arrives after the head, which is normal: most servers write the
    head and the body separately.

  When both hold, URLSession decodes the gzip body it has already read, and
  only then delivers the head. The head is still refused (`.malformed`), but
  the decoded memory has already been allocated, and it stays in the process
  footprint after the call. The status.md probe (C23: "refusing there gave 0
  bytes … 30 MB") sent the head and body in one write. The fake server always
  sends a `Content-Type`. So neither saw this. The identity check itself has
  no bypass (see "Checked" below).

  Measurements. The answer is 1,043,658 bytes of gzip (1 GiB of spaces) with
  `Content-Encoding: gzip` and no `Content-Type`:
  - **The branch's session.** `RemoteHTTPSession.data(.serverVersion)` (cap
    64 KiB). The server sends the head, waits 200 ms, then sends the body. The
    call ends `.malformed` after 250 to 300 ms, with a footprint of 164 to
    405 MB after one call. Eight calls in one session leave 590 MB held.
  - **The same head logic, 30 runs per case** (peak resident):
    - head and body in two writes, no pause: 18 of 30 runs at 333 to 798 MB;
    - a 10 ms pause: every run at 173 MB or more, two at 2,062 MB;
    - a 200 ms pause: every run at 269 MB or more, 13 of 30 at 1 GB or more,
      up to 2,062 MB;
    - 2 MiB of gzip (2 GiB decoded): up to 2,484 MB.
  - **How much is decoded.** About 1,000 times what the system read in one go
    before it delivered the head. That depends on socket buffers: a faster
    link reads more.
  - **Controls.** The same answer with `Content-Type: application/json`: 12 to
    28 MB. Head and body in one write: 44 MB.
* Exploit Scenario: A person types an attacker's address in Add Server…. It
  can be https with a publicly trusted certificate for the attacker's own
  name, or plain http to a local host after the notice. The unauthenticated
  `GET /api/server/version` gets about 1 MiB as above. The app's memory rises
  by hundreds of MB to over 2 GB per attempt, and each retry adds more. A
  compromised Immich server can do the same on every thumbnail (six at a
  time), album list, search page and original. This affects availability
  only: nothing is read or written.
* Recommendation: URLSession has no public way to turn off content decoding or
  sniffing, so no check in the delegate can close this. The owner chooses:
  - **(a) A transport that never decodes.** Either:
    - `URLSessionStreamTask` (`streamTask(withHostName:port:)`, then
      `startSecureConnection()`). Check that the server-trust challenge still
      reaches `SessionDelegate.handle`.
    - `NWConnection`, with `sec_protocol_options_set_verify_block` running
      `TrustDecision.decide`. This changes CLAUDE.md's "Nothing else may use
      `URLSession`" wording.

    Both need a small HTTP/1.1 reader written here:
    - the status line and headers under a fixed total (64 KiB, say);
    - `Content-Length` or chunked bodies;
    - any `Content-Encoding` other than identity refused;
    - today's caps counted on the bytes as they arrive.

    That reader is a new parser of outside data, a risk area that needs its
    own tests (for example: an encoded answer ends at its head and no decoded
    byte reaches a sink). It also closes Low 1.
  - **(b) Accept a documented bound.** Hundreds of MB to a few GB per answer,
    as measured. Then correct the C23 record in status.md ("Seventh code
    review") and code-review.md, which say the body is refused "before a byte
    of its body is read".

  Either way, add a fake-server fault that sends the head with no
  `Content-Type`, pauses, then sends a gzip body, so the case is exercised.

## Lows

- **L1: unbounded response head** (URLSession behavior, older than this
  diff). The system buffers a head until it ends or the request timeout (30 s)
  fires. Measured with the branch's session, the server sending at 40 MiB/s:
  - one endless header line: peak 1.04 GB;
  - endless 1 KB header lines: peak 2.66 GB, about 2.4 times the bytes sent.

  Both ended `.unreachable("The request timed out.")` after 30.5 s, and the
  memory stayed held. A flood of `100 Continue` heads peaked at 215 MB before
  the system dropped the connection (-1005). This is bounded by bandwidth and
  time and not amplified, so it is rated Low. A 1 GbE link would reach several
  GB. Option (a) above fixes it.

## Checked and sound

- **The identity check** (probed against the system's parsing):
  - The header lookup ignores case.
  - The system joins repeated `Content-Encoding` lines, and every joined form
    is refused: `gzip, identity`, `identity, gzip`, `identity, ` and `, gzip`.
  - A folded line reads `identity gzip` and is refused.
  - Also refused: `Content-Encoding : gzip`, no space, a tab, `\v`, a trailing
    NUL, `x-gzip` and `identity , gzip`.
  - `Transfer-Encoding: gzip, chunked` is not decoded: the compressed bytes
    arrive as they are, in pieces of at most 132 KB, and the cap counts them.
  - `Content-Type: application/x-gzip` without `Content-Encoding` is not
    decoded.
  - In `multipart/x-mixed-replace`, each part's head goes through
    `received(_ response:)` again, and a part labelled gzip is refused without
    being decoded.
- **The key.** `makeRequest` is unchanged: the allowlist is checked first, the
  built host is checked, and `x-api-key` is sent only when `sendsKey` is set.
  Data tasks get the same redirect delegate (`completionHandler(nil)`). No
  description or error carries the key. The new error strings are the
  system's own: URLError text with the failing URL removed, and `.disk`
  reasons from the local disk. None carries text the server sent.
- **Certificates.**
  - A refusal is recorded only for the connection's own host.
  - A refused handshake never produces a response, so a refusal taken by the
    wrong task, or left over, can only change which error is reported
    (cancelled or unreachable instead of the certificate). It never lets an
    answer through.
  - Only `.pinned` and `.systemTrusted` are accepted.
  - The check sends one request at a time.
- **Caps on plain answers.**
  - `Content-Length` is checked at the head.
  - Each piece is counted before it is appended.
  - A download is checked against `limit` before each write.
  - A refusal at the head (status or encoding) writes nothing.
  - The result is delivered only from `didCompleteWithError`, the last
    callback, and the handle is closed after it, so nothing is written after
    close.
  - The partial file is `.download-<UUID>.<ext>` in the chosen folder, with
    the extension taken from a name F1 already restricts.
- **Result handoff (C22).** There is one sink per task identifier, and
  identifiers are never reused in a session. The first result wins, and a
  second wait traps. A call already cancelled ends `.cancelled` with its
  partial file removed. No path delivers twice, delivers to another call or
  leaves a partial file.
- **Session posture** is unchanged:
  - the session is ephemeral;
  - there are no cookies, no cache and no credential storage;
  - challenges other than server trust get `.rejectProtectionSpace`.
- **Fake server.** The changes are for tests only: `onRequest`,
  `onAnswered` and the `contentEncoding` fault.

## Status

Vuln 1 is open: the owner chooses (a) or (b), and the engineer then builds it
or corrects the record. L1 is recorded for information; option (a) would
close it.
