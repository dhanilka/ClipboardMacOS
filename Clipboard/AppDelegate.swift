import AppKit
import ApplicationServices
import Carbon
import SwiftUI

private final class FloatingPickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class QuickPickerContainerController: NSViewController {
    private let hostingController: NSHostingController<MenuBarView>

    init(rootView: MenuBarView) {
        self.hostingController = NSHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 18
        effectView.layer?.masksToBounds = true
        effectView.layer?.backgroundColor = NSColor.clear.cgColor
        view = effectView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(hostingController)

        let hostedView = hostingController.view
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.wantsLayer = true
        hostedView.layer?.backgroundColor = NSColor.clear.cgColor

        view.addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: view.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let clipboardViewModel = ClipboardViewModel()
    let hotkeyManager = GlobalHotkeyManager()

    private init() {}
}

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate, NSWindowDelegate {
    private let viewModel: ClipboardViewModel
    private let hotkeyManager: GlobalHotkeyManager

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let pickerContentSize = NSSize(width: 350, height: 440)
    private var quickPickerPanel: FloatingPickerPanel?
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
        if let quickPickerPanel, quickPickerPanel.isVisible {
            closeQuickPicker()
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover(focusSearch: false)
        }
    }

    func showPopover(focusSearch: Bool) {
        guard let button = statusItem.button else { return }
        closeQuickPicker()
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

    private func toggleQuickPicker() {
        if let quickPickerPanel, quickPickerPanel.isVisible {
            closeQuickPicker()
        } else {
            showQuickPicker(focusSearch: true)
        }
    }

    private func showQuickPicker(focusSearch: Bool) {
        rememberPreviousActiveApplication()
        popover.performClose(nil)

        let panel = makeQuickPickerPanelIfNeeded()
        applyThemeAppearance(to: panel)
        positionQuickPicker(panel)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if focusSearch {
            viewModel.requestSearchFocus()
            DispatchQueue.main.async { [weak self] in
                self?.viewModel.requestSearchFocus()
            }
        }
    }

    private func closeQuickPicker() {
        guard let quickPickerPanel, quickPickerPanel.isVisible else { return }
        quickPickerPanel.orderOut(nil)
        viewModel.clearImageSelection()
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
        popover.contentSize = pickerContentSize
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                viewModel: viewModel,
                onClosePopover: { [weak self] in
                    self?.handleItemSelection()
                },
                presentationStyle: .popover
            )
        )
    }

    private func makeQuickPickerPanelIfNeeded() -> FloatingPickerPanel {
        if let quickPickerPanel {
            return quickPickerPanel
        }

        let panel = FloatingPickerPanel(
            contentRect: NSRect(origin: .zero, size: pickerContentSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.delegate = self
        panel.contentViewController = QuickPickerContainerController(
            rootView: MenuBarView(
                viewModel: viewModel,
                onClosePopover: { [weak self] in
                    self?.handleItemSelection()
                },
                presentationStyle: .quickPicker
            )
        )

        quickPickerPanel = panel
        return panel
    }

    private func applyThemeAppearance(to panel: NSPanel) {
        let themeRawValue = UserDefaults.standard.string(forKey: appThemeStorageKey) ?? AppTheme.dark.rawValue
        let theme = AppTheme(rawValue: themeRawValue) ?? .dark

        switch theme {
        case .system:
            panel.appearance = nil
        case .light:
            panel.appearance = NSAppearance(named: .aqua)
        case .dark:
            panel.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func positionQuickPicker(_ panel: NSPanel) {
        panel.setFrame(calculateQuickPickerFrame(), display: false)
    }

    private func calculateQuickPickerFrame() -> NSRect {
        let cursorLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(cursorLocation) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let inset: CGFloat = 8

        let width = pickerContentSize.width
        let height = pickerContentSize.height

        let minX = visibleFrame.minX + inset
        let maxX = visibleFrame.maxX - width - inset
        let minY = visibleFrame.minY + inset
        let maxY = visibleFrame.maxY - height - inset

        var originX = cursorLocation.x - (width / 2)
        originX = min(max(originX, minX), maxX)

        var originY = cursorLocation.y - height - 12
        if originY < minY {
            originY = cursorLocation.y + 16
        }
        originY = min(max(originY, minY), maxY)

        return NSRect(x: originX, y: originY, width: width, height: height)
    }

    private func configureHotkey() {
        hotkeyManager.onHotKeyPressed = { [weak self] in
            self?.toggleQuickPicker()
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
        closeQuickPicker()
        pasteIntoPreviouslyActiveApp()
    }

    func popoverDidClose(_ notification: Notification) {
        viewModel.clearImageSelection()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel, panel == quickPickerPanel else {
            return
        }
        // OCR sheet/popovers can temporarily move key focus within the app.
        // Only close the quick picker after the app actually deactivates.
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel else { return }
            guard panel == self.quickPickerPanel else { return }
            guard !NSApp.isActive else { return }
            self.closeQuickPicker()
        }
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
