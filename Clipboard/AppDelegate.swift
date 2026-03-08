import AppKit
import ApplicationServices
import Carbon
import SwiftUI

@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let clipboardViewModel = ClipboardViewModel()
    let hotkeyManager = GlobalHotkeyManager()

    private init() {}
}

@MainActor
final class MenuBarController: NSObject {
    private let viewModel: ClipboardViewModel
    private let hotkeyManager: GlobalHotkeyManager

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var previousActiveApplication: NSRunningApplication?

    init(viewModel: ClipboardViewModel, hotkeyManager: GlobalHotkeyManager) {
        self.viewModel = viewModel
        self.hotkeyManager = hotkeyManager
        super.init()
        configureStatusItem()
        configurePopover()
        configureHotkey()
    }

    @objc func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover(focusSearch: false)
        }
    }

    func showPopover(focusSearch: Bool) {
        guard let button = statusItem.button else { return }
        rememberPreviousActiveApplication()
        NSApp.activate(ignoringOtherApps: true)

        if focusSearch {
            viewModel.requestSearchFocus()
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        if focusSearch {
            DispatchQueue.main.async { [weak self] in
                self?.viewModel.requestSearchFocus()
            }
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipVault")
        button.action = #selector(togglePopover(_:))
        button.target = self
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 350, height: 440)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                viewModel: viewModel,
                onClosePopover: { [weak self] in
                    self?.handleItemSelection()
                }
            )
        )
    }

    private func configureHotkey() {
        hotkeyManager.onHotKeyPressed = { [weak self] in
            self?.showPopover(focusSearch: true)
        }
    }

    private func rememberPreviousActiveApplication() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.processIdentifier != currentPID {
            previousActiveApplication = frontmost
        }
    }

    private func handleItemSelection() {
        popover.performClose(nil)
        pasteIntoPreviouslyActiveApp()
    }

    private func pasteIntoPreviouslyActiveApp() {
        guard requestAccessibilityPermissionIfNeeded() else {
            return
        }

        previousActiveApplication?.activate(options: [])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Self.postCommandV()
        }
    }

    private func requestAccessibilityPermissionIfNeeded() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func postCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }

        let keyCode = CGKeyCode(kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment.shared
        menuBarController = MenuBarController(
            viewModel: environment.clipboardViewModel,
            hotkeyManager: environment.hotkeyManager
        )
    }
}
