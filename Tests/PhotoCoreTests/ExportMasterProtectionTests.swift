import Foundation
import ImageIO
import PhotoFixtures
import Testing
@testable import PhotoCore

// Issue #160: an export never writes over a catalogued master, whatever the
// policy for existing files says.

@Suite("Export naming: masters are never replaced")
struct ExportMasterNamingTests {
    let folder = URL(fileURLWithPath: "/shoot")
    let settings = ExportSettings()

    func context(_ name: String) -> TemplateContext {
        ExportNamingTests().context(name)
    }

    func file(_ name: String) -> URL {
        folder.appending(path: name, directoryHint: .notDirectory)
    }

    func exists(_ names: Set<String>) -> (URL) -> Bool {
        { names.contains($0.lastPathComponent) }
    }

    @Test func aPhotoExportedOverItsOwnMasterGetsANumberedName() {
        let masters = MasterFiles([file("a.jpg")])
        let plan = ExportNaming.entries([context("a.jpg")], settings: settings, in: folder, policy: .overwrite,
                                        masters: masters, fileExists: exists(["a.jpg"]))
        #expect(plan == [ExportPlanEntry(destination: .write(file("a-2.jpg"), replacing: false), nameExists: true,
                                         isMaster: true)])
    }

    @Test func anotherPhotosMasterIsNotReplacedEither() {
        // a.NEF exports as a.jpg, which is the master of a photo that is not in the batch.
        let masters = MasterFiles([file("a.NEF"), file("a.jpg")])
        let plan = ExportNaming.plan([context("a.NEF")], settings: settings, in: folder, policy: .overwrite,
                                     masters: masters, fileExists: exists(["a.NEF", "a.jpg"]))
        #expect(plan == [.write(file("a-2.jpg"), replacing: false)])
    }

    @Test func numberedNamesAvoidMastersAndExistingFiles() {
        // a-2.jpg is an ordinary file and a-3.jpg a master whose file is gone:
        // the fallback neither replaces the one nor takes the other's place.
        let masters = MasterFiles([file("a.jpg"), file("a-3.jpg")])
        for policy in [ExportConflictPolicy.overwrite, .keepBoth] {
            let plan = ExportNaming.plan([context("a.NEF")], settings: settings, in: folder, policy: policy,
                                         masters: masters, fileExists: exists(["a.jpg", "a-2.jpg"]))
            #expect(plan == [.write(file("a-4.jpg"), replacing: false)], "\(policy)")
        }
    }

    @Test func namesMatchAsTheFileSystemComparesThem() {
        // Case, and composed against decomposed accents.
        let masters = MasterFiles([file("IMG_1.JPG"), file("Caf\u{E9}.jpg")])
        let contexts = [context("img_1.NEF"), context("Cafe\u{301}.NEF")]
        let plan = ExportNaming.plan(contexts, settings: settings, in: folder, policy: .overwrite, masters: masters,
                                     fileExists: exists(["img_1.jpg", "Cafe\u{301}.jpg"]))
        #expect(plan == [.write(file("img_1-2.jpg"), replacing: false),
                         .write(file("Cafe\u{301}-2.jpg"), replacing: false)])
    }

    @Test func anOrdinaryFileIsStillReplaced() {
        // b.jpg exists and is no master; a master of that name in another folder changes nothing.
        let masters = MasterFiles([file("a.jpg"), URL(fileURLWithPath: "/elsewhere/b.jpg")])
        let entries = ExportNaming.entries([context("a.NEF"), context("b.NEF")], settings: settings, in: folder,
                                           policy: .overwrite, masters: masters, fileExists: exists(["a.jpg", "b.jpg"]))
        #expect(entries.map(\.destination) == [.write(file("a-2.jpg"), replacing: false),
                                               .write(file("b.jpg"), replacing: true)])
        #expect(entries.map(\.isMaster) == [true, false])
    }

    @Test func skipLeavesAnExistingMasterAndKeepBothNumbersIt() {
        let masters = MasterFiles([file("a.jpg")])
        let taken = exists(["a.jpg"])
        #expect(ExportNaming.plan([context("a.NEF")], settings: settings, in: folder, policy: .skip, masters: masters,
                                  fileExists: taken) == [.skip(file("a.jpg"))])
        #expect(ExportNaming.plan([context("a.NEF")], settings: settings, in: folder, policy: .keepBoth,
                                  masters: masters, fileExists: taken) == [.write(file("a-2.jpg"), replacing: false)])
    }

    @Test func aMissingMastersPlaceIsNotTaken() {
        // The master's file is gone (deleted, or its volume's folder emptied):
        // nothing to skip or replace, and still nothing is written in its place.
        let masters = MasterFiles([file("a.jpg")])
        for policy in ExportConflictPolicy.allCases {
            let plan = ExportNaming.plan([context("a.NEF")], settings: settings, in: folder, policy: policy,
                                         masters: masters) { _ in false }
            #expect(plan == [.write(file("a-2.jpg"), replacing: false)], "\(policy)")
        }
    }

    @Test func clashesCountExistingFilesAndTheMastersAmongThem() {
        // a.jpg: an existing master. b.jpg: an existing ordinary file. c.jpg: a master with no file. d.jpg: free.
        let masters = MasterFiles([file("a.jpg"), file("c.jpg")])
        let contexts = ["a.NEF", "b.NEF", "c.NEF", "d.NEF"].map(context)
        #expect(ExportNaming.clashes(contexts, settings: settings, in: folder, masters: masters,
                                     fileExists: exists(["a.jpg", "b.jpg"])) == ExportClashes(existing: 2, masters: 1))
    }
}

