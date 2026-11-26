# Publish to Immich: design

Owner: apple-ui-designer. Date: 2026-11-25.
Issue: #28. Status: complete against PRD revision 4 (2026-11-25). Immich
behaviour was verified on 3.2.0 and 3.4.2 (§15). Every requirements issue, owner
question and design question is ruled (§16); none is open.

**Inputs.**

- Requirements: the PRD, the body of issue #28. Cited as "R‹n›", "AC‹n›".
- House designs followed: [`../immich-import/design.md`](../immich-import/design.md)
  ("II": the Server sheet, security wording, result texts), the Export sheet and
  `docs/UI_REDESIGN.md` §8 (sheets, forms, Activity, the quit alert),
  [`../hdr-merge/design.md`](../hdr-merge/design.md) (refusals shown before
  anything runs), the UI reconciliation's rule that a background job reports in
  Activity and raises no alert.
- Code read: `ExportSheet`, `ExportModel` (settings and presets),
  `ExportSettings`, `ExportActivityReport`, `ServerSheet`, `ImmichClient`
  (check), `RemoteServices`, `LibraryModal`, `LibraryCommands`,
  `LibraryMenuContext`, `LibraryToolbar`, `PhotoContextMenu`,
  `ActivityToolbarItem`, `ActivityLog`, `QuitConfirmation`, `QuitGuard`,
  `MergeSheet`, `SettingsView`.
- HIG pages read 2026-11-25 (markdown versions): Keyboards, Sheets. Alerts,
  Menus and Toolbars are applied as II and the house designs cite them.
- Immich behaviour: [`status.md`](status.md), "Immich verification". Cited as
  "§15" here, which summarizes what it means for this design.

**Custom chrome.** None. Every surface is a system component: menu items, a
toolbar button, SwiftUI sheets made of grouped `Form`s with `Picker`, `Menu`,
`Toggle`, `TextField`, `DisclosureGroup`, `ProgressView`,
`ContentUnavailableView` and `.alert`.

## 1. Rulings in one place (the engineer's index)

| # | Ruling | Section |
|---|---|---|
| P1 | **File ▸ Publish…** (⌥⌘E), directly under Export…; a **Publish** toolbar item after Export, shown by default; **Publish…** after Export… in the photo context menus | §2 |
| P2 | One **sheet on the library window**, built like Export: header, one scrolling form, Cancel and **Publish N Photos** | §3 |
| P3 | Render settings are a summary row with the preset menu; the full export form is a **page** of the sheet. The form is shared with Export, not copied | §3.6 |
| P4 | Add and Edit Server reuse the #271 sheet. It **replaces** the publish sheet and the publish sheet comes back afterwards; never a sheet on a sheet. Where it was opened decides which permissions it requires | §4 |
| P5 | Missing permissions are named **under the option that needs them**, before Publish can be pressed, and checked again when it is pressed | §5 |
| P6 | The folder map is a **page** of the publish sheet, saved to the server on Done, with a worked example from the selection under each pair | §6 |
| P7 | **Check Originals** sits with Stack with original, and the caption there says that unmatched photos are published unstacked | §7 |
| P8 | **Skip / New Copy / Cancel**: one alert on the sheet after Publish is pressed; **Skip** is the default | §8 |
| P9 | The run is an Activity job with Stop; an ending run waits a bounded time for answers to fully sent files, with Stop dimmed; no alert at the end, whatever happened | §9 |
| P10 | **Publish Results** sheet, opened from the Activity row or File ▸ Publish Results…, lists every reason and holds **Retry Failed** | §10 |
| P11 | The Import window marks published assets **In Library** with their own tooltip | §11 |
| P12 | Nothing in Settings, the sidebar, the standalone importer or `photocli` | §12 |
| P13 | No text says the app only reads from a server; the new strings, the `Info.plist` one included, are listed | §4.1 |
| P14 | Edit Server warns under the address when a changed address leaves records or links behind | §4.2 |
| P15 | With **Archive** and stacking both on, the sheet warns that stacked originals leave the timeline too; it does not block Publish | §3.4 |
| P16 | An already-there photo that is trashed, hidden or unreadable is listed as **Already There, Nothing Else Done**: not a failure, not retried | §10 |

## 2. Where the command lives

### 2.1 Menu bar

| Menu | Item | Key | Enabled when |
|---|---|---|---|
| File | Export… | ⇧⌘E | unchanged |
| File | **Publish…** | **⌥⌘E** | the targets include a photo and no publish is running |
| File | **Publish Results…** | none | a publish run has ended since launch |
| File | **Stop Publishing** (the single Stop item) | ⌘. | publishing is the newest job Activity shows |

- Order in File: Publish… and Publish Results… go between Export… and Remove
  from Library…; the rest of the menu is unchanged. Both new items are always
  present and dimmed when unavailable (HIG Menus).
