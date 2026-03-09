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
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let viewModel: ClipboardViewModel
    private let hotkeyManager: GlobalHotkeyManager

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var previousActiveApplication: NSRunningApplication?
    private var lastNonClipVaultApplication: NSRunningApplication?
    private var workspaceActivationObserver: NSObjectProtocol?

    init(viewModel: ClipboardViewModel, hotkeyManager: GlobalHotkeyManager) {
        self.viewModel = viewModel
        self.hotkeyManager = hotkeyManager
        super.init()
        configureWorkspaceObserver()
        configureStatusItem()
        configurePopover()
        configureHotkey()
    }

    deinit {
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
        }
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
        popover.delegate = self
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

    private func configureWorkspaceObserver() {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastNonClipVaultApplication = frontmost
        }

        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else {
                return
            }
            Task { @MainActor [weak self] in
                self?.lastNonClipVaultApplication = app
            }
        }
    }

    private func rememberPreviousActiveApplication() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.processIdentifier != currentPID {
            previousActiveApplication = frontmost
            lastNonClipVaultApplication = frontmost
            return
        }

        if let lastNonClipVaultApplication, lastNonClipVaultApplication.processIdentifier != currentPID {
            previousActiveApplication = lastNonClipVaultApplication
        }
    }

    private func handleItemSelection() {
        popover.performClose(nil)
        pasteIntoPreviouslyActiveApp()
    }

    func popoverDidClose(_ notification: Notification) {
        viewModel.clearImageSelection()
    }

    private func pasteIntoPreviouslyActiveApp() {
        guard let targetApplication = resolvePasteTargetApplication() else {
            return
        }

        guard requestAccessibilityPermissionIfNeeded() else {
            targetApplication.activate(options: [])
            return
        }

        targetApplication.activate(options: [])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.pasteAfterTargetIsFrontmost(
                targetPID: targetApplication.processIdentifier,
                remainingAttempts: 16
            )
        }
    }

    private func resolvePasteTargetApplication() -> NSRunningApplication? {
        let currentPID = ProcessInfo.processInfo.processIdentifier

        if let previousActiveApplication, previousActiveApplication.processIdentifier != currentPID {
            return previousActiveApplication
        }

        if let lastNonClipVaultApplication, lastNonClipVaultApplication.processIdentifier != currentPID {
            return lastNonClipVaultApplication
        }

        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.processIdentifier != currentPID {
            return frontmost
        }

        return nil
    }

    private func pasteAfterTargetIsFrontmost(targetPID: pid_t, remainingAttempts: Int) {
        let currentFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if currentFrontmostPID == targetPID || remainingAttempts <= 0 {
            Self.postCommandV()
            previousActiveApplication = nil
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) { [weak self] in
            self?.pasteAfterTargetIsFrontmost(
                targetPID: targetPID,
                remainingAttempts: remainingAttempts - 1
            )
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