@Suite("Export naming: a file with a master's content is never replaced")
struct ExportMasterContentNamingTests {
    let folder = URL(fileURLWithPath: "/card/DCIM")
    let settings = ExportSettings()

    func context(_ name: String) -> TemplateContext { ExportNamingTests().context(name) }
    func file(_ name: String) -> URL { folder.appending(path: name, directoryHint: .notDirectory) }

    /// a.jpg and b.jpg exist; a.jpg has a master's content. No place says so.
    func plan(_ policy: ExportConflictPolicy, asked: inout [String]) -> [ExportPlanEntry] {
        var seen: [String] = []
        let entries = ExportNaming.entries(["a.NEF", "b.NEF", "c.NEF"].map(context), settings: settings, in: folder,
                                           policy: policy, masters: .none,
                                           holdsMasterContent: { seen.append($0.lastPathComponent)
                                               return $0.lastPathComponent == "a.jpg" },
                                           fileExists: { ["a.jpg", "b.jpg"].contains($0.lastPathComponent) })
        asked = seen
        return entries
    }

    @Test func replaceNumbersItAndStillReplacesTheOrdinaryFile() {
        var asked: [String] = []
        let entries = plan(.overwrite, asked: &asked)
        #expect(entries == [
            ExportPlanEntry(destination: .write(file("a-2.jpg"), replacing: false), nameExists: true, isMaster: true),
            ExportPlanEntry(destination: .write(file("b.jpg"), replacing: true), nameExists: true, isMaster: false),
            ExportPlanEntry(destination: .write(file("c.jpg"), replacing: false), nameExists: false, isMaster: false),
        ])
        // Only the files that would be replaced are read; a free name is not.
        #expect(asked == ["a.jpg", "b.jpg"])
    }

    @Test func nothingIsReadWhereNothingWouldBeReplaced() {
        var asked: [String] = []
        #expect(plan(.keepBoth, asked: &asked).map(\.destination.url.lastPathComponent) == ["a-2.jpg", "b-2.jpg", "c.jpg"])
        #expect(asked.isEmpty)
        #expect(plan(.skip, asked: &asked).map(\.destination) == [.skip(file("a.jpg")), .skip(file("b.jpg")),
                                                                   .write(file("c.jpg"), replacing: false)])
        #expect(asked.isEmpty)
    }

    @Test func aMasterByPlaceIsNotReadAgain() {
        var asked: [String] = []
        let masters = MasterFiles([file("a.jpg")])
        let plan = ExportNaming.plan([context("a.NEF"), context("b.NEF")], settings: settings, in: folder,
                                     policy: .overwrite, masters: masters,
                                     holdsMasterContent: { asked.append($0.lastPathComponent)
                                         return false },
                                     fileExists: { ["a.jpg", "b.jpg"].contains($0.lastPathComponent) })
        #expect(plan == [.write(file("a-2.jpg"), replacing: false), .write(file("b.jpg"), replacing: true)])
        #expect(asked == ["b.jpg"])
    }

    @Test func theQuestionCountsThemBeforeAPolicyIsChosen() {
        var asked: [String] = []
        let clashes = ExportNaming.clashes(["a.NEF", "b.NEF", "c.NEF"].map(context), settings: settings, in: folder,
                                           masters: .none,
                                           holdsMasterContent: { asked.append($0.lastPathComponent)
                                               return $0.lastPathComponent == "a.jpg" },
                                           fileExists: { ["a.jpg", "b.jpg"].contains($0.lastPathComponent) })
        #expect(clashes == ExportClashes(existing: 2, masters: 1))
        #expect(asked == ["a.jpg", "b.jpg"])
    }
}

@Suite("Master files: a master's content, wherever it is")
struct MasterContentTests {
    /// 4,096 bytes of `byte`, with `last` as the final one.
    func bytes(_ byte: UInt8, last: UInt8? = nil) -> Data {
        var data = Data(repeating: byte, count: 4096)
        if let last { data[4095] = last }
        return data
    }

    func masters(of data: Data) -> MasterFiles {
        MasterFiles([URL](), contents: [MasterFiles.Content(size: Int64(data.count), hash: Digest.sha256Hex(data))])
    }

