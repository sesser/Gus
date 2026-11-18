import Foundation
import Testing
@testable import PhotoCore

@Suite("Zip archives")
struct ZipArchiveTests {
    @Test func readsStoredAndDeflatedMembers() throws {
        let text = Data(String(repeating: "a look-up table line 0.5 0.25 0.125\n", count: 400).utf8)
        let data = ZipWriter.archive([
            .init(path: "dir/stored.txt", data: text, deflated: false),
            .init(path: "dir/deflated.txt", data: text, deflated: true),
            .init(path: "empty.txt", data: Data(), deflated: false),
        ])
        let archive = try ZipArchive(data: data)
        #expect(archive.entries.map(\.path) == ["dir/stored.txt", "dir/deflated.txt", "empty.txt"])
        let deflated = try #require(archive.entries.first { $0.path == "dir/deflated.txt" })
        #expect(deflated.compressedSize < text.count)
        for entry in archive.entries.prefix(2) { #expect(try archive.contents(of: entry) == text) }
        #expect(try archive.contents(of: archive.entries[2]).isEmpty)
    }

    @Test func checksCRCAndRefusesWhatItCannotRead() throws {
        let data = ZipWriter.archive(["a.txt": Data("hello hello hello".utf8)], deflated: false)
        var corrupted = data
        // The member's first byte (after the 30-byte header and the 5-byte name).
        corrupted[35] ^= 0xFF
        let archive = try ZipArchive(data: corrupted)
        #expect(throws: ZipArchive.Failure.damaged) { try archive.contents(of: archive.entries[0]) }

        #expect(throws: ZipArchive.Failure.notAZip) { try ZipArchive(data: Data("not a zip at all".utf8)) }
        #expect(throws: ZipArchive.Failure.notAZip) { try ZipArchive(data: Data()) }
        // Cut short: the central directory is gone.
        #expect(throws: ZipArchive.Failure.damaged) { try ZipArchive(data: data.prefix(data.count - 30)) }
        #expect(throws: ZipArchive.Failure.damaged) { try ZipArchive(data: data.prefix(40)) }

        // A ZIP64 end record (65535 entries) is beyond what is read.
        var zip64 = data
        let end = zip64.count - 22
        zip64[end + 10] = 0xFF
        zip64[end + 11] = 0xFF
        #expect(throws: ZipArchive.Failure.tooLarge) { try ZipArchive(data: zip64) }
    }

    /// The central directory's fields of the first member, at their offsets, rewritten.
    static func patched(_ data: Data, central offset: Int, _ bytes: [UInt8]) -> Data {
        var data = data
        let end = data.count - 22
        let directory = Int(data[end + 16]) | Int(data[end + 17]) << 8 | Int(data[end + 18]) << 16 | Int(data[end + 19]) << 24
        for (index, byte) in bytes.enumerated() { data[directory + offset + index] = byte }
        return data
    }

    /// The reader's limits and refusals, each checked (code review C3).
    @Test func refusesWhatIsOverItsLimitsOrUnsupported() throws {
        let data = ZipWriter.archive(["a.txt": Data("hello hello hello".utf8)], deflated: false)
        // Declared size one byte over the member limit (central directory, uncompressed size at +24).
        let size = UInt32(ZipArchive.maximumMemberSize + 1)
        let huge = Self.patched(data, central: 24, [UInt8(size & 0xFF), UInt8(size >> 8 & 0xFF),
                                                    UInt8(size >> 16 & 0xFF), UInt8(size >> 24)])
        let hugeArchive = try ZipArchive(data: huge)
        #expect(throws: ZipArchive.Failure.tooLarge) { try hugeArchive.contents(of: hugeArchive.entries[0]) }
        // Encrypted (flags at +8, bit 0).
        let encrypted = try ZipArchive(data: Self.patched(data, central: 8, [0x01, 0x00]))
        #expect(throws: ZipArchive.Failure.unsupported) { try encrypted.contents(of: encrypted.entries[0]) }
        // A method other than stored or deflate (method at +10; 12 is bzip2).
        let bzip2 = try ZipArchive(data: Self.patched(data, central: 10, [12, 0]))
        #expect(throws: ZipArchive.Failure.unsupported) { try bzip2.contents(of: bzip2.entries[0]) }
        // More members than the limit (the end record's count at +10), refused before the directory is walked.
        var many = data
        let count = UInt16(ZipArchive.maximumEntryCount + 1)
        many[many.count - 22 + 10] = UInt8(count & 0xFF)
        many[many.count - 22 + 11] = UInt8(count >> 8)
        #expect(throws: ZipArchive.Failure.tooLarge) { try ZipArchive(data: many) }
        // Each maps to the pack's reason.
        #expect(LuminarPack.Failure(.unsupported) == .damaged)
        #expect(LuminarPack.Failure(.tooLarge) == .tooLarge)
    }

    @Test func truncatedDeflateIsDamaged() throws {
        let text = Data((0..<3000).map { "\($0 % 97) 0.2 0.3\n" }.joined().utf8)
        let deflated = ZipWriter.deflate(text)
        var data = ZipWriter.archive([ZipWriter.Member(path: "a.txt", data: text)])
        // The second half of the deflated stream zeroed, its sizes unchanged.
        let start = 30 + 5
        for index in (start + deflated.count / 2)..<(start + deflated.count) { data[index] = 0 }
        let archive = try ZipArchive(data: data)
        #expect(archive.entries[0].uncompressedSize == text.count)
        #expect(throws: ZipArchive.Failure.damaged) { try archive.contents(of: archive.entries[0]) }
    }
}

@Suite("Strings tables")
struct StringsTableTests {
    @Test func readsTheEncodingsPacksUse() {
        let text = "/* note */ \"Pack Name\" = \"Amerikanischer Traum – ü\"; // trailing\n\"b\"\t=\t\"2\" ;"
        let expected = ["Pack Name": "Amerikanischer Traum – ü", "b": "2"]
        #expect(StringsTable.parse(Data(text.utf8)) == expected)
        #expect(StringsTable.parse(text.data(using: .utf16)!) == expected)
        #expect(StringsTable.parse(text.data(using: .utf16LittleEndian)!) == expected)
        #expect(StringsTable.parse(text.data(using: .utf16BigEndian)!) == expected)
        #expect(StringsTable.parse(Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)) == expected)
        #expect(StringsTable.parse(Data("\"a\" = \"1\"; \"a\" = \"2\";".utf8)) == ["a": "2"])
        #expect(StringsTable.parse(Data("\"a\" = \"b\"".utf8)) == nil)
        #expect(StringsTable.parse(Data("hello".utf8)) == nil)
    }
}

@Suite("Preset packs: reading")
struct PresetPackReadingTests {
    @Test func readsPresetsInThePacksOrderWithTheirTables() throws {
        let packs = try LuminarPack.read(PackFixture.packData(), fileName: "Test_Pack.lnpc", language: "en")
        let pack = try #require(packs.first)
        #expect(packs.count == 1)
        #expect(pack.name == "Test Pack")
        #expect(pack.presets.map(\.name) == ["Beta", "Alpha"])
        #expect(pack.presets[1].resources == ["TABLE.CUBE": PackFixture.identityCube])
        #expect(pack.presets[1].uuid == "11111111-0000-0000-0000-000000000000")
        #expect(pack.presets[0].resources.isEmpty)
    }

