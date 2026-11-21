import Foundation
import PhotoCore
import PhotoUI

/// The words of File ▸ Merge to HDR… (hdr-merge design §13).
enum MergeText {
    static var menuTitle: String {
        String(localized: "Merge to HDR…", comment: "File menu and the grid's context menu: merges the selected photos into one new photo")
    }

    /// The undo action name and the Activity rows' title.
    static var title: String {
        String(localized: "Merge to HDR", comment: "Undo action name (Edit ▸ Undo Merge to HDR) and the title of the merge's Activity rows")
    }

    static var stopMenu: String {
        String(localized: "Stop Merge", comment: "File menu (⌘.): stops the running HDR merge")
    }

    // MARK: Sheet

    static func sheetTitle(_ count: Int) -> String {
        String(localized: "Merge \(count) Photos to HDR", comment: "Merge to HDR sheet: its title; how many photos are merged (a RAW+JPEG pair counts once)")
    }

    static func source(_ name: String) -> String {
        String(localized: "From \(name)", comment: "Export and Merge to HDR sheets: the sidebar source")
    }

    static var photosSection: String { String(localized: "Photos", comment: "Merge to HDR sheet: the section listing the photos") }
    static var resultSection: String { String(localized: "Result", comment: "Merge to HDR sheet: the section about the file written") }
    static var photoColumn: String { String(localized: "Photo", comment: "Merge to HDR sheet: column of the photos' names") }
    static var typeColumn: String { String(localized: "Type", comment: "Merge to HDR sheet: column of the photos' file types") }
    static var shutterColumn: String { String(localized: "Shutter", comment: "Merge to HDR sheet: column of the photos' exposure times") }
    static var compensationColumn: String {
        String(localized: "Compensation", comment: "Merge to HDR sheet: column of the photos' exposure compensation")
    }

    static var referenceRole: String {
        String(localized: "Reference", comment: "Merge to HDR sheet: after the name of the photo that names the result and the others are lined up to")
    }

    static var problem: String {
        String(localized: "Problem", comment: "VoiceOver: the value of a photo row the sheet's message is about")
    }

    static func referenceCaption(_ name: String) -> String {
        String(localized: "“\(name)” names the result and is the photo the others are lined up to.",
               comment: "Merge to HDR sheet: caption under the photos; the reference photo's name")
    }

    static var sameExposureNote: String {
        String(localized: "These photos have the same exposure settings. Merging them won't widen the range of light.",
               comment: "Merge to HDR sheet: a note when every photo has the same shutter, aperture, ISO and compensation")
    }

    static var formatLabel: String { String(localized: "Format", comment: "Merge to HDR sheet: the file format choice") }
    static var tiff: String { FileKindText.badge(.tiff) }
    static var dng: String { String(localized: "DNG", comment: "Merge to HDR sheet: a file format") }

    static var tiffCaption: String {
        String(localized: "16-bit, Display P3, tone-mapped. Looks right in any app.",
               comment: "Merge to HDR sheet: caption of the TIFF format")
    }

    /// The DNG holds half floats (status.md, RI-E1: the system's RAW decoder
    /// reads no 32-bit floating-point DNG).
    static var dngCaption: String {
        String(localized: "16-bit floating point, not tone-mapped. Tone it in the Adjust tab.",
               comment: "Merge to HDR sheet: caption of the DNG format")
    }

    static var nameLabel: String { String(localized: "Name", comment: "Merge to HDR sheet: the file name the result gets") }
    static var folderLabel: String { String(localized: "Folder", comment: "Merge to HDR sheet: the folder the result is saved in") }

    static func savedNextTo(_ name: String) -> String {
        String(localized: "Saved next to “\(name)”. The originals are not changed, and your adjustments are not used: the photos are merged as they were shot.",
               comment: "Merge to HDR sheet: caption under the result; the reference photo's name")
    }

    static var severalFolders: String {
        String(localized: "The photos are in several folders. The result goes in the reference's.",
               comment: "Merge to HDR sheet: caption when the photos are in more than one folder")
    }

