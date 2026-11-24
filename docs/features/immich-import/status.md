Issue: #271 · Complexity: hard

# Import from Immich: status

Owner: swift-macos-engineer. Branch `feature/immich-import` (off `develop`).
Spec: the PRD (issue #271, rev3: R1 to R25, AC1 to AC17, rulings RI-2 and
RI-6) and [design.md](design.md) (DQ-1 to DQ-4 ruled, §14.3).

**State: In progress.**

## API verification (first task, 2026-11-23)

Read from the OpenAPI spec of the tags `v3.2.0` (the minimum, Q1) and
`v3.4.2` (the latest release), and from the server's source at `v3.4.2`
(`server/src/services/search.service.ts`, `utils/database.ts`,
`services/asset-media.service.ts`, `dtos/auth.dto.ts`, `services/api-key.service.ts`,
`enum.ts`, `services/library.service.ts`). Every endpoint and field below is
the same in both tags. Not checked against the owner's server.

| Item (PRD "Not verified") | Finding | What the code does |
|---|---|---|
| `filter.albumIds` | `IdsFilter`: `{ "any": [uuid], "all": [uuid], "none": [uuid] }` | `{"albumIds": {"any": [id]}}` |
| `filter.type` | `EnumFilterAssetType`: `{ "eq" \| "ne": "IMAGE"… , "in" \| "notIn": [...] }` | `{"type": {"eq": "IMAGE"}}` |
| `filter.visibility` | `EnumFilterAssetVisibility`, values `archive`, `timeline`, `hidden`, `locked` | `{"visibility": {"eq": "timeline"}}` (archive, hidden and locked left out, Q4) |
| Trashed assets | **The v3 search does not leave trashed assets out by default** (`searchAssetBuilder` has no `deletedAt` default; only the deprecated flat shape had `withDeleted`) | `{"trashedAt": {"eq": null}}` in the filter, and every listed asset with `isTrashed`, another type or another visibility is dropped on our side too |
| Date range (R10b) | `filter.takenAt`: `DateFilter` (`gte`, `lte`, …) | `gte` start of the first day, `lt` start of the day after the last |
| Order | `orderBy: {field: fileCreatedAt \| localDateTime \| …, direction: asc \| desc}`, default `fileCreatedAt desc` | `{"field": "fileCreatedAt", "direction": "desc"}` (newest capture first, R9) |
| Paging | `size` 1 to 1000 (default 250); `cursor` is an encoded offset (`offset + size`); `nextCursor` null on the last page | 250 per page (`ImmichAPI.pageSize`) |
| `count` / `total` | `count` is the page's length; **`total` is also the page's length** (`mapResponse`: `total: assets.length`), deprecated since v3.0.0 | No exact total exists for All Photos, so All Photos never shows a count (R10, as the PRD allows) |
| Album count | `GET /albums` items carry `assetCount` (every asset, videos included) | Shown as the server's number (R10, RI-5) |
| Albums listed | `GET /albums?isOwned=true` gives the account's own albums (`isOwned` exists since before v3.2.0) | Own albums only; shared-with-me albums are a non-goal |
| **Partners' photos** | **The search universe is the account's own assets plus every partner whose timeline the account shows** (`getUserIdsToSearch`). Album-confined searches list every asset in the album, whoever owns it | See **Requirements issues**, RI-E1. Built: assets whose `ownerId` is not the account's are dropped when the account's id is known (see RI-E1) |
| `/server/version`, `/server/ping` | No security scheme: no key needed | The check reads `/server/version` without the key first (not Immich, too old), then `/api-keys/me` with it |
| `/api-keys/me` | Any valid key (`permission: false`); returns `id`, `name`, `createdAt`, `updatedAt`, `permissions` (a list; `all` for a full key); 403 "Not authenticated with an API Key" for a session | Missing permissions are read from this list (R2, R3); `all` covers the four. The read-per-permission fallback of design §3.4 is not needed on 3.2.0 or later |
| `edited` on `/assets/{id}/original` | Defaults to `false` (`isEditedOnly(auth, edited = false)`, true only for a shared link) | `edited=false` is sent explicitly on `/original` and `/thumbnail` (R21) |
| Byte ranges on `/original` | Served by Express `res.sendFile`, which honours `Range` | Not used: no resume (non-goal) |
| Rate limits | No throttling in the server (no throttler module or rate setting at v3.4.2); a reverse proxy in front may have one | Retries: see **Retries and timeouts** |
| RAW+JPEG pairs | Each uploaded file is its own asset; stacks group assets only when someone stacked them. The search lists stacked assets unless `withStacked: false` | `withStacked` is not sent, so both files of a pair are listed as two tiles (design §4.5); pairing happens after landing (R14) |
| Live Photos | The still is an `IMAGE` with `livePhotoVideoId`; the motion part is a `VIDEO` asset with visibility `hidden` | Never listed (type and visibility filters); a still with `livePhotoVideoId` counts toward "Live Photo videos were not downloaded" when imported |
| `checksum` | Base64 of 20 bytes. **For assets of an external library the checksum can be the SHA-1 of `"path:" + originalPath`, not of the file** (`ChecksumAlgorithm.sha1Path`, still written by `library.service.ts` at v3.4.2; the response does not say which) | See **Requirements issues**, RI-E2. Built as R13 says: a mismatch is a failure |
| `image.caption` | Is the library's Description (`DescriptiveField.caption` shown as Description, `FieldLabel`) | Immich `exifInfo.description` goes to `image.caption` (R17) |
| `exifInfo.rating` | 1 to 5 or null | Rating 1 to 5; null is 0 (R17) |
| `exifInfo.fileSizeInByte` | Nullable | The byte count checked is `fileSizeInByte`, else the response's `Content-Length`, else none (SHA-1 only) |
| Auth header | `x-api-key` (security scheme `api_key`) | Sent only to the connection's host; redirects are never followed (R7) |

