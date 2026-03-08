import AppKit
import Foundation
import CryptoKit

enum ClipboardContentType: String, Codable {
    case text
    case image
    case url
}

enum ClipboardContent {
    case text(String)
    case image(NSImage)
    case url(URL)
}

/// Represents one captured clipboard entry.
struct ClipboardItem: Identifiable {
    let id: UUID
    let content: ClipboardContent
    let contentType: ClipboardContentType
    let timestamp: Date
    let previewText: String
    var isPinned: Bool

    /// Internal signature used for quick duplicate checks.
    let duplicateKey: String

    init(id: UUID = UUID(), content: ClipboardContent, contentType: ClipboardContentType, timestamp: Date = Date(), previewText: String, isPinned: Bool = false, duplicateKey: String) {
        self.id = id
        self.content = content
        self.contentType = contentType
        self.timestamp = timestamp
        self.previewText = previewText
        self.isPinned = isPinned
        self.duplicateKey = duplicateKey
    }
}

extension ClipboardItem {
    static func fromText(_ text: String) -> ClipboardItem? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let preview = String(normalized.prefix(240))

        return ClipboardItem(
            content: .text(normalized),
            contentType: .text,
            previewText: preview,
            duplicateKey: "text:\(normalized)"
        )
    }

    static func fromURL(_ url: URL) -> ClipboardItem {
        let value = url.absoluteString
        let domain = url.host(percentEncoded: false) ?? value
        return ClipboardItem(
            content: .url(url),
            contentType: .url,
            previewText: String(domain.prefix(140)),
            duplicateKey: "url:\(value)"
        )
    }

    static func fromImage(_ image: NSImage) -> ClipboardItem? {
        guard let data = image.tiffRepresentation else { return nil }
        let digest = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        let width = Int(image.size.width.rounded())
        let height = Int(image.size.height.rounded())
        let preview = "Image \(width)x\(height)"

        return ClipboardItem(
            content: .image(image),
            contentType: .image,
            previewText: preview,
            duplicateKey: "image:\(digest)"
        )
    }

    var searchableText: String {
        switch content {
        case .text(let text):
            return "\(previewText) \(text)"
        case .url(let url):
            return "\(previewText) \(url.absoluteString)"
        case .image:
            return previewText
        }
    }
}