    @Test func namesFollowTheLanguageWhenThePackHasIt() throws {
        let german = try #require(try LuminarPack.read(PackFixture.packData(), fileName: "p.lnpc", language: "de").first)
        #expect(german.name == "Testpaket")
        #expect(german.presets.map(\.name) == ["Beta", "Alfa"])
        let french = try #require(try LuminarPack.read(PackFixture.packData(), fileName: "p.lnpc", language: "fr").first)
        #expect(french.name == "Test Pack")
        #expect(french.presets.map(\.name) == ["Beta", "Alpha"])
    }

    @Test func anUntranslatedNameFallsBackToTheFileName() throws {
        var files = PackFixture.files(presets: PackFixture.twoPresets())
        files["\(PackFixture.packID)/localizations/en.strings"] = nil
        files["\(PackFixture.packID)/localizations/de.strings"] = nil
        let pack = try #require(try LuminarPack.read(ZipWriter.archive(files), fileName: "Valley_of_Quiet_Lakes.lnpc",
                                                     language: "en").first)
        #expect(pack.name == "Valley of Quiet Lakes")
    }

    @Test func anUnreadablePresetIsSkippedInItsPlace() throws {
        var files = PackFixture.files(presets: PackFixture.twoPresets(), extraListed: ["33333333-0000-0000-0000-000000000000.lnp"])
        files["\(PackFixture.packID)/22222222-0000-0000-0000-000000000000.lnp/template.lmps"] = Data("{not json".utf8)
        files["\(PackFixture.packID)/44444444-0000-0000-0000-000000000000.lnp/template.lmps"] =
            PackFixture.json(PackFixture.template("Gamma", [PackFixture.tool(.color, PackFixture.effect(
                "MIPLSaturationEffect", PackFixture.param("Saturation", 5)))]))
        let pack = try #require(try LuminarPack.read(ZipWriter.archive(files), fileName: "p.lnpc", language: "en").first)
        let summary = pack.entries.map { entry -> String in
            switch entry {
            case .preset(let preset): preset.name
            case .unreadable(let name): "unreadable \(name ?? "-")"
            }
        }
        // Beta's settings are damaged, the third listed is missing, Gamma is not listed (it follows).
        #expect(summary == ["unreadable -", "Alpha", "unreadable -", "Gamma"])
    }

    @Test func hiddenAndEscapingMembersAreIgnored() throws {
        var files = PackFixture.files(presets: PackFixture.twoPresets())
        files["__MACOSX/._x"] = Data("junk".utf8)
        files["\(PackFixture.packID)/.DS_Store"] = Data("junk".utf8)
        files["../evil.lnp/template.lmps"] = PackFixture.json(PackFixture.template("Evil", []))
        files["/abs.lnp/template.lmps"] = PackFixture.json(PackFixture.template("Absolute", []))
        let packs = try LuminarPack.read(ZipWriter.archive(files), fileName: "p.lnpc", language: "en")
        #expect(packs.flatMap(\.presets).map(\.name) == ["Beta", "Alpha"])
    }

    /// AC8: each refusal has its reason, distinct in PhotoCore even where the app words two alike.
    @Test func refusesWhatIsNotAReadablePack() throws {
        func failure(_ data: Data) -> LuminarPack.Failure? {
            do {
                _ = try LuminarPack.read(data, fileName: "x.lnpc", language: "en")
                return nil
            } catch {
                return error as? LuminarPack.Failure
            }
        }
        let good = PackFixture.packData()
        #expect(failure(good) == nil)
        #expect(failure(good.prefix(good.count / 2)) == .damaged)
        #expect(failure(Data("PK not really".utf8)) == .notAZip)
        #expect(failure(Data("a text file".utf8)) == .notAZip)

        var noConfig = PackFixture.files(presets: PackFixture.twoPresets())
        noConfig["Config/config.json"] = nil
        #expect(failure(ZipWriter.archive(noConfig)) == .missingConfig)
        #expect(failure(ZipWriter.archive(["readme.txt": Data("x".utf8)])) == .missingConfig)

        var badConfig = PackFixture.files(presets: PackFixture.twoPresets())
        badConfig["Config/config.json"] = Data("{".utf8)
        #expect(failure(ZipWriter.archive(badConfig)) == .unreadableSettings)

        #expect(failure(ZipWriter.archive(PackFixture.files(presets: []))) == .noPresets)

        var allBroken = PackFixture.files(presets: PackFixture.twoPresets())
        for key in allBroken.keys where key.hasSuffix("template.lmps") { allBroken[key] = Data("[]".utf8) }
        #expect(failure(ZipWriter.archive(allBroken)) == .unreadableSettings)
    }

    /// The decompression budget of one file (code review C3).
    @Test func refusesAPackOverItsReadBudget() throws {
        let data = PackFixture.packData()
        #expect(try LuminarPack.read(data, fileName: "p.lnpc", language: "en").count == 1)
        #expect(throws: LuminarPack.Failure.tooLarge) {
            try LuminarPack.read(data, fileName: "p.lnpc", language: "en", readBudget: 200)
        }
    }

    /// Configurations, templates and `.strings` larger than the text limit are refused before they are
    /// decompressed or parsed (code review C8); a table is not text and only has the member limit.
    @Test func refusesTextMembersOverTheTextLimit() throws {
        #expect(LuminarPack.maximumTextSize == 4 * 1024 * 1024)
        var files = PackFixture.files(presets: PackFixture.twoPresets())
        let table = "\(PackFixture.packID)/11111111-0000-0000-0000-000000000000.lnp/resources/TABLE.CUBE"
        var textSizes: [Int] = []
        for (path, data) in files where !path.hasSuffix(".CUBE") && !path.hasSuffix(".jpg") { textSizes.append(data.count) }
        let limit = textSizes.max() ?? 0
        // A table larger than the text limit reads.
        files[table] = Data(String(repeating: "# padding\n", count: limit).utf8) + PackFixture.identityCube
        let pack = try #require(try LuminarPack.read(ZipWriter.archive(files), fileName: "p.lnpc", language: "en",
                                                     textLimit: limit).first)
        #expect(pack.presets.count == 2)
        #expect((pack.presets[1].resources["TABLE.CUBE"]?.count ?? 0) > limit)

        let texts = ["Config/config.json", "\(PackFixture.packID)/config.json",
                     "\(PackFixture.packID)/11111111-0000-0000-0000-000000000000.lnp/template.lmps",
                     "\(PackFixture.packID)/localizations/en.strings"]
        for path in texts {
            var oversized = files
            // Trailing spaces: still valid, one byte over the limit.
            oversized[path] = (files[path] ?? Data()) + Data(repeating: 0x20, count: limit + 1 - (files[path]?.count ?? 0))
            #expect(throws: LuminarPack.Failure.tooLarge, "\(path)") {
                try LuminarPack.read(ZipWriter.archive(oversized), fileName: "p.lnpc", language: "en", textLimit: limit)
            }
        }
    }

    /// A list can name far more presets than the archive holds: refused before any row is made (code review C1).
    @Test func refusesAPackListingTooManyPresets() throws {
        var files = PackFixture.files(presets: PackFixture.twoPresets(),
                                      extraListed: Array(repeating: "", count: LuminarPack.maximumPresetCount))
        #expect(throws: LuminarPack.Failure.tooLarge) {
            try LuminarPack.read(ZipWriter.archive(files), fileName: "p.lnpc", language: "en")
        }
        files = PackFixture.files(presets: PackFixture.twoPresets(),
                                  extraListed: Array(repeating: "", count: LuminarPack.maximumPresetCount - 2))
        let pack = try #require(try LuminarPack.read(ZipWriter.archive(files), fileName: "p.lnpc", language: "en").first)
        #expect(pack.entries.count == LuminarPack.maximumPresetCount)
        #expect(pack.presets.count == 2)
    }

    /// The file is read only when it is a regular file, links followed, and never past the limit (code review C2, C3).
    @Test func readsOnlyRegularFilesWithinTheLimit() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let manager = FileManager.default
            let file = root.appending(path: "big.lnpc")
            try Data(repeating: 7, count: 64).write(to: file)
            #expect(try LuminarPack.contents(of: file, limit: 64).count == 64)
            #expect(throws: LuminarPack.Failure.tooLarge) { try LuminarPack.contents(of: file, limit: 63) }
            // A link reports its own small size; the file it leads to is what counts.
            let link = root.appending(path: "link.lnpc")
            try manager.createSymbolicLink(at: link, withDestinationURL: file)
            #expect(throws: LuminarPack.Failure.tooLarge) { try LuminarPack.contents(of: link, limit: 63) }
            #expect(try LuminarPack.contents(of: link, limit: 64).count == 64)
            // Not a regular file: a folder, a link to one, a device.
            let folder = root.appending(path: "folder.lnpc")
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            let folderLink = root.appending(path: "folder-link.lnpc")
            try manager.createSymbolicLink(at: folderLink, withDestinationURL: folder)
            let device = root.appending(path: "device.lnpc")
            try manager.createSymbolicLink(at: device, withDestinationURL: URL(fileURLWithPath: "/dev/zero"))
            for url in [folder, folderLink, device] {
                #expect(throws: LuminarPack.Failure.notAZip) { try LuminarPack.contents(of: url, limit: 1 << 20) }
            }
            // A folder import lists the file and the link to it, never the others.
            let found = PresetImport.files(in: root).map(\.lastPathComponent)
            #expect(found == ["big.lnpc", "link.lnpc"])
        }
    }

    /// AC8 and R9: the archive is read in memory; the code that reads it writes no file anywhere.
    @Test func packCodeWritesNoFiles() throws {
        let root = RepositoryFiles.root
        let folder = root.appending(path: "Sources/PhotoCore/Presets/Luminar")
        var sources = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        sources.append(root.appending(path: "Sources/PhotoCore/Support/ZipArchive.swift"))
        #expect(sources.count >= 6)
        let writing = ["write(to", "createFile", "createDirectory", "temporaryDirectory", "NSTemporaryDirectory",
                       "FileHandle(forWriting", "moveItem", "copyItem", "Process("]
        for source in sources {
            let text = try String(contentsOf: source, encoding: .utf8)
            for call in writing { #expect(!text.contains(call), "\(source.lastPathComponent) uses \(call)") }
        }
    }
}
