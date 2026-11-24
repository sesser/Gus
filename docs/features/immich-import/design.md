# Import from Immich: design

Owner: apple-ui-designer. Date: 2026-11-23.
Issue: #271. Status: complete. Four design questions for the owner (§14.2),
all answered 2026-11-23 ("Accept defaults"; rulings DQ-1 to DQ-4 in §14.3), and
six notes for the product manager (§14.1), whose PRD revision is pending; none
blocks the engineer. Implementation rulings DQ-5 and DQ-6 (§15, 2026-11-23);
DQ-7 to DQ-9 (§15, design review 2026-11-23). Review: [review.md](review.md).

**Inputs.**

- Requirements: the PRD, the body of issue #271 (approved 2026-11-23; Q1 to Q11
  as defaults, Q11 left to this design). Cited as "R‹n›", "AC‹n›", "Q‹n›".
- House designs followed: `docs/UI_REDESIGN.md` §8 (the Import window, form
  conventions, sheets versus windows, the states table, the quit alert),
  [`../copy-adjustments-selective/design.md`](../copy-adjustments-selective/design.md)
  ("CA": the sheet's construction, strings and checks sections),
  [`../hdr-merge/design.md`](../hdr-merge/design.md) (sheet height rule, refusals
  shown before anything runs), [`../library-ops/design.md`](../library-ops/design.md)
  (confirmations with no default button), [`../preset-list-view/design.md`](../preset-list-view/design.md)
  (Full Keyboard Access reading).
- Code read: `Sources/PhotoUI/Import/` (`ImportWindow`, `CardImportModel`,
  `ImportCommands`, `ImportGrid`, `ImportCell`, `ImportDebugCommands`),
  `PhotoCore/CardImport/` (`ImportGridState`, `SourceScanner`),
  `PhotoCore/Import/QuitConfirmation`, `PhotoUI/QuitGuard`, `PhotoApp`
  (`ActivityToolbarItem`, `LibraryCommands`, `SettingsView`, `MainView`'s empty
  state), `ExportModel` (Activity report lines), `docs/USER_GUIDE.md`.
- HIG pages read 2026-11-23 (markdown versions): Alerts, Text fields, Privacy,
  Managing accounts. Sheets, Toggles, Menus and Toolbars are applied as already
  recorded in UID, CA and HM, which cite them.

**Custom chrome.** None of substance. Every surface is a system component: a
`Menu` and `Picker` in the toolbar, a SwiftUI sheet made of a grouped `Form`,
`TextField`, `SecureField`, a checkbox `Toggle`, `DatePicker` in a popover,
`ContentUnavailableView`, `.alert`. Two small pieces are drawn by us and
justified here: (1) the grid cell's **Edited** badge reuses the existing
`Badges` text renderer and dark backing of the **In Library** badge, because the
cell is already custom (a layer-based `NSCollectionViewItem` to the library
cell's measurements, UI_REDESIGN decision 18) and the mark must live on the
image; (2) the certificate fingerprint is a monospaced selectable `Text`, because
the person has to compare it with another screen.

## 1. Rulings in one place (the engineer's index)

| # | Ruling | Section |
|---|---|---|
| D1 | **Q11.** A saved server is a third kind of **source** in the Import window's Source pop-up, beside cards and folders. **Add Server…** is in the same menu, next to Choose Folder…. Nothing in the sidebar, nothing in Settings in this feature | §2 |
| D2 | Adding, editing and removing a server is one **sheet on the Import window** with two pages (Server, Certificate), plus one removal alert. No Settings tab yet | §3 |
| D3 | The **check** runs when Add or Save is pressed and when a server is chosen as source; it never runs on its own (not at launch, not when the Import window opens) | §2.3, §3.3 |
| D4 | Security prompts have **no default button** and nothing pre-checked; Return does nothing on them, Esc cancels. Wording states the fact and the consequence and never says "continue", "allow" or "proceed" | §3.5, §3.6 |
| D5 | Key rejected, missing permission, too old, unreachable, not Immich, certificate changed, Keychain failure are **seven named results**, each shown under the field it concerns | §3.4 |
| D6 | Scope is a **toolbar pop-up named Album** (All Photos first, then albums by name with the server's count); the date range is a second toolbar item that opens a popover (R10b) | §4.2, §4.3 |
| D7 | A server source starts with **nothing checked**. Select All takes the photos loaded so far that are not marked (owner rulings DQ-2 and DQ-3, 2026-11-23) | §4.6, §14.3 |
| D8 | Marked photos (**In Library**) stay **visible** in a server grid; Show Videos and Show Photos Already in Library do not apply and are left out of the Selection pull-down | §4.5 |
| D9 | **Edited** badge on the image, top-trailing; full phrase in the tooltip and to VoiceOver | §4.5 |
| D10 | Paging: the next page loads when the visible area comes within one screen of the last loaded photo; appending never scrolls, flashes or refetches thumbnails already shown | §4.4 |
| D11 | The inspector gets a first section, **Server** (name, address, version, how the connection is protected, Edit Server…); **After Import** is absent (nothing is ever deleted on a server); the project name is a plain text field prefilled from Q6 | §5 |
| D12 | Outcomes: a deliberate Stop and a clean finish give **no alert** (subtitle and Activity row); a failure or an error stop gives one alert with a title and a message, and the Activity row carries the per-photo reasons | §6 |
| D13 | The standalone importer shows **none** of this | §9 |
| D14 | **Owner rulings of 2026-11-23** ("Accept defaults"): DQ-1 File ▸ Import from Card or Folder… is not renamed in this branch; DQ-2 Select All on a partly loaded album takes what is loaded; DQ-3 a server source starts with nothing checked; DQ-4 the Album control is a pop-up menu | §14.3 |

## 2. Where Immich appears (Q11)

### 2.1 The ruling and the alternatives

| Option | Verdict |
|---|---|
| Immich as a Library in the sidebar | Ruled out by the owner (nothing is referenced in place) |
| A **Servers** tab in Settings, with the Source pop-up only listing them | Not now. Settings has no tabs (one form, two sections); a tab for one consumer changes the scene's shape. When Publish (#28) needs servers from the library window, a Settings ▸ Servers tab opens the same sheet (§3.8). Mail and Calendar put accounts in Settings because many windows use them; here one window does |
| A separate **Immich** toolbar button | Duplicates the Source pop-up and puts a brand in the toolbar of an app that must work with other sources later |
| **A server is a source in the Source pop-up; add, edit and remove are items of that menu and of the File menu; the work is a sheet on the Import window** | **Chosen.** One mental model ("pick where photos come from"), nothing new in the toolbar until a server is chosen, the same menu item for the first server and the tenth, and the precedent exists (the metadata preset editor is a sheet on this window, UI_REDESIGN §8) |

### 2.2 The Source pop-up

The existing `SourceMenu` gains a third kind of row and two or four items:

```
  ▣ Untitled                 sdcard      cards (mounted), then
  ▢ Trip 2026                folder      chosen folders (as today)
  ▤ Home Server              server.rack saved servers, by name
  ───────────
  Choose Folder…       ⌘O
  Add Server…
  ───────────                            only while a server is the current source
  Edit “Home Server”…
  Remove “Home Server”…
```

- The inline `Picker` lists cards, folders, then servers with the symbol
  `server.rack`. A server is a saved connection, so it stays in the list after
  a relaunch; cards and folders stay session-only as today.
- Choosing a server is choosing a source: the window starts its check (§2.3)
  and shows the browse view (§4). Nothing else happens.
- **Add Server…** is always present in the library app, with or without servers.
  It is the first-run path: no promotional text, no banner. (HIG Managing
  accounts: "Delay sign-in for as long as possible"; the feature is reached by
  choosing it.)
- **Edit “‹name›”…** and **Remove “‹name›”…** name the current server, the way
  the Metadata pop-up names its preset ("Edit “‹name›”…", UI_REDESIGN §8's
  Presets row). They appear only while a server is the current source, so a
  server that is broken (unreachable, key rejected) is edited by choosing it,
  and its failure state also carries an **Edit Server…** button (§4.7).
- The whole menu is disabled while an import runs, as `SourceMenu` is today.
- The menu's title shows the current source: `server.rack` and the name. The
  label with no source stays as it is ("No Card Connected"): the menu opens to
  every choice, and the empty grid says the rest (§2.4).

### 2.3 When the app contacts a server

**Only when the person chooses a server, or presses Add or Save in the sheet.**
Not at launch, not when ⌘I opens the Import window, not when the window opens
with a card in it, not on a timer. A person who opens Import for a card must not
wait on a LAN server that is off, and "the app contacts no host the owner did
not enter" is easier to believe when contact follows an act the person can name.
The source is not remembered across windows: the window opens as it does today
(a mounted card, else empty).

### 2.4 The empty state of the window

`ImportGridState.noSource` keeps its text and its **Choose Folder…** button for
the standalone importer. In the library app it becomes:

| Servers saved | Shown |
|---|---|
| none | `ContentUnavailableView`: label **Insert a Card, Choose a Folder or Add a Server** (symbol `sdcard`), actions **Choose Folder…** and **Add Server…** |
| one or more | the same label with **Insert a Card, Choose a Folder or Open a Server**, actions **Choose Folder…** and a `Menu` button **Open Server** listing the servers (and **Add Server…** at its end) |

This is the discoverability answer to the File menu's current name (§14.3,
DQ-1, which keeps the name in this branch): an empty Import window says servers
exist whatever that item is called.

### 2.5 What the Source pop-up and window do not carry

No icon-only "cloud" affordance, no server status dot in the pop-up (colour is
never the only signal and a dot needs a legend), no list of albums in the
Source pop-up (scope is its own control, §4.2).

## 3. Connections: the Server sheet

### 3.1 Construction

A **sheet on the Import window**, window-modal, 460 pt wide (the metadata preset
editor's width), height by content (grouped `Form`; about 360 pt for Add, +90
when the unencrypted notice shows, never taller than the window minus 40 pt;
the form scrolls between the title row and the button bar when clamped, as
Export's does). Appearance follows the system, like the Import window. One
sheet at a time; the Certificate page is a **page** in this sheet with a Back
button, not a second sheet (UI_REDESIGN §8, the look-up table browser's rule).
The sheet is a reusable view with no Import-window dependency, so Publish (#28)
and a future Settings tab can host it (§3.8).

There is no "Type" pop-up: Immich is the only provider in v1 and a pop-up with
one item is noise. The provider is a stored value (R22); when a second provider
exists the sheet gains a **Type** pop-up as its first row.

### 3.2 Page 1: the form

```
┌ Add Server ─────────────────────────────────────────────┐
│ Name            [ Home Server                         ] │
│ Server address  [ https://photos.example.com          ] │
│                 Will connect to https://photos.example.com
│ API key         [ ••••••••••••                        ] │
│                 Create the key in Immich, in your account settings. It
│                 needs only these permissions: asset.read, asset.view,
│                 asset.download, album.read and user.read.
│                 This Mac keeps its copy of the key in the Keychain.
│ ⚠ result for the check, under the field it concerns     │
├─────────────────────────────────────────────────────────┤
│ [Remove Server…]                         [Cancel] [Add] │
└─────────────────────────────────────────────────────────┘
```

| Row | Control | Rules |
|---|---|---|
| Name | `TextField`, rounded border, prompt = the address's host once one is typed | Optional: left empty it is the host. Names are unique among servers; a clash says **A server named “‹name›” already exists.** under the field. Used in the Source pop-up, the Activity title and tooltips |
| Server address | `TextField`, rounded border, prompt `https://photos.example.com` | Trimmed. No scheme means `https://`. A trailing slash and a trailing `/api` are removed; a path prefix (a reverse proxy at `/immich`) and a port are kept; any scheme but `http` and `https` says **Use an address that starts with https:// or http://.** The normalized address is shown back under the field in 11 pt secondary text, **Will connect to ‹address›**, whenever it differs from what was typed and always before the first check, so the person sees where the key will go |
| API key | `SecureField`, label **API key**; prompt **Paste the key here** (Add) or **Leave empty to keep the current key** (Edit) | Never shown, never read back, never copied to the clipboard by us. Empty on Edit keeps the stored key. Autofill and password managers are the system's |
| Captions | 11 pt secondary, under the row (`Caption`) | The permission names are written as Immich shows them, so they can be matched on screen (§3.4 names the same words). **Text only, no link** (Q2's second half; the owner took the defaults, and opening a web page is a network act of its own) |

- **Add** (Return, the default) is enabled when the address is valid (§3.3
  covers `http://`) and the key is not empty. **Save** in Edit is enabled when
  something changed. A dimmed default button says why through the field that is
  wrong, which is already marked; no extra "fill in the fields" text.
- **Cancel** (Esc). During a check Cancel stops the check and leaves nothing
  saved.
- **Remove Server…** is on the leading side, Edit only, as **Delete Preset…** is
  in the preset editor (§3.7).
- Fields are disabled while a check runs, so the checked values are the saved
  ones.
- Validation of the address happens when the field loses focus, and again on
  Add (HIG Text fields: "validate … when people switch to another field").
  Errors are an `exclamationmark.triangle` and text under the field, never a
  red border alone.

### 3.3 The check (R2) and the unencrypted notice (R5)

Add and Save run the check; so does choosing a server in the Source pop-up (with
its result shown in the grid, §4.7). One check is: reach the server, read its
version, confirm the key is accepted, confirm the five permissions (§15, DQ-7). While it
runs the sheet shows a spinner and **Checking the server…** at the button bar's
leading edge (where Merge puts its spinner), and the fields are disabled.
The check is bounded (the engineer proposes the timeout, R20) and Cancel always
stops it. There is no stage list: one sentence, then a result.

A pass **closes the sheet in one step**: the server is saved (row and Keychain
item together), becomes the current source, and the browse view loads. A name-only edit
saves without a check.

**Plain `http://` (R5)** is handled **before** the check, on page 1, never by an
alert:

- To a host that is not on the local network (`http://example.com`,
  `http://8.8.8.8`): refused at once. Under the address: **“‹host›” is not on
  your local network. http:// is only allowed for servers on your local network;
  use https://.** Add stays dimmed. Nothing is sent.
- To a local host (`192.168.x.x`, `10.x`, `172.16–31.x`, `.local`, a name with
  no dots): a notice appears under the address, in the form, and **Add stays
  dimmed until its check box is ticked**:

```
│ ⚠ This connection is not encrypted                       │
│   The address starts with http://. Your API key and every│
│   photo you import cross your network without encryption,│
│   so anyone on it could read them. Use https:// if your  │
│   server offers it.                                      │
│   ☐ Send my key and photos without encryption            │
```

  The check box is a system checkbox, unchecked each time the sheet opens or
  the address changes; its label names the act in the first person. A checked
  box is the confirmation R5 asks for, stored with the connection so it is not
  asked at every open, and asked again if the address changes. Why a check box
  and not an alert: the text stays on screen while the person decides, nothing
  is "defaulted", and Return cannot confirm it by reflex (HIG Alerts: avoid
  making a button the default when you want people to read).
- A server that is plain `http://` stays visible as such afterwards: the Import
  window's subtitle ends **· Not encrypted** and the inspector's Server section
  says **Not encrypted (http)** (§5), so the choice is never hidden after it is
  made.

### 3.4 The named results (R2, AC2)

Each is an `exclamationmark.triangle`, a **title** (13 pt semibold) and one or
two lines of detail (11 pt secondary), under the field it concerns. Plain
words; the key is never in any of them. All are announced to VoiceOver when
they appear (§8).

| Result | Under | Title | Detail |
|---|---|---|---|
| Unreachable (no route, refused, DNS, timeout) | Address | **Can't reach “‹host›”** | "Check the address, that the server is running, and that this Mac can reach it." + the system's own reason in one clause ("The request timed out.", "Could not connect to the server.") + for a local host: "If macOS asked to allow access to your local network, check System Settings ▸ Privacy & Security ▸ Local Network." |
| Not Immich (answers, but not as Immich) | Address | **This doesn't look like an Immich server** | "“‹host›” answered, but not as Immich does. Check the address, including any path or port." |
| Key rejected (401, or 403 on every read) | API key | **The server rejected this API key** | "The key may be mistyped, expired or deleted. Create a new key in Immich and paste it here." |
| Missing permission | API key | **This API key is missing permissions** | "Add ‹asset.download, album.read› to the key in Immich, or create a new key with the five permissions listed above." The names are the missing ones, in the order the caption lists them, in plain text (design review 2026-11-23: a localized sentence is a plain `String`, and the names are tokens the person matches by their characters, so the monospaced font is dropped; §15, DQ-7) |
| Server too old (R2: both versions) | Address | **This Immich server is too old** | "It runs version ‹3.1.0›. Importing needs version ‹3.2.0› or newer." |
| Certificate changed (R6) | Address | **The server's certificate has changed** | "It is no longer the certificate you trusted for “‹name›”. That is expected if the certificate was renewed, but it can also mean that someone is intercepting the connection. Nothing was sent to the server." Action: **Review Certificate…** (opens page 2 in its changed variant) |
| Keychain failure | API key | **The key couldn't be saved** | "The Keychain returned an error: ‹system text›." Nothing is saved. |

- **Nothing was sent** is a requirement on the engineer, not just text: the
  certificate comparison must happen in the TLS challenge, before any request
  bytes (and so before the key) leave. If the engineer finds that cannot be
  guaranteed, the sentence is dropped, not softened.
- A key that has permissions beyond the four **passes** (R3). If the server tells
  us the key's permissions and they are more than needed, the inspector says so
  (§5); the sheet does not scold on success.
- When the server gives no list of the key's permissions the app tries a read
  per permission and names the one that was refused (PRD Q2's fallback); the
  result text is the same.

### 3.5 Page 2: the certificate (R6)

An untrusted certificate (`https://`, the system doesn't trust it: self-signed or
a private authority) is a result of the check that **replaces page 1** with this
page. Back (`chevron.backward`, ⌘[) returns to page 1 with the form as it was.

```
┌ Trust this certificate? ────────────────────── ‹ Back ──┐
│ macOS can't tell who issued the certificate that        │
│ “photos.lan” presented. That is normal for a server you │
│ set up yourself, but another device on your network can │
│ present a certificate too. Trust it only if the         │
│ fingerprint below matches your server's.                │
│                                                         │
│ Issued to    photos.lan                                 │
│ Issued by    photos.lan                                 │
│ Valid        Nov 3, 2026 to Nov 3, 2027                 │
│ Fingerprint (SHA-256)                                   │
│   4F 2A 9C 01 7E B3 D4 56  A8 11 6D C0 3B 9F 22 E7      │
│   0A 5C D1 84 F6 39 7B 2E  C5 90 4D 18 A3 6F E2 07      │
│                                                         │
│ If you trust it, this Mac will accept only this exact   │
│ certificate for “Home Server”. If it ever changes,      │
│ connecting fails until you review it again.             │
├─────────────────────────────────────────────────────────┤
│                              [Cancel] [Trust Certificate]│
└─────────────────────────────────────────────────────────┘
```

- **No default button.** Neither button answers Return; **Esc** and **Cancel**
  go back to page 1 with the server unsaved. **Trust Certificate** is a plain
  bordered button, never prominent, on the trailing side (HIG Alerts:
  "avoid making any button the default button" when people should read). It is
  not destructive-styled: trusting is not data loss, and a red button would
  mean the opposite of what the page needs to say.
- **Wording rules for both security pages** (this one and §3.3's notice): say
  what the system could not verify; say the plain consequence; say what the app
  will do if the person agrees; never "Continue", "Proceed", "Allow", "Accept",
  "Safe", "Secure" or "Don't worry"; no exclamation marks; no urgency; no
  reassurance the app cannot back. "That is normal for a server you set up
  yourself" is a fact about self-signed certificates, and the next clause says
  the risk in the same breath.
- The fingerprint is the certificate's **SHA-256 (32 bytes, 64 hexadecimal
  digits) shown as two lines of 16 pairs in a monospaced 12 pt font**, upper
  case, pairs separated by a space, a wider gap after every eighth pair;
  selectable (`textSelection`)
  and copied as colon-separated pairs, the form most servers and browsers show.
  It is the page's most important element and stays at the same size at every
  window size.
- After **Trust Certificate**: the page returns to page 1 and the check **runs
  again by itself** (**Checking the server…**), now against the trusted
  certificate; a pass closes the sheet. A different certificate on that second
  connection is the changed-certificate result, not a new prompt.
- **Changed variant** (a pinned server whose certificate differs; reached from
  **Review Certificate…** in the grid state or the Edit sheet): title **Trust the
  new certificate?**; the first paragraph is **“‹host›” presented a different
  certificate from the one you trusted on ‹date›. That is expected if it was
  renewed. It can also mean that someone is intercepting the connection.**; two
  rows **Trusted before** and **Now** each with its fingerprint and the dates;
  the closing paragraph as above. The same two buttons. This is the only place
  a pinned certificate can be replaced, and never during an import (R6): an
  import that meets a changed certificate **stops** (§6.3) and says so.
- No "trust for this session only", no "don't ask again", no switch anywhere
  that turns checking off (R6). Removing the server forgets the fingerprint.

### 3.6 Edit

The Edit sheet is page 1 prefilled: name, address, an empty key field with the
prompt **Leave empty to keep the current key**. **Save** checks only when the
address or key changed. A failed check saves nothing and leaves the stored
server and key as they were. Editing the address of a plain-`http` server shows
the notice again with its box unticked; editing a pinned `https` server's
address drops the pin (a new host is a new certificate) and a self-signed
result prompts again.

### 3.7 Remove (R4)

**Remove Server…** (the sheet's leading button, the Source pop-up, File ▸ Remove
Server…) asks first, in a window-modal alert on the Import window:

> **Remove the server “Home Server”?**
> The API key is deleted from the Keychain. Photos you already imported stay in
> the library. The key itself still works on the server until you delete it in
> Immich.
>
> [ Remove ]  [ Cancel ]

- **Remove** is destructive-styled (it deletes the key, which can't be got back
  from this Mac); **Cancel** is `.cancel`; **no default button**, so Return
  does nothing, as for Remove from Library… (library-ops design, its
  confirmation: "No default button"). HIG
  Alerts: "If there's a destructive action, include a Cancel button … you don't
  want to make a Cancel button the default."
- Why the last sentence: a person who removes a server to be safe should know
  that the key is still live on the server. It is the one fact this dialog can
  add that they might not know (judgment, not Apple policy).
- The alert makes **no promise about what the links do** if the server is added
  again (§14.1, RI-2).
- Removing the current source clears it: the window returns to its empty state
  (§2.4). A running import blocks the item (the menu is disabled while importing).
- No undo: the Keychain item is gone. The alert says so by saying the key is
  deleted.

### 3.8 Not done here

A Settings ▸ Servers tab (§2.1), a "test connection" button apart from Add and
Save (the check is Add and Save), editing a server's permissions, several keys
per server, signing in with a password or OAuth, and a "Connect…" prompt at
launch. When #28 lands it hosts this same sheet from Settings and widens the
permission list the check takes (PRD, note for the owner).

## 4. Browsing a server

### 4.1 The toolbar for a server source

The toolbar is still fixed (not customizable). A server source adds **two items to
the `.navigation` group**, after the Source pop-up and before Rescan; they are not
there for cards and folders.

```
┌ [server.rack Home Server ▾] [photo.on.rectangle All Photos ▾] [calendar] [⟳] │ Import · 6 selected · 250 of 3,412 loaded │ ⟳ Loading more photos… │ [☑▾] [◨] [Import 6 Photos] ┐
```

Everything else is as for a card: the Activity status (§4.4, §6), the Selection
pull-down (§4.6), Show / Hide Options, and the one prominent **Import N Photos**
(Return) that becomes **Stop** (⌘.). At the window minimum (900 pt) the system
overflow chevron takes what does not fit, the two new items first (they are the
least-needed once a scope is chosen); the labels middle-truncate through
`ToolbarMetrics.statusLine`.

### 4.2 Scope: the Album pop-up (R10)

A `Menu` with an inline `Picker`, label **Album** (tooltip and VoiceOver name),
title = the chosen scope: **All Photos** or the album's name.

```
  ✓ All Photos
  ───────────
    Holiday 2024 (123)
    Kids (1,204)
    Trip to Lisbon (88)
```

- **All Photos** first, then albums sorted by name (case-insensitive, localized
  comparison), each **Name (count)** in plain text. The count is **what the
  server says the album holds** (§14.1, RI-5: it may include videos, which the
  grid never lists, so it can exceed what the grid shows). **All Photos** has a
  count only if the server gave one for exactly this query; it is never
  estimated from the pages loaded.
- Choosing a scope reloads the grid from its first page (**Reading ‹name›…**
  with the toolbar status, as a card scan), clears the selection, and scrolls to
  the top. The project name follows (§5.3).
- The list is read with the first page (in parallel) and again by Rescan. While
  it loads the pop-up is disabled with **All Photos** as its title. If the
  album list fails but photos load, the pop-up shows **All Photos** and a
  dimmed item **Albums unavailable**, and Activity gets one warning with the
  reason; Rescan tries both again.
- The album chosen last is **not** remembered across windows in v1 (an album id
  in preferences goes stale; two clicks reach it). A candidate follow-up.
- **Scale.** A pop-up menu does not suit hundreds of albums, though it scrolls
  and the first letters typed jump to a name. Judgment: it is right for a
  homelab's tens of albums. Owner ruling DQ-4 (§14.3, 2026-11-23): the pop-up
  menu stands; he gave no album count. If it proves too many (more than about
  sixty), the chooser becomes a toolbar button that opens a popover with a
  search field and a list, a later change local to this control.
- An album that is gone when chosen (the server answers not found) shows the
  state of §4.7 with **Show All Photos**.

### 4.3 Date range (R10b, Should)

A toolbar button, `calendar`, label **Date Range** (tooltip **Show only photos taken
within a date range**), opens a **popover** under it:

```
┌ Capture date ───────────────────┐
│ From  [ Nov 1, 2026  ]  compact │
│ To    [ Nov 30, 2026 ]  compact │
│ The start date is after the end date.   (only when true)
│                    [Clear] [Apply]│
└─────────────────────────────────┘
```

- Two compact date pickers (date only; either may be left unset with the
  picker's own **Any**-style toggle, so "from March" and "up to May" are
  possible). Whole days inclusive, in the photo's own local time as the grid
  shows it. **Apply** (Return) reloads the grid from page one; **Clear** applies
  at once and closes; **Esc** closes without applying. **Apply** is dimmed when
  the start is after the end, with the sentence above shown (an icon and text).
- While a range is on, the toolbar item shows `calendar` with its text, **Nov 1 –
  Nov 30, 2026** (**On or after Nov 1, 2026** / **On or before Nov 30, 2026** when only one end is set), so the state is
  visible and not a colour; VoiceOver reads it as the item's value, **Any date**
  when off.
- The range is part of the scope: it clears with the source, not with the
  album, and the empty state names it (§4.7).
- This is separable. If the owner drops R10b the rest is unchanged (the item,
  the popover, the View ▸ Date Range… item and two strings go).

### 4.4 Paged loading and thumbnails (R9, AC6)

- Photos are listed **newest capture first**, in pages. The next page is
  requested when the visible area comes **within one screen height of the last
  loaded photo** (judgment: far enough ahead that a trackpad flick does not
  reach the end, near enough that no second page is fetched while the first is
  still out of reach, AC6). The page size is the engineer's (200 or more, so a
  first screen never asks for a second page).
- **Appending a page never moves anything**: the scroll position, the keyboard
  focus and the cells on screen stay, no cell reloads, no thumbnail already
  shown is fetched again (insert items, do not `reloadData` the whole grid; the
  controller's `update` does that today when the list differs). Only a change
  of source, scope, date range or Rescan replaces the list.
- **Progress** is shown in the toolbar's status slot: a spinner and **Loading
  more photos…** while a page is out; **Loading photos…** for the first page of
  a scope after **Connecting to ‹name›…** for the check. No footer row, no
  count of requests. The subtitle (§4.6) says how many are loaded and how many
  there are when the server told us.
- **A page that fails** posts one Activity warning ("Couldn't load more photos
  from “‹name›”: ‹reason›. Scroll to try again.") and the status goes away;
  what is loaded stays usable; the next time the visible area comes near the end
  the page is asked for again (a person-driven retry, never a loop). Rescan
  reloads everything.
- **Thumbnails** are requested as cells come on screen, at the cell's pixel
  size, a handful at a time (the engineer's limit), and **cancelled when the cell
  is reused or scrolled away** (the cell already cancels its load in
  `prepareForReuse`). Until one arrives the cell shows the existing placeholder
  (`Palette.cellSelected` square, never blank); the image replaces it with no
  animation (Reduce Motion needs nothing). A thumbnail that fails leaves the
  placeholder, adds the tooltip sentence **The server didn't return a preview.**,
  and never stops the photo being selected or imported. Thumbnails live in
  memory only (R7); the existing `SourceThumbnails` is keyed by file URL and
  cannot hold them, so a remote one is separate, bounded the same way.

### 4.5 The grid and its marks (R11, R21)

The grid is the shared `NSCollectionView` with `ImportCell`s at the library's
measurements. One tile per **server photo**: pairs are not grouped in the list
(PRD Q8: pairs form only after the files land), so a RAW and its JPEG may be two
tiles. The tile shows the file name without extension, the type badge from the
original file's extension (`FileKindText.badge`), and the capture date line as
a card tile does.

| State of a photo | Shown |
|---|---|
| New | check box top-leading on its dark backing, image at full strength when checked, 50% when not (as today) |
| **Already imported** (it has a link to this connection, R15) | no check box; the existing **In Library** badge in its place; image at 50%; tooltip **Already imported from “‹name›”**; not selectable, skipped by Select All and Import |
| **Edited on server** (`isEdited`, R21) | a text badge **Edited** top-trailing on the same dark backing, white 10 pt bold, drawn by the `Badges` renderer as In Library is; the photo is otherwise a normal new tile; tooltip **Edited on the server. The original is imported.**; VoiceOver adds **edited on server** |
| Both | both badges; they fit (In Library about 63 pt and Edited about 50 pt in a 168 pt image) |
| Thumbnail pending / failed | placeholder / placeholder and the tooltip of §4.4 |

- **In Library, not "Imported".** The badge text is the existing one: the photo
  is in the library, which is what the person cares about, and a content
  duplicate of a photo that came from a card is the same state after download.
  Before download only a link marks a photo; a photo already in the library
  from another source (a card) is not marked and is found as a duplicate when
  imported (R13), and the end report says so (§6.2). The tooltip, not the badge,
  says where it came from.
- **Why "Edited", not "Edited on server", on the image.** The full phrase is
  about 90 pt at 10 pt bold; with In Library beside it the two overrun a 168 pt
  image. The phrase is the tooltip's first words, VoiceOver's, and the user
  guide's.
- **Marked photos stay visible (D8).** A card's duplicates are hidden until
  asked for. A server grid is a browse view of a list the person did not make,
  paged by position; hiding photos client-side makes pages look empty and breaks
  "load the next page near the end". So **Show Videos** (videos are never
  listed, R14) and **Show Photos Already in Library** do not apply to a server
  source: they are left out of the Selection pull-down and **dimmed** in the View
  menu (HIG Menus: dim, don't remove, in the menu bar). A "hide imported" filter
  is a possible follow-up; it needs the paging rule to count visible photos.
- **Context menu**: Select / Deselect (not on a marked photo), Select All,
  Deselect All; unchanged.
- **VoiceOver**: a cell is a check box, label "‹name›, ‹type›, ‹date›" plus
  ", edited on server" when it is; value checked or unchecked; a marked photo is
  an image whose value says **Already in the library** (the existing text).

### 4.6 Selection, subtitle and Select All (R11)

- **A server source starts with nothing checked (D7).** A card is a shoot and
  starts all-checked; a server is a library the person browses, and the window's
  one default key, **Return**, imports. Checking everything loaded by default
  would make Return import 250 photos the person never looked at.
  Selecting is one step (⌘A) and the Import button shows the count
  (**Import 0 Photos**, dimmed, until something is checked). This departs from
  card import; §14.1 RI-1 and the owner's ruling DQ-3 (§14.3) record it and the PRD's repeat
  scenario ("only new ones import") is met by Select All, which skips marked
  photos.
- **Select All takes the photos loaded so far that are not marked** (R11,
  AC7). With pages left it is not "all of the album", and the window says so:
  the subtitle reads **250 selected · 250 of 3,412 loaded** and the Import button
  reads **Import 250 Photos**, so what Return will do is on screen. Owner ruling
  DQ-2 (§14.3, 2026-11-23): Select All does not fetch the rest first. Select All stays available while a page is loading and takes
  what is loaded at that instant.
- Click, ⇧-click (range over loaded photos), Space, **Deselect All** (⇧⌘A) and
  the check boxes work as in a card import. The selection survives paging and
  Rescan by remote id, and is cleared by a change of source, album or date range.
- **Subtitle** (the window's title is **Import**, unchanged):

| Situation | Subtitle |
|---|---|
| Everything loaded | **6 of 380 selected** (the existing text; the denominator leaves out marked photos, as `shots.count − duplicateCount` does today) |
| Pages left, total known | **6 selected · 250 of 3,412 loaded** |
| Pages left, total unknown | **6 selected · 250 loaded** |
| After an import | **Imported 46 photos** (the existing `doneText` slot), until the selection or source changes |
| Plain `http` | the line above, then **· Not encrypted** |

  No camera and no shutter count (a server has none to give).
- **Rescan** (⌘R) reloads the first page of the current scope and the album list,
  keeping the selection of photos that are still listed. It is dimmed while an
  import runs and while no server is chosen.

### 4.7 States of the grid area (R9, the states table)

These extend `ImportGridState`; the standalone importer's cases are unchanged.
All are `ContentUnavailableView` or `ProgressView`, as today.

| State | Shown |
|---|---|
| Connecting | centered `ProgressView` **Connecting to ‹name›…**; the toolbar status says the same |
| Loading the first page | **Reading ‹name›…** (the existing key); toolbar status **Loading photos…** |
| **Can't connect** (any result of §3.4) | `exclamationmark.triangle`, label **Can't Connect to ‹name›**; description = the result's title and detail from §3.4, in a `Text` the person can select; actions **Try Again** (the Rescan action) and **Edit Server…**; a certificate result's action is **Review Certificate…** in place of Edit Server… |
| No photos, All Photos | label **No Photos on ‹name›** (`photo.on.rectangle`); description **Only your own photos are listed. Videos, archived, hidden, locked and trashed photos are not.** |
| No photos in an album | label **No Photos in “‹album›”** (the existing key); the same description; action **Show All Photos** |
| No photos in the date range | label **No Photos in This Date Range**; the same description; actions **Clear Date Range** |
| Album gone | label **“‹album›” Is No Longer on the Server**; action **Show All Photos** |
| The grid | as §4.5 |

- There is no "all imported" state for a server: marked photos are shown (D8).
- After an import that stopped for a connection reason (§6.3) the window
  rescans, as it does today; if the server still can't be reached this is the
  state the person lands in, with the actions that fix it.

## 5. The options inspector for a server

The inspector is the same grouped `Form`, `.inspectorColumnWidth(min: 300, ideal:
320, max: 400)`. For a server source:

| Section | Rows |
|---|---|
| **Server** (new, first) | **Name**: the name. **Address**: the normalized address, middle-truncated, full text as tooltip. **Version**: **Immich ‹3.4.2›** (from the check). **Connection**: **Encrypted (https)**, **Encrypted, certificate trusted by you** (pinned), or **Not encrypted (http)** with `exclamationmark.triangle`. A caption (11 pt): **Photos are copied from the server. Nothing on the server is changed.** Only when the server told us the key's permissions and they are more than the four: a second caption **This key can do more than importing needs. Only reading is used.** A button **Edit Server…** |
| Destination | unchanged: Folder with Choose Folder…, Subfolders, File names, one example under the fields |
| Project | **Add to** (New Project or an existing project), **Project name** (§5.3), **Job code** with its recent-codes menu |
| Metadata | **Preset** pop-up as today, its caption, and for a server a second caption **Description and star rating from Immich are added to a new photo when it has none here.** |
| After Import | **absent** |

### 5.1 Why Server first and why After Import goes

The sections are in the order the decisions are made (UI_REDESIGN §8): where
from, where to, which project, how described. The Server section is where the
person confirms where photos come from and how the connection is protected, and
it carries the one persistent, non-colour sign of an unencrypted connection. It
also gives Edit a home that is on screen all the time.

**After Import** holds **Delete originals from “‹source›”** and **Eject**, both
meaningless here: nothing on a server is ever deleted or changed (non-goal), and
a server cannot be ejected. The section is absent, not dimmed, and
`deletesOriginals` is never offered or set for a server (the engineer must also
ignore it if it was left on from a card, so a deletion can never reach a server
path).

### 5.2 Templates

The Subfolders and File names fields and their Insert menus are as for a card.
Their example comes from the first selected (else first visible) photo's
metadata **as the server listed it** (name, capture date, camera make, model and
lens when the listing carries them). A token the server has no value for
(**Serial Number**) renders empty, exactly as it does today for a file without
that metadata, and the example under the field shows it. The Insert menu is not
changed (no dimmed items for a source kind). The files get the **original's**
extension, never a converted one.

### 5.3 Project name (Q6)

A server source's **Project name** is a **plain text field** (not a template
field), prefilled **‹connection name› - ‹scope›**: **Home Server - All Photos**
or **Home Server - Holiday 2024**. It is prefilled again when the album changes,
unless the person edited it for this window; it is not remembered across
windows. One project per import run. When **Add to** names an existing project
the field is absent, as the template is today. Why plain: the template tokens
(`{capture:yyyy}`, `{job}`) have no connection or album token, and a card's
default (`{capture:yyyy-MM-dd} {job}`) is meaningless for 3,000 photos from
every year. Adding source and album tokens to the template grammar is a larger
change than the feature needs (§14.1, RI-3).

## 6. Importing, stopping and what the person is told

### 6.1 While it runs (R12, R18, R19)

- Start: **Import N Photos** (Return), as today. The button becomes **Stop**
  (⌘.). The window's selection and source can't change (the existing
  `isCopying` rule: Select All, Deselect All and the Source pop-up are dimmed).
- The toolbar status is the card's: a 160 pt bar and **File 12 of 50 · 80 of
  410 MB** (bytes of the originals as the server listed them), the file being
  downloaded as its tooltip.
- After a request has failed and is being retried the detail line becomes
  **Waiting for “‹name›”…** until a request succeeds or the retries (R20, the
  engineer's numbers) are spent. A stall is then visible instead of a frozen bar.
- The **Activity** job is the existing one (the library's Activity item shows it
  when the Import window closes, and the copy goes on): title **Import from
  “‹name›”**, the same detail line, progress and **Stop**.
- Each file is downloaded to a temporary name and moved into place only when its
  byte count and SHA-1 match (R12, R13); nothing about that is on screen except
  a verified photo appearing as done.
- **Stop** (button, ⌘., File ▸ Stop Import, Activity's Stop): downloads end, partial
  files are removed, finished photos stay with their links (R18).
- **Quitting** asks through the existing rule with the existing words (R18):
  **Quit While Importing?** / **The rest is not copied.** / **Keep Importing**
  (default, Return and Esc) / **Stop and Quit**. A server import is a copying
  import to `QuitConfirmation`; no new case.

### 6.2 How it ends (R19, AC14)

| Ending | Import window | Activity row (library window) |
|---|---|---|
| Everything imported | subtitle **Imported 46 photos**; no alert | the summary, below |
| Some failed or were left out | one alert (§6.3's pattern): title **Imported 46 photos. 2 could not be imported.**, message **The reasons are listed in Activity in the library window.**; button **OK** | the summary and one line per failure |
| **Stopped by the person** | subtitle **Stopped after 12 photos**; **no alert** (the person just pressed Stop; export's rule, UI reconciliation) | **Import stopped after 12 photos.** and the same counts |
| Stopped by a failure (§6.3) | one alert | the summary, the cause, and the counts |

The **Activity message** is one block of lines, in this order, a line only when
its count is not zero (the shape `ExportModel.detail` already uses):

```
Imported 46 photos.
3 were already in the library.
2 Live Photo videos were not downloaded.
5 imported photos were checked by size only, not against the server's checksum, because they are in an Immich external library.
2 could not be imported.
IMG_0412.HEIC: the download did not match the server's checksum and was discarded.
IMG_0413.HEIC: it was deleted on the server during the import.
```

The size-only line (R13, R19; §15, DQ-8) counts photos **imported** after a size
check without the checksum, never a photo found to be a duplicate, and sits after
the Live Photo line so every count of what was done comes before the failures. It
names its own noun ("imported photos"), since it follows lines whose subject
differs.

- When nothing was imported the first line is **No photos were imported.**
- "Already in the library" counts a photo found to be a content duplicate
  (R13) **and** a photo whose link already existed (R15; only possible if it
  appeared between listing and import). "Already imported" is not used in the
  report: the person's question is whether it is in the library.
- Per-failure lines use the photo's name and one of these plain reasons (the
  engineer maps the failure kinds; nothing else may appear, and none contains
  the server's raw text or any URL):

| Kind | Reason |
|---|---|
| Checksum differs | **the download did not match the server's checksum and was discarded.** |
| Short read or size differs | **the download was incomplete and was discarded.** |
| External-library photo with no size to check against (R13; §15, DQ-9) | **the server did not say how large the file is, so the download could not be checked and was discarded.** |
| Asset gone (not found) | **it was deleted on the server during the import.** |
| Server error for this file | **the server could not provide the original (‹status›).** with the numeric status |
| Disk | the existing write-failure sentence with the system's reason |

- At most **10** failure lines are listed (`ExportActivityReport.failureListLimit`'s
  rule), then **And ‹n› more.** (the existing key). No line, here or anywhere,
  contains the key; the server's address appears only as the connection's name.
- The Activity row is a warning row (`exclamationmark.triangle`) when anything
  failed or the import stopped for a failure, else information.

### 6.3 Failures that stop the job (R20)

A bounded number of retries per request first (**Waiting for “‹name›”…**). Then
the job stops, keeps what finished, removes any partial file, and ends with one
alert on the Import window (nothing, if its window is closed: the Activity warning
is posted either way). The alert has a **title** and a **message**, one **OK**
button, and says which fault it is:

| Cause | Title | Message |
|---|---|---|
| Unreachable or timing out | **“‹name›” stopped responding** | "‹12› photos were imported before the import stopped. Photos already imported are marked, so importing again takes only the rest." |
| Key rejected (401 or 403, no named permission) | **“‹name›” rejected the API key** | "‹12› photos were imported before the import stopped. The key may have been deleted or expired. Choose Edit Server… to enter a new one." |
| A named permission (the 403 names it) | **The API key for “‹name›” is missing a permission** | "‹12› photos were imported before the import stopped. Add ‹asset.download› to the key in Immich, or choose Edit Server… to enter another key." |
| Certificate changed | **The certificate of “‹name›” has changed** | "‹12› photos were imported before the import stopped. Nothing more was downloaded. Choose Edit Server…, then Review Certificate…, to see the new one." |

- **There is no re-trust button in this alert** (R6: a failure, not a prompt in
  the middle of an import). The window rescans after any stop, as it does today,
  and lands in the connection-failure state of §4.7 whose buttons (**Try Again**,
  **Edit Server…**, **Review Certificate…**) are the way on.
- **An asset deleted on the server mid-import is not one of these**: it is a
  counted failure with its reason line, and the import continues (R20).
- "Choose Edit Server…" in the messages names the Source pop-up's and File
  menu's item by its exact title (HIG Alerts: refer to a control by its exact
  title without quotes; "choose" works whatever the input).

## 7. Menu bar and keyboard (every command is in a menu)

`ImportCommands` is shared with the standalone importer and enabled while an
Import window is key. The server items go in with `includesLibraryItems` (the
flag that already gates Show Photos Already in Library), so the importer's menus
are unchanged (§9).

| Menu | Item | Key | Enabled when |
|---|---|---|---|
| File | Choose Folder… | ⌘O | not importing (unchanged) |
| File | **Add Server…** | none | not importing |
| File | **Edit Server…** | none | the current source is a server and not importing |
| File | **Remove Server…** | none | the current source is a server and not importing |
| File | Rescan | ⌘R | a source is chosen and not importing (unchanged) |
| File | Import Selected Photos | Return | at least one photo is checked and not importing (unchanged) |
| File | Stop Import | ⌘. | an import runs (unchanged; the library app's single Stop item) |
| Edit | Select All / Deselect All | ⌘A / ⇧⌘A | as §4.6 |
| View | Show Videos, Show Photos Already in Library | none | **dimmed for a server** (§4.5) |
| View | **Album ▸** All Photos, then the albums, radio-style check on the current | none | the current source is a server and its albums are loaded |
| View | **Date Range…** | none | the current source is a server |

- **Add Server… has no shortcut.** A person adds a server rarely and the
  shortcut space around ⌘O and ⌘I is taken; HIG Keyboards: shortcuts for
  frequent actions. Edit and Remove have none for the same reason, and a key
  that removes a credential should not exist.
- **Choosing among sources** (card, folder, server) is the toolbar pop-up only,
  as for cards and folders today; there is no File menu list of sources. This is
  the one exception to "every command in a menu" and it is the existing one
  (judgment: a selection among live, changing items, not a command).
- **File ▸ Import from Card or Folder…** in the library window keeps its name in
  this branch (§14.3, DQ-1).
- **In the library window's own menus nothing changes in behavior.** Server
  items are enabled only while the Import window is key. Design review
  2026-11-23: they are *present but dimmed* the rest of the time (File ▸ Add /
  Edit / Remove Server…, View ▸ Album ▸, Date Range…), the way Choose Folder…,
  Rescan and Show Videos already are in the library app, and HIG Menus asks for
  dimming rather than removing in the menu bar. Not a violation. Whether a
  dimmed **Album** submenu in the library window's View menu reads as the
  library's own albums is a manual check (M9).

**Keyboard in the Server sheet.** **Return** is the default button (Add or
Save) from anywhere in the sheet; it is dimmed when its conditions are not met
and Return then does nothing. **Esc** cancels (on page 2, Back). **Tab** order:
Name, Server address, the unencrypted check box when it shows (it sits under
the address, so the order follows the layout; design review 2026-11-23 corrects
the earlier order that put it after API key), API key, Remove Server…, Cancel,
Add. The unencrypted check box is toggled by **Space**. A field
taking focus scrolls into view when the sheet is clamped. The initial focus is
the system's (the Name field); do not set it in code (CA §8). On page 2 nothing
is the default and **Tab** reaches Back, Cancel and Trust Certificate in that
order. After the sheet closes the keyboard returns to the grid so Space, arrows
and ⌘A work at once (post `.browserShouldTakeFocus` if it does not).

**Keyboard in the grid.** Unchanged: arrows move the focus, Space toggles, Home
and End jump, Page Up and Page Down page. **End** goes to the last loaded photo
and, being near the end, loads the next page; pressing it again goes on. The
keyboard never needs the mouse to reach a later page.

## 8. Accessibility and appearance (R8's P6; nothing here asks for a VoiceOver, macOS 15 or macOS 26 check by the owner)

**VoiceOver** (covered by CI, not by hand):

- Source pop-up: its title is the source, role pop-up button, name **Source**;
  server items read "‹name›, server" (a symbol-only difference is also in the
  accessibility label).
- The Album pop-up is named **Album** and its value is the scope; **Date Range**
  is a button whose value is **Any date** or the range.
- A result in the sheet is announced when it appears (a medium-priority
  announcement of its title, then its detail, `AccessibilityText.announce`),
  because the result is added below the field and focus does not move. The result
  is also the field's accessibility hint, so it is read when the person goes
  back to it. The spinner **Checking the server…** is a status element.
- The fingerprint is one element, **SHA-256 fingerprint**, value the pairs
  grouped in fours so VoiceOver reads them as short chunks; selectable.
- The unencrypted notice is read as its title, text and the check box in order;
  the check box's label is its sentence.
- Cells as in §4.5; the Edited badge is not a separate element. The first page
  landing is announced once, **‹n› photos loaded**; later pages are not
  announced (the subtitle changes; announcing each would be noise). An import's
  end is announced as every Activity report is.
- Alerts are the system's; the Remove alert's buttons are named by their titles.

**Full Keyboard Access**: every control is a system control, so with the setting
on each is a Tab stop and Space acts (the house reading, CA §8); with it off the
system Tabs to text fields only, for every app, and Return and Esc still work.
The date pickers and the Album pop-up are keyboard operable as system controls.

**Appearance.** The Import window and its sheet follow the system (Light and Dark;
the library window alone is dark-only). All text uses system styles and
`.secondary`; the grid uses `Palette`. The **Edited** badge is white text on the
existing 55% black backing, the In Library badge's measure: worst case on a white
photo it is white on 45% black over white, about 4.8:1, above the 4.5:1 floor.
**Increase Contrast** needs nothing beyond the system's and `Palette`'s variants;
**Reduce Transparency** needs nothing (no glass of our own; the toolbar and sheet
material is the system's); **Reduce Motion**: no motion is added (thumbnails
appear without a transition, pages append without animation). Colour is never
the only signal: every error has an icon and text, the unencrypted state is
words, an active date range is words.

## 9. The standalone importer (R24, AC16)

It shows **nothing** of this feature. Its Source pop-up lists cards and folders
and **Choose Folder…** and nothing else; no server rows, no **Add Server…**; its
empty state is today's **Insert a Card or Choose a Folder** with **Choose
Folder…**; its inspector has no Server section and keeps **After Import**; its
File and View menus have none of the §7 items (`includesLibraryItems` false); its
toolbar has no Album or Date Range items; its Selection pull-down is unchanged.
All of it is gated by the model having no library (`copiesOnly`), one flag the
existing code already has, so the shared window is not forked. The importer links
no connection code that touches the catalog and no Keychain code (AC16).

## 10. Strings (the String Catalog; `LocalizationTests` fails without them)

Add by hand to `Sources/PhotoUI/Resources/Localizable.xcstrings`, each with a
`comment`. **No string contains the product name; "Immich" is a third-party name
and appears only where the person needs it.** Plural forms as the neighbors
(plurals follow the first number only). A real ellipsis (…) and curly quotes.

**New**

| Key | Use |
|---|---|
| `Add Server…` | Source pop-up, File menu, the empty state |
| `Edit Server…`, `Remove Server…` | File menu |
| `Remove “%@”…` | Source pop-up (`Edit “%@”…` exists and is reused, the argument being the server's name) |
| `Add Server`, `Edit Server` | sheet titles |
| `Server address`, `API key` | row labels |
| `https://photos.example.com` | address prompt |
| `Paste the key here`, `Leave empty to keep the current key` | key prompts |
| `Will connect to %@` | normalized address under the field |
| `Use an address that starts with https:// or http://.` | scheme error |
| `A server named “%@” already exists.` | name clash |
| `Create the key in Immich, in your account settings. It needs only these permissions: asset.read, asset.view, asset.download, album.read and user.read.` | key caption (the permission names are not translated; five, §15 DQ-7) |
| `This Mac keeps its copy of the key in the Keychain.` | key caption |
| `Checking the server…` | sheet status |
| `“%@” is not on your local network. http:// is only allowed for servers on your local network; use https://.` | refusal |
| `This connection is not encrypted` | notice title |
| `The address starts with http://. Your API key and every photo you import cross your network without encryption, so anyone on it could read them. Use https:// if your server offers it.` | notice body |
| `Send my key and photos without encryption` | notice check box |
| `Can't reach “%@”` / `Check the address, that the server is running, and that this Mac can reach it.` | unreachable (title, detail) |
| `If macOS asked to allow access to your local network, check System Settings ▸ Privacy & Security ▸ Local Network.` | unreachable, local hosts |
| `This doesn't look like an Immich server` / `“%@” answered, but not as Immich does. Check the address, including any path or port.` | not Immich |
| `The server rejected this API key` / `The key may be mistyped, expired or deleted. Create a new key in Immich and paste it here.` | key rejected |
| `This API key is missing permissions` / `Add %@ to the key in Immich, or create a new key with the five permissions listed above.` | missing permission (the argument is the list; §15, DQ-7) |
| `This Immich server is too old` / `It runs version %@. Importing needs version %@ or newer.` | too old |
| `The server's certificate has changed` / `It is no longer the certificate you trusted for “%@”. That is expected if the certificate was renewed, but it can also mean that someone is intercepting the connection. Nothing was sent to the server.` | changed (§3.4) |
| `Review Certificate…` | action |
| `The key couldn't be saved` / `The Keychain returned an error: %@.` | Keychain |
| `Trust this certificate?` / `Trust the new certificate?` | page 2 titles |
| `macOS can't tell who issued the certificate that “%@” presented. That is normal for a server you set up yourself, but another device on your network can present a certificate too. Trust it only if the fingerprint below matches your server's.` | page 2 body |
| `“%@” presented a different certificate from the one you trusted on %@. That is expected if it was renewed. It can also mean that someone is intercepting the connection.` | changed body |
| `Issued to`, `Issued by`, `Valid`, `SHA-256 fingerprint`, `Trusted before`, `Now` | page 2 rows |
| `%@ to %@` | validity |
| `If you trust it, this Mac will accept only this exact certificate for “%@”. If it ever changes, connecting fails until you review it again.` | page 2 footer |
| `Trust Certificate` | button |
| `Remove the server “%@”?` | alert title |
| `The API key is deleted from the Keychain. Photos you already imported stay in the library. The key itself still works on the server until you delete it in Immich.` | alert message |
| `The server “%@” wasn't removed` / `The Keychain wouldn't delete the API key: %@. Nothing was removed. Choose Remove Server… to try again. If it keeps failing, delete the key in Immich so it stops working.` | alert when the Keychain refuses to delete the key (§15, DQ-5); the second argument is the system's text without its final period |
| `Insert a Card, Choose a Folder or Add a Server`, `Insert a Card, Choose a Folder or Open a Server`, `Open Server` | empty state |
| `Album`, `%@ (%lld)`, `Albums unavailable` | scope pop-up (`All Photos` exists in the sidebar's strings and is reused) |
| `Date Range`, `Show only photos taken within a date range`, `Date Range…`, `Capture date`, `To`, `The start date is after the end date.`, `Any date`, `On or after %@`, `On or before %@` (`From`, `Clear`, `Apply` exist, and `From %@` is taken by the Copy Adjustments header, so it is not reused; `%@ to %@` is the range's text, as for validity above) | date range |
| `Connecting to %@…`, `Loading photos…`, `Loading more photos…`, `Waiting for “%@”…` | status |
| `Can't Connect to %@`, `Try Again` | grid state |
| `No Photos on %@` (exists), `No Photos in This Date Range`, `Clear Date Range`, `Show All Photos`, `“%@” Is No Longer on the Server` | grid states |
| `Only your own photos are listed. Videos, archived, hidden, locked and trashed photos are not.` | grid states |
| `%lld selected · %lld of %lld loaded`, `%lld selected · %lld loaded`, ` · Not encrypted`, `Stopped after %lld photos` | subtitle (plural on the first number) |
| `Edited`, `Edited on the server. The original is imported.`, `Already imported from “%@”`, `The server didn't return a preview.`, `edited on server` | cell |
| `Server`, `Version`, `Connection`, `Immich %@`, `Encrypted (https)`, `Encrypted, certificate trusted by you`, `Not encrypted (http)` | inspector rows (`Server` is a section header; `Name` and `Address` exist) |
| `Photos are copied from the server. Nothing on the server is changed.` | inspector |
| `This key can do more than importing needs. Only reading is used.` | inspector |
| `Description and star rating from Immich are added to a new photo when it has none here.` | inspector Metadata caption |
| `Imported %lld photos.`, `No photos were imported.`, `%lld were already in the library.`, `%lld Live Photo videos were not downloaded.`, `%lld could not be imported.`, `Import stopped after %lld photos.` | Activity (plurals; the 1 forms "1 was already in the library.", "1 Live Photo video was not downloaded.", "1 could not be imported.") |
| `%@: the download did not match the server's checksum and was discarded.` | Activity failure |
| `%@: the download was incomplete and was discarded.` | Activity failure |
| `%@: the server did not say how large the file is, so the download could not be checked and was discarded.` | Activity failure, external-library photo with no size (§15, DQ-9) |
| `%lld imported photos were checked by size only, not against the server's checksum, because they are in an Immich external library.` (plural; the 1 form "1 imported photo was checked by size only, not against the server's checksum, because it is in an Immich external library.") | Activity, after the Live Photo line (§15, DQ-8) |
| `%@: it was deleted on the server during the import.` | Activity failure |
| `%@: the server could not provide the original (%@).` | Activity failure |
| `Couldn't load more photos from “%@”: %@. Scroll to try again.` | Activity warning |
| `Couldn't load the albums of “%@”: %@. Choose Rescan to try again.` | Activity warning when the album list fails but photos load (§15, DQ-6); the second argument is the same plain reason as the line above |
| `Imported %lld photos. %lld could not be imported.` / `The reasons are listed in Activity in the library window.` | alert (title, message) |
| `“%@” stopped responding` / `%lld photos were imported before the import stopped. Photos already imported are marked, so importing again takes only the rest.` | alert |
| `“%@” rejected the API key` / `…The key may have been deleted or expired. Choose Edit Server… to enter a new one.` | alert |
| `The API key for “%@” is missing a permission` / `…Add %@ to the key in Immich, or choose Edit Server… to enter another key.` | alert |
| `The certificate of “%@” has changed` / `…Nothing more was downloaded. Choose Edit Server…, then Review Certificate…, to see the new one.` | alert |

**Reused unchanged:** `Import`, `Choose Folder…`, `Rescan`, `Select All`,
`Deselect All`, `Stop`, `Stop Import`, `Cancel`, `Remove`, `OK`, `In Library`,
`Reading %@…`, `Import from “%@”`, `File %lld of %lld · %@ of %@`, `Quit While
Importing?` and its message and buttons, `And %lld more.`, `Add to`, `New
Project`, `Project name`, `Job code`, `Preset`, `Done`.

**Info.plist (not the catalog; `Scripts/build-app.sh` from `Branding.xcconfig`,
the PRD's list gains one key):** `NSLocalNetworkUsageDescription` = **Connects to
the server you add, on your local network, to import photos from it.** (a
complete active sentence, sentence case, final period; HIG Privacy "purpose
string"). No pre-alert screen of ours: macOS asks on the first connection to a
local address, and the app adds nothing in front of it (HIG Privacy:
pre-alert screens should have only one button; here there is no screen).

## 11. Debug script (R25; CLAUDE.md: UI checks use `--debug-script`)

The script cannot click a sheet, so logic is driven by commands and the surfaces are
observed. Names follow `import …`; the engineer may adjust spelling but not the
coverage. **No command, `print` or snapshot may ever show a key**, and a
scripted copy uses the in-memory key store, never the Keychain (PRD, library
launch guard).

- `import server fake start <fixture>` starts the in-process fake server
  (assets, albums, versions, permissions, certificates) and prints its
  address; `… stop`, `… fault <kind>` (drop, revoke, delete-asset, corrupt-file,
  slow) for AC8 and AC14.
- `import server add <name> <address> [<key>]`, `edit`, `remove` (with
  `confirm yes|no`), `list`, `select <name>`, `check` (prints the result's kind
  and title, never text containing a key), `trust` (accepts the certificate
  the page shows), `sheet add|edit|close` opens the real sheet and
  `print serversheet` prints its rows, fields' names (never the key), the
  notice and its check box, the result, the default button's state, and its size
  against its ideal (as `merge sheet` does).
- `import album <name>|all`, `import dates <from> <to>|clear`, `import scroll
  <n>|end` (drives paging), `import import` is `import run` as today.
- `print importserver` prints the source, scope, range, loaded and total counts,
  the status text, the subtitle, the state of §4.7, and the inspector's Server
  rows. `import grid` (existing) prints each cell with `marked` and `edited` added.
- `import accessibility …` (existing) covers cells; SwiftUI sheets are not in
  the tree without an assistive app, so the sheet's text is read from `print
  serversheet`.

## 12. User guide, README and About terms (R8, AC17)

The engineer updates `docs/USER_GUIDE.md` in the same change (it owns the file).
Terms to match the UI exactly: **Add Server…**, **Edit Server…**, **Remove
Server…**, **Album**, **Date Range**, **Server** (inspector section), **Edited**,
**In Library**, **Trust Certificate**, **Review Certificate…**, "Not encrypted",
"Checking the server…". Lines that change: the "Importing and culling" opening
paragraph (a third source and its sentence on choosing nothing by default),
line 1044 ("the app itself contacts nothing" becomes "the About window contacts
nothing", per the PRD), and the permission list ("asset.read, asset.view,
asset.download, album.read and user.read") appears once, copied from §3.2's caption. New
section **Importing from an Immich server** covering: adding a server and its key,
the two prompts and what they mean, the Album and Date Range controls, what the
grid never lists (videos, archived, hidden, locked, trashed), that nothing is
checked until you check it, what the marks mean, what is imported (the original,
never the server's edit; Live Photo stills only; description and rating when
empty), what happens on Stop or a failure, and that the app contacts only the
server you add. The README and roadmap lines are the product manager's.

**About window.** Its code stays network-free and AC17 pins that. Immich is an
API the app talks to, not code it includes, studies or reimplements; whether it
belongs in `Acknowledgements.all` ("what the project is to the app") is the
product manager's and owner's call, not designed here.

## 13. Tests and checks to expect

- **PhotoCore tests** (the engineer's): the address normalizer and the
  transport policy (AC3: the six addresses; `.local`, single-label, private
  ranges, IPv6 ULA and link-local, redirects), the source-menu model (kinds,
  order, items for a server, none for the importer), `ImportGridState` for the
  server states (§4.7), the subtitle texts of §4.6, the selection rules (nothing
  checked on a server; Select All skips marked; denominators), the paging rule
  (when the next page is due, never earlier, AC6), the Activity summary builder
  (§6.2: order, zero lines dropped, plurals, the ten-line cap, "And n more.",
  no key text anywhere, AC1), the result titles of §3.4 (AC2), the fingerprint
  formatter, the project-name prefill.
- **`LocalizationTests`** fails until every string of §10 is in the catalog;
  `BrandingTests` must not find the product name in them.
- **Debug-script checks** (the engineer's, QA runs): AC6 to AC8, AC13, AC14 with the
  fake server; the sheet's `print`; the empty state with and without servers.
- **Manual checks for a person** (none for VoiceOver, macOS 15 or macOS 26,
  which CI covers; these fold into the PRD's P1 to P6):
  - **M1** The Server sheet, its unencrypted notice and the certificate page in
    Light, Dark and Increase Contrast: row pitch, the fingerprint's legibility,
    no clipped text, Trust Certificate not prominent (PRD P6).
  - **M2** Real flows with the keyboard, Full Keyboard Access on: Source pop-up to
    Add Server…, Tab through the sheet, Return with the notice unticked does
    nothing, Space on its check box, Esc on the certificate page; ⌘A, Return;
    End through two pages (PRD P1).
  - **M3** A real self-signed server, then renewing its certificate: the page's
    wording read aloud by the owner against "does this nudge me to trust it?"
    (PRD P1).
  - **M4** An album of a few hundred photos: thumbnails arriving, no hitch, the
    scroll position kept when pages append, Album and Date Range menus with the
    real album list (PRD P2); this shows whether DQ-4's pop-up menu is enough
    (a later change if not).
  - **M5** The toolbar at the 900 pt window minimum: overflow, truncation,
    Import and Stop still reachable.
  - **M6** Pulling the network cable and revoking the key mid-import: the
    wording of the two alerts and the state the window lands in (PRD P3, P4).

## 14. Requirements issues, design questions and notes

### 14.1 For the product manager (none blocks the engineer; the design assumes each answer given)

1. **RI-1. R11 says "Import All"; there is no such command.** The window has
   Select All and Import N Photos. The design reads "skipped by Import All" as
   "skipped by Select All and never importable" (§4.6). The same requirement
   says marked photos are "unchecked by default", and the repeat scenario says
   "only new ones import"; the design starts a **server** source with nothing
   checked (D7) and meets the scenario with Select All. Please word R11 and AC7
   to that, or ask the owner to flip DQ-3.
2. **RI-2. R16 and R22 disagree about a re-added connection.** R16 says links
   survive removal and "Publish later finds them by remote id if the connection is
   added again", but R22's `remoteService` row gets a new id when it is re-added,
   so links keyed on the old connection id would not match, the photos would not be marked,
   and a re-import would re-download them (caught only after download as
   duplicates by content). Something has to make a re-added server the same
   connection: a stable connection key (provider plus normalized address plus
   account), or links matched on provider, address and remote id. The removal alert
   (§3.7) says only that photos stay in the library, and nothing about marks. Please rule.
3. **RI-3. R12 and Q6 disagree on the project name.** R12: "a project named as in
   card import (Q6)". Q6: "<connection name> - <album name or 'All photos'>".
   The card template has no connection or album token. The design uses a plain
   prefilled text field (§5.3) and the scope's shown name ("All Photos").
   Please word R12 to Q6.
4. **RI-4. R2 lists four failures; the sheet needs seven.** Added by the design
   because each is a distinct thing the person can fix: **not Immich**,
   **certificate changed** (R6 already requires it), **Keychain failure**
   (R1). Please extend R2 and AC2.
5. **RI-5. R10's counts.** An album's count from the server may include videos
   the grid never lists, and "All photos" may have no count at all (the PRD
   assumes `total` is unconfirmed). The design shows the server's number for
   albums, none for All Photos unless exact, and says nothing is estimated
   (§4.2, §4.6). Please say so in R10.
6. **RI-6. R17 and sidecars.** A description and rating stored as library values
   queue XMP sidecar writes when sidecars are on (the existing triggers). That
   probably is wanted; the PRD is silent. Also the PRD's Info.plist list lacks
   `NSLocalNetworkUsageDescription` (§10). The design assumes both are fine.

**Status of §14.1 (2026-11-23):** the PRD revision for RI-1 to RI-6 is pending
with the product manager. The notes above are unchanged; none has a ruling yet.
(RI-1's "or ask the owner to flip DQ-3" is answered: the owner kept
DQ-3's default, §14.3.)

### 14.2 For the owner (answered 2026-11-23: each default stands; the rulings are in §14.3)

The questions as asked, kept for the reasoning. Each "Default" below is now the
ruling.

1. **DQ-1. The name of File ▸ Import from Card or Folder…** (⌘I, also the toolbar
   item, the sidebar's menu and the library's empty state). With a server as a
   source it is no longer accurate. **Recommendation: rename to "Import…"**
   (Photos and most Mac apps do), and the empty library's sentence becomes "Import
   copies photos from a card, a folder or a server into the folder you choose."
   It touches five strings and the user guide, nothing in behavior; the design
   works unchanged either way, since the Import window's own empty state already
   says servers exist (§2.4). **Default: not renamed in this branch.**
2. **DQ-2. Select All on a partly loaded album.** **Default: it takes what is
   loaded** and the subtitle and button say so (§4.6). The alternative is that
   it first loads every remaining page (tens of thousands of listings at 1,000
   per request, seconds), then selects; one more state ("Loading all photos…",
   Stop) and a bigger default action.
3. **DQ-3. Nothing checked on a server.** **Default: nothing**, because Return
   imports and a server is browsed (§4.6). The card's behavior (every new
   photo loaded, checked) is the alternative; it would check at most one page
   and could not mean "everything in the album".
4. **DQ-4. How many albums does your server have?** **Default: a pop-up menu**
   (§4.2). If it is more than about sixty, a searchable popover is better; the
   change is local to the Album control.

### 14.3 Owner rulings on §14.2

The owner answered all four on 2026-11-23 with "Accept defaults". The engineer
builds each as stated; cite them by number.

### DQ-1. File ▸ Import from Card or Folder… is not renamed in this branch

Ruled by the owner, 2026-11-23: accept the default. The item (⌘I, the toolbar
item, the sidebar's menu, the library's empty state) and the user guide keep
their current names and sentences. No string changes for it. The Import window's
own empty state already says servers exist (§2.4). A rename to "Import…" is a
separate change if the owner wants it later.

### DQ-2. Select All on a partly loaded album takes what is loaded

Ruled by the owner, 2026-11-23: accept the default. Select All checks the
unmarked photos loaded at that instant and does not fetch remaining pages; the
subtitle and the Import button say how many are selected and how many are loaded
(§4.6). No "Loading all photos…" state.

### DQ-3. A server source starts with nothing checked

Ruled by the owner, 2026-11-23: accept the default. Import is **Import 0
Photos** and dimmed until something is checked; the card's all-checked start does
not apply to a server (§4.6). RI-1 (§14.1) asks the product manager to word R11
and AC7 to match.

### DQ-4. The Album control is a pop-up menu

Ruled by the owner, 2026-11-23: accept the default. The owner did not give his
album count. The searchable popover (§4.2) stays a later, local change if the
list proves too long (more than about sixty); M4 (§13) looks at it on a real
album list.

**Assumptions** (the design needs no answer): Q2's second half (a link to create
the key) is **text only**, since the owner took the defaults and the PRD named no
link as the default; the Server sheet has no Type pop-up in v1; no sandbox
(PRD); the check is bounded by timeouts the engineer proposes.

## 15. Design questions from implementation

The engineer returns each as a **Design question**; each ruling is
recorded here as `### DQ-‹n›` and cited by number. DQ-1 to DQ-4 are taken by the
owner's rulings in §14.3, so the first question from implementation is **DQ-5**.

### DQ-5. The Keychain refuses to delete the key during Remove Server

Ruled by the designer, 2026-11-23 (judgment, not Apple policy; the HIG is silent
on this case). **The behavior built stands**: nothing is removed, and the person
is told. **The alert built does not match**: it puts the Keychain sentence in the
alert's title with no message and no explanation. It must be a normal alert
(the `serverAlert` path of §6.3: title, message, one **OK**).

- **Why nothing is removed.** §3.7's confirmation promised "The API key is
  deleted from the Keychain." Removing the row anyway would make that false and
  leave a live secret on this Mac with nothing in the app that names it, which
  the person can't find (the item's account is a UUID, §3.7's data rule) and the
  app can't offer to delete again. A server that stays listed is recoverable:
  the next Remove Server… tries again. Why not offer "remove anyway": it is the
  one choice here that cannot be undone and cannot be seen afterwards.
- **What counts as success.** An item that is already gone (`errSecItemNotFound`)
  is a successful removal, not a refusal; the build already does this
  (`KeychainKeyStore.deleteKey`). Keep it, and keep a test for it. Any other
  status, including the person's own Deny on a Keychain access prompt, is a
  refusal and shows this alert.
- **The alert.** Window-modal on the Import window, the same host as the
  confirmation, shown after it closes:

  > **The server “Home Server” wasn't removed**
  > The Keychain wouldn't delete the API key: ‹the system's text›. Nothing was
  > removed. Choose Remove Server… to try again. If it keeps failing, delete the
  > key in Immich so it stops working.
  >
  > [ OK ]

  One button, **OK**, which is the default (Return and Esc both dismiss; the
  alert is informational and nothing here is destructive, so the destructive
  no-default rule of §3.7 doesn't apply; HIG Alerts: use a single button when
  the alert only informs). The title says what did not happen, in the sentence
  form of §6.3's titles; the message says why, what state things are in, and the
  next step, naming the control by its exact title without quotes. There is no
  **Try Again** button: the likely causes (a locked Keychain, a Deny) need the
  person to act first, and repeating a delete from a default button is the wrong
  default. The last sentence is there because the person who removes a server
  to be safe must still end up with a dead key (the same reason as §3.7's last
  sentence).
- **State after.** The server stays in the list and stays the current source if
  it was; the window does not change otherwise. The key and the row are as before.
  No log line contains the key.
- **The system's text.** Keychain messages end with a period
  ("The specified item could not be found in the keychain."), so the string would
  end ".." as built. The engineer trims one trailing period (and surrounding
  white space) from the system text before it goes into this sentence and into
  `The Keychain returned an error: %@.` (§3.4), whose copy is otherwise
  unchanged. That is a fix to the build of the existing string, not new copy.

### DQ-6. The album list fails but photos load

Ruled by the designer, 2026-11-23. **The Album pop-up is as built and stays as
§4.2 says**: it is enabled, shows **All Photos** (checked) and a dimmed
**Albums unavailable**, and the person can import everything the grid lists; only
choosing an album is lost. Nothing blocks the photos, so nothing but the one
Activity warning is shown (no alert, no state in the grid). **The Activity text
built does not match**: it is the bare reason. The sentence is:

> **Couldn't load the albums of “Home Server”: ‹reason›. Choose Rescan to try again.**

- The title of the Activity row stays the server's (**Import from “‹name›”**),
  as built; the sentence names the server again, because the row can be read
  after the Import window has closed. It is a warning row
  (`exclamationmark.triangle`), as built.
- The reason is the same plain reason as **Couldn't load more photos from
  “‹name›”: ‹reason›. Scroll to try again.** (§10), in the same position, so the
  two warnings read alike. The sentence names the way on, **Rescan**, which §4.2
  already says retries both the albums and the photos (the toolbar item and
  File ▸ Rescan; the exact title, no quotes).
- One warning per failed load: each Rescan that fails again posts another.
  Choosing an album is not offered, so nothing else can post it.

**Engineer's changes for DQ-5 and DQ-6**

1. DQ-5: replace `alertText` in `CardImportModel.removeServer` with a
   `serverAlert` (title and message above, one OK); trim the one trailing period
   from the Keychain's text for both Keychain sentences; add a test that a
   refusing store leaves the row and key and sets the alert, and that
   `errSecItemNotFound` removes the row.
2. DQ-6: wrap the reason in the sentence above in `loadAlbums`.
3. Add the two new strings in §10 to `Localizable.xcstrings` with comments and
   the user guide's sentences for both if it describes either case.

### DQ-7. The API key caption and the missing-permission detail name five permissions

Ruled by the designer, 2026-11-23 (judgment; the HIG has no rule for this copy).
**Confirmed as built.** RI-E1 added `user.read`, so the caption reads **Create
the key in Immich, in your account settings. It needs only these permissions:
asset.read, asset.view, asset.download, album.read and user.read.** and the
missing-permission detail reads **Add ‹names› to the key in Immich, or create a
new key with the five permissions listed above.** §3.2, §3.4 and §10 are updated.

- **Why the count stays in the detail.** It lets the person check that they
  ticked all of them; the cost is that Publish (#28), which widens the list,
  changes this string again, which it must do anyway because the caption changes
  with it.
- **Why the caption does not say why `user.read`.** The person is working from a
  checklist in Immich's own key screen; the reason (it tells the app which photos
  are yours) is in the user guide, where it already is. A sixth line in a caption
  that already runs three would push the Keychain line off a short sheet.
- **"above" is true:** the result renders under the key field, below both
  captions (`resultView(concernsAddress: false)` follows them).
- **Plain text, not monospaced.** §3.4 asked for the missing names in the
  monospaced font. A localized sentence with an interpolated list is a plain
  `String`; styling one run needs an `AttributedString` and a second catalog
  path for no gain, since the names are matched by their characters, which a
  proportional font shows as well. The requirement is dropped, not deferred.
- **No string changes** for this ruling.

### DQ-8. The size-only line in Activity

Ruled by the designer, 2026-11-23 (judgment). **Rewritten.** The built line,
"‹n› were checked by size only (photos in an Immich external library).", depends
on the line above it for its subject: after "2 Live Photo videos were not
downloaded." the "‹n›" reads as more Live Photo videos. It also does not say what
the person should take from it. The line is now a complete sentence with its own
noun, the reason and the consequence:

> **5 imported photos were checked by size only, not against the server's
> checksum, because they are in an Immich external library.**
> One: **1 imported photo was checked by size only, not against the server's
> checksum, because it is in an Immich external library.**

- "Imported photos" is exact: the count is photos that landed (`.inserted`), never
  a duplicate (the engineer's rule, kept; a duplicate counts only as "already in
  the library").
- "not against the server's checksum" is the true limit: the copy is still read
  back and hashed, the one comparison skipped is the server's checksum, which for
  an external library can be of the file's path (user guide, same words).
- "Immich external library" is Immich's own term, so the person can find it in
  Immich; "external library" is kept, not paraphrased.
- Position unchanged: after the Live Photo line, before the failures (§6.2).
- Plural on the number, both forms as above, as the neighbors.

### DQ-9. An external-library photo with no size to check against

Ruled by the designer, 2026-11-23 (judgment). **Rewritten.** The built reason
("the server gave no size to check the download against, so it was discarded.")
ends in a dangling preposition and does not say that the file itself may be fine.
The reason is now, in the shape of the table's other rows:

> **‹name›: the server did not say how large the file is, so the download could
> not be checked and was discarded.**

- Consistent with "the download was incomplete and was discarded.": a download,
  not a photo, is what is discarded, and the person can try again later.
- No action is offered: nothing the person can do changes what the server
  reports, and the user guide already says such a photo is not imported.
- No server text, URL or key.

**Engineer's changes for DQ-7 to DQ-9** (exactly these)

1. DQ-7: none.
2. DQ-8: in `ServerText.line(for:)` (`.verifiedBySizeOnly`) and the catalog, replace
   the key `%lld were checked by size only (photos in an Immich external library).`
   with `%lld imported photos were checked by size only, not against the server's
   checksum, because they are in an Immich external library.`; plural `one`:
   `%lld imported photo was checked by size only, not against the server's
   checksum, because it is in an Immich external library.`; keep the comment.
3. DQ-9: in `ServerText.failureLine` (`.unverifiable`) and the catalog, replace
   the key `%@: the server gave no size to check the download against, so it was
   discarded.` with `%@: the server did not say how large the file is, so the
   download could not be checked and was discarded.`; keep the comment.
4. No test asserts either old sentence (grep of `Tests/`); if one is added for the
   Activity text, it uses the new strings. `docs/USER_GUIDE.md` needs no change
   ("Activity says how many were" and "one whose size the server doesn't give is
   not imported" still hold).