    static var mergeButton: String { String(localized: "Merge", comment: "Merge to HDR sheet: the button that starts the merge") }

    // MARK: Refusals (design §6)

    static func refusal(_ refusal: MergeRefusal) -> String {
        switch refusal {
        case .tooFew:
            String(localized: "Select at least two different photos. A RAW+JPEG pair counts as one.",
                   comment: "Merge to HDR sheet: refusal, fewer than two photos once pairs count once")
        case .tooMany(let limit):
            String(localized: "At most \(limit) photos can be merged at once. Select fewer.",
                   comment: "Merge to HDR sheet: refusal, too many photos; the limit")
        case .video(let name):
            String(localized: "“\(name)” is a video. Only photos can be merged.",
                   comment: "Merge to HDR sheet: refusal; the video's name")
        case .sameFile(let copy, let original):
            String(localized: "“\(copy)” is a copy of “\(original)”, the same file. Select each photo once.",
                   comment: "Merge to HDR sheet: refusal; the copy's name, then its original's")
        case .mixedKinds:
            String(localized: "These photos are a mix of raw and non-raw files. Select only raws, or only JPEG, HEIC or TIFF files.",
                   comment: "Merge to HDR sheet: refusal")
        case .differentSize(let name, let reference):
            String(localized: "“\(name)” is a different size from “\(reference)”. Merged photos must be the same size.",
                   comment: "Merge to HDR sheet: refusal; the photo's name, then the reference's")
        case .tooLarge(let name, let megapixels):
            String(localized: "“\(name)” is too large to merge. A photo can have at most \(megapixels) megapixels.",
                   comment: "Merge to HDR sheet and Activity: refusal; the photo's name, then the limit in megapixels")
        case .tooMuchMemory:
            String(localized: "These photos are too large to merge together on this Mac. Select fewer.",
                   comment: "Merge to HDR sheet: refusal, the photos' pixels would take more memory than a merge may use")
        case .offline(let name, let count):
            count == 1
                ? String(localized: "“\(name)” is offline. Connect its drive and try again.",
                         comment: "Merge to HDR sheet: refusal; the offline photo's name")
                : String(localized: "\(count) of these photos are offline. Connect their drives and try again.",
                         comment: "Merge to HDR sheet: refusal; how many photos are offline")
        case .unreadable(let name):
            String(localized: "“\(name)” can't be read. Check that the file is still there.",
                   comment: "Merge to HDR sheet: refusal; the photo's name")
        case .unwritableFolder(let reference, let folder):
            String(localized: "The merged photo would be saved next to “\(reference)”, in “\(folder)”, which can't be written to. It may be on a read-only disk, or you may not have permission.",
                   comment: "Merge to HDR sheet: refusal; the reference photo's name, then its folder's")
        }
    }

    // MARK: Activity (design §7)

    static func jobTitle(_ fileName: String) -> String {
        String(localized: "Merge to “\(fileName)”", comment: "Activity: the running merge's title; the file it writes")
    }

    static func detail(_ phase: MergeProgress.Phase) -> String {
        switch phase {
        case .reading(let done, let total):
            String(localized: "Reading \(done) of \(total)", comment: "Activity: a merge reading its photos")
        case .aligning(let done, let total):
            String(localized: "Aligning \(done) of \(total)", comment: "Activity: a merge lining its photos up")
        case .merging: String(localized: "Merging", comment: "Activity: a merge combining its photos")
        case .toneMapping: String(localized: "Tone mapping", comment: "Activity: a merge tone mapping its result")
        case .saving: String(localized: "Saving", comment: "Activity: a merge writing its file")
        case .adding: String(localized: "Adding to the library", comment: "Activity: a merge cataloguing its file")
        }
    }

    static func merged(_ count: Int, path: String) -> String {
        String(localized: "Merged \(count) photos into \(path).", comment: "Activity: a merge finished; how many photos, the file's full path")
    }

    static var stopped: String {
        String(localized: "The merge was stopped. Nothing was added to the library.", comment: "Activity: a merge was stopped")
    }

