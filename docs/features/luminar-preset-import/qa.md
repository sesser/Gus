# Import preset packs (.lnpc): QA

Owner: qa-tester. Date: 2026-11-17. Step 4 of `docs/WORKFLOW.md`.
Tested: `feature/luminar-preset-import` at b235516 (first run at 5e5e386; rerun after design §13, commit 50b582f), on a Mac with Apple M4 Pro, macOS 27.2.1 (26B131), Xcode SDK 27.2
(the bundle's executable records `sdk 27.2`, `minos 15.0`).
Spec: the PRD (issue #203, rev 3), `design.md` rev 2 with §13, `status.md`, `review.md` (with its second confirmation), `code-review.md` (fifth pass).

## Verdict

Passes, signed off by the owner on 2026-11-18 (see Follow-up): AC1 to AC12 are met; AC12's eye comparison (P5) was done by the owner. The one finding (Q1, the table tool's report wording) is
fixed and confirmed on b235516; no failures. The owner's library and the owner's four packs were not touched (checked at
the end of both runs, see Scripts).

## Acceptance criteria

How: Test, Script or Person. Tests run with `swift test` (full run on b235516: 1137 tests in 170 suites, all pass, no warnings,
`git status` clean afterwards so no golden or file changed). Scripts are in "Scripts" below.

| AC | How | Evidence | Result |
|---|---|---|---|
| AC1 import accepts `.lnpc`, several at once, existing formats still import | Test, Script, Person | `PresetPackImportTests.importsPacksBesideOtherFormats` (two packs and a `.guspreset` in one import; fails without `lnpc` in `fileExtensions`); `PresetPackTableTests.everyImportExtensionHasAType`; Scripts S1, S6 (a folder; a pack, a plain preset file and a damaged file in one import); the open panel itself: P1 | Pass (panel half: P1, done by the owner 2026-11-18) |
| AC2 N presets, pack's order; German names with a German system language, English otherwise | Test, Script | `importsPacksBesideOtherFormats` (order Beta, Alpha as the pack lists them), `namesInTheSystemLanguage`, `PresetPackReadingTests.namesFollowTheLanguageWhenThePackHasIt`; Script S3 (launch with `-AppleLanguages "(de)"`: "Erfundenes Paket / Goldtest", the preset with no German name stays English) | Pass |
| AC3 table in a look-up table collection of the pack's name; applying renders with it at the mapped intensity | Test, Script | `importsPacksBesideOtherFormats` (table installed, collection `Test Pack`, applied `effective.lookTable` intensity 80); Script S2 (`luts` lists "Made Up Pack: Warm Look"), S8 (preset applied in the loupe: stack hash changes, saved, the photo renders brighter with vignette; snapshots looked at) | Pass |
| AC4 each mapped tool against prototype-derived values; curves at 17 points; Develop instances add up; RAW Develop only alone | Test | `PresetPackMappingTests` (26 tests, `lookUpTableContrastAndSaturationAreApproximated` now pins `lookUpTable:mapped`, `lookUpTable:approximated`, `develop:mapped` per design §13; `PresetPackReportLineTests.aTableWithContrastCountsUnderBothStatuses`; every tool of the README table, `curvesComposeInToolOrderAt17Points`, `developInstancesAddUpWithColorSaturation`, `rawDevelopIsUsedOnlyAlone`, ...). Read: expected values are literal numbers the prototype gives for the same made-up templates, not computed by the code under test. Also the opt-in suite on the owner's packs: `PresetPackSampleTests.conversionsMatchThePrototype` compared 40 of 40 presets with the prototype's own output (same groups, every parameter within 2e-4) | Pass |
| AC5 a converted preset changes only the groups it sets | Test | `applyingChangesOnlyTheGroupsItSets` (Exposure, Clarity, Grain, Color Mixer of the photo untouched, only Presence replaced) | Pass |
| AC6 Accent AI and a mask left out and listed; mapped and approximated named; no value set from them | Test, Script | `accentAIAndAMaskAreLeftOutAndSetNothing` (the result equals the same preset without those tools), `leftOutToolsAreReportedOnlyWhenTheyChangeSomething`, `PresetPackReportLineTests`; Script S1 ("Left out: Smart Tone, Texture, Accent AI, Sky Enhancer, and Masks", "Approximated: Structure (as Clarity)", "Mapped: Develop"; the preset's groups are Tone and Presence only) | Pass |
| AC7 importing twice leaves counts unchanged | Test, Script | `importingAgainDuplicatesNothing` (presets, ids, collections, table entries and files); Script S4: the same pack twice in one run and again in a second launch on the same library: 2 presets, 1 collection of each name, 1 table entry per pack and 10 files in `LUTs` (8 built-in, 2 ours) before and after; pack header says "replaced" | Pass |
| AC8 truncated zip, zip without `Config/config.json`, non-zip each give a reason and import nothing; a valid file with them imports; no temp files | Test, Script | `badFilesAreRefusedAndTheRestImport`, `refusesWhatIsNotAReadablePack`, the limits tests (`refusesWhatIsOverItsLimitsOrUnsupported`, `refusesAPackOverItsReadBudget`, `readsOnlyRegularFilesWithinTheLimit`, ...); Script S1 (the three refused with "The file is damaged or incomplete." / "Not a preset pack." and the good pack imported). No temp files: `packCodeWritesNoFiles` is a source search for write calls (a tripwire, not a run), so I also compared the user temp folder (`getconf DARWIN_USER_TEMP_DIR`, 3,996 entries) before and after Script S1: no difference | Pass |
| AC9 each assumed scale a named constant; a test fails if one changes | Test | `assumedScalesAreTheRecordedOnes` (ten constants, plus the mapping uses them) | Pass |
| AC10 no file type, UTI, document type or Finder association; the one table and its catalog entries; verbatim fallback; no other Luminar asset or string | Test, Script, Person | `PresetPackTableTests`: `everyToolInTheTableIsOneTheMappingHandles` (36 cases), `theLeftOutToolsOfR6AreInTheTable`, `aToolNotInTheTableIsReportedVerbatim`, `theCatalogHoldsExactlyTheTablesToolNames`, `packsAreNotAFileTypeOfTheApps`, `noStringNamesTheFormatsApplication`; `LocalizationTests` and `BrandingTests` pass in the full run. Script S9: no `lnpc` in either built `Info.plist`; the only types declared are the app's own (`me.sesser.gus.versions`, `me.sesser.gus.preset`); no `*.lnp*` or `*.lmps` file and no "luminar" or "skylum" text in either `.app`; `git ls-files` has no pack, icon or artwork file and the only tracked data with the tool identifiers are the table and made-up test fixtures. A real double-click: P3 | Pass (Finder half: P3, done by the owner 2026-11-18) |
| AC11 existing suite and goldens pass unchanged | Test | full `swift test` (b235516): 1137 tests, 170 suites, all pass; `git status` clean, no golden file differs; diff against `develop` has no migration and no `currentPipelineVersion` change | Pass |
| AC12 the owner imports his four packs and compares a sample with the prototype's output by eye | Script, Person | Script S5: the four packs (read through symbolic links, files unchanged afterwards) import with "4 packs · 40 presets · 36 look-up tables added", nothing refused, no "Not recognized" line (rerun S5 and S10 on b235516); opt-in suite 40 of 40 match the prototype (rerun, and its per-pack totals now print: American Dream 27 mapped, 28 approximated, 7 left out; Camping Trip 21, 21, 13; Land of the Rising Sun 21, 17, 6; Wonderful Scandinavia 35, 52, 13); the eye comparison: P5, done by the owner 2026-11-18 ("P1-5 all check out") | Pass (P5 done by the owner, 2026-11-18) |

Counts (after the owner's sign-off, 2026-11-18): 12 Pass, 0 Open, 0 Fail. Before it: 11 Pass (4 by test alone: AC4, AC5, AC9, AC11; 6 by test and script: AC2, AC3, AC6, AC7, AC8, AC10; AC1 by test
and script, with the panel left to P1), 1 Open for a person (AC12), 0 Fail. AC1's panel half (P1) and AC10's Finder half (P3) were also done by the owner.

Design requirements the designer marked for a manual check (`review.md` M1 to M12) are in "For a person" below, with
what the script covered.

## Findings

**Q1 (low, Design question): closed.** Where a preset's look-up table tool also carried Contrast or Saturation, the
report listed it only as "Approximated: LUT Mapping (as Contrast and Saturation)", never under Mapped, although the
table itself was carried exactly (24 of the 36 presets with a table in the four packs; "Heritage Hues: 2 mapped, 5
approximated"). The designer ruled (design §13) that the table tool is listed under both statuses; the engineer
changed `toolReports()` in commit 50b582f (`exactAndApproximated`, the table tool only). Confirmed on b235516, see
Follow-up and Script S10.

Observations, not findings: `packCodeWritesNoFiles` is a source search, not a run (covered above by the temp folder
comparison); a debug-script `preset import` with a path that has spaces splits it at the spaces (existing behavior of
the script, so the owner's packs were passed through space-free symbolic links); the report names an unknown tool once
(the tool's name) and not the unknown effect inside it (`MIPLAnotherUnknownEffect` in the made-up pack), which matches
the design (A1) and the tests.

## Scripts

Setup for all scripts (S0). Bundle from `Scripts/build-app.sh` (it needs Xcode 26 or later; this run: SDK 27.2), copied
into the scratch space and given its own identifier. Every launch below passes `--library-root` on a copy of the
scratch library. `$Q` is a scratch folder; `$R fresh <name> "<script>"` copies the scratch library to `$Q/lib-<name>`
and runs the copy's executable with `--debug-script "<script>; quit"`; `keep` reuses `$Q/lib-<name>`.

```
Scripts/build-app.sh
cp -R build/Gus.app $Q/app/Gus.app
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest $Q/app/Gus.app/Contents/Info.plist
codesign --force --deep --sign - $Q/app/Gus.app
swift run -c release photobench generate --output $Q/gen --jpeg 4 --dng 0 --heic 0 --pairs 0 --videos 0
mkdir -p $Q/lib && swift run -c release photobench import --library-root $Q/lib --source $Q/gen
```

`$R` is:

```
timeout 240 $Q/app/Gus.app/Contents/MacOS/Gus --library-root $Q/lib-<name> --debug-script "<script>; quit"
```

Made-up packs (`python3 -I mkpacks.py $Q/packs`; structure as the format has it, values and names our own): `MadeUp.lnpc`
("Made Up Pack", German "Erfundenes Paket"; presets "Golden Test" (a table, Develop, Color Mixer, Grain, Vignette), a long
named one (Develop with Smart Tone and Texture, Accent AI, Sky Enhancer, a masked Color tool, Structure, an unknown tool
`SomeFutureToolAdjustmentLayer`) and "Broken" (an unreadable template)), `Second.lnpc` (one preset, another table),
`NoConfig.lnpc` (no `Config/config.json`), `Damaged.lnpc` (MadeUp with its last 100 bytes cut), `NotAPack.lnpc` (text),
and `Plain.guspreset` (written by the app: `preset save Plain Bright; preset export …`).

```python
import json, sys, zipfile, os
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
CUBE = "# test\nLUT_3D_SIZE 2\nDOMAIN_MIN 0.0 0.0 0.0\nDOMAIN_MAX 1.0 1.0 1.0\n0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n"
CUBE2 = "LUT_3D_SIZE 2\n0 0 0\n0 0 1\n0 1 0\n0 1 1\n1 0 0\n1 0 1\n1 1 0\n1 1 1\n"
def p(name, v, d=0, ot="0", ov="0", pretty=None):
    r = {"name": name, "value": str(v), "default": str(d), "min": "-100", "max": "100", "opt_data_type": ot, "opt_data_value": ov}
    if pretty: r["pretty_name"] = pretty
    return r
def eff(i, *ps): return {"id": i, "params_array": list(ps)}
def tool(n, *es, mask=""):
    return {"permanent": "true", "locked": "false", "enabled": "true", "tool_name": n, "mask": mask,
            "source_image": "", "blend_mode": "0", "effects_array": list(es)}
def lut(f, amt=80, name="Look"):
    return tool("LUTMappingEffect", eff("MIPLLUTMappingEffect", p("Texture", 0, 50, "2", f, name), p("Amount", amt, 30), p("Contrast", 0), p("Saturation", 0)))
def template(name, uuid, tools):
    return {"name": name, "uuid": uuid, "canvas_size": ["1", "1"], "layers_array": [{"enabled": "true", "alive": "true",
            "source_image": "", "mask": "", "blend_mode": "0", "opacity": "1", "edits_array": tools}]}
def strings(d): return "".join('"%s" = "%s";\n' % (k, v) for k, v in d.items()).encode()
def pack(path, packname, de, presets, no_config=False):
    pid = "aaaaaaaa-0000-0000-0000-000000000000"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        if not no_config: z.writestr("Config/config.json", json.dumps({"name": "Category", "identifier": "c", "version": 1.1}))
        z.writestr(pid + "/config.json", json.dumps({"name": "Pack Name", "identifier": pid, "templates": [u + ".lnp" for (u, _, _, _, _) in presets], "description": "d"}))
        z.writestr(pid + "/localizations/en.strings", strings({"Pack Name": packname}))
        if de: z.writestr(pid + "/localizations/de.strings", strings({"Pack Name": de}))
        for (u, n, n_de, tools, res) in presets:
            f = pid + "/" + u + ".lnp"
            z.writestr(f + "/template.lmps", "{" if tools is None else json.dumps(template(n, u, tools)))
            z.writestr(f + "/localizations/en.strings", strings({n: n}))
            if n_de: z.writestr(f + "/localizations/de.strings", strings({n: n_de}))
            z.writestr(f + "/icon.jpg", b"\xff\xd8\xff")
            for k, v in res.items(): z.writestr(f + "/resources/" + k, v)
dev = lambda *ps: tool("DefaultEffects", eff("MIPLDevelopCommonEffectID", *ps))
presets_a = [
 ("11111111-0000-0000-0000-000000000000", "Golden Test", "Goldtest",
  [lut("A.CUBE", 80, "Warm Look"), dev(p("Exposure", 20), p("Contrast", 10), p("Highlights", -15)),
   tool("ExtendedColorAdjustmentLayer", eff("MIPLChannelsEffect", p("hRed", 10), p("sBlue", -20))),
   tool("GrainNewAdjustmentLayer", eff("MIPLGrainNewEffect", p("Amount", 22), p("Size", 20, 20), p("Roughness", 40, 30))),
   tool("VignetteAdjustmentLayer", eff("MIPLVignetteEffect", p("Amount", -20), p("Vignette Size", 60, 50)))], {"A.CUBE": CUBE}),
 ("22222222-0000-0000-0000-000000000000", "Long Mix With A Quite Long Name To Test Truncation Of The Row", None,
  [dev(p("Contrast", 30), p("Smart Tone", 20), p("Texture", 5)),
   tool("AIEnhanceAdjustmentLayer", eff("MIPLDynamicContrastEffect", p("Boost", 40)), eff("MIPLSkyEnhancerEffect", p("Amount", 25))),
   tool("ExtendedColorAdjustmentLayer", eff("MIPLVibranceEffect", p("Vibrance", 20)), mask="mask-data"),
   tool("AIStructureEffect", eff("MIPLAIStructureEffect", p("Amount", 12))),
   tool("SomeFutureToolAdjustmentLayer", eff("MIPLAnotherUnknownEffect", p("Amount", 9)))], {}),
 ("33333333-0000-0000-0000-000000000000", "Broken", None, None, {}),
]
pack(out + "/MadeUp.lnpc", "Made Up Pack", "Erfundenes Paket", presets_a)
presets_b = [("44444444-0000-0000-0000-000000000000", "Solo", None, [lut("B.CUBE", 60, "Swap"), dev(p("Exposure", -30))], {"B.CUBE": CUBE2})]
pack(out + "/Second.lnpc", "Second Pack", None, presets_b)
pack(out + "/NoConfig.lnpc", "No Config", None, presets_b, no_config=True)
data = open(out + "/MadeUp.lnpc", "rb").read()
open(out + "/Damaged.lnpc", "wb").write(data[:len(data) - 100])
open(out + "/NotAPack.lnpc", "w").write("just text, not a zip\n")
```

**S1, refused files and a good pack in one import (AC1, AC6, AC8, R9).**
`wait 2; preset import $P/MadeUp.lnpc $P/Damaged.lnpc $P/NotAPack.lnpc $P/NoConfig.lnpc; preset report; preset`
Showed: "1 pack · 2 presets · 1 look-up table added"; Not imported: Damaged.lnpc "The file is damaged or incomplete.",
NotAPack.lnpc and NoConfig.lnpc "Not a preset pack."; Golden Test "5 mapped" (LUT Mapping, Develop, Color, Grain and
Vignette); the long preset "1 mapped, 1 approximated, 6 left out" (Mapped: Develop; Approximated: Structure (as
Clarity); Left out: Smart Tone, Texture, Accent AI, Sky Enhancer, and Masks; Not recognized:
SomeFutureToolAdjustmentLayer); "Preset 3: Its settings can't be read."; the saved presets are the two readable ones, with
groups `[Tone, Color Mixer, Look-Up Table, Vignette, Grain]` and `[Tone, Presence]` (nothing from Accent AI, Sky
Enhancer or the masked tool). The user temp folder had no new entry afterwards.

**S2, collections (AC3).** `wait 2; preset import $P/MadeUp.lnpc; luts` showed the look-up table collection "Made Up
Pack: Warm Look [sRGB]" beside Built-in.

**S3, German (AC2).** Launch with `-AppleLanguages "(de)"` before the debug script:
`wait 2; preset import $P/MadeUp.lnpc; preset` gave the collection "Erfundenes Paket", the preset "Goldtest" and, with no
German name in the pack, the other preset in English.

**S4, importing again (AC7, R8).** Launch 1 on a fresh library: `wait 2; preset import $P/MadeUp.lnpc; preset import
$P/MadeUp.lnpc; preset`. Second import: "1 pack · 2 presets" (no tables added), header "2 presets · 1 look-up table ·
replaced". Launch 2, same library: `wait 2; preset import $P/MadeUp.lnpc $P/Second.lnpc; preset`: "2 packs · 3 presets ·
1 look-up table added", Made Up Pack "replaced", Second Pack "1 preset · 1 look-up table". `sqlite3` on the scratch
catalog afterwards: `adjustmentPreset` 2 + 1 rows by collection, 2 look-up table entries, collections "Made Up Pack" and
"Second Pack"; 10 files in `Library/LUTs`.

**S5, the owner's four packs (AC12, script half).** Symbolic links to the four packs in `$Q/realpacks` (the script splits
paths at spaces): `wait 2; preset import $Q/realpacks/American_Dream.lnpc $Q/realpacks/Camping_Trip.lnpc
$Q/realpacks/Land_of_the_Rising_Sun.lnpc $Q/realpacks/Wonderful_Scandinavia.lnpc; preset reportpage; wait 1; preset
windowshot $Q/real-report.png`. Showed "4 packs · 40 presets · 36 look-up tables added", each pack 10 presets, nothing
refused, no "Not recognized" line; the snapshot (looked at) is the page of design §2.3: Back and title, summary line,
pack header with its trailing summary, collapsed rows with count lines, Done at the bottom. The four files' size and
modification time were the same before and after. Opt-in suite, run in this checkout:
`LUMINAR_PACKS=~/Projects/luminar-presets LUMINAR_PROTOTYPE_OUTPUT=~/Projects/luminar-presets/gus-presets swift test --filter PresetPackSampleTests`
gave "Compared 40 presets with the prototype's", 2 tests passed (a debug build: 29 s to save, which the status
records for debug builds; the release time is 0.7 s).

**S6, a folder and a mixed import (AC1, design §2, M11).** `wait 2; preset import $Q/packs; preset`: the pack presets
under their own pack names (Made Up Pack, Second Pack), the plain preset in the collection "Packs" (the folder's
name), "Other presets: Presets imported: 1 Collections: Packs", refused files under Not imported. And `wait 2; preset
import $P/MadeUp.lnpc $P/Plain.guspreset $P/Damaged.lnpc; preset reportpage; wait 1; preset windowshot $Q/mixed-report.png`:
one result (no alert), "1 pack · 3 presets · 1 look-up table added"; the snapshot (looked at) shows Not imported first
with a warning symbol and Damaged.lnpc's reason, the pack with its two rows and the unreadable "Preset 3" row with a
warning symbol, then "Other presets", then Done.

**S7, the report waits for every modal source of the window (code review F2, C7, C9, C10; M9 in part).** For each
source: open it, import a pack with `preset summary` (imports and shows the result as a person's import does), print
`preset sheets`, close the source, wait, print `preset sheets`, snapshot the sheet. Each launch is on a fresh library;
`$P` is the packs folder. With the source up the output was always "presets false page report waits true attached 1"
with only that source true; after it closed "presets true page report waits false attached 1" and all sources false.

| Source | Script (after `wait 2;`) | Up | After closing |
|---|---|---|---|
| Remove from Library confirmation | `project 0; focus 0; removephotos; preset summary $P/MadeUp.lnpc; preset sheets; preset close removal; preset sheets; preset windowshot $Q/m1.png; waitimport` | `removal true`, waits | report open; `waitimport` prints `gen=4`: the four photos are still there after Cancel |
| Remove Project from Library confirmation | `project 0; removeproject; preset summary …; preset sheets; preset close removal; preset sheets; preset windowshot $Q/m2.png; waitimport` | `removal true`, waits | report open; `gen=4` |
| New Smart Album sheet | `smartalbum Stars; sheet smart; preset summary …; preset sheets; sheet; wait 1; preset sheets; preset windowshot $Q/m3.png` | `sidebarSheet true`, waits | report open |
| New Album sheet | `sheet album; preset summary …; preset sheets; sheet; wait 1; preset sheets; preset windowshot $Q/m4.png` | `sidebarSheet true`, waits | report open |
| Sidebar delete confirmation | `smartalbum Stars; wait 1; sheet deletesmart; wait 1; preset sheets; preset summary …; preset sheets; sheet deleteclose; wait 1; preset sheets; preset windowshot $Q/m5.png` | `sidebarDeletion true` before and after the import, waits | report open (the one path with no `onDismiss`, as code review asked) |
| Export sheet | `selectall; export window; preset summary …; preset sheets; export close; wait 1; preset sheets; preset windowshot $Q/m6.png` | `export true`, waits | report open |
| Look-up table browser | `lutwindow open; preset summary …; preset sheets; lutwindow close; wait 1; preset sheets; preset windowshot $Q/m7.png` | `lookTables true`, waits | report open |
| Summary alert (plain preset file) | `preset summary $P/Plain.guspreset; preset sheets; preset summary $P/MadeUp.lnpc; preset sheets; preset close summary; wait 1; preset sheets; preset windowshot $Q/m8.png` | `importSummary true`, waits | report open |

A first run of the delete-confirmation row printed `sidebarDeletion false`: `smartalbum` creates its album after the
command returns, so `sheet deletesmart` had nothing to delete. The `wait 1` after it fixed the script, not the app.
All eight snapshots are byte-identical (same hash) and I looked at one of them, `m1.png`: the Import Report page for the
made-up pack (Back and title, summary line, "Made Up Pack" header with "2 presets · 1 look-up table", Golden Test "5
mapped", the long preset "1 mapped, 1 approximated, 6 left out", the "Preset 3" row with a warning symbol, Done).
With no other modal up the manager opens at once on the report (S1 to S6 print `presets true … attached 1`).
Not covered by a script (the script awaits each import): a second import started while the first runs (P4).

**S8, the preset applied (AC3).** `wait 2; focus 0; selectall; key return; wait 2; print loupe; snapshot $Q/ap-before.png;
preset import $P/MadeUp.lnpc; preset apply Golden Test; wait 3; print previews; snapshot $Q/ap-after.png`. `print loupe`:
"mode loupe"; after the apply the stack hash is `9611b4ee0663` (before `6c76a50e5dc3`), saved, with a memory and a disk
preview. Both snapshots looked at: after, the photo is brighter (+0.4 EV from Exposure 20), a little warmer and with
darker corners. The table is an identity cube, so its effect is not visible; the intensity is what the unit test checks.

**S9, nothing of the format's in the bundle (AC10).** `plutil -p build/Gus.app/Contents/Info.plist` and the same for
`build/Gus Importer.app`: no `lnpc` in either; `UTExportedTypeDeclarations` hold only `me.sesser.gus.versions` and
`me.sesser.gus.preset`. `grep -r -i -l -E "luminar|skylum"` over both bundles: no file. `find` for `*.lnp*` and `*.lmps`
in the bundle: none. `git grep -i -E "luminar|skylum|lnpc"` outside `docs/`: only the source and tests of this feature
(type names, the table, made-up fixtures) and the catalog's format-list entries that say `.lnpc`.

**S10, rerun on b235516 after design §13 (Q1, AC6, AC7, code review F2, C7, C9, C10).** A new bundle copy
(`build/Gus.app` rebuilt, id `me.sesser.gus.debugtest`, ad hoc signed), fresh library copies, every launch with
`--library-root`.
- The owner's four packs, as S5 (`… preset reportpage; wait 1; preset windowshot $Q/real-report2.png; preset`):
  "4 packs · 40 presets · 36 look-up tables added", nothing refused. **Heritage Hues "3 mapped, 5 approximated"**, "Mapped:
  LUT Mapping, Color Toning, and Develop", "Approximated: LUT Mapping (as Contrast and Saturation), Matte Look (as Tone Curve
  and Saturation), Supercontrast (as Tone Curve), Vividness (as Vibrance), and Warmth (as Color Grading)"; Freedom "3 mapped,
  3 approximated, 1 left out"; Americana still "4 mapped". "LUT Mapping" is now under Mapped in all 36 presets with a table,
  and also under Approximated in the 24 with contrast or saturation. Heritage Hues' groups are unchanged (`[Tone, Presence,
  Tone Curve, Color Grading, Look-Up Table]`). The snapshot (looked at) is the collapsed page with the new counts. The four
  packs had the same size and modification time afterwards.
- A made-up pack with a table with contrast 15 and saturation -10, and one whose table is not a cube with contrast 20
  (`TableContrast.lnpc`, made with the same Python helper as S0): `wait 2; preset import $Q/packs/TableContrast.lnpc; preset`:
  "Table With Contrast: 1 mapped, 1 approximated" (Mapped: LUT Mapping; Approximated: LUT Mapping (as Contrast and
  Saturation)); **"Unreadable Table: 1 approximated, 1 left out"** (Approximated: LUT Mapping (as Contrast and Saturation);
  Left out: LUT Mapping), the same as in the first run, groups `[Tone]` only.
- The eight modal sources of S7, the same scripts: with the source up "presets false page report waits true attached 1"
  and only that source true (the sidebar delete confirmation and the summary alert also before the import: page list);
  after closing, "presets true page report waits false attached 1". Remove from Library and Remove Project: `gen=4`
  after Cancel. The eight snapshots are byte-identical to S7's (same hash), which I looked at.

**End checks (both runs).** No `Gus` process was running at the end (`pgrep -x Gus`); nothing in `~/Library/Application
Support/Gus` was newer than the marker made before the first launch; the four packs in `~/Projects/luminar-presets`
had the same size and modification time as before; `git status` was clean.

## For a person

Status: P1 to P5 were done by the owner on 2026-11-18 on a scratch library, all fine ("P1-5 all check out"), on bdaf297. None is open. The steps are kept as run.

The owner is not asked for VoiceOver, macOS 15 or macOS 26 (project memory), so M10 is not on this list (see below).
To build the bundle and run it on a scratch library of four photos, never the real one:

```
cd ~/Projects/Gus
Scripts/build-app.sh
mkdir -p /tmp/gus-qa
swift run -c release photobench generate --output /tmp/gus-qa/gen --jpeg 4 --dng 0 --heic 0 --pairs 0 --videos 0
mkdir -p /tmp/gus-qa/lib
swift run -c release photobench import --library-root /tmp/gus-qa/lib --source /tmp/gus-qa/gen
cp -R build/Gus.app /tmp/gus-qa/Gus.app
plutil -replace CFBundleIdentifier -string me.sesser.gus.debugtest /tmp/gus-qa/Gus.app/Contents/Info.plist
codesign --force --deep --sign - /tmp/gus-qa/Gus.app
open -n /tmp/gus-qa/Gus.app --args --library-root /tmp/gus-qa/lib
```

Every launch needs `--library-root`; without it the app opens the real library. Use your four packs in
`~/Projects/luminar-presets` (read only) for P1, P2, P4 and P5, and any plain `.guspreset`, `.lrtemplate` or `.xmp` for P1.

- **P1 (M1, M4, M5, M6, M11), the panel and the three ways in.** Adjust ▸ Import Presets…: the panel lets you choose
  `.lnpc` files (not greyed out), four at once, and a folder of them; its message names `.lnpc`. Choose the four packs:
  the manager opens on the Import Report, no alert. Back shows four collections of ten presets; the look-up tables are
  in four collections of the same names (Browse Look-Up Tables…). Close the manager and open it again: the **Import
  Report** button is there and shows the last report. Import the same four again: each pack header says "replaced",
  nothing doubles in the list. Repeat once from the Presets heading's **Import…** button. Then choose one pack, one
  damaged or renamed text file (`something.lnpc`) and one `.guspreset` together: the pack imports, the bad file is under
  Not imported with its reason, the plain preset is under Other presets, and no alert appears.
- **P2 (M2, M3, M7), the page's look and keys.** On the four-pack report: look in Dark and with Increase Contrast (System
  Settings ▸ Accessibility ▸ Display) and with Reduce Transparency; long names truncate at the tail with a tooltip and
  tool lines wrap at the sheet's width. Click a preset's arrow: Mapped, Approximated and Left out lines with symbols
  and words, nothing red or green. Include a table preset with a contrast setting (American Dream's Heritage Hues:
  "3 mapped, 5 approximated", "LUT Mapping" under Mapped and again, "as Contrast and Saturation", under Approximated):
  the two lines read as one tool whose table was carried and whose contrast was approximated, with the count line
  matching the entries. With Full Keyboard Access on: Tab reaches Back, the rows and Done; arrows move
  between rows; Right, Left or Space open and close a row (design review's risk: the page's `List` has no selection, so
  this may not work, and if it does not that goes back as a Design question); Esc goes Back and does not close the
  sheet; ⌘[ is Back; Return is Done. For "Not recognized" you need a pack with an unknown tool: not in your four, so
  use `MadeUp.lnpc` from the script above (S1) if you want it (the identifier line must be monospaced, unaltered, wrap
  at its commas, and be selectable and copyable).
- **P3 (M8), Finder.** Double-click a `.lnpc` in the Finder, and drag one onto the app's Dock icon: neither opens or
  imports into the app (the app has no file type for it).
- **P4 (M9 narrowed, M12), the report and other sheets, the busy state.** Choose the four packs and press ⇧⌘E at once,
  in the second after the panel closes (needs a selected photo): the Export sheet stays; Cancel it; the manager then
  opens on the report with nothing doubled. Repeat with Browse Look-Up Tables…. Quick; the scripts (S7) cover every
  other source and the model's rules, not a real key or the system's real close timing. Also, with the manager open,
  choose Import… twice in a row with the four packs: **Import…** is dimmed with "Importing…" while one runs, and Done
  during an import does not leave the sheet stuck.
- **P5 (AC12), the eye comparison.** Import a sample of your presets (for example one with a table and a Supercontrast,
  one black and white, one with Warmth) and apply each to a photo you have; compare with the same preset's look from the
  prototype's output (`~/Projects/luminar-presets/gus-presets/*.guspreset`, opened in the same scratch library) on the
  same photo. The numbers already agree for 40 of 40 presets (S5); this is the check that the look is as you expect.
  Q1's wording (a table with a contrast setting under both statuses) is part of P2's look.
- **M10 (not for the owner).** Accessibility of the page by reading: headings, a status line as one element, the spoken
  summary. Not checked by an assistive app here, and not asked of the owner. The design review passed it by reading
  `PresetImportReportPage` and `AccessibilityText.announce`.

## Follow-up

Reruns after fixes and the owner's sign-off are recorded here.

- **Rerun, 2026-11-17, on b235516** (design §13 in 50b582f; design review's second confirmation, code review's fifth
  pass, status and guide fixes up to b235516). `swift test`: 1137 tests in 170 suites pass (one more than before: the new
  count test), `Scripts/build-app.sh` succeeds, `git status` clean, no warnings. Opt-in four-pack suite: 40 of 40 match
  the prototype, 2 tests pass. Script checks S10.
- **Q1: Fixed.** Heritage Hues reads "3 mapped, 5 approximated" with LUT Mapping under both statuses; every preset with a
  table lists it as mapped; the unreadable-table case is unchanged ("1 approximated, 1 left out"); the eight modal-source
  waits still pass; no value, group or pack count changed. AC1 to AC11 still Pass (the counts above are unchanged: 11
  Pass, 1 Open for a person, 0 Fail).
- P1 to P5: were open here; superseded by the owner's sign-off below (all done 2026-11-18). P2 included a table preset with a contrast setting.
- **Owner's sign-off, 2026-11-18, on bdaf297** (HEAD of `feature/luminar-preset-import`, the commit after the rerun
  above; it changes only docs). The owner did P1 to P5 by hand on a scratch library, including P5's eye comparison
  (AC12), and wrote: "P1-5 all check out. Sign off on this feature." P1 to P5 are done; AC12 is therefore closed (12
  Pass, 0 Open, 0 Fail). Checks left open: none. VoiceOver and macOS 15 and 26 are never asked of the owner (CI covers
  the two systems), so they are not open items here.
