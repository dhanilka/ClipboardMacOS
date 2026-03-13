import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DropShelfViewModel: ObservableObject {
    @Published private(set) var items: [DropShelfItem] = []
    @Published var isDropTargeted: Bool = false

    let supportedTypeIdentifiers: [String] = [
        UTType.fileURL.identifier,
        UTType.url.identifier,
        UTType.plainText.identifier,
        UTType.image.identifier,
        UTType.png.identifier,
        UTType.tiff.identifier
    ]

    private let maxItems = 24
    private let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClipVaultDropShelf", isDirectory: true)

    var hasItems: Bool {
        !items.isEmpty
    }

    func handleDrop(_ providers: [NSItemProvider]) {
        Task {
            var parsedItems: [DropShelfItem] = []
            for provider in providers {
                if let item = await parseItem(from: provider) {
                    parsedItems.append(item)
                }
            }

            guard !parsedItems.isEmpty else { return }
            for item in parsedItems.reversed() {
                items.insert(item, at: 0)
            }

            if items.count > maxItems {
                items = Array(items.prefix(maxItems))
            }
        }
    }

    func removeItem(_ item: DropShelfItem) {
        items.removeAll { $0.id == item.id }
    }

    func clearAll() {
        items.removeAll()
    }

    func itemProvider(for item: DropShelfItem) -> NSItemProvider {
        if let fileURL = item.fileURL {
            let provider = NSItemProvider()
            provider.registerObject(fileURL as NSURL, visibility: .all)

            let fileType = UTType(filenameExtension: fileURL.pathExtension) ?? .data
            provider.registerFileRepresentation(
                forTypeIdentifier: fileType.identifier,
                fileOptions: [],
                visibility: .all
            ) { completion in
                completion(fileURL, false, nil)
                return nil
            }
            provider.suggestedName = fileURL.lastPathComponent
            return provider
        }

        if let urlValue = item.urlValue {
            return NSItemProvider(object: urlValue as NSURL)
        }

        if let textValue = item.textValue {
            return NSItemProvider(object: textValue as NSString)
        }

        if let imageValue = item.imageValue {
            return NSItemProvider(object: imageValue)
        }

        return NSItemProvider()
    }

    private func parseItem(from provider: NSItemProvider) async -> DropShelfItem? {
        if provider.canLoadObject(ofClass: NSURL.self),
           let nsURL = await loadObject(ofClass: NSURL.self, from: provider) {
            let url = nsURL as URL
            if url.isFileURL {
                return DropShelfItem(
                    kind: .file,
                    title: url.lastPathComponent,
                    subtitle: url.path,
                    fileURL: url
                )
            }

            return DropShelfItem(
                kind: .url,
                title: url.host(percentEncoded: false) ?? url.absoluteString,
                subtitle: url.absoluteString,
                urlValue: url
            )
        }

        if provider.canLoadObject(ofClass: NSImage.self),
           let image = await loadObject(ofClass: NSImage.self, from: provider) {
            if let fileURL = persistImageToTemporaryFile(image) {
                return DropShelfItem(
                    kind: .image,
                    title: fileURL.lastPathComponent,
                    subtitle: "Image",
                    fileURL: fileURL,
                    imageValue: image
                )
            }

            return DropShelfItem(
                kind: .image,
                title: "Image",
                subtitle: "Dragged image",
                imageValue: image
            )
        }

        if provider.canLoadObject(ofClass: NSString.self),
           let textObject = await loadObject(ofClass: NSString.self, from: provider) {
            let text = String(textObject).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            if let url = URL(string: text), url.scheme != nil {
                return DropShelfItem(
                    kind: .url,
                    title: url.host(percentEncoded: false) ?? url.absoluteString,
                    subtitle: url.absoluteString,
                    urlValue: url
                )
            }

            let preview = text.count > 80 ? String(text.prefix(80)) + "..." : text
            return DropShelfItem(
                kind: .text,
                title: "Text",
                subtitle: preview,
                textValue: text
            )
        }

        return nil
    }

    private func loadObject<T: NSItemProviderReading>(ofClass objectType: T.Type, from provider: NSItemProvider) async -> T? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: objectType) { object, _ in
                continuation.resume(returning: object as? T)
            }
        }
    }

    private func persistImageToTemporaryFile(_ image: NSImage) -> URL? {
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            return nil
        }

        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            let url = temporaryDirectory.appendingPathComponent("dropshelf-\(UUID().uuidString).png")
            try pngData.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