    @Test func aFileWithAMastersBytesIsOneWhateverItsNameOrPlace() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let original = bytes(7)
            let masters = masters(of: original)
            let copy = root.appending(path: "any name at all.jpg")
            try original.write(to: copy)
            #expect(masters.holdsContent(ofFileAt: copy))
            #expect(!masters.contains(copy), "no place says so")
            // A link to it is followed.
            let link = root.appending(path: "link.jpg")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: copy)
            #expect(masters.holdsContent(ofFileAt: link))
            // Nothing there: nothing to replace.
            #expect(!masters.holdsContent(ofFileAt: root.appending(path: "missing.jpg")))
            #expect(!MasterFiles.none.holdsContent(ofFileAt: copy))
        }
    }

    @Test func theSameSizeWithOtherBytesIsAnOrdinaryFile() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let masters = masters(of: bytes(7))
            let other = root.appending(path: "b.jpg")
            try bytes(7, last: 8).write(to: other)
            #expect(!masters.holdsContent(ofFileAt: other))
            let shorter = root.appending(path: "c.jpg")
            try bytes(7).dropLast().write(to: shorter)
            #expect(!masters.holdsContent(ofFileAt: shorter))
        }
    }

    @Test func aFileIsReadOnlyWhenItsSizeIsAMasters() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let masters = masters(of: bytes(7))
            // Neither file can be read. The one of another size is never opened, so it
            // is known to be ordinary; the one of a master's size can't be told apart
            // from the master and is taken for it.
            let otherSize = root.appending(path: "other-size.jpg")
            try Data(repeating: 1, count: 100).write(to: otherSize)
            let sameSize = root.appending(path: "same-size.jpg")
            try bytes(9).write(to: sameSize)
            for url in [otherSize, sameSize] {
                try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
            }
            defer {
                for url in [otherSize, sameSize] {
                    try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
                }
            }
            #expect(!masters.holdsContent(ofFileAt: otherSize))
            #expect(masters.holdsContent(ofFileAt: sameSize))
        }
    }

    @Test func aReadCutShortByCancellationCountsAsAMaster() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let masters = masters(of: bytes(7))
            let other = root.appending(path: "b.jpg")
            try bytes(7, last: 8).write(to: other)
            let cancelled = await Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return masters.holdsContent(ofFileAt: other)
            }.value
            #expect(cancelled)
            #expect(!masters.holdsContent(ofFileAt: other))
        }
    }

    @Test func aFileOfSeveralChunksHashesAsTheCatalogDoes() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            // Two and a half chunks, no two of them alike, and an empty file.
            var data = Data(count: MasterFiles.hashChunkSize * 5 / 2)
            for index in stride(from: 0, to: data.count, by: 4093) { data[index] = UInt8(truncatingIfNeeded: index / 4093) }
            let file = root.appending(path: "large.tif")
            try data.write(to: file)
            #expect(try MasterFiles.hash(of: file) == Digest.sha256Hex(data))
            #expect(try await SHA256ContentHasher().contentHash(of: file) == MasterFiles.hash(of: file))
            #expect(masters(of: data).holdsContent(ofFileAt: file))
            let empty = root.appending(path: "empty.tif")
            try Data().write(to: empty)
            #expect(try MasterFiles.hash(of: empty) == Digest.sha256Hex(Data()))
            #expect(throws: (any Error).self) { try MasterFiles.hash(of: root.appending(path: "missing.tif")) }
        }
    }

    /// The memory this process is charged with (`phys_footprint`, what Activity Monitor shows).
    func footprint() -> Int64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : nil
    }

    /// C8: a read that fails after the file opened. A folder opens and then can't be
    /// read (EISDIR), which is the one such failure a test can make happen.
    @Test func aFileThatOpensAndCannotBeReadCountsAsAMaster() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let folder = root.appending(path: "IMG_1.jpg", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // EISDIR is `read`'s error: `open` went through, so this is the read's branch.
            #expect { try MasterFiles.hash(of: folder) } throws: { ($0 as? POSIXError)?.code == .EISDIR }
            // Of a master's size, so it is opened: what can't be read is not known to be ordinary.
            let size = try #require((try FileManager.default.attributesOfItem(atPath: folder.path)[.size] as? NSNumber)?
                .int64Value)
            let masters = MasterFiles([URL](), contents: [MasterFiles.Content(size: size, hash: "any")])
            #expect(masters.holdsContent(ofFileAt: folder))
            // Of another size it is never opened, and known to be ordinary.
            let others = MasterFiles([URL](), contents: [MasterFiles.Content(size: size + 1, hash: "any")])
            #expect(!others.holdsContent(ofFileAt: folder))
        }
    }

    /// C6: hashing held every chunk it read until the plan returned (2 GiB for a 2 GiB file).
    /// Other tests run beside this one and move the footprint too, so the file is far
    /// larger than what they take in the time one attempt lasts (1 GiB, sparse: no disk
    /// is used), the limit is half of it, and one quiet attempt of five is enough. Held
    /// chunks would show in every attempt, at about the file's size each (C9: at a
    /// quarter of the file and three attempts this failed without a fault about once
    /// in 300 full runs; the reviewer's samples had no three moments in a row over half).
    @Test func hashingALargeFileHoldsOneChunkNotTheFile() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let size: Int64 = 1 << 30
            let file = root.appending(path: "large.tif")
            #expect(FileManager.default.createFile(atPath: file.path, contents: nil))
            let handle = try FileHandle(forWritingTo: file)
            try handle.truncate(atOffset: UInt64(size))
            try handle.close()
            // Of a master's size and other content: read whole, then found ordinary.
            let masters = MasterFiles([URL](), contents: [MasterFiles.Content(size: size, hash: "not this file's")])
            let limit = size / 2
            var growth: [Int64] = []
            for _ in 0..<5 {
                let before = try #require(footprint())
                #expect(!masters.holdsContent(ofFileAt: file))
                growth.append(try #require(footprint()) - before)
                if growth.last! < limit { break }
            }
            #expect(try #require(growth.min()) < limit, "footprint grew by \(growth) bytes hashing \(size)")
        }
    }

    @Test func theCatalogGivesEveryMastersSizeAndHash() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await ExportJobTests().makeLibrary(root)
            let masters = try await library.catalog.masterFiles()
            let elsewhere = root.appending(path: "Elsewhere", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
            for name in ["a.DNG", "a.jpg", "b.jpg"] {
                let copy = elsewhere.appending(path: "copy of " + name)
                try FileManager.default.copyItem(at: library.folder.appending(path: name), to: copy)
                #expect(masters.holdsContent(ofFileAt: copy), "\(name)")
                #expect(!masters.contains(copy), "\(name)")
            }
        }
    }
}

