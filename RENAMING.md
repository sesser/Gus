# Renaming the app

The working name lives in exactly two files. Nothing else needs to change.

## 1. `Sources/PhotoCore/Branding/AppBranding.swift`

| constant | what it controls |
|---|---|
| `displayName` | name in window titles, menus, dialogs (passed as `%@` to localized strings) |
| `bundleIdentifier` | logging subsystem; must equal `PRODUCT_BUNDLE_IDENTIFIER` |
| `appSupportDirectoryName` | `~/Library/Application Support/<name>/` (catalog location) |
| `cacheDirectoryName` | `~/Library/Caches/<name>/` (preview cache location) |
| `urlScheme` | custom URL scheme; must equal `PRODUCT_URL_SCHEME` |
| `sidecarNamespace`, `sidecarNamespacePrefix` | custom XMP namespace (see note below) |

When renaming, also **prepend the old values** so existing data is carried over:

- old `appSupportDirectoryName` → `previousAppSupportDirectoryNames`
- old `cacheDirectoryName` → `previousCacheDirectoryNames`

## 2. `Branding.xcconfig`

Set `PRODUCT_NAME`, `PRODUCT_DISPLAY_NAME`, `PRODUCT_BUNDLE_IDENTIFIER` and
`PRODUCT_URL_SCHEME`. `Scripts/build-app.sh` fills `Support/Info.plist` and names
the `.app` and its executable from these.

## 3. Verify

```bash
swift test --filter BrandingTests
```

```bash
Scripts/build-app.sh
```

`BrandingTests` fails if the two files disagree, or if the name (old or new
spelling) appears anywhere else in `Sources/`, `Scripts/`, `Support/` or
`Package.swift`. The String Catalog never contains the name; it uses `%@`.

## What happens on first launch after a rename

`DataDirectoryMigrator.migrateStandardLocations()` runs before the catalog opens:

1. Old cache folders listed in `previousCacheDirectoryNames` are deleted. Previews
   are regenerated on demand, so nothing is lost.
2. If `Application Support/<appSupportDirectoryName>` does not exist and one of
   `previousAppSupportDirectoryNames` does, that folder is renamed to the new
   name (a same-volume move, atomic). The catalog file inside is `catalog.sqlite`
   and the schema contains no product name, so nothing inside needs rewriting.
3. If both old and new folders exist, nothing is moved and the conflict is logged.

Things a rename does **not** carry over automatically:

- **Preferences**: `UserDefaults` is keyed by bundle identifier. Phase 1 stores only
  cosmetic settings (thumbnail size, auto-advance). To keep them, run once before
  launching the renamed app:

  ```bash
  defaults export OLD.BUNDLE.ID - | defaults import NEW.BUNDLE.ID -
  ```

- **Privacy permissions** (Files and Folders, removable volumes) are tied to the
  bundle identifier and will be asked for again.
- **XMP namespace**: phase 1 writes no sidecars. Once sidecars exist in the wild,
  keep `sidecarNamespace` unchanged across renames (it is an opaque URI, not a
  display string), or add the old URI to a legacy-read list when sidecar reading lands.

The app icon, `Support/AppIcon.png`, contains no name or letter, so a rename
does not require new artwork; replace it only if the new brand calls for it.

The repository folder name is not referenced by the build and can be anything.