- **Name.** "Publish…", with an ellipsis because it needs more choices. No brand
  in the command: the server is a value in the sheet, and a later destination
  uses the same command (II D1's reasoning; owner, 2026-11-25; R1).
- **⌥⌘E** pairs with Export's ⇧⌘E. ⇧⌘P and ⌘P are the system's Page Setup and
  Print and are not used. No clash in the app's own shortcuts. Judgment: the HIG
  has nothing to say about publishing.
- Targets are Export's (`ExportTargets`): the grid selection, the loupe's photo,
  or the active comparison pane. Videos are counted and skipped, a pair
  publishes once from its raw, each virtual copy is its own publication (R2).

### 2.2 Toolbar

`ToolbarItem(id: "publish")` immediately after `export`, in the default set,
customizable. Label **Publish**, symbol `paperplane`, tooltip **Publish the
selected photos to a server**. Dimmed exactly as the menu item. Not
`icloud.and.arrow.up` (that means iCloud) and not a second share-arrow glyph
that reads as Export.

### 2.3 Context menu

**Publish…** directly after **Export…** in `PhotoContextMenu`, shown when the
command is enabled (the context menu leaves unavailable items out, as it does
for Export…).

## 3. The publish sheet

### 3.1 Construction

A sheet on the library window, 560 pt wide, minimum height 480, ideal 640, never
taller than the window allows (Export's frame and `presentationSizing(.fitted)`).
Fixed header, one scrolling grouped `Form`, fixed button bar. It freezes the
targets when it opens. Add `publish` to `LibraryModal` (§4 and §10 add two more).

```
┌ [thumb] Publish 12 Photos ───────────────────────────────────┐
│         From Iceland · 1 video is skipped                    │
├──────────────────────────────────────────────────────────────┤
│ Server                                                       │
│   Server          [ Home Server ▾ ]                          │
│                   https://photos.example.com                 │
│ Album                                                        │
│   Album           [ None ▾ ]                                 │
│   Show in         [ Timeline | Archive ]                     │
│ Stacking                                                     │
│   ☑ Stack with original                                      │
│     Each photo goes on top of its original in Immich. …      │
│   Folder map      2 folders          [ Edit Folder Map… ]    │
│   [ Check Originals ]                                        │
│ Files                                                        │
│   Preset          [ None ▾ ]                                 │
│   Settings        JPEG 90% · sRGB · Full Size · All metadata │
│                                      [ Edit Settings… ]      │
│   Description     [ Leave empty to keep each photo's own ]   │
│     Immich is told each file's name and capture date. …      │
├──────────────────────────────────────────────────────────────┤
│                           [ Cancel ] [ Publish 12 Photos ]   │
└──────────────────────────────────────────────────────────────┘
```

The section order follows the decisions: where, how it is filed there, what it
sits on, what file is sent.

### 3.2 Header

Reference thumbnail (44 pt), **Publish N Photos** (13 pt semibold, a header
trait), then **From ‹source›** with **· N videos are skipped** as in Export.
Information lines below, each `info.circle` and 11 pt secondary, only when true:

- **N originals are offline and won't be published.** N counts the photos in the
  title; they stay in it and are reported as failures (R2).
- **N photos have HDR on. Published photos are SDR.** (R3; the counterpart of
  Export's notice.)

### 3.3 Server section

- **Server**: a `Menu` with an inline `Picker` of saved servers by name, a
  divider, **Add Server…**, and **Edit “‹name›”…** (§4).
- Under it, 11 pt secondary: the normalized address, middle-truncated, full text
  as tooltip. For plain http, a persistent second line with
  `exclamationmark.triangle`: **Not encrypted (http). Your key and photos cross
  the network unprotected.** (II §3.3: the choice is never hidden after it is
  made.) The line cannot be dismissed. The consent given when the server was
  added covers publishing, so there is no second confirmation (R1, AC18). An
  https server has no such line.
- Preselected: the server last published to, else the only one, else the first by
  name.
- **Opening the sheet contacts the preselected server**, and choosing another
  contacts that one. Opening Publish is an act aimed at a server; nothing
  contacts one at launch or on a timer (II D3).

| State | Shown |
|---|---|
| No saved server | The form is replaced by `ContentUnavailableView`: **Add a Server to Publish To** (`server.rack`), description **Photos are published to an Immich server.**, action **Add Server…**. The button bar has Cancel and a dimmed Publish |
| Checking | A small spinner and **Checking “‹name›”…** under the address. Settings stay editable; the Album pop-up, Check Originals and Publish are dimmed |
| Failed | II §3.4's title and detail (`ServerText`), selectable, with **Try Again** and **Edit Server…**; a changed or untrusted certificate shows **Review Certificate…** in place of Edit Server… (it opens the Server sheet on its certificate page). Publish dimmed |
| Keychain refused | **The key couldn't be read** and the system's text; **Try Again**, **Edit Server…** |
| Passed | Nothing extra |

The publish check is II's check (reachable, Immich, 3.2.0 or newer, key
accepted, certificate) but it asks for **only the permissions the chosen options
need** (§5), not import's five. In particular it reads the key's account (which
needs `user.read`; import's check always does) only when stacking is on. A missing
permission is not one of the **Failed** states above: §5 shows it. The version
result uses the publishing wording of §4.1.

### 3.4 Album section (R6)

**Album**, a pop-up:

```
  ✓ None
    New Album…
  ───────────
    Holiday 2024 (123)
    Kids (1,204)
```

- Existing entries are the account's own albums, sorted as II §4.2. While they
  load, the pop-up is dimmed and titled **Loading albums…**. If the list fails,
  **None** and **New Album…** stay usable and an issue line says **The server's
  albums couldn't be listed: ‹reason›** with **Try Again**.
- **A key without `album.read`** can use no album, new or existing (R8). The list
  isn't requested, and **None** is the only item that can be chosen. **New
  Album…** stays in the menu, dimmed, over a dimmed line **Albums need album.read
  on this key**, so the person can tell why there are none (HIG Menus: dim an
  unavailable item rather than hide it). A remembered or already chosen album is
  not switched to None silently: the pop-up keeps showing it, §5's issue line
  stands, and Publish is dimmed until None is chosen or the key is fixed. Neither
  the list-failure line nor the album-gone line shows in this case.
- **New Album…** adds a row **Name** (`TextField`). Publish is dimmed while the
  trimmed name is empty. If an album of that exact name exists, a note (not a
  refusal; Immich allows it): **An album with this name already exists. A second
  one will be made.** with a button **Use the Existing Album**.
- The album is made with the first photo that gets an album step (a new upload,
  or an already-there photo that can be used, §10.1), so a run in which none does
  leaves no empty album. After it is made it is remembered as an existing album
  (R7). A lost answer never makes a second album, and an older album of the same
  name is never taken for the one the run made (R22, AC24).
- **A remembered album that is gone** is never replaced silently. The pop-up reads
  **Choose an Album** with the issue **“‹album›”, used last time, is no longer on
  this server. Choose another album or None.** Publish is dimmed until one is
  chosen.
- **Show in**: segmented **Timeline** (default) and **Archive**, set by the
  upload itself. When Archive is chosen, an 11 pt secondary line under the
  control:
  - Stacking off: **Published photos go to the archive, not the timeline.**
  - Stacking on, with `exclamationmark.triangle`: **Published photos go to the
    archive, not the timeline. A stacked original leaves the timeline with its
    edit, and so does the rest of its stack. Their own visibility isn't
    changed.**
- The stacked form is a warning, not a refusal (owner, R6): Publish stays
  enabled, and there is no alert or extra check box. It follows the **Stack with
  original** box at once, although the two are in different sections, and is
  announced when it appears (§13). The sheet's height counts it.

### 3.5 Stacking section (R10 to R16)

- `Toggle` check box **Stack with original**, on by default.
- Caption, always: **Each photo goes on top of its original in Immich. A photo
  whose original isn't found is still published, unstacked. Check Originals shows
  which ones before anything is uploaded.** This is the R16 check presented with
  the owner's choice (R15).
- **Folder map** row: **No folders** or **N folders**, and **Edit Folder Map…**
  (§6).
- When no folder is mapped and no selected photo was imported from this server
  (both known locally), an `info.circle` line: **No original can be found yet:
  none of these photos was imported from this server, and no folder is mapped.**
- **Check Originals** (§7).
- With the box off, the folder-map row, the info line and the check are hidden.
  The sheet does not change size.

### 3.6 Files section (R3 to R5)

- **Preset**: the Export sheet's preset menu (None, the export presets, Save as
  Preset…, Update, Delete), the same component and the same stored presets.
- **Settings**: a one-to-two-line summary, **‹format and quality or bit depth› ·
  ‹color space› · ‹size› · ‹metadata level›**, then **· Watermark** and
  **· Template names** when they apply; the trailing button **Edit Settings…**
  opens the settings page.
- A settings problem Export would report (missing watermark image, empty
  template) shows as an issue line under the summary and dims Publish.
- **Description**: `TextField(axis: .vertical)`, two to four lines, prompt
  **Leave empty to keep each photo's own**. Typed text goes into every file of
  this run and not into the library. Never remembered. At a metadata level that
  omits descriptions the field is dimmed, keeps its text, and the caption reads
  **Not sent: Include is set to “‹level›”.**
- Caption, always: **Immich is told each file's name and capture date. Ratings,
  flags and labels are never sent.** At **All metadata**, add **Location is
  included.** so the one privacy-relevant setting is visible without opening the
  page.

**Settings page** (same sheet, same size). Title **File Settings**; the form holds
Export's **File Names**, **File Type**, **Size**, **Metadata** and **Watermark**
sections. No Destination and no Show in Finder. Buttons **Cancel** (Esc, restores
the settings as they were on entering) and **Done** (Return). No Back button as
well (HIG Sheets: don't show Cancel, Done and Back together). A preset saved or
deleted from the main page stays saved or deleted.

Extract the sections from `ExportForm` into views bound to an `ExportSettings`
binding plus a small model for the example name, watermark image and issues. Both
sheets use them. Two copies would drift, and R3 requires the same settings.

### 3.7 What is remembered (R7)

- Per server: render settings (and the preset they match), album, visibility,
  stacking. Saved **when a run starts**, never on Cancel. Changing server loads
  that server's values.
- A server never published to starts with a copy of Export's current settings,
  Album None, Timeline, stacking on. Publish never writes back into Export's
  remembered settings.
- Never remembered: the description.

### 3.8 Pressing Publish

**Publish N Photos** is the default button. It is dimmed while: no server; the
check is running or failed; a needed permission is missing; the new album name is
empty; the remembered album is unresolved; a settings issue stands; a publish is
running.

When pressed: the button bar shows a spinner and **Checking…**; the app confirms
permissions again and looks up records. A failure appears in its section and the
sheet stays. If any photo was published to this server before, §8's alert. Then
the sheet closes and the run starts. **Cancel** or Esc at any point before that
sends nothing that writes.

## 4. Adding and editing a server (R1)

The #271 `ServerSheet` is reused with its two pages and its check. **Where it was
opened (its host) decides which permissions it requires** (R1, AC25), for Add,
Edit and Review Certificate alike, including the check that runs again after
**Trust Certificate**:

| Host | The check requires | Reads the account (`user.read`) |
|---|---|---|
| Publish | `asset.upload` and `asset.read` only | No |
| Import | Import's five, as in #271 | Yes, as in #271 |

- So a key made only for publishing is saved from Publish. A key lacking
  `asset.upload` or `asset.read` is not saved from Publish. Album and stacking
  permissions are never required by the sheet; §5 names them in the publish sheet.
- A name-only edit still saves without a check, from either host (II §3.6).
- Such a server is a normal saved server. Choosing it as the Import window's
  source names the missing import permissions and imports nothing (§4.1). A new
  address, key or certificate for it is saved from Publish; from Import the check
  asks for import's permissions and saves nothing without them. It is removed from
  Import, like any server.
- Choosing **Add Server…**, **Edit “‹name›”…**, **Edit Server…** or **Review
  Certificate…** closes the publish sheet, presents the Server sheet on the
  library window, and reopens the publish sheet when it closes, with every choice
  and the typed description kept (HIG Sheets: one sheet at a time; close the
  first, then show it again). A newly added server is selected; Cancel restores
  the previous selection. Nothing else (such as a waiting preset report) may open
  in the gap.
- `ServerSheetModel` depends on `CardImportModel` today. It needs a small host
  interface (catalog, saved list, "saved", dismiss, window height, required
  permissions and the host's wording) so both windows host one sheet. II §3.1
  intended this.
- Hosted from Publish, the sheet has **no Remove Server…** button. Removal stays
  on the Import window, one path to deleting a credential.
- II §3.8 expected a Settings ▸ Servers tab with this feature. **It is not added.**
  The PRD needs adding and editing at the point of use only, and the folder map is
  used only while publishing.
- The File menu's server items stay Import-window items (II §7).
- While a publish runs, **Edit Server…** and **Remove Server…** for that server
  are dimmed in both windows.

### 4.1 Changed wording (R27, AC22)

No text may say the app only reads from a server. These are the engineer's, in
the same change as the behaviour.

| Where | New text |
|---|---|
| Server sheet **from Import**, key caption | **Create the key in Immich, in your account settings. Importing needs asset.read, asset.view, asset.download, album.read and user.read.** Second line: **Publishing needs asset.upload and asset.read. Albums also need album.read and albumAsset.create, and a new album needs album.create. Stacking needs user.read and stack.create.** The Keychain caption below it is unchanged |
| Server sheet **from Publish**, key caption | **Create the key in Immich, in your account settings. Publishing needs asset.upload and asset.read. Albums also need album.read and albumAsset.create, and a new album needs album.create. Stacking needs user.read and stack.create.** Second line: **Importing from this server needs asset.read, asset.view, asset.download, album.read and user.read.** The Keychain caption is unchanged |
| Server sheet **from Import**, missing-permission result | **Add ‹names› to the key in Immich, or create a new key with the importing permissions listed above.** ("the five permissions" is unclear once the caption lists more). When the key holds `asset.upload` and `asset.read`, a further sentence: **To save a key made only for publishing, choose Publish… in the File menu.** |
| Server sheet **from Publish**, missing-permission result | **Add ‹names› to the key in Immich, or create a new key that has asset.upload and asset.read.** Names in that order. Title unchanged: **This API key is missing permissions** |
| Server too old, **from Publish** (sheet and publish sheet) | **It runs version ‹3.1.0›. Publishing needs version ‹3.2.0› or newer.** Title unchanged; Import keeps **Importing needs…** |
| Import window grid, missing permissions (the chosen server's check) | Label **Can't Import from ‹name›** in place of **Can't Connect to ‹name›**, since the server answered and the key may publish. Description: **This API key is missing permissions** and **Add ‹names› to the key in Immich to import from this server, or choose Edit Server… to enter a key that has them.** Nothing there is "listed above". Actions unchanged: **Try Again**, **Edit Server…**. Other failures keep II §4.7 |
| Server sheet, unencrypted notice | **The address starts with http://. Your API key and every photo you import or publish cross your network without encryption, so anyone on it could read them. Use https:// if your server offers it.** Title and check box unchanged |
| Import inspector, first caption | **Photos are copied from the server. Importing changes nothing on it.** |
| Import inspector, second caption | **This key can do more than importing needs. Importing only reads.** (shown under the same condition as today) |
| Remove Server alert | **The API key is deleted from the Keychain, along with this server's folder map and publishing choices. Photos you already imported stay in the library, and the record of what you published is kept. The key itself still works on the server until you delete it in Immich.** |
| Library app `Support/Info.plist`, `NSLocalNetworkUsageDescription` | **Connects to the server you add, on your local network, to import photos from it and publish photos to it.** Plain English in the plist, as #271 ruled; the standalone importer's plist gets no such key |

Permission names are the server's own, verified on 3.2.0 and 3.4.2 (§15, item 7).
`stack.read` appears nowhere. The About window changes only if it says the app
only reads. The user guide's server import section is also the engineer's (R27).

The user guide's publishing text must also say these three things (AC22). The
wording is a proposal; the facts are required.

| From | Proposed wording |
|---|---|
| R14, trashed stack members | **When a published photo joins a stack, any photo of that stack that is in the server's trash drops out of it. If you restore it, it stays unstacked.** |
| R17, a lost answer | **If publishing ends just after a file has been sent, because you stop, quit or lose the server, the server may keep a photo the app has no record of. It isn't marked In Library. Publishing it again reports it as already on the server only if the file is identical; otherwise you get a second copy.** |
| R23, unfinished steps | **Unfinished steps are not kept after you quit. Stack the photo in Immich, or publish it again as a New Copy. That stacks the existing photo if the server finds the file identical; otherwise the first upload stays loose beside the new one.** |

### 4.2 Changing a server's address (R26, AC19)

In Edit Server, when the address typed differs from the saved one **after
normalizing** and the library holds publish records or import links for the saved
address, a line shows under the address field, with
`exclamationmark.triangle`:

**Photos imported from or published to the old address won't be recognized at the
new one.**

- It shows as soon as the typed address first differs, before Save can be
  pressed, and does not wait for the field to lose focus. It goes when the saved
  address is typed back.
- It does not block Save, adds no check box and no alert, and carries nothing
  over (follow-up #300).
- No line for a change of name or key only, for a spelling that normalizes to the
  saved address, or for a server with neither records nor links.
- It applies wherever the sheet is hosted. It is announced once (§13), and the
  sheet's ideal height counts it.

## 5. Missing permissions (R8, AC5)

After the check, the key's list is compared with what the **current options**
need. Each gap is an `exclamationmark.triangle` issue under its option, and
Publish is dimmed until it is fixed or the option is turned off.

| Needs | When | Shown under | Text |
|---|---|---|---|
| `asset.upload`, `asset.read` | always | Server | **This key can't publish. It is missing ‹names›.** |
| `album.read`, `albumAsset.create` | Any album, new or existing | Album | **An album needs ‹names› on this key. Add it, or choose None.** |
| `album.create` | New album (name every album gap in one line with the row above) | Album | the same |
| `user.read`, `stack.create` | Stacking on | Stacking | **Stacking needs ‹names› on this key. Add it, or turn off Stack with original.** |

- Names are the missing ones only, in plain text, comma-separated. **Add it**
  reads **Add them** for two or more (a plural variation).
- Under the Server section, once for any gap: **Add the permissions in Immich, or
  choose Edit Server… to enter another key.** with **Check Again** and **Edit
  Server…**.
- With Album None and stacking off, the sheet shows no album or stack permission
  issue and requires only `asset.upload` and `asset.read` (AC5). A missing
  `album.read` leaves None as the only album choice; the one mention of it then is
  inside the open pop-up (§3.4).
- `asset.read` is needed on every publish, whatever the options: every
  already-there answer is read (R19), and so are linked and mapped originals. It
  is in the Server row and is never listed under Stacking.
- `stack.read` is not asked for (R8).
- The mapping of reads to requests is the engineer's, but every permission a
  request uses must appear in this table. Report additions as a Design question.
- A server import still asks for its own five and nothing more. The Server sheet
  requires what its host needs: from Publish only `asset.upload` and
  `asset.read`, from Import the five (§4). No import permission beyond the table
  above is needed to publish.
- Turning an option off, or adding the permission and choosing **Check Again**,
  clears its issue (R8). Stacking is on for a server never published to, so a
  publish-only key shows the Stacking issue, naming `user.read` and
  `stack.create`, as soon as it is added.

## 6. The folder map (R12)

A page of the publish sheet, from **Edit Folder Map…**.

```
┌ Folder Map for “Home Server” ────────────────────────────────┐
│ Tell the app where Immich sees your folders, so it can find  │
│ originals Immich reads from an external library. Photos      │
│ imported from this server don't need this. When folders      │
│ overlap, the longest one wins.                               │
│                                                              │
│ ┌ On this Mac     /Volumes/Photos            [ Choose… ]   ┐ │
│ │ On the server   [ /mnt/media/photos                    ] │ │
│ │ IMG_0412.RW2 is looked for at                            │ │
│ │ /mnt/media/photos/2024/IMG_0412.RW2                      │ │
│ └                                      [ Remove Folder ]   ┘ │
│ [ Add Folder… ]                                              │
├──────────────────────────────────────────────────────────────┤
│                                       [ Cancel ] [ Done ]    │
└──────────────────────────────────────────────────────────────┘
```

- One `Form` section per pair. A form is chosen over an editable `Table`: there
  are few pairs, each needs a path, a field, an example and an error, and form
  fields have reliable keyboard behaviour.
- **Add Folder…** opens a folder panel (`WindowModal`), then adds a section with
  the server field empty and focused. With no pairs the page shows the
  explanation and the button only.
- **On this Mac**: the folder's current path, head-truncated, full path as
  tooltip; **(not connected)** after the last known path when its volume is
  away. **Choose…** replaces it.
- **On the server**: `TextField`, prompt `/mnt/media/photos`. A trailing slash is
  dropped. The text is otherwise kept exactly (case counts). Matching also finds
  an accented name encoded the other way (R13), with nothing for the person to
  set.
- **Example**, live, from the first selected photo under that folder for which
  this pair wins, using the raw's path for a pair of files: **‹name› is looked for
  at ‹server path›**, selectable, wrapping. Otherwise **No selected photo is in
  this folder.** This catches a wrong map before any request is made.
- Issues, each under its field: **Enter the path on the server, or remove this
  folder.**; **This folder is already in the map.** Done is dimmed while either
  stands. A path not starting with `/` gets a note only: **Server paths usually
  start with /.**
- **Done** (Return) saves the map to the server's settings at once, even if the
  publish is then cancelled: it describes the server, not this run. **Cancel**
  (Esc) discards the page's changes. **Remove Folder** has no confirmation
  because Cancel undoes it.

## 7. Check Originals (R16, AC12)

A button in the Stacking section. It reads only and uploads nothing. Enabled when
the server check passed and neither `asset.read` nor a stacking permission is
missing.

| State | Shown in place under the button |
|---|---|
| Not run | nothing |
| Running | `ProgressView` with **Checking originals… 40 of 120** and **Stop** |
| Result | the block below |
| Failed | `exclamationmark.triangle`, **The check stopped: ‹reason›**; the button runs it again |
| Stale | a change of server, folder map or the stacking box removes the result |

```
✓ Originals found for 38 of 41 photos.
  ▸ 2: Nothing at the mapped path
  ▸ 1: Size differs
  1 photo is offline and wouldn't be published.
  Photos without an original are published unstacked.
```

- The icon is `checkmark.circle` when all are found, else
  `exclamationmark.triangle`; the words carry the meaning.
- One `DisclosureGroup` per reason, closed, listing photo names with the reason
  sentence of §7.1 (including the path looked for), at most 10 then **And ‹n›
  more.** Text is selectable. When only one reason occurs, its group opens.
- Counts cover the photos that could be published: videos are already excluded,
  offline photos are counted on their own line. Skip, chosen later, can lower
  what the run stacks; the check does not ask that question.
- Publishing never requires a check. Publishing while a check runs cancels it.
- The check and the run use one matching function, so AC12 holds by construction.

### 7.1 Reasons for no original (R15, AC9)

Used by the check and the results. Names, not codes; the server path is shown
because it is what the person fixes. No sentence claims more than the server
said, and no request is made only to find a reason.

| Case | Group title | Sentence | Given |
|---|---|---|---|
| No link, no mapped folder | No mapped folder | **not imported from this server, and no mapped folder holds it.** | always |
| Linked asset not returned, no mapped folder holds the photo | Imported original not found | **the server didn't return the photo it was imported from, and no mapped folder holds it.** | always |
| Linked asset not returned, nothing at the mapped path | Imported original not found | **the server didn't return the photo it was imported from, and nothing is at ‹path›. Capital letters count.** | always |
| Nothing at the path (wrong case included) | Nothing at the mapped path | **nothing at ‹path›. Capital letters count.** | always |
| More than one | More than one match | **more than one photo at ‹path›.** | always |
| Size differs | Size differs | **a photo at ‹path› has a different size.** | always |
| Something this library published, nothing usable | Published from here | **a photo at ‹path› was published from your library, and nothing there can be used.** | always |
| In the trash | In the trash | **its original is in the server's trash.** | when revealed |
| Hidden | Hidden | **its original is hidden on the server.** | when revealed |
| Another account | Another account's | **a photo at ‹path› belongs to another account.** | when revealed |
| Not an image | Not a photo | **an item at ‹path› isn't a photo.** | when revealed |

A **locked** asset is never revealed (R15): the server answers as if it were not
there, so no row, group or sentence says "locked".

**Which asset at a mapped path is used** (R13), across all the spellings it
matches:

- Another account's assets are ignored whenever the account has an asset there;
  **Another account's** is given only when it has none. In a household where a
  partner's library covers the same files, the own asset is used and nothing is
  said about the partner's.
- An own asset **qualifies** when it is a photo, not in the trash, hidden or
  locked, not published from this library, and of the master's size when the
  server gives one.
- Exactly one qualifying asset is used, whatever else is at the path. Assets that
  don't qualify never make **More than one match**; two qualifying ones do.
- When the account has assets there and none qualifies, one reason is given, the
  first that applies to any of them:
  1. **Size differs** (an asset with nothing else wrong).
  2. **Published from here.**
  3. **In the trash.**
  4. **Hidden.**
  5. **Not a photo.**
- An asset with several faults counts under the first of 2 to 5 that it has. A
  linked asset with several faults takes its reason in the same order; one that
  belongs to another account reads as that, whatever else is wrong, as at a
  path.

A linked asset must pass R13's rules (R11). If it fails them, the folder map is
tried, and the reason is chosen in this order:

1. The map **finds an original**: the photo is stacked; no reason.
2. The map says something about an asset at the path (more than one, or the one
   reason chosen above): report that.
3. Otherwise, the map has nothing or has no folder for the photo, and the
   server **revealed why the linked asset failed**: report that. A **hidden**
   linked asset reads **Hidden: its original is hidden on the server.** A trashed
   one reads **In the trash** (AC9). Another
   account's or a non-photo reads **its original belongs to another account.** or
   **its original isn't a photo.** under the same group titles, since no path is
   involved. A linked asset that this library's records say it published reads
   **the photo it was imported from was published from your library.**
4. Otherwise, a link exists and the server did not return the asset: **Imported
   original not found**, in the first variant when no mapped folder holds the
   photo and the second, with the path, when one does and nothing is there. The
   asset is never called deleted. This includes a locked asset, which the app
   can't tell from a missing one, so the sentence says neither "deleted" nor
   "locked".
5. No link: **No mapped folder** when no folder covers the photo, else **Nothing
   at the mapped path**.

- A "when revealed" case the server doesn't reveal reads, for a path match, as
  **Nothing at the mapped path**.
- For a pair, report the raw path's reason; when the raw path's is "nothing" and
  the JPEG's path gives another, report the JPEG's. Where a sentence shows a
  "nothing there" path, in step 4 as in
  step 5, it is the raw's mapped path, or the JPEG's when no mapped folder holds
  the raw. "No mapped folder holds it" means neither file is covered.

## 8. Skip or New Copy (R18, AC13)

An alert on the publish sheet after Publish is pressed, once per run.

> **3 photos were already published to “Home Server”**
> Skip leaves them as they are on the server. New Copy publishes them again;
> no photo on the server is replaced, and a file that hasn't changed may be
> reported as already there. The other 9 photos are published either way.
>
> [ Skip ] [ New Copy ] [ Cancel ]

- Singular and plural variations; the last sentence is left out when every photo
  has a record.
- **Skip** is the default (Return). A new copy can't be removed by the app, so the
  reflex answer is the one that adds nothing (HIG Alerts: don't make the riskier
  choice the default). Neither button is destructive-styled. **Cancel** (Esc)
  returns to the sheet with nothing sent.
- The titles are verbs; no "OK" and no Replace.

## 9. While it runs (R21, R22, R24)

- One Activity job: title **Publish to “‹name›”** (toolbar form through
  `ToolbarMetrics.statusLine`), determinate progress over photos, detail
  **Rendering 3 of 12** or **Uploading 3 of 12**. During a retried request:
  **Waiting for “‹name›”…**.
- Each photo's album and stacking steps follow its upload (R21). There is no
  separate stacking pass and no separate detail line for those steps: they run
  under **Uploading**, and a photo counts toward progress when all its steps have
  ended. Several edits of one original are stacked in grid order, one at a time,
  each naming the stack's primary as read just before, so the last shown is
  primary (R14), whatever order uploads finish in.
- An already-there photo is read before any album or stack step, whatever the
  options (R19; §10.1). Adding a photo that is already in the album counts as done
  and is not reported (R22).
- **Stop** in the popover and **File ▸ Stop Publishing** (⌘.). No confirmation.
  What reached the server and its records stay. Only photos in progress can be
  left uploaded and missing their album or stack (AC20); §10 counts them.
- **Ending a run** (R17, AC23), whether by Stop, Stop and Quit or a fault:
  - An upload whose file is not fully sent is cancelled at once, with no wait.
  - For a file fully sent and not yet answered, the app waits for the answer, at
    most the 10 s that import and merge allow at quit. An accepted upload is
    recorded. No further album or stacking step is started for it, so it is
    **Not finished** (§10.1). With no answer in time there is no record, and the
    photo counts as not published (a failure only if it is the upload that met
    the fault).
  - The bound counts from the moment the run starts ending. Nothing, a quit
    included, restarts or extends it.
  - "Fully sent" means handed to macOS, read at the moment the run starts ending
    (§15; the PRD's assumptions).
- **While it waits**, the Activity job stays, with its title, an indeterminate
  spinner in place of the progress bar, and the detail **Stopping. Waiting for
  “‹name›” to answer…**. The popover's **Stop** stays in place, dimmed. **File ▸
  Stop Publishing** keeps that title, dimmed, until the run ends: ⌘. must not move
  on to another job, or a second press would stop an export or import. There is no
  second control that abandons the wait. With nothing to wait for, the run ends at
  once and this state never shows. The stop reason (§10.1) appears when the run
  has ended.
- **Publish stays unavailable until the run has ended**: the menu item, toolbar
  item and context menu item, and **Retry Failed**, which gives **A publish is
  already running.** The server's **Edit Server…** and **Remove Server…** stay
  dimmed too.
- Not on the undo stack. One publish at a time; export, import and merge may run
  beside it.
- A photo removed from the library before its turn is a failure: **it was removed
  from the library before it was published.**
- **Quit** uses the existing rule with a new case, `publishing`: **Quit While
  Publishing?** / **Photos already on the server stay there, but unfinished steps
  can't be retried after quitting. The rest are not published.** / **Keep
  Publishing** (default, Return and Esc) / **Stop and Quit**. The middle clause
  covers a photo in progress left out of its album or stack, and earlier failures
  of the run (R23). After **Stop and Quit** the run ends as above, and before the
  app goes accepted uploads are recorded and rendered files removed. A quit while
  a run is **already ending** asks nothing, since there is nothing left to keep
  publishing; the app waits out what remains of the bound, then quits. With no
  publish running, quitting asks nothing, even if a finished run could still be
  retried (R21).

## 10. Results and Retry Failed (R23, AC11, AC16)

No alert and no sheet appears by itself, even when the run stopped on a fault: the
toolbar's Activity item keeps its warning mark until read. This is the house rule
for background jobs, and it avoids interrupting whatever the person moved on to.

### 10.1 The Activity row

A warning row when anything failed or the run stopped on a fault, else
information. Title **Publish to “‹name›”**. Lines in this order, only when not
zero:

```
Publishing stopped: “Home Server” stopped responding.
Published 10 photos.
4 were already on the server.
1 already there is in the server's trash; nothing else was done with it.
1 already there is hidden on the server; nothing else was done with it.
1 already there couldn't be read on the server; nothing else was done with it.
3 were skipped.
9 were stacked on their originals.
2 are not stacked: no original was found.
1 video was left out.
2 failed.
1 is on the server but not finished.
4 were not published because publishing stopped.
[ Show Results… ]
```

- First line only for a stop: **“‹name›” stopped responding**, **“‹name›”
  rejected the API key**, **The certificate of “‹name›” has changed**, **The API
  key is missing ‹permission›**; for the person's own Stop, **Publishing stopped
  after 5 of 12 photos.** When nothing was published: **No photos were
  published.**
- Counting: **Published** is new assets the server accepted. **Already on the
  server** is every upload answered as an identical file, and is not in
  Published. **Stacked** includes already-there photos that ended on a stack.
- **Already there, nothing else done** (R19, R23). The app reads every
  already-there photo first. Three answers end its part in the run: it is in the
  trash, it is hidden, or the server refuses to show it. Each has its own line
  after **already on the server**, shown when not zero, with plural variations:
  - **‹n› already there is in the server's trash; nothing else was done with
    it.**
  - **‹n› already there is hidden on the server; nothing else was done with it.**
  - **‹n› already there couldn't be read on the server; nothing else was done
    with it.** This is the wording for a refusal, a locked photo's included; the
    word "locked" is never used.

  These photos are part of **already on the server** and of nothing else: not
  **stacked**, **not stacked**, **failed** or **not finished**. They are not
  retried, and alone they don't make a warning row.
- A read that fails for a temporary condition or a fault is **not** one of the
  three. It is an unfinished step: no album or stack step follows, and the photo
  is **failed** or **not finished** as below, while still counted as already on
  the server.
- A stacking step that fails, looking for the original included, is a **failure**,
  never a "no original" reason; so is a stack the server refuses, or a primary
  that can't be read (R14, R15). Retry Failed repeats it. Trashed members that
  drop out of a stack are not reported (R14).
- A photo with an unfinished step is in exactly one of two further counts:
  - **Failed**: a step was tried and failed, including the step that met the fault
    which stopped the run.
  - **Not finished**: its upload was accepted, no step failed, and an album step,
    a stacking step or the read of an already-there photo was never tried or was
    cut off because the run ended (by the person's Stop, or by a fault met on
    another photo). The line reads **‹n› are on the server but not finished.**,
    for new and already-there photos alike.
  Either can overlap **Published** or **already on the server**. A not-finished
  photo is counted in neither **stacked** nor **not stacked**: its original may
  not have been looked for.
- **Not published because publishing stopped** counts photos not uploaded and not
  failed, after a fault stop or the person's Stop alike. An upload cancelled
  because its file wasn't fully sent, and one fully sent with no answer within the
  bound (§9), are among these.
- A stop that leaves unfinished photos but no failure makes an information row, as
  any stop by the person does.
- **Show Results…** needs `ActivityLog.Message` to carry an optional action. It
  closes the popover, then presents the sheet.

### 10.2 The Publish Results sheet

`publishResults` in `LibraryModal`; 520 pt wide, ideal height 520.

```
┌ Publish to “Home Server” ────────────────────────────────────┐
│ 2:14 PM · Stopped: “Home Server” stopped responding.         │
│ Run  [ 2:14 PM, Home Server ▾ ]        (only with 2 or more) │
├──────────────────────────────────────────────────────────────┤
│ Published 10 · Already on the server 2 · Skipped 3 · …       │
│ Failed                                                       │
│   IMG_0412   published, but not stacked: ‹reason›            │
│ Not Finished                                                 │
│   IMG_0413   published, but not stacked before publishing …  │
│ Not Stacked                                                  │
│   IMG_0415   nothing at /mnt/media/…                         │
│ Already There, Nothing Else Done                             │
│   IMG_0420   in the server's trash.                          │
│   IMG_0421   couldn't be read on the server.                 │
├──────────────────────────────────────────────────────────────┤
│ [ Retry Failed ]                                   [ Done ]  │
└──────────────────────────────────────────────────────────────┘
```

- A grouped `Form`; counts as `LabeledContent` rows (the diagram abbreviates),
  including **Not finished** and **Not published** when not zero. Directly under
  **Already on the server**, indented and only when not zero: **In the server's
  trash**, **Hidden on the server**, **Couldn't be read on the server**.
  Every failed, not-finished and unstacked photo, and every already-there photo
  with nothing else done, is listed (no cap here), name and reason, selectable.
  Photos not published because publishing stopped are counted, not listed. Empty
  sections are absent. Section order: Failed, Not Finished, Not Stacked, Already
  There, Nothing Else Done.
- **Already There, Nothing Else Done** reasons: **in the server's trash.**,
  **hidden on the server.**, **couldn't be read on the server.**
- **Done** is the default (Return and Esc).
- Runs are kept until the app quits; **File ▸ Publish Results…** opens the newest,
  and the **Run** pop-up reaches earlier ones, so Retry Failed stays available as
  R23 says, even after the Activity message has scrolled out of its 20.

Failure sentences. Where the server gave a message, append it in quotes,
selectable, cut at 200 characters, with the key and any URL removed.

| Step | Sentence |
|---|---|
| Original offline | **not published: its original is offline.** |
| Original unreadable | **not published: its original couldn't be read.** |
| Render | **not published: it couldn't be rendered. ‹system reason›** |
| Upload refused | **not published: the server didn't accept the upload (‹status›). “‹message›”** |
| Upload interrupted | **not published: the upload didn't finish.** |
| Read an already-there photo (temporary condition or fault) | **already on the server, but the app couldn't check it. ‹reason›** |
| Make album | **published, but the album “‹album›” couldn't be made. ‹reason›** |
| Make album, answer lost and the album couldn't be looked for | **published, but the app couldn't tell whether the album “‹album›” was made. ‹reason›** |
| Add to album | **published, but not added to “‹album›”. ‹reason›** |
| Look for the original, or read its stack | **published, but not stacked: the original couldn't be checked. ‹reason›** |
| Stack refused by the server | **published, but not stacked: the server refused the stack.** |
| Stack, any other failure | **published, but not stacked. ‹reason›** |
| Record | **published, but the app couldn't record it. ‹reason›** |

For an already-on-server photo, "published, but" reads **already on the server,
but**. The refused-stack sentence takes the server's message like any other, and
does not say why beyond it: no "locked".

**Not Finished** sentences name what is left:

| Left | Sentence |
|---|---|
| Album | **published, but not added to “‹album›” before publishing stopped.** |
| Stack | **published, but not stacked before publishing stopped.** |
| Both | **published, but not added to “‹album›” or stacked before publishing stopped.** |
| The read of an already-there photo | **already on the server, but not checked before publishing stopped.** |

An already-there photo not yet checked uses the last row alone, whatever the
options: what else is left isn't known until it has been read.

### 10.3 Retry Failed (R23, AC21)

Shown when the selected run has a failed or not-finished photo, or was stopped by
a fault with photos not yet uploaded. It closes the sheet and runs as an Activity
job with the same Stop and quit rules. In R23's order, it:

- repeats only the steps that did not succeed, and creates no second asset, album
  or stack (AC11), except the second copy R17 describes when an upload's answer
  was lost;
- uses the run's server, settings, album, visibility, description and stacking
  choice, and does not ask Skip or New Copy;
- renders a photo that still needs uploading as saved when the retry starts;
- finishes the remaining steps of any photo whose upload was accepted, however the
  run ended, the person's own Stop included. An edit it stacks becomes primary at
  that point (R14);
- includes photos not yet uploaded and not failed only when a fault stopped the
  run, not after the person's own Stop. The latest ending decides, a retry's
  included, so stopping a retry leaves them out of the next one;
- leaves out a photo not yet uploaded, whether it failed or was not reached, that
  a later run has since published to this server;
- is unavailable, with the reason on a line beside the dimmed button, while a
  publish is running (**A publish is already running.**), when the server was
  removed (**This server was removed.**), or when its address changed (**This
  server's address has changed since this run.**).

Further:

- An already-there photo that wasn't checked is read first; the answer then
  decides between finishing its album and stacking steps and **Already There,
  Nothing Else Done**. Photos in that section are never retried and don't by
  themselves make the button appear (R19).
- After the person's Stop with photos not yet uploaded, and the button shown, a
  caption beside it reads **Photos not yet uploaded when you stopped aren't
  included.** When there is nothing failed or unfinished, there is no button and
  no caption.
- The title stays **Retry Failed** (R23's name) even when all it has to do is
  finish steps.
- A permission, key or certificate problem found when it starts stops it at once
  and is reported like any run; the person fixes it from Publish… ▸ Edit
  Server….
- The retried run updates its entry in the results rather than adding one, and
  posts a new Activity message.
- Nothing unfinished is kept after quitting. The user guide says so and what to do
  then (R23's closing paragraph; AC22; wording in §4.1).

## 11. The Import window (R20, AC15)

An asset published from this library to the chosen server's address gets the
existing **In Library** treatment: badge, 50% image, no check box, skipped by
Select All and Import, out of the subtitle's denominator. Tooltip **Published to
“‹name›” from this library**; VoiceOver's value is the existing **Already in the
library**. A photo both linked and published shows the import tooltip. If a record
is written while the window shows that server, the cell updates in place without
reloading the grid, and a checked photo that becomes marked is unchecked. The
standalone importer is unchanged.

## 12. Not in this design

Settings ▸ Servers, a sidebar entry, "Published to" or "Changed since published"
filters, any mark on library thumbnails, share links, Replace or any request that
updates or deletes something on the server (the stack Immich replaces when a photo
joins it is the server's own doing, R9), finding or reporting trashed stack
members, named destinations, several servers per run, separate keys for importing
and publishing on one server, and anything in the standalone importer or
`photocli`.

## 13. Keyboard, accessibility, appearance

- Publish sheet: **Return** Publish, **Esc** Cancel. In the description field
  Return presses the default button and Option-Return inserts a line, the system
  behaviour; the engineer confirms it, since an accidental publish can't be
  undone from the app. If Return instead inserts a line, that is also acceptable.
  Pages: Return is Done, Esc is Cancel. After any sheet closes the keyboard
  returns to the grid or loupe.
- Initial focus is the system's. Every control is a system control and works with
  Full Keyboard Access.
- Issues are an icon and text, announced (medium priority) when they appear and
  set as the control's accessibility hint (II §8's rule); the Archive warning
  (§3.4) belongs to **Show in** the same way. The check's summary is announced
  once; progress is a status element. A disclosure group's label includes its
  count.
- No new colour, glass or motion. The sheets are in the dark library window and
  use system styles, so Increase Contrast, Reduce Transparency and Reduce Motion
  need nothing extra. Colour is never the only signal.
- Strings go in the String Catalog with plural variations for every count. No
  product name in any of them. No string contains the key.
- VoiceOver and older macOS releases are left to CI (owner's standing ruling).

## 14. Checks the design review will make

Debug-script commands are the engineer's to name; the review needs to drive: open
the sheet; choose server, album, visibility, stacking; type a description; open
and edit both pages; run and print the check; publish; answer the question; stop;
open results; retry; stop and quit while the fake server holds back an answer,
printing the Activity detail and what Stop and Publish allow; edit a server's
address and print the sheet's warning; and
print the sheet's issues, the Archive caption, the album pop-up's items and the
enabled buttons, against the fake server with each permission removed. The fake
server also needs to answer an upload as already there with the existing photo
trashed, hidden, unreadable or failing to read for now, and to refuse a stack.

With a key holding only `asset.upload` and `asset.read` (AC25): add and edit the
server from **Publish** (saved; print the sheet's captions, and the publish
sheet's Album and Stacking issues); add it from **Import** (refused; print the
result); choose the saved server as the Import window's source and print the
grid's label, description and actions. Also from Publish, a key lacking one of the
two (refused), and Review Certificate from each host.

For a person (to be numbered in `review.md`): the sheet and both pages at the
smallest window; keyboard only from ⌥⌘E to Publish; Return in the description
field; menus and context menu by eye; the quit alert during a real run; the real
server (AC17).

## 15. Immich behaviour, verified

Checked by the engineer on live 3.2.0 and 3.4.2 servers, with synthetic data,
through the API (2026-11-25; the full record is in [`status.md`](status.md)). Both
versions behaved the same. The numbers are the ones `status.md` uses.

| # | Question | Outcome | What this design does |
|---|---|---|---|
| 1 | Does the upload's date set the capture date of a file with none embedded? | Yes for the date. Immich shows the time in UTC, so the app sends the wall-clock time labelled UTC (R4) | No UI change |
| 2 | Can the upload set visibility? | Yes | **Show in** stays, with no update request |
| 3 | Does an archived primary leave a timeline original alone? | No: the original leaves the stacked timeline. Its own visibility is unchanged | The Archive warning (§3.4; R6) |
| 4 | Does the import listing include stacked, non-primary originals? | Yes | No change |
| 5 | Does creating a stack keep trashed members? | No: they drop out and stay unstacked. The app doesn't see them | Said in the user guide (§4.1); no results line (R14) |
| 6 | What do search and a read reveal? | Trashed, hidden, not a photo, and a partner's or shared-album asset in some cases. A locked asset never. A path search returns partners' assets too | **Hidden** wording; only own assets count (§7.1; R13, R15) |
| 7 | Permission names | As listed, in both versions. `stack.read` is not needed | §4.1, §5 (R8) |
| 8 | Can a lost create be detected? | A repeated stack create is harmless. A repeated album create makes a second album; finding the first needs `album.read`. Telling it from an older album of the same name is still to be confirmed (below) | `album.read` for a new album too (§3.4, §5; R22) |
| 9 | Can a trashed duplicate be told? | Yes, by reading it. Hidden reads as hidden; locked can't be read. The server accepts later steps on a trashed one | Read first, and **Already There, Nothing Else Done** (§10; R19) |
| 10 | New primary on an existing stack with no update? | Yes, if the create names the current primary. Immich replaces the stack | No UI change; §12 (R9, R14) |
| 11 | Can album and stack steps follow each upload? | Yes, with stack requests one at a time per original | §9 (R14, R21) |

Also verified: the app can tell that a file is fully sent, meaning handed to macOS
(§9; R17); two renders of an unchanged photo were byte-identical in every case
tried, so a New Copy of one is answered as already there (§8 says it may be);
paths differ by Unicode form (§7.1; R13).

Not verified: https, certificate trust or a reverse proxy; Immich's web interface;
the owner's server (AC17); and two open questions the PRD gives the engineer: what
a stack create does when the original's current primary is itself in the trash,
and whether the lost-album-create lookup can tell the run's album from an older one
of the same name, also when the first photo was already on the server and in that
older album (R22, AC24). Nothing in this design depends on those answers unless the
engineer returns one.

## 16. Rulings and open items

### 16.1 Requirements issues, ruled (PRD revision 1, 2026-11-25)

| # | Issue | Ruling | Where |
|---|---|---|---|
| RI-1 | Reasons for no original | A specific reason only when the app knows it or the server reveals it, else "nothing at the mapped path"; no extra requests. A reason for an imported original was added (reworded by N-1). R11 and R13 say which rules apply to a linked asset (R15, AC9) | §7.1 |
| RI-2 | Address edits drop records and links silently | Owner: warn in Edit Server; nothing is carried over (R26, AC19). Carrying over is follow-up #300 | §4.2 |
| RI-3 | What Retry renders and covers | R23 spells it out; AC21 | §10.3 |
| RI-4 | "Selection order" | The order the grid shows, which Export uses; a retried edit becomes primary when stacked (R14, AC10) | §9, §10.3 |
| RI-5 | Unfinished steps after quitting | Accepted, and documented in the user guide (R23). Album and stacking follow each upload, so a stop or quit can't leave a whole run unstacked (R21, AC20) | §9, §10 |
| RI-6 | Read-only wording | R27 and AC22 list the texts and who changes each | §4.1 |

### 16.2 Owner answers (2026-11-25)

| # | Question | Answer |
|---|---|---|
| Q1 | Command name | **Publish…** (R1, AC1) |
| Q2 | Does the plain-http consent cover publishing? | Yes, with a permanent "Not encrypted" line and no second confirmation (R1, AC18) |
| Q3 | Address edits | Warn in Edit Server; follow-up #300 covers carrying records over (R26) |

### 16.3 Issues raised by revision 1, ruled (PRD revision 2, 2026-11-25)

| # | Issue | Ruling | Where |
|---|---|---|---|
| N-1 | What to call a linked asset the server doesn't return | **The server didn't return the photo it was imported from**, with what the folder map found: no mapped folder holds the photo, or nothing is at the mapped path. Never called deleted (R11, R15, AC7, AC9) | §7.1 |
| N-2 | Whether Retry leaves out unreached photos that a later run published | Yes, as well as failed ones (R23, AC21) | §10.3 |
| N-3 | Retry coverage after a stopped retry, and the button's title | The latest ending decides, a retry's included; the title stays **Retry Failed** (R23, AC21) | §10.3 |
| N-4 | An answer cut off by the end of a run | A file not fully sent is cancelled at once; a fully sent one gets the bounded quit wait, and an accepted upload is recorded. The remaining gap is documented, and R23's "no second asset" excepts it (R17, R23, AC22, AC23, a non-goal). The engineer confirmed "fully sent" can be told (§15) | §9, §4.1 |

### 16.4 Immich verification, ruled (PRD revision 3, 2026-11-25)

Requirements issues, from `status.md`:

| # | Issue | Ruling | Where |
|---|---|---|---|
| RI-V1 | Time of day with no date in the file | Owner: the capture's wall-clock time is sent labelled UTC (R4, AC3) | no UI change |
| RI-V2 | Archive takes a stacked original out of the timeline | Owner: allowed together, with the sheet saying so (R6, AC4) | §3.4 |
| RI-V3 | Trashed members leave the stack | Accepted, documented in the user guide, no results line (R14, AC10, AC22) | §4.1, §10.1 |
| RI-V4 | Partners' assets at a mapped path | Only the account's own count (R13, AC8, AC9) | §7.1 |
| RI-V5 | `stack.read` unused | Dropped (R8, AC5) | §4.1, §5 |
| RI-V6 | Hidden or unreadable duplicates | As the trashed one: reported and left alone; every duplicate is read first (R19, R23, AC14) | §10 |
| RI-V7 | A stack create replaces the stack it joins | Owner: accepted. The create names the current primary, one at a time per original (R9, R14) | §9, §12 |
| RI-V8 | Composed and decomposed paths | Both match; case counts (R13, AC8, AC9) | §6, §7.1 |

Design questions, from `status.md`:

| # | Question | Ruling | Where |
|---|---|---|---|
| DQ-V1 | `album.read` with New album | Required for any album, new or existing (R8, R22). With it missing, None is the only album that can be chosen; New Album… is dimmed with the reason in the menu | §3.4, §5 |
| DQ-V2 | The Archive caption | With stacking on, a warning that a stacked original, and the rest of its stack, leaves the timeline; with it off, the plain sentence. Never blocks Publish | §3.4 |
| DQ-V3 | "Hidden or locked" | **Hidden**. A locked asset is never revealed, so nothing says "locked" | §7.1 |

### 16.5 Issues raised against revision 3, ruled (PRD revision 4, 2026-11-25)

| # | Issue | Ruling | Where |
|---|---|---|---|
| V3-1 | A key made only for publishing couldn't be saved | Owner: publish-only keys are allowed. The Server sheet opened from Publish requires only `asset.upload` and `asset.read`; from Import it is unchanged. Stacking needs `user.read` and `stack.create` (R1, R8, AC5, AC25; separate keys are a non-goal) | §3.3, §4, §4.1, §5, §14 |
| V3-2 | Own assets at a path that can't be originals | Only qualifying assets count toward "the only match"; with none, one reason: size differs, published, trash, hidden, not a photo (R13, R15, AC8, AC9) | §7.1 |
| V3-3 | A refused stack or unreadable primary: which count | A failure that Retry Failed repeats, not "no original found", as designed (R14, R15, R23, AC10) | §10.1, §10.2 |
