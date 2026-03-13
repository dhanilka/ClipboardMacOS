import AppKit
import Foundation

enum DropShelfItemKind {
    case file
    case text
    case url
    case image
}

struct DropShelfItem: Identifiable {
    let id: UUID
    let kind: DropShelfItemKind
    let title: String
    let subtitle: String
    let fileURL: URL?
    let textValue: String?
    let urlValue: URL?
    let imageValue: NSImage?

    init(
        id: UUID = UUID(),
        kind: DropShelfItemKind,
        title: String,
        subtitle: String,
        fileURL: URL? = nil,
        textValue: String? = nil,
        urlValue: URL? = nil,
        imageValue: NSImage? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.fileURL = fileURL
        self.textValue = textValue
        self.urlValue = urlValue
        self.imageValue = imageValue
    }

    var iconName: String {
        switch kind {
        case .file:
            return "doc"
        case .text:
            return "text.alignleft"
        case .url:
            return "link"
        case .image:
            return "photo"
        }
    }
}