    static var failed: String {
        String(localized: "The photos couldn't be merged. Nothing was added to the library.",
               comment: "Activity: a merge failed; the reason follows")
    }

    static func reason(_ failure: HDRMergeJob.Failure) -> String {
        switch failure {
        case .refused(let why): refusal(why)
        case .misaligned(let name, let reference):
            String(localized: "“\(name)” doesn't line up with “\(reference)”. Merge photos of the same scene.",
                   comment: "Activity: why a merge failed; the photo's name, then the reference's")
        case .unreadable(let name):
            String(localized: "“\(name)” couldn't be read.", comment: "Activity: why a merge failed; the photo's name")
        case .differentSize(let name, let reference):
            refusal(.differentSize(name: name, reference: reference))
        case .tooLarge(let name):
            refusal(.tooLarge(name: name, megapixels: MergeLimits.maximumPixels / 1_000_000))
        case .noSpace(let volume):
            String(localized: "There isn't enough space on “\(volume)”.", comment: "Activity: why a merge failed; the disk's name")
        case .writeFailed(let reason):
            String(localized: "The file couldn't be saved: \(reason).", comment: "Activity: why a merge failed; the system's reason")
        case .noMemory:
            String(localized: "There wasn't enough memory to merge these photos.", comment: "Activity: why a merge failed")
        case .catalogFailed(let path, _):
            savedNotAdded(path)
        case .invalidName(let name):
            String(localized: "“\(name)” has a name or place a merged photo can't be saved beside.",
                   comment: "Activity: why a merge failed; the reference photo's name (a damaged library)")
        case .sameContent:
            String(localized: "The library already has a photo with the same content.",
                   comment: "Activity: why a merge failed; its file was the same as a photo already in the library")
        }
    }

    static func savedNotAdded(_ path: String) -> String {
        String(localized: "The merged photo was saved at \(path) but couldn't be added to the library. Add the folder again to import it.",
               comment: "Activity warning: the merge's file is complete but the catalog write failed; its full path")
    }

    static func removedFromLibrary(_ name: String, path: String) -> String {
        String(localized: "“\(name)” was removed from the library. The file is still at \(path).",
               comment: "Activity: after Undo of a merge; the file's name, then its full path")
    }

    static func notAddedBack(_ name: String) -> String {
        String(localized: "“\(name)” couldn't be added back because the file has changed or is missing.",
               comment: "Activity warning: Redo of a merge whose file changed; the file's name")
    }

    // MARK: VoiceOver

    static func announceMerged(_ name: String) -> String {
        String(localized: "Merged to “\(name)”.", comment: "VoiceOver, after a merge; the file's name")
    }

    static var announceFailed: String {
        String(localized: "The photos couldn't be merged.", comment: "VoiceOver, after a merge failed")
    }

    static var announceStopped: String {
        String(localized: "The merge was stopped.", comment: "VoiceOver, after a merge was stopped")
    }

    // MARK: Formatting

    /// "1/250 s", "2 s", "0.5 s"; "—" when unknown.
    static func shutter(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        if seconds < 1 {
            let denominator = Int((1 / seconds).rounded())
            return String(localized: "1/\(denominator) s", comment: "Merge to HDR sheet: an exposure time under a second")
        }
        let value = seconds.formatted(.number.precision(.fractionLength(0...1)))
        return String(localized: "\(value) s", comment: "Merge to HDR sheet: an exposure time of a second or more")
    }

    /// "−2 EV", "0 EV", "+0.3 EV" with the Unicode minus; "—" when unknown.
    static func compensation(_ ev: Double?) -> String {
        guard let ev else { return "—" }
        let magnitude = abs(ev).formatted(.number.precision(.fractionLength(0...1)))
        let sign = ev > 0.04 ? "+" : ev < -0.04 ? "\u{2212}" : ""
        return String(localized: "\(sign + magnitude) EV", comment: "Merge to HDR sheet: exposure compensation in stops, signed")
    }
}
