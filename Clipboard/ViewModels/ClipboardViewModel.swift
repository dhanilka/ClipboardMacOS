import Foundation
import Combine
import AppKit
import SwiftUI
import CryptoKit

@MainActor
final class ClipboardViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published private(set) var searchFocusTrigger: UUID = UUID()
    @Published private(set) var items: [ClipboardItem] = []

    private let clipboardMonitor: ClipboardMonitorService
    private let storageService: ClipboardStorageService
    private let historyLimit = 100
    private var cancellables: Set<AnyCancellable> = []
    private var isBootstrapping = true

    init(
        clipboardMonitor: ClipboardMonitorService,
        storageService: ClipboardStorageService
    ) {
        self.clipboardMonitor = clipboardMonitor
        self.storageService = storageService

        Task { [weak self] in
            await self?.bootstrapHistory()
        }
    }

    convenience init() {
        self.init(
            clipboardMonitor: ClipboardMonitorService(),
            storageService: ClipboardStorageService()
        )
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

    func saveEditedText(for item: ClipboardItem, updatedText: String) {
        guard case .text(let currentText) = item.content else {
            return
        }

        let normalized = updatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized != currentText else {
            return
        }

        let newDuplicateKey = "text:\(normalized)"
        let duplicateWasPinned = items.contains { existing in
            existing.id != item.id && existing.duplicateKey == newDuplicateKey && existing.isPinned
        }

        let editedItem = ClipboardItem(
            id: item.id,
            content: .text(normalized),
            contentType: .text,
            timestamp: Date(),
            previewText: String(normalized.prefix(240)),
            isPinned: item.isPinned || duplicateWasPinned,
            duplicateKey: newDuplicateKey
        )

        var updated = items
        updated.removeAll { existing in
            existing.id == item.id || existing.duplicateKey == newDuplicateKey
        }
        updated.insert(editedItem, at: 0)
        enforceHistoryLimit(on: &updated)
        items = updated
    }

    func exportHistory(to url: URL) async throws {
        let archive = makeArchive(from: items)
        try await storageService.exportArchive(archive, to: url)
    }

    func importHistory(from url: URL) async throws {
        let archive = try await storageService.importArchive(from: url)
        let importedItems = archive.items.compactMap(makeClipboardItem(from:))

        var merged = items
        for importedItem in importedItems.reversed() {
            upsertClipboardItem(importedItem, into: &merged)
        }
        enforceHistoryLimit(on: &merged)
        items = merged
    }

    private func bootstrapHistory() async {
        await restorePersistedHistory()
        setupAutoSave()
        isBootstrapping = false
        startMonitoring()
    }

    private func restorePersistedHistory() async {
        do {
            guard let archive = try await storageService.loadArchive() else {
                return
            }

            let restoredItems = archive.items.compactMap(makeClipboardItem(from:))
            items = normalizedHistory(from: restoredItems)
        } catch {
            // Ignore unreadable persisted history and continue with a fresh in-memory list.
            items = normalizedHistory(from: items)
        }
    }

    private func setupAutoSave() {
        $items
            .dropFirst()
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.isBootstrapping else { return }
                Task { [weak self] in
                    await self?.persistCurrentHistory()
                }
            }
            .store(in: &cancellables)
    }

    private func persistCurrentHistory() async {
        do {
            let archive = makeArchive(from: items)
            try await storageService.saveArchive(archive)
        } catch {
            // Persistence failures should not block clipboard monitoring flow.
        }
    }

    private func addClipboardItem(_ item: ClipboardItem) {
        var updated = items
        upsertClipboardItem(item, into: &updated)
        enforceHistoryLimit(on: &updated)
        items = updated
    }

    private func normalizedHistory(from source: [ClipboardItem]) -> [ClipboardItem] {
        var normalized: [ClipboardItem] = []
        for item in source.reversed() {
            upsertClipboardItem(item, into: &normalized)
        }
        enforceHistoryLimit(on: &normalized)
        return normalized
    }

    private func upsertClipboardItem(_ item: ClipboardItem, into list: inout [ClipboardItem]) {
        let wasPinned = list.contains { existing in
            existing.duplicateKey == item.duplicateKey && existing.isPinned
        }
        list.removeAll { existing in
            existing.duplicateKey == item.duplicateKey
        }

        var newestItem = item
        newestItem.isPinned = newestItem.isPinned || wasPinned
        list.insert(newestItem, at: 0)
    }

    private func enforceHistoryLimit(on list: inout [ClipboardItem]) {
        var remainingNonPinned = historyLimit

        list = list.filter { item in
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

    private func makeArchive(from items: [ClipboardItem]) -> ClipboardArchive {
        let persistedItems = items.compactMap(makePersistedItem(from:))
        return ClipboardArchive(items: persistedItems)
    }

    private func makePersistedItem(from item: ClipboardItem) -> PersistedClipboardItem? {
        switch item.content {
        case .text(let text):
            return PersistedClipboardItem(
                id: item.id,
                contentType: .text,
                timestamp: item.timestamp,
                previewText: item.previewText,
                isPinned: item.isPinned,
                duplicateKey: item.duplicateKey,
                textValue: text,
                urlValue: nil,
                imageBase64: nil
            )
        case .url(let url):
            return PersistedClipboardItem(
                id: item.id,
                contentType: .url,
                timestamp: item.timestamp,
                previewText: item.previewText,
                isPinned: item.isPinned,
                duplicateKey: item.duplicateKey,
                textValue: nil,
                urlValue: url.absoluteString,
                imageBase64: nil
            )
        case .image(let image):
            guard let imageData = pngData(from: image) ?? image.tiffRepresentation else {
                return nil
            }
            return PersistedClipboardItem(
                id: item.id,
                contentType: .image,
                timestamp: item.timestamp,
                previewText: item.previewText,
                isPinned: item.isPinned,
                duplicateKey: item.duplicateKey,
                textValue: nil,
                urlValue: nil,
                imageBase64: imageData.base64EncodedString()
            )
        }
    }

    private func makeClipboardItem(from persisted: PersistedClipboardItem) -> ClipboardItem? {
        switch persisted.contentType {
        case .text:
            guard let text = persisted.textValue else { return nil }
            return ClipboardItem(
                id: persisted.id,
                content: .text(text),
                contentType: .text,
                timestamp: persisted.timestamp,
                previewText: persisted.previewText,
                isPinned: persisted.isPinned,
                duplicateKey: persisted.duplicateKey.isEmpty ? "text:\(text)" : persisted.duplicateKey
            )
        case .url:
            guard let urlString = persisted.urlValue, let url = URL(string: urlString) else { return nil }
            return ClipboardItem(
                id: persisted.id,
                content: .url(url),
                contentType: .url,
                timestamp: persisted.timestamp,
                previewText: persisted.previewText,
                isPinned: persisted.isPinned,
                duplicateKey: persisted.duplicateKey.isEmpty ? "url:\(url.absoluteString)" : persisted.duplicateKey
            )
        case .image:
            guard
                let base64 = persisted.imageBase64,
                let imageData = Data(base64Encoded: base64),
                let image = NSImage(data: imageData)
            else {
                return nil
            }
            return ClipboardItem(
                id: persisted.id,
                content: .image(image),
                contentType: .image,
                timestamp: persisted.timestamp,
                previewText: persisted.previewText,
                isPinned: persisted.isPinned,
                duplicateKey: persisted.duplicateKey.isEmpty ? imageDuplicateKey(from: imageData) : persisted.duplicateKey
            )
        }
    }

    private func pngData(from image: NSImage) -> Data? {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func imageDuplicateKey(from imageData: Data) -> String {
        let digest = SHA256.hash(data: imageData).compactMap { String(format: "%02x", $0) }.joined()
        return "image:\(digest)"
    }
}
