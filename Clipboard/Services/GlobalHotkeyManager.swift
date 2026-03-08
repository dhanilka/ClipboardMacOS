import AppKit
import Carbon
import Foundation
import Combine

struct HotkeyShortcut: Codable, Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    static let `default` = HotkeyShortcut(
        keyCode: UInt32(kVK_ANSI_V),
        carbonModifiers: UInt32(cmdKey | shiftKey)
    )
}

@MainActor
final class GlobalHotkeyManager: ObservableObject {
    @Published private(set) var shortcut: HotkeyShortcut

    /// Invoked when the registered hotkey is pressed system-wide.
    var onHotKeyPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private var hotKeyHandlerUPP: EventHandlerUPP?

    private let keyCodeStoreKey = "clipvault.hotkey.keyCode"
    private let modifiersStoreKey = "clipvault.hotkey.modifiers"
    private let hotKeySignature: OSType = 0x4350564C // "CPVL"

    init() {
        shortcut = Self.loadShortcut()
        installHotKeyHandlerIfNeeded()
        registerHotKey()
    }

    func updateShortcut(_ newShortcut: HotkeyShortcut) {
        guard newShortcut != shortcut else { return }
        shortcut = newShortcut
        storeShortcut(newShortcut)
        registerHotKey()
    }

    func resetToDefault() {
        updateShortcut(.default)
    }

    var shortcutDisplayText: String {
        Self.displayText(for: shortcut)
    }

    static func shortcut(from event: NSEvent) -> HotkeyShortcut? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let supportedModifiers = modifiers.intersection([.command, .shift, .option, .control])
        guard !supportedModifiers.isEmpty else { return nil }

        // Ignore modifier-only keys.
        let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        guard !modifierKeyCodes.contains(event.keyCode) else { return nil }

        return HotkeyShortcut(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: carbonModifiers(from: supportedModifiers)
        )
    }

    static func displayText(for shortcut: HotkeyShortcut) -> String {
        var parts: [String] = []

        if shortcut.carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if shortcut.carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if shortcut.carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if shortcut.carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }

        parts.append(displayKey(for: shortcut.keyCode))
        return parts.joined()
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    private static func displayKey(for keyCode: UInt32) -> String {
        switch keyCode {
        case UInt32(kVK_ANSI_A): return "A"
        case UInt32(kVK_ANSI_B): return "B"
        case UInt32(kVK_ANSI_C): return "C"
        case UInt32(kVK_ANSI_D): return "D"
        case UInt32(kVK_ANSI_E): return "E"
        case UInt32(kVK_ANSI_F): return "F"
        case UInt32(kVK_ANSI_G): return "G"
        case UInt32(kVK_ANSI_H): return "H"
        case UInt32(kVK_ANSI_I): return "I"
        case UInt32(kVK_ANSI_J): return "J"
        case UInt32(kVK_ANSI_K): return "K"
        case UInt32(kVK_ANSI_L): return "L"
        case UInt32(kVK_ANSI_M): return "M"
        case UInt32(kVK_ANSI_N): return "N"
        case UInt32(kVK_ANSI_O): return "O"
        case UInt32(kVK_ANSI_P): return "P"
        case UInt32(kVK_ANSI_Q): return "Q"
        case UInt32(kVK_ANSI_R): return "R"
        case UInt32(kVK_ANSI_S): return "S"
        case UInt32(kVK_ANSI_T): return "T"
        case UInt32(kVK_ANSI_U): return "U"
        case UInt32(kVK_ANSI_V): return "V"
        case UInt32(kVK_ANSI_W): return "W"
        case UInt32(kVK_ANSI_X): return "X"
        case UInt32(kVK_ANSI_Y): return "Y"
        case UInt32(kVK_ANSI_Z): return "Z"
        case UInt32(kVK_ANSI_0): return "0"
        case UInt32(kVK_ANSI_1): return "1"
        case UInt32(kVK_ANSI_2): return "2"
        case UInt32(kVK_ANSI_3): return "3"
        case UInt32(kVK_ANSI_4): return "4"
        case UInt32(kVK_ANSI_5): return "5"
        case UInt32(kVK_ANSI_6): return "6"
        case UInt32(kVK_ANSI_7): return "7"
        case UInt32(kVK_ANSI_8): return "8"
        case UInt32(kVK_ANSI_9): return "9"
        case UInt32(kVK_Return): return "↩"
        case UInt32(kVK_Space): return "Space"
        case UInt32(kVK_Tab): return "⇥"
        case UInt32(kVK_Delete): return "⌫"
        case UInt32(kVK_Escape): return "⎋"
        default: return "Key\(keyCode)"
        }
    }

    private func installHotKeyHandlerIfNeeded() {
        guard hotKeyHandlerRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        hotKeyHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.onHotKeyPressed?()
            return noErr
        }

        if let hotKeyHandlerUPP {
            let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            InstallEventHandler(
                GetApplicationEventTarget(),
                hotKeyHandlerUPP,
                1,
                &eventType,
                userData,
                &hotKeyHandlerRef
            )
        }
    }

    private func registerHotKey() {
        unregisterHotKey()

        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: 1)
        RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }

    private static func loadShortcut() -> HotkeyShortcut {
        let defaults = UserDefaults.standard
        guard
            defaults.object(forKey: "clipvault.hotkey.keyCode") != nil,
            defaults.object(forKey: "clipvault.hotkey.modifiers") != nil
        else {
            return .default
        }

        let keyCode = UInt32(defaults.integer(forKey: "clipvault.hotkey.keyCode"))
        let modifiers = UInt32(defaults.integer(forKey: "clipvault.hotkey.modifiers"))
        return HotkeyShortcut(keyCode: keyCode, carbonModifiers: modifiers)
    }

    private func storeShortcut(_ shortcut: HotkeyShortcut) {
        let defaults = UserDefaults.standard
        defaults.set(Int(shortcut.keyCode), forKey: keyCodeStoreKey)
        defaults.set(Int(shortcut.carbonModifiers), forKey: modifiersStoreKey)
    }
}
