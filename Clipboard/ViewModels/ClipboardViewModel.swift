import Foundation
import Combine
import AppKit
import SwiftUI

@MainActor
final class ClipboardViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published private(set) var searchFocusTrigger: UUID = UUID()
    @Published private(set) var items: [ClipboardItem] = []

    private let clipboardMonitor: ClipboardMonitorService
    private let historyLimit = 100

    init(clipboardMonitor: ClipboardMonitorService) {
        self.clipboardMonitor = clipboardMonitor
        startMonitoring()
    }

    convenience init() {
        self.init(clipboardMonitor: ClipboardMonitorService())
    }

    var filteredPinnedItems: [ClipboardItem] {
        filtered(items: items.filter(\.isPinned))
    }

    var filteredHistoryItems: [ClipboardItem] {
        filtered(items: items.filter { !$0.isPinned })
    }

    var hasNonPinnedItems: Bool {
        items.contains { !$0.isPinned }
    }

    var hasVisibleItems: Bool {
        !(filteredPinnedItems.isEmpty && filteredHistoryItems.isEmpty)
    }

    private func filtered(items: [ClipboardItem]) -> [ClipboardItem] {
        guard !searchText.isEmpty else {
            return items
        }

        return items.filter { $0.searchableText.localizedCaseInsensitiveContains(searchText) }
    }

    func startMonitoring() {
        clipboardMonitor.startMonitoring { [weak self] latestItem in
            guard let self else { return }
            self.addClipboardItem(latestItem)
        }
    }

    func stopMonitoring() {
        clipboardMonitor.stopMonitoring()
    }

    func clearHistory() {
        items.removeAll { !$0.isPinned }
    }

    func requestSearchFocus() {
        searchFocusTrigger = UUID()
    }

    func togglePin(for item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        items[index].isPinned.toggle()
    }

    func copyItemToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.content {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .url(let url):
            pasteboard.writeObjects([url as NSURL])
        case .image(let image):
            pasteboard.writeObjects([image])
        }
    }

    private func addClipboardItem(_ item: ClipboardItem) {
        // Skip adding an immediate duplicate at the top of the list.
        if let first = items.first, first.duplicateKey == item.duplicateKey {
            return
        }

        items.insert(item, at: 0)
        enforceHistoryLimit()
    }

    private func enforceHistoryLimit() {
        var remainingNonPinned = historyLimit

        items = items.filter { item in
            if item.isPinned {
                return true
            }

            if remainingNonPinned > 0 {
                remainingNonPinned -= 1
                return true
            }

            return false
        }
    }
}
