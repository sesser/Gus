import AppKit
import PhotoCore
import Testing

/// The keys that apply a focused Presets list row (#241, code review C2 and C4).
@Suite("Presets list row keys")
struct PresetRowKeyTests {
    func applies(_ characters: String?, _ flags: NSEvent.ModifierFlags = []) -> Bool {
        PresetRowKey.applies(characters: characters, modifierFlags: flags.rawValue)
    }

    @Test func returnAndKeypadEnterApply() {
        #expect(applies("\r"))
        #expect(applies("\u{3}", .numericPad))
        #expect(applies("\r", .function))
    }

    /// C4: Caps Lock is a state of the keyboard, not a chosen modifier.
    @Test func capsLockDoesNotStopThem() {
        #expect(applies("\r", .capsLock))
        #expect(applies("\u{3}", [.capsLock, .numericPad]))
    }

    @Test func chosenModifiersDo() {
        for flag: NSEvent.ModifierFlags in [.command, .option, .control, .shift] {
            #expect(!applies("\r", flag))
            #expect(!applies("\r", [flag, .capsLock]))
        }
    }

    /// Device-dependent bits (which side's key) never count.
    @Test func deviceDependentBitsAreIgnored() {
        #expect(PresetRowKey.applies(characters: "\r", modifierFlags: 0x100))
    }

    @Test func otherKeysDoNot() {
        #expect(!applies(" "))
        #expect(!applies("a"))
        #expect(!applies("\t"))
        #expect(!applies(nil))
    }
}
