import AppKit
import Foundation

/// Polls NSPasteboard and emits supported clipboard entries.
final class ClipboardMonitorService {
    private let pasteboard: NSPasteboard
    private let monitorQueue = DispatchQueue(label: "com.clipvault.monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    func startMonitoring(onNewItem: @escaping (ClipboardItem) -> Void) {
        stopMonitoring()

        let timer = DispatchSource.makeTimerSource(queue: monitorQueue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            self?.pollClipboard(onNewItem: onNewItem)
        }
        self.timer = timer
        timer.resume()
    }

    func stopMonitoring() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    deinit {
        stopMonitoring()
    }

    private func pollClipboard(onNewItem: @escaping (ClipboardItem) -> Void) {
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = pasteboard.changeCount

        guard let item = readClipboardItem() else {
            return
        }

        // UI state is updated on the main queue via the ViewModel.
        DispatchQueue.main.async {
            onNewItem(item)
        }
    }

    private func readClipboardItem() -> ClipboardItem? {
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.first {
            return ClipboardItem.fromURL(url)
        }

        if let image = (pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.first {
            return ClipboardItem.fromImage(image)
        }

        if let text = pasteboard.string(forType: .string) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed), url.host(percentEncoded: false) != nil {
                return ClipboardItem.fromURL(url)
            }
            return ClipboardItem.fromText(text)
        }

        // Unsupported content types are intentionally ignored.
        return nil
    }
}
