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