@Suite("Export clashes: how many of the files in the way are originals")
struct ExportClashOriginalsTests {
    @Test func noneOfThem() {
        #expect(ExportClashes(existing: 3, masters: 0).originals == .none)
        #expect(ExportClashes(existing: 1, masters: 0).originals == .none)
        #expect(ExportClashes().originals == .none)
    }

    @Test func someOfSeveral() {
        #expect(ExportClashes(existing: 3, masters: 1).originals == .some(1))
        #expect(ExportClashes(existing: 3, masters: 2).originals == .some(2))
    }

    @Test func theOneFileInTheWay() {
        #expect(ExportClashes(existing: 1, masters: 1).originals == .theOnlyFile)
    }

    @Test func allOfSeveral() {
        #expect(ExportClashes(existing: 2, masters: 2).originals == .all)
        #expect(ExportClashes(existing: 40, masters: 40).originals == .all)
    }
}

@Suite("Master files")
struct MasterFilesTests {
    /// `root/Real/Shoot/IMG_1.JPG` (an empty file) with `root/Link` pointing at `root/Real`.
    func makeFolders(_ root: URL) throws -> (shoot: URL, master: URL) {
        let shoot = root.appending(path: "Real/Shoot", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        let master = shoot.appending(path: "IMG_1.JPG", directoryHint: .notDirectory)
        try Data().write(to: master)
        try FileManager.default.createSymbolicLink(at: root.appending(path: "Link"),
                                                   withDestinationURL: root.appending(path: "Real"))
        return (shoot, master)
    }

    @Test func aFolderReachedThroughASymbolicLinkIsTheSameFolder() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let (shoot, master) = try makeFolders(root)
            let masters = MasterFiles([master])
            #expect(masters.contains(master))
            #expect(masters.contains(root.appending(path: "Link/Shoot/IMG_1.JPG")))
            #expect(masters.contains(root.appending(path: "Link/Shoot/img_1.jpg")))
            #expect(masters.contains(shoot.appending(path: "../Shoot/IMG_1.JPG")))
            #expect(!masters.contains(root.appending(path: "Link/Shoot/IMG_2.JPG")))
            #expect(!masters.contains(root.appending(path: "Link/IMG_1.JPG")))
            // The other way round: the catalog knows the master by the linked path.
            #expect(MasterFiles([root.appending(path: "Link/Shoot/IMG_1.JPG")]).contains(master))
            #expect(masters.names(in: root.appending(path: "Link/Shoot", directoryHint: .isDirectory))
                .contains("img_1.JPG"))
            #expect(masters.names(in: root).isEmpty)
            // The folder itself is the link, not one on the way to it.
            let direct = root.appending(path: "Direct")
            try FileManager.default.createSymbolicLink(at: direct, withDestinationURL: shoot)
            #expect(masters.contains(direct.appending(path: "IMG_1.JPG")))
            #expect(masters.names(in: direct).contains("IMG_1.JPG"))
            #expect(MasterFiles([direct.appending(path: "IMG_1.JPG")]).contains(master))
        }
    }

    @Test func aFolderSpelledInAnotherCaseIsTheSameWhereTheVolumeSaysSo() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let (_, master) = try makeFolders(root)
            let caseSensitive = try root.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
                .volumeSupportsCaseSensitiveNames ?? false
            let masters = MasterFiles([master])
            // On a case-sensitive volume `real/SHOOT` is another folder (one that does not exist).
            #expect(masters.contains(root.appending(path: "real/SHOOT/IMG_1.JPG")) == !caseSensitive)
        }
    }

    @Test func foldersThatDoNotExistCompareAsWritten() async {
        await RepositoryFiles.withTemporaryDirectory { root in
            let masters = MasterFiles([root.appending(path: "Gone/Sub/a.jpg")])
            #expect(masters.contains(root.appending(path: "Gone/Sub/A.JPG")))
            #expect(masters.contains(root.appending(path: "gone/sub/a.jpg")))
            #expect(!masters.contains(root.appending(path: "Gone/a.jpg")))
            #expect(!MasterFiles.none.contains(root.appending(path: "Gone/Sub/a.jpg")))
            #expect(MasterFiles.none.isEmpty && !masters.isEmpty)
        }
    }

    @Test func theCatalogListsEveryMasterWhereExportReadsIt() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await ExportJobTests().makeLibrary(root)
            let masters = try await library.catalog.masterFiles()
            for name in ["a.DNG", "a.jpg", "b.jpg"] {
                #expect(masters.contains(library.folder.appending(path: name)), "\(name)")
            }
            #expect(!masters.contains(library.folder.appending(path: "c.jpg")))
            #expect(!masters.contains(library.output.appending(path: "a.jpg")))
            #expect(try await Catalog.makeInMemory().masterFiles().isEmpty)
        }
    }
}

