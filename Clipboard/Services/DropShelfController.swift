import AppKit
import Combine
import QuartzCore
import SwiftUI

private final class DropShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DropShelfController: NSObject {
    private let viewModel: DropShelfViewModel
    private let panelSize = NSSize(width: 320, height: 360)
    private let autoHideDelay: TimeInterval = 10.0

    private var panel: DropShelfPanel?
    private var globalDragMonitor: Any?
    private var localDragMonitor: Any?
    private var globalMouseUpMonitor: Any?
    private var localMouseUpMonitor: Any?
    private var hideWorkItem: DispatchWorkItem?
    private var lastDragProbeTimestamp: CFTimeInterval = 0
    private var lastSeenDragPasteboardChangeCount: Int
    private var itemsCancellable: AnyCancellable?
    private var previousItemCount = 0

    override init() {
        self.viewModel = DropShelfViewModel()
        self.lastSeenDragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
        super.init()
        configureMonitors()
        observeShelfItems()
    }

    init(viewModel: DropShelfViewModel) {
        self.viewModel = viewModel
        self.lastSeenDragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
        super.init()
        configureMonitors()
        observeShelfItems()
    }

    deinit {
        if let globalDragMonitor {
            NSEvent.removeMonitor(globalDragMonitor)
        }
        if let localDragMonitor {
            NSEvent.removeMonitor(localDragMonitor)
        }
        if let globalMouseUpMonitor {
            NSEvent.removeMonitor(globalMouseUpMonitor)
        }
        if let localMouseUpMonitor {
            NSEvent.removeMonitor(localMouseUpMonitor)
        }
    }

    /// Re-opens shelf from hotkey without consuming clipboard panel behavior.
    func revealFromHotkeyIfNeeded() {
        guard viewModel.hasItems else { return }
        showPanel(origin: .manual)
    }

    private var isPanelVisible: Bool {
        panel?.isVisible == true
    }

    private func configureMonitors() {
        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMouseDragged()
            }
        }

        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.handleMouseDragged()
            return event
        }

        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMouseUp()
            }
        }

        localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.handleMouseUp()
            return event
        }
    }

    private func observeShelfItems() {
        itemsCancellable = viewModel.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                guard let self else { return }

                let count = items.count
                defer { self.previousItemCount = count }

                guard count > 0 else {
                    self.hidePanel(animated: false)
                    return
                }

                if self.previousItemCount == 0 {
                    // First successful drop: keep shelf open for a short grace period.
                    self.showPanel(origin: .drop)
                } else if self.isPanelVisible {
                    self.scheduleAutoFadeHide()
                }
            }
    }

    private func handleMouseDragged() {
        // Throttle drag probes to avoid unnecessary pasteboard work.
        let now = CACurrentMediaTime()
        guard now - lastDragProbeTimestamp > 0.12 else {
            return
        }
        lastDragProbeTimestamp = now

        // Only react to new drag pasteboard payloads so regular mouse drags
        // do not reopen the shelf from stale drag data.
        let dragPasteboard = NSPasteboard(name: .drag)
        let currentChangeCount = dragPasteboard.changeCount
        guard currentChangeCount != lastSeenDragPasteboardChangeCount else {
            return
        }

        // Only show shelf for real file drags.
        guard dragPasteboardContainsFileURLs(in: dragPasteboard) else {
            return
        }
        lastSeenDragPasteboardChangeCount = currentChangeCount

        showPanel(origin: .drag)
    }

    private func handleMouseUp() {
        guard isPanelVisible else { return }

        if viewModel.hasItems {
            scheduleAutoFadeHide()
        } else {
            // Drag ended without dropping into shelf.
            hidePanel(animated: false)
        }
    }

    private func dragPasteboardContainsFileURLs(in dragPasteboard: NSPasteboard) -> Bool {
        guard let items = dragPasteboard.pasteboardItems, !items.isEmpty else {
            return false
        }

        for item in items {
            if item.availableType(from: [.fileURL]) != nil {
                return true
            }
        }

        return false
    }

    private func makePanelIfNeeded() -> DropShelfPanel {
        if let panel {
            applyThemeAppearance(to: panel)
            return panel
        }

        let panel = DropShelfPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1.0

        let rootView = DropShelfView(viewModel: viewModel, onClose: { [weak self] in
            self?.hidePanel(animated: false)
        })

        panel.contentView = NSHostingView(rootView: rootView)
        self.panel = panel
        applyThemeAppearance(to: panel)
        return panel
    }

    private enum ShowOrigin {
        case drag
        case drop
        case manual
    }

    private func showPanel(origin: ShowOrigin) {
        hideWorkItem?.cancel()
        hideWorkItem = nil

        let panel = makePanelIfNeeded()
        panel.alphaValue = 1.0
        panel.setFrame(calculatePanelFrame(), display: false)
        panel.orderFrontRegardless()

        if viewModel.hasItems {
            switch origin {
            case .drag:
                // Wait for drag end to decide hide behavior.
                break
            case .drop, .manual:
                scheduleAutoFadeHide()
            }
        }
    }

    private func scheduleAutoFadeHide() {
        hideWorkItem?.cancel()
        guard viewModel.hasItems else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.viewModel.hasItems else {
                self.hidePanel(animated: false)
                return
            }
            self.hidePanel(animated: true)
        }

        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoHideDelay, execute: work)
    }

    private func hidePanel(animated: Bool) {
        hideWorkItem?.cancel()
        hideWorkItem = nil

        guard let panel else { return }
        guard panel.isVisible else {
            panel.alphaValue = 1.0
            panel.orderOut(nil)
            return
        }

        guard animated else {
            panel.alphaValue = 1.0
            panel.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1.0
        })
    }

    private func calculatePanelFrame() -> NSRect {
        let cursorLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(cursorLocation) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let inset: CGFloat = 14
        let x = visibleFrame.maxX - panelSize.width - inset
        let centeredY = visibleFrame.midY - (panelSize.height / 2)
        let minY = visibleFrame.minY + inset
        let maxY = visibleFrame.maxY - panelSize.height - inset
        let y = min(max(centeredY, minY), maxY)

        return NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height)
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
}
