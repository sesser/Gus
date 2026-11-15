import Darwin
import Foundation
import Testing
@testable import PhotoCore

/// The memory this process is charged with (`phys_footprint`, what Activity Monitor shows).
func processFootprint() -> Int64? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Int64(info.phys_footprint) : nil
}

/// Issue #164: the importer's hashing and copying hold one chunk of a file, not
/// the file, and give the same digests as before. Serialized so that the
/// memory tests don't measure each other.
@Suite("Import hashing memory", .serialized)
struct ImportHashMemoryTests {
    /// A file of `size` bytes that takes no disk space (all zeros).
    private func sparseFile(_ size: Int64, in root: URL) throws -> URL {
        let file = root.appending(path: "large.mov")
        #expect(FileManager.default.createFile(atPath: file.path, contents: nil))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(size))
        try handle.close()
        return file
    }

    /// Runs `work` until one run grows the footprint by less than `limit` (at
    /// most five runs) and returns each run's growth. The footprint is the whole
    /// test process's, which other tests move while this runs, so one quiet run
    /// out of five is the pass (the same guard as
    /// `hashingALargeFileHoldsOneChunkNotTheFile`, #160's C9): holding the file
    /// adds its whole size, twice the limit, to every run.
    private func growth(limit: Int64, _ work: () async throws -> Void) async throws -> [Int64] {
        var growth: [Int64] = []
        for _ in 0..<5 {
            let before = try #require(processFootprint())
            try await work()
            growth.append(try #require(processFootprint()) - before)
            if growth.last! < limit { break }
        }
        return growth
    }

    @Test func theContentHasherHoldsOneChunkNotTheFile() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let size: Int64 = 1 << 30
            let file = try sparseFile(size, in: root)
            let limit = size / 2
            let growth = try await growth(limit: limit) {
                _ = try await SHA256ContentHasher().contentHash(of: file)
            }
            #expect(try #require(growth.min()) < limit, "footprint grew by \(growth) bytes hashing \(size)")
        }
    }

    /// Both modes in one test, one after the other: run side by side, each
    /// would measure the other's memory.
    @Test func theCopyImportersHashHoldsOneChunkNotTheFile() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let size: Int64 = 1 << 30
            let file = try sparseFile(size, in: root)
            let limit = size / 2
            for uncached in [false, true] {
                let growth = try await growth(limit: limit) {
                    _ = try CopyImporter.hash(of: file, uncached: uncached)
                }
                #expect(try #require(growth.min()) < limit,
                        "footprint grew by \(growth) bytes hashing \(size), uncached \(uncached)")
            }
        }
    }

    /// The copy loop and the verification after it: measured when the copy
    /// loop has written the last byte, and again after verifying.
    @Test func aVerifiedCopyHoldsOneChunkNotTheFile() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            let size: Int64 = 1 << 30
            let file = try sparseFile(size, in: root)
            let destination = root.appending(path: "copy.mov")
            let limit = size / 2
            var copyLoopGrowth: [Int64] = []
            let growth = try await growth(limit: limit) {
                try? FileManager.default.removeItem(at: destination)
                let before = try #require(processFootprint())
                var copied: Int64 = 0
                var atEndOfCopy: Int64?
                _ = try CopyImporter.copyVerified(file, to: destination, modifiedAt: Date()) { count in
                    copied += count
                    if copied == size { atEndOfCopy = processFootprint() }
                }
                copyLoopGrowth.append(try #require(atEndOfCopy) - before)
            }
            #expect(try #require(copyLoopGrowth.min()) < limit, "the copy loop grew the footprint by \(copyLoopGrowth) bytes")
            #expect(try #require(growth.min()) < limit, "copying and verifying grew the footprint by \(growth) bytes")
        }
    }

    /// Digests from outside this code (`hashlib`, and FIPS 180-2's million
    /// "a"s), over files that end inside a chunk and span several.
    @Test func digestsAreTheKnownOnes() async throws {
        try await RepositoryFiles.withTemporaryDirectory { root in
            // 9 MiB and 13 bytes: two whole 4 MiB chunks and part of a third.
            let patterned = Data((0..<(9 << 20) + 13).map { UInt8($0 % 251) })
            let patternedDigest = "40591012a7860122523d49ed2cc32cc98600a3adc0c179591c14c8423c5843b0"
            let millionA = Data(repeating: UInt8(ascii: "a"), count: 1_000_000)
            let millionADigest = "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
            let empty = Data()
            let emptyDigest = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

            for (index, (data, digest)) in [(patterned, patternedDigest), (millionA, millionADigest),
                                            (empty, emptyDigest)].enumerated() {
                let file = root.appending(path: "file\(index).bin")
                try data.write(to: file)
                #expect(try await SHA256ContentHasher().contentHash(of: file) == digest)
                #expect(try await SHA256ContentHasher(chunkSize: 4093).contentHash(of: file) == digest)
                #expect(try CopyImporter.hash(of: file, uncached: false) == digest)
                #expect(try CopyImporter.hash(of: file, uncached: true) == digest)
                #expect(try MasterFiles.hash(of: file) == digest)

                let copy = root.appending(path: "copy\(index).bin")
                var reported: Int64 = 0
                #expect(try CopyImporter.copyVerified(file, to: copy, modifiedAt: Date()) { reported += $0 } == digest)
                #expect(reported == Int64(data.count))
                #expect(try Data(contentsOf: copy) == data)
            }
        }
    }

    /// Opening still goes through `FileHandle`, so a missing file gives the error it did.
    @Test func aMissingFileStillThrowsWhenOpened() async {
        await RepositoryFiles.withTemporaryDirectory { root in
            let missing = root.appending(path: "missing.mov")
            await #expect(throws: CocoaError.self) { try await SHA256ContentHasher().contentHash(of: missing) }
            #expect(throws: CocoaError.self) { try CopyImporter.hash(of: missing, uncached: false) }
            #expect(throws: CocoaError.self) {
                try CopyImporter.copyVerified(missing, to: root.appending(path: "copy.mov"), modifiedAt: Date()) { _ in }
            }
            #expect(!FileManager.default.fileExists(atPath: root.appending(path: "copy.mov").path))
        }
    }
}