**App Transport Security (Info.plist).** Apple's documentation for
`NSAllowsLocalNetworking`: on macOS 14 and later ATS no longer allows plain
http to IP addresses by default; the key "enable[s] access to unqualified
domains, .local domains, and IP addresses that they would otherwise restrict".
So `NSAppTransportSecurity` ▸ `NSAllowsLocalNetworking = YES` is the narrowest
setting that lets `http://192.168.1.5`, `http://nas.local` and `http://nas`
load; `NSAllowsArbitraryLoads` is not set. The key also lets an IP literal
outside the local ranges through ATS, so the code's transport policy
(`TransportPolicy`, R5) is the guard that refuses `http://8.8.8.8`.
`NSLocalNetworkUsageDescription` carries design §10's sentence. The app has
only English, so the sentence is in the Info.plist template itself (an
`InfoPlist.strings` would be needed for other languages; the String Catalog
compiler writes `Localizable.strings` only).

**Sandbox.** `Scripts/build-app.sh` signs ad hoc with no entitlements: the app
is not sandboxed, so no network-client or local-network entitlement is needed.
macOS's Local Network privacy prompt applies to unsandboxed apps too (P7).

## Sidecars: how the import writes description and rating (RI-6)

`insertMasters` inserts the image and its default version with the file's own
values and records them as the sidecar baseline (`metadataSync`); the sidecar
triggers fire on `UPDATE` only. The Immich values are then written by an
`UPDATE` of `image.caption` and of the default version's `rating`, in the same
transaction as the link, and only where the library's value is empty (caption
null or blank; rating 0). So a description or rating that came from Immich
differs from the baseline, the existing triggers (`sidecar_description`,
`sidecar_culling`) queue the photo's sidecar, and `SidecarSync` writes it under
its existing rules (only when sidecars are on; never over a sidecar another app
changed). A download has no sidecar beside it, so the first write creates one.
Nothing about the triggers changed.

## Retries and timeouts (R20)

- Each request: 30 s without a byte (`timeoutIntervalForRequest`); the
  connection check as a whole is bounded by 20 s per request and stops on
  Cancel.
- A request that fails for a transport reason (timeout, connection lost,
  cannot connect, DNS) or answers 502, 503 or 504 is tried again up to **3
  times**, after 1 s, 2 s and 4 s (so about 7 s plus the timeouts). Then the job
  stops ("stopped responding").
- 401 stops the job at once (key rejected); 403 stops it with the permission
  the request needs. 404 on one asset is a counted failure and the job goes on.
  Other statuses on one asset are a counted failure with the number.
- Thumbnails: at most 6 at once, no retry (a failed one leaves the
  placeholder).

## Requirements issues

(Filled in at the end of the step that met them.)
