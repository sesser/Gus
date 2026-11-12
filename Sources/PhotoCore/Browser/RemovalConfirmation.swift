/// What the confirmation before a removal from the library says
/// (docs/features/library-ops, R7–R10; design §6.2 and §7.2; copies:
/// docs/features/virtual-copies design §7); the UI puts it into words. The
/// sentences are in the order they are shown.
public struct RemovalConfirmation: Hashable, Sendable {
    public enum Title: Hashable, Sendable {
        /// One photo, by its file name, or a copy's name ("IMG_0412 copy 2").
        case photo(fileName: String)
        /// Several, counted as the grid shows them (a grouped pair once).
        case photos(Int)
        case project(name: String)
    }

    public enum Sentence: Hashable, Sendable {
        /// "Its ‹N› photos are removed with it."
        case projectPhotos(Int)
        /// "It has no photos."
        case projectHasNoPhotos
        /// "Both files of each RAW+JPEG pair are removed, ‹F› files in all."
        case pairFiles(Int)
        /// "Its ‹K› albums are deleted." (albums and smart albums together)
        case projectAlbums(Int)
        /// "Its copy is removed with it." / "Its ‹C› copies are removed with
        /// it.": one original whose copies were not chosen themselves.
        case copiesOfPhoto(Int)
        /// "‹C› copies of these photos are removed with them."
        case copiesOfPhotos(Int)
        /// Files and sidecars stay, edits are lost, no undo.
        case photosConsequences
        /// Only a copy goes: the original and its file are not affected.
        case copyConsequences
        /// The same for several copies.
        case copiesConsequences
        /// The same for a project: the folder stays too.
        case projectConsequences
        /// "The folder stays on disk, unchanged."
        case emptyProjectConsequences
    }

    public var title: Title
    public var sentences: [Sentence]

    /// Removing `shown` photos (the command's targets, copies included),
    /// which takes `fileCount` files. `fileName` is the one target's name,
    /// when there is one. `originals` of the targets are originals (all of
    /// them when nil); `extraCopies` copies go with their originals without
    /// having been chosen.
    ///
    /// - Every target a copy: no file, sidecar or original is involved, and
    ///   the message says so instead.
    /// - The pair sentence is there only when pairs add files beyond the
    ///   originals chosen. Copies never count as files.
    /// - The copies sentence is there only for copies that are not targets.
    public static func photos(shown: Int, fileName: String?, fileCount: Int, originals: Int? = nil,
                              extraCopies: Int = 0) -> RemovalConfirmation {
        let originals = originals ?? shown
        let title: Title = if shown == 1, let fileName { .photo(fileName: fileName) } else { .photos(shown) }
        guard originals > 0 else {
            return RemovalConfirmation(title: title, sentences: [shown == 1 ? .copyConsequences : .copiesConsequences])
        }
        var sentences: [Sentence] = []
        if fileCount > originals { sentences.append(.pairFiles(fileCount)) }
        if extraCopies > 0 { sentences.append(shown == 1 ? .copiesOfPhoto(extraCopies) : .copiesOfPhotos(extraCopies)) }
        sentences.append(.photosConsequences)
        return RemovalConfirmation(title: title, sentences: sentences)
    }

    /// The confirmation for `plan`, whose targets the grid shows as `shown`
    /// items, the one target named `fileName`.
    public static func photos(_ plan: PhotoRemovalPlan, shown: Int, fileName: String?) -> RemovalConfirmation {
        photos(shown: shown, fileName: fileName, fileCount: plan.fileCount, originals: plan.originalCount,
               extraCopies: plan.extraCopyCount)
    }

    /// Removing a project with `photoCount` photos as the sidebar counts
    /// them, `fileCount` files and `albumCount` albums and smart albums of
    /// its own.
    public static func project(name: String, photoCount: Int, fileCount: Int, albumCount: Int) -> RemovalConfirmation {
        var sentences: [Sentence] = [photoCount > 0 ? .projectPhotos(photoCount) : .projectHasNoPhotos]
        if fileCount > photoCount { sentences.append(.pairFiles(fileCount)) }
        if albumCount > 0 { sentences.append(.projectAlbums(albumCount)) }
        sentences.append(photoCount > 0 ? .projectConsequences : .emptyProjectConsequences)
        return RemovalConfirmation(title: .project(name: name), sentences: sentences)
    }

    public static func project(_ plan: ProjectRemovalPlan) -> RemovalConfirmation {
        project(name: plan.project.name, photoCount: plan.photoCount, fileCount: plan.fileCount,
                albumCount: plan.albumCount)
    }
}

/// Whether a removal may start (design §6.1, §7.1 and §8): one at a time,
/// and never beside an import. An import writes into a project, and fails
/// if that project is removed under it. An export and a batch measurement
/// are no obstacle: an export works from what it read when it started, and
/// a measurement writes only to the photos still there when it ends.
public enum RemovalAvailability {
    public static func canStart(isRemoving: Bool, isAddingFolders: Bool, isCopying: Bool) -> Bool {
        !(isRemoving || isAddingFolders || isCopying)
    }
}

/// The photo the browser focuses after a removal (design §6.3 and §7.3).
/// The focused photo keeps the focus when the removal did not take it (a
/// project removed from its row's menu while another source is on screen).
/// Otherwise it goes to the photo that followed the last removed one in the
/// grid's order, or to the nearest one before it when none followed.
public enum RemovalFocus {
    /// `focus`: the focused photo's index before the removal. `isRemoved`:
    /// whether the photo at an index is taken by the removal (the targets,
    /// and with pairs ungrouped their partners).
    public static func index(count: Int, focus: Int?, isRemoved: (Int) -> Bool) -> Int? {
        if let focus, (0..<count).contains(focus), !isRemoved(focus) { return focus }
        guard let last = (0..<count).last(where: isRemoved) else { return nil }
        if last + 1 < count { return last + 1 }
        return (0..<last).last { !isRemoved($0) }
    }
}
