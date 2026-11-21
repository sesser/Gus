/// Which keys apply a focused row of the Presets list (#241): Return and
/// keypad Enter with no modifier the person chose. Caps Lock, the keypad flag
/// (keypad Enter) and the fn flag (fn-Return) are states of the keyboard, not
/// chosen modifiers, so they are ignored, as the culling keys ignore them
/// (`CullingKeymap`). Space is AppKit's own handling of a focused button.
///
/// Flags are `NSEvent.ModifierFlags` raw values: PhotoCore has no AppKit.
public enum PresetRowKey {
    /// `NSEvent.ModifierFlags.deviceIndependentFlagsMask`.
    static let deviceIndependentFlags: UInt = 0xffff_0000
    /// `.capsLock`, `.numericPad` and `.function`.
    static let ignoredFlags: UInt = (1 << 16) | (1 << 21) | (1 << 23)

    /// - Parameters:
    ///   - characters: The event's `charactersIgnoringModifiers`.
    ///   - modifierFlags: The event's `modifierFlags.rawValue`.
    public static func applies(characters: String?, modifierFlags: UInt) -> Bool {
        let chosen = modifierFlags & deviceIndependentFlags & ~ignoredFlags
        return chosen == 0 && (characters == "\r" || characters == "\u{3}")
    }
}
