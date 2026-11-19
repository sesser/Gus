import Foundation

/// The White Balance group's captions for a raw whose camera color data the
/// app's decoder cannot use (white-balance-across-decoders design §6): the
/// photo renders as shot and white balance cannot be changed. Each is also
/// the Mode pop-up's help.
enum WhiteBalanceText {
    /// W1: nothing is stored; the pop-up is dimmed on As Shot.
    static let unavailable = String(
        localized: "Not available for this photo: its color data can't be read.",
        comment: "Adjust tab, under the dimmed White Balance Mode pop-up and as its tooltip: a raw file macOS can't decode whose camera color data (matrix or white balance) the app's decoder can't use; white balance can't be changed")
    /// W2: a white balance is stored (pasted, from a preset) and cannot be applied.
    static let notApplied = String(
        localized: "Not applied: this photo's color data can't be read. It's shown as shot.",
        comment: "Adjust tab, after a warning symbol under the White Balance Mode pop-up and as its tooltip: the photo holds a white balance (pasted or from a preset) that can't be applied because its camera color data can't be used; the setting is kept")
}