@Suite("Master files: volumes mounted elsewhere than recorded")
struct MasterFilesMountTests {
    func file(_ path: String) -> URL { URL(fileURLWithPath: path) }

    @Test func aVolumeIsPlacedWhereItIsMountedNowAndWhereItWasRecorded() async throws {
        // The fixture's volume: identity TEST-VOLUME, recorded at /Volumes/Test.
        let fixture = try await CatalogFixture.make()
        try await fixture.addMasters([CatalogFixture.master(1, path: "shoot/IMG_0001.CR3"),
                                      CatalogFixture.master(2, path: "IMG_0002.CR3")])
        let recordedOnly = try await fixture.catalog.masterFiles(mounted: [])
        #expect(recordedOnly.contains(file("/Volumes/Test/shoot/IMG_0001.CR3")))
        #expect(!recordedOnly.contains(file("/Volumes/Test 1/shoot/IMG_0001.CR3")))

        // The same volume is now at /Volumes/Test 1 and, a share mounted twice, at /Volumes/Again.
        let mounted = [VolumeDescriptor(identity: "TEST-VOLUME", name: "Test", mountPath: "/Volumes/Test 1"),
                       VolumeDescriptor(identity: "TEST-VOLUME", name: "Test", mountPath: "/Volumes/Again"),
                       VolumeDescriptor(identity: "ANOTHER", name: "Other", mountPath: "/Volumes/Other")]
        let masters = try await fixture.catalog.masterFiles(mounted: mounted)
        for mount in ["/Volumes/Test 1", "/Volumes/Again", "/Volumes/Test"] {
            #expect(masters.contains(file(mount + "/shoot/IMG_0001.CR3")), "\(mount)")
            #expect(masters.contains(file(mount + "/shoot/img_0001.cr3")), "\(mount)")
            // A master at the volume's root.
            #expect(masters.contains(file(mount + "/IMG_0002.CR3")), "\(mount)")
        }
        #expect(!masters.contains(file("/Volumes/Other/shoot/IMG_0001.CR3")))
        // Asking changes nothing in the catalog: export is a read.
        #expect(try await fixture.catalog.volumes().map(\.mountPath) == ["/Volumes/Test"])
    }
}

@Suite("Export job: masters are never replaced")
struct ExportMasterProtectionTests {
    var settings: ExportSettings {
        var settings = ExportSettings()
        settings.sizing = .longEdge
        settings.edgeLength = 100
        return settings
    }

