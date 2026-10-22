import SwiftUI
import MouseElfCore

extension HotkeyBinding {
    /// Menu equivalents also handle app-directed key events, while Carbon owns
    /// system-wide keys. macOS dispatches a recognized menu key only once.
    var menuShortcut: KeyboardShortcut? {
        let key: KeyEquivalent
        switch keyCode {
        case 36: key = .return
        case 49: key = .space
        case 53: key = .escape
        case 48: key = .tab
        case 51: key = .delete
        case 123: key = .leftArrow
        case 124: key = .rightArrow
        case 125: key = .downArrow
        case 126: key = .upArrow
        case 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111:
            let functionKeys: [UInt32] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
            let index = functionKeys.firstIndex(of: keyCode)!
            key = KeyEquivalent(Character(UnicodeScalar(0xF704 + index)!))
        default:
            guard let name = KeyNames.options.first(where: { $0.code == keyCode })?.name, name.count == 1 else { return nil }
            key = KeyEquivalent(Character(name.lowercased()))
        }
        var flags: EventModifiers = []
        if modifiers & 0x100 != 0 { flags.insert(.command) }
        if modifiers & 0x1000 != 0 { flags.insert(.control) }
        if modifiers & 0x800 != 0 { flags.insert(.option) }
        if modifiers & 0x200 != 0 { flags.insert(.shift) }
        return KeyboardShortcut(key, modifiers: flags)
    }
}
