import CoreGraphics

/// The size in pixels the loupe and the comparison panes give a photo when
/// it arrives, before its full-resolution rendition is there.
///
/// The rendition's own size when it is known (`PreviewService.outputSize`,
/// asked ahead for the loupe's neighbors and kept after every rendition), so
/// the photo neither resizes nor moves when the rendition replaces the
/// preview. Otherwise the catalog's size, which is the file's metadata: for a
/// raw read by ExifTool that is its raw data (a Sony ARW 6048 x 4024 against
/// 6000 x 4000 rendered), and no crop is in it; the loupe then corrects the
/// size as soon as the rendition's is known, keeping the same place in the
/// middle.
public enum LoupeArrivalSize {
    public static func size(knownOutput: CGSize?, catalog: CGSize?) -> CGSize? {
        knownOutput ?? catalog
    }
}