    /// Every file in `folder`, by name.
    func contents(of folder: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) {
            result[name] = try Data(contentsOf: folder.appending(path: name, directoryHint: .notDirectory))
        }
        return result
    }

    func longEdge(_ url: URL) -> Int? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return max(image.width, image.height)
    }

    @Test("Replace into the photos' own folder leaves every master as it was")
    func replacingInTheSourceFolderWritesNumberedNames() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await ExportJobTests().makeLibrary(root)
            let before = try contents(of: library.folder)
            #expect(Set(before.keys) == ["a.DNG", "a.jpg", "b.jpg"])
            // The pair exports from a.DNG as a.jpg, its partner's master; b.jpg exports over itself.
            let ids = ExportTargets.resolve(try await library.items()).versionIDs
            let request = ExportRequest(versionIDs: ids, settings: settings, destination: library.folder,
                                        policy: .overwrite)
            let clashes = try await library.job.clashes(for: try await library.job.items(for: ids), settings: settings,
                                                        in: library.folder)
            #expect(clashes == ExportClashes(existing: 2, masters: 2))

            let summary = await library.job.run(request)
            #expect(summary.failures.isEmpty && summary.protectedMasters == 2)
            #expect(Set(summary.written.map(\.lastPathComponent)) == ["a-2.jpg", "b-2.jpg"])
            let after = try contents(of: library.folder)
            for (name, data) in before {
                #expect(after[name] == data, "\(name) was changed")
            }
            #expect(longEdge(library.folder.appending(path: "b-2.jpg")) == 100)

            // Again: the earlier exports are ordinary files, but the photos' first
            // names are still the masters', so nothing is replaced.
            let again = await library.job.run(request)
            #expect(Set(again.written.map(\.lastPathComponent)) == ["a-3.jpg", "b-3.jpg"])
            #expect(try contents(of: library.folder).filter { before[$0.key] != nil } == before)
        }
    }

    @Test("A template that names an export like another photo's master does not replace it")
    func anotherPhotosMasterOutsideTheBatch() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await ExportJobTests().makeLibrary(root)
            let before = try contents(of: library.folder)
            let raw = try #require(try await library.items(grouped: false).first { $0.fileName == "a.DNG" })
            var settings = self.settings
            settings.naming = .template
            settings.fileNameTemplate = "b"
            let summary = await library.job.run(ExportRequest(versionIDs: [raw.versionID], settings: settings,
                                                              destination: library.folder, policy: .overwrite))
            #expect(summary.written.map(\.lastPathComponent) == ["b-2.jpg"] && summary.protectedMasters == 1)
            #expect(try contents(of: library.folder).filter { before[$0.key] != nil } == before)
        }
    }

    @Test("The source folder reached through a symbolic link is still the source folder")
    func throughASymbolicLink() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await ExportJobTests().makeLibrary(root)
            let before = try contents(of: library.folder)
            let link = root.appending(path: "Link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: library.folder)
            let ids = ExportTargets.resolve(try await library.items()).versionIDs
            let summary = await library.job.run(ExportRequest(versionIDs: ids, settings: settings, destination: link,
                                                              policy: .overwrite))
            #expect(summary.failures.isEmpty && summary.protectedMasters == 2, "\(summary)")
            #expect(Set(summary.written.map(\.lastPathComponent)) == ["a-2.jpg", "b-2.jpg"])
            #expect(try contents(of: library.folder).filter { before[$0.key] != nil } == before)
        }
    }

    @Test("A master whose name differs from the export's only in case is not replaced")
    func caseInsensitiveNames() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let folder = root.appending(path: "Shoot")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try SyntheticImages.writeJPEG(to: folder.appending(path: "IMG_1.JPG"), width: 320, height: 240, seed: 3)
            let catalog = try Catalog.makeInMemory()
            _ = try await Importer(catalog: catalog, metadataReader: ImageIOMetadataReader()).importFolder(folder)
            let before = try contents(of: folder)
            let ids = try await catalog.libraryItems(matching: LibraryFilter()).map(\.versionID)
            let job = ExportJob(catalog: catalog, renderer: ExportRenderer())
            // The export's name is IMG_1.jpg: the master itself wherever names ignore case.
            let summary = await job.run(ExportRequest(versionIDs: ids, settings: settings, destination: folder,
                                                      policy: .overwrite))
            #expect(summary.written.map(\.lastPathComponent) == ["IMG_1-2.jpg"] && summary.protectedMasters == 1)
            let after = try contents(of: folder)
            #expect(after["IMG_1.JPG"] == before["IMG_1.JPG"])
            #expect(Set(after.keys) == ["IMG_1.JPG", "IMG_1-2.jpg"])
        }
    }

    @Test("A file that is no master is replaced, in the masters' folder too")
    func ordinaryFilesAreStillReplaced() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await ExportJobTests().makeLibrary(root)
            let before = try contents(of: library.folder)
            var settings = self.settings
            settings.naming = .template
            settings.fileNameTemplate = "{name}-web"
            let leftover = library.folder.appending(path: "b-web.jpg")
            try Data("not a picture".utf8).write(to: leftover)
            let ids = ExportTargets.resolve(try await library.items()).versionIDs
            let items = try await library.job.items(for: ids)
            #expect(try await library.job.clashes(for: items, settings: settings, in: library.folder)
                == ExportClashes(existing: 1, masters: 0))
            let summary = await library.job.run(ExportRequest(versionIDs: ids, settings: settings,
                                                              destination: library.folder, policy: .overwrite))
            #expect(summary.failures.isEmpty && summary.protectedMasters == 0)
            #expect(Set(summary.written.map(\.lastPathComponent)) == ["a-web.jpg", "b-web.jpg"])
            #expect(longEdge(leftover) == 100)
            #expect(try contents(of: library.folder).filter { before[$0.key] != nil } == before)
        }
    }

    @Test("A master on a volume mounted elsewhere than the catalog recorded is not replaced")
    func aVolumeMountedElsewhereThanRecorded() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await ExportJobTests().makeLibrary(root)
            let exported = try #require(try await library.items(grouped: false).first { $0.fileName == "b.jpg" })
            // A card the catalog last saw at a mount point that is gone, with DCIM/b.jpg on it.
            // It is mounted at root/Mount now; only its identity says it is the same volume.
            let catalog = library.catalog
            let card = try await catalog.registerVolume(
                VolumeDescriptor(identity: "uuid:CARD", name: "Card", mountPath: "/Volumes/Card-\(UUID().uuidString)"))
            let project = try await catalog.createProject(name: "Card")
            _ = try await catalog.insertMasters([CatalogFixture.master(7, hash: String(repeating: "c7", count: 32),
                                                                       path: "DCIM/b.jpg")],
                                                volumeID: try #require(card.id), projectID: try #require(project.id))
            let mount = root.appending(path: "Mount", directoryHint: .isDirectory)
            let folder = mount.appending(path: "DCIM", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let original = Data("the card's original".utf8)
            try original.write(to: folder.appending(path: "b.jpg"))

            let mountPath = mount.path
            var job = library.job
            job.mountedVolumes = { [VolumeDescriptor(identity: "uuid:CARD", name: "Card", mountPath: mountPath)] }
            let items = try await job.items(for: [exported.versionID])
            #expect(try await job.clashes(for: items, settings: settings, in: folder)
                == ExportClashes(existing: 1, masters: 1))
            let summary = await job.run(ExportRequest(versionIDs: [exported.versionID], settings: settings,
                                                      destination: folder, policy: .overwrite))
            #expect(summary.failures.isEmpty && summary.protectedMasters == 1, "\(summary)")
            #expect(summary.written.map(\.lastPathComponent) == ["b-2.jpg"])
            #expect(try Data(contentsOf: folder.appending(path: "b.jpg")) == original)

            // The recorded mount point alone does not find it: this is what went wrong.
            #expect(try await !catalog.masterFiles(mounted: []).contains(folder.appending(path: "b.jpg")))
        }
    }

    @Test("When the catalog can't say where the masters are, nothing is written and no folder is made")
    func nothingIsWrittenWithoutTheMasters() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await ExportJobTests().makeLibrary(root)
            let before = try contents(of: library.folder)
            let ids = ExportTargets.resolve(try await library.items()).versionIDs
            let items = try await library.job.items(for: ids)
            // The photos are read; from here on the masters can't be.
            try await library.catalog.database.write { db in
                try db.execute(sql: "ALTER TABLE image RENAME TO imageAway")
            }
            await #expect(throws: (any Error).self) {
                try await library.job.clashes(for: items, settings: settings, in: library.folder)
            }
            let summary = await library.job.run(ExportRequest(versionIDs: ids, settings: settings,
                                                              destination: library.folder, policy: .overwrite),
                                                items: items)
            #expect(summary.written.isEmpty && summary.protectedMasters == 0 && !summary.cancelled)
            #expect(Set(summary.failures.map(\.fileName)) == ["a.DNG", "b.jpg"])
            #expect(summary.failures.allSatisfy { if case .writeFailed = $0.reason { true } else { false } })
            #expect(try contents(of: library.folder) == before)

            let fresh = root.appending(path: "Fresh/Deeper", directoryHint: .isDirectory)
            let other = await library.job.run(ExportRequest(versionIDs: ids, settings: settings, destination: fresh),
                                              items: items)
            #expect(other.written.isEmpty && other.failures.count == 2)
            #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Fresh").path))
        }
    }

    @Test("A missing master's place is kept when the export makes its folder again")
    func aDeletedFolderOfMastersMadeAgain() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await ExportJobTests().makeLibrary(root)
            let exported = try #require(try await library.items(grouped: false).first { $0.fileName == "b.jpg" })
            // Another photo's master, Gone/b.jpg, whose folder has since been deleted.
            let gone = root.appending(path: "Gone", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: gone, withIntermediateDirectories: true)
            try SyntheticImages.writeJPEG(to: gone.appending(path: "b.jpg"), width: 200, height: 100, seed: 9)
            _ = try await Importer(catalog: library.catalog, metadataReader: ImageIOMetadataReader()).importFolder(gone)
            #expect(try await library.catalog.masterFiles().contains(gone.appending(path: "b.jpg")))
            try FileManager.default.removeItem(at: gone)

            for policy in [ExportConflictPolicy.overwrite, .skip] {
                let summary = await library.job.run(ExportRequest(versionIDs: [exported.versionID], settings: settings,
                                                                  destination: gone, policy: policy))
                #expect(summary.failures.isEmpty && summary.protectedMasters == 1, "\(policy) \(summary)")
                #expect(summary.written.map(\.lastPathComponent) == ["b-2.jpg"], "\(policy)")
                #expect(try FileManager.default.contentsOfDirectory(atPath: gone.path) == ["b-2.jpg"], "\(policy)")
                try FileManager.default.removeItem(at: gone)
            }
        }
    }

    /// A card with no volume UUID (a FAT32 volume with serial 0, say): its identity
    /// names its mount point, so once it is mounted elsewhere the catalog can't tell
    /// it is the same volume. `DCIM/b.jpg` on it is a catalogued master, here at
    /// `root/Mount/DCIM/b.jpg`, a place the catalog has never heard of.
    struct UnrecognizedCard {
        var folder: URL
        var master: URL
        var bytes: Data
        var job: ExportJob
    }

    func makeUnrecognizedCard(_ root: URL, library: ExportJobTests.Library) async throws -> UnrecognizedCard {
        let mount = root.appending(path: "Mount", directoryHint: .isDirectory)
        let folder = mount.appending(path: "DCIM", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let master = folder.appending(path: "b.jpg")
        try SyntheticImages.writeJPEG(to: master, width: 400, height: 300, seed: 77)
        let bytes = try Data(contentsOf: master)
        let catalog = library.catalog
        let recorded = "/Volumes/NOUUID-\(UUID().uuidString)"
        let card = try await catalog.registerVolume(
            VolumeDescriptor(identity: "mount:NOUUID@\(recorded)", name: "NOUUID", mountPath: recorded))
        let project = try await catalog.createProject(name: "Card")
        _ = try await catalog.insertMasters(
            [NewMaster(relativePath: "DCIM/b.jpg", fileSize: Int64(bytes.count), modifiedAt: Date(),
                       contentHash: Digest.sha256Hex(bytes), metadata: ImageMetadata(pixelWidth: 400, pixelHeight: 300))],
            volumeID: try #require(card.id), projectID: try #require(project.id))
        var job = library.job
        let mountPath = mount.path
        // Mounted now, under the identity its new mount point gives it.
        job.mountedVolumes = { [VolumeDescriptor(identity: "mount:NOUUID@\(mountPath)", name: "NOUUID", mountPath: mountPath)] }
        return UnrecognizedCard(folder: folder, master: master, bytes: bytes, job: job)
    }

    @Test("A master on a volume the catalog can't recognize is known by its content and not replaced")
    func aMasterOnAnUnrecognizedVolume() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await ExportJobTests().makeLibrary(root)
            let ids = ExportTargets.resolve(try await library.items()).versionIDs
            let card = try await makeUnrecognizedCard(root, library: library)
            // Beside it, a file of the same size with other bytes: an ordinary file.
            var other = card.bytes
            other[other.count - 1] ^= 0xFF
            let ordinary = card.folder.appending(path: "a.jpg")
            try other.write(to: ordinary)
            // No place covers the master: this is what identity can't see.
            #expect(try await !library.catalog.masterFiles(mounted: card.job.mountedVolumes()).contains(card.master))

            // The pair exports as a.jpg (the ordinary file), b.jpg as b.jpg (the card's master).
            let items = try await card.job.items(for: ids)
            #expect(try await card.job.clashes(for: items, settings: settings, in: card.folder)
                == ExportClashes(existing: 2, masters: 1))
            let summary = await card.job.run(ExportRequest(versionIDs: ids, settings: settings,
                                                           destination: card.folder, policy: .overwrite))
            #expect(summary.failures.isEmpty && summary.protectedMasters == 1, "\(summary)")
            #expect(Set(summary.written.map(\.lastPathComponent)) == ["a.jpg", "b-2.jpg"])
            #expect(try Data(contentsOf: card.master) == card.bytes)
            // The file of the same size and other content was replaced, as asked.
            #expect(longEdge(ordinary) == 100)
            #expect(try Data(contentsOf: ordinary) != other)
        }
    }

    @Test("A file with a master's content under another name is not replaced either")
    func aMastersContentUnderAnotherName() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let library = try await ExportJobTests().makeLibrary(root)
            let raw = try #require(try await library.items(grouped: false).first { $0.fileName == "a.DNG" })
            let card = try await makeUnrecognizedCard(root, library: library)
            // The card's b.jpg again, as a.jpg in a folder of its own: a backup, or the
            // master renamed on a volume the catalog can't follow. No telling which.
            let folder = root.appending(path: "Backup", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appending(path: "a.jpg")
            try card.bytes.write(to: copy)
            let summary = await card.job.run(ExportRequest(versionIDs: [raw.versionID], settings: settings,
                                                           destination: folder, policy: .overwrite))
            #expect(summary.written.map(\.lastPathComponent) == ["a-2.jpg"] && summary.protectedMasters == 1)
            #expect(try Data(contentsOf: copy) == card.bytes)

            // Keep Both numbers it without reading it, so it is not counted as protected.
            let kept = await card.job.run(ExportRequest(versionIDs: [raw.versionID], settings: settings,
                                                        destination: folder, policy: .keepBoth))
            #expect(kept.written.map(\.lastPathComponent) == ["a-3.jpg"] && kept.protectedMasters == 0)
            #expect(try Data(contentsOf: copy) == card.bytes)
        }
    }
}
