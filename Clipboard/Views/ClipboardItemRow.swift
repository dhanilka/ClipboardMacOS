import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let onPinTapped: () -> Void
    let onSaveEditedText: (String) -> Void
    let onSelected: () -> Void

    @State private var isHovered = false
    @State private var showsLargeImagePreview = false
    @State private var showsLargeTextPreview = false
    @State private var hoverPreviewTask: DispatchWorkItem?
    @State private var dismissPreviewTask: DispatchWorkItem?
    @State private var isPreviewPopoverHovered = false
    @State private var previewSearchText: String = ""
    @State private var previewEditableText: String = ""

    @AppStorage("clipvault.previewDelayMs") private var previewDelayMs: Double = 300
    private let previewDismissDelay: TimeInterval = 0.25

    private var iconName: String {
        switch item.contentType {
        case .text:
            return "text.alignleft"
        case .url:
            return "link"
        case .image:
            return "photo"
        }
    }

    private var contentTypeLabel: String {
        item.contentType.rawValue.uppercased()
    }

    private var textPreviewContent: String? {
        guard case .text(let text) = item.content else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    private var hasUnsavedTextChanges: Bool {
        guard let originalText = textPreviewContent else {
            return false
        }
        return previewEditableText != originalText
    }

    private var imageContent: NSImage? {
        guard case .image(let image) = item.content else { return nil }
        return image
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: iconName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(contentTypeLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(item.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            onPinTapped()
                        } label: {
                            Image(systemName: item.isPinned ? "pin.fill" : "pin")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(item.isPinned ? .yellow : .secondary)
                        .help(item.isPinned ? "Unpin item" : "Pin item")
                    }

                    switch item.content {
                    case .text(let text):
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    case .url(let url):
                        Text(item.previewText)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(url.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    case .image(let image):
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.medium)
                            .scaledToFill()
                            .frame(width: 64, height: 44)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .help("Drag image to drop it into another app")
                            .onDrag {
                                imageItemProvider(for: image)
                            }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelected)

        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isHovered = hovering
            }

            if hovering {
                dismissPreviewTask?.cancel()
                scheduleHoverPreview()
            } else {
                schedulePreviewDismiss()
            }
        }
        .popover(isPresented: $showsLargeImagePreview, arrowEdge: .trailing) {
            if let imageContent {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Image Preview")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Image(nsImage: imageContent)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 560, height: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .onDrag {
                            imageItemProvider(for: imageContent)
                        }

                    Text(item.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(width: 590)
                .onHover { hovering in
                    handlePopoverHoverChange(hovering)
                }
            }
        }
        .popover(isPresented: $showsLargeTextPreview, arrowEdge: .trailing) {
            if let textPreviewContent {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Text Preview")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Spacer()

                        if hasUnsavedTextChanges {
                            Button {
                                onSaveEditedText(previewEditableText)
                            } label: {
                                Image(systemName: "square.and.arrow.down")
                            }
                            .help("Save changes")
                        }
                    }

                    TextField("Search in preview", text: $previewSearchText)
                        .textFieldStyle(.roundedBorder)

                    SearchableEditableTextView(
                        text: $previewEditableText,
                        searchQuery: previewSearchText
                    )
                    .frame(width: 520, height: 300)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .onAppear {
                        previewEditableText = textPreviewContent
                    }

                    if !previewSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       previewEditableText.range(
                           of: previewSearchText,
                           options: [.caseInsensitive, .diacriticInsensitive]
                       ) == nil {
                        Text("No matches found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("You can edit, select multiple lines, and copy from here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(width: 560)
                .onHover { hovering in
                    handlePopoverHoverChange(hovering)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.28) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.6)
        )
    }

    private func scheduleHoverPreview() {
        hoverPreviewTask?.cancel()
        dismissPreviewTask?.cancel()

        let task = DispatchWorkItem {
            guard isHovered else { return }

            if textPreviewContent != nil {
                previewSearchText = ""
                previewEditableText = textPreviewContent ?? ""
                showsLargeTextPreview = true
            }

            if imageContent != nil {
                showsLargeImagePreview = true
            }
        }

        hoverPreviewTask = task
        let secondsDelay = max(0, previewDelayMs) / 1000.0
        DispatchQueue.main.asyncAfter(deadline: .now() + secondsDelay, execute: task)
    }

    private func cancelHoverPreview() {
        hoverPreviewTask?.cancel()
        hoverPreviewTask = nil
        dismissPreviewTask?.cancel()
        dismissPreviewTask = nil

        showsLargeTextPreview = false
        showsLargeImagePreview = false
        isPreviewPopoverHovered = false
        previewSearchText = ""
        previewEditableText = ""
    }

    private func schedulePreviewDismiss() {
        dismissPreviewTask?.cancel()

        let task = DispatchWorkItem {
            guard !isHovered, !isPreviewPopoverHovered else {
                return
            }
            cancelHoverPreview()
        }

        dismissPreviewTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + previewDismissDelay, execute: task)
    }

    private func handlePopoverHoverChange(_ hovering: Bool) {
        isPreviewPopoverHovered = hovering

        if hovering {
            dismissPreviewTask?.cancel()
        } else if !isHovered {
            schedulePreviewDismiss()
        }
    }

    private func imageItemProvider(for image: NSImage) -> NSItemProvider {
        let provider = NSItemProvider()
        let imagePNGData = pngData(from: image)
        let tempFileURL = createTemporaryImageFileURL(pngData: imagePNGData, fallbackImage: image)

        // Expose both PNG and TIFF so more target apps can accept the drag payload.
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            completion(imagePNGData, nil)
            return nil
        }

        provider.registerDataRepresentation(forTypeIdentifier: UTType.tiff.identifier, visibility: .all) { completion in
            completion(image.tiffRepresentation, nil)
            return nil
        }

        if let tempFileURL {
            // Many web-based chat inputs accept file URL drops instead of raw image bytes.
            provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
                completion(tempFileURL.absoluteString.data(using: .utf8), nil)
                return nil
            }

            provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
                completion(tempFileURL, false, nil)
                return nil
            }
        }

        provider.suggestedName = "ClipVault Image"
        return provider
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

    private func createTemporaryImageFileURL(pngData: Data?, fallbackImage: NSImage) -> URL? {
        let data: Data
        let fileExtension: String

        if let pngData {
            data = pngData
            fileExtension = "png"
        } else if let tiffData = fallbackImage.tiffRepresentation {
            data = tiffData
            fileExtension = "tiff"
        } else {
            return nil
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ClipVaultDrag", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            let url = tempDirectory.appendingPathComponent("clipvault-\(UUID().uuidString).\(fileExtension)")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

}

private struct SearchableEditableTextView: NSViewRepresentable {
    @Binding var text: String
    let searchQuery: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindPanel = true
        textView.enabledTextCheckingTypes = 0
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.drawsBackground = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.applySearchSelection(force: true, scrollToMatch: true)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }

        if !context.coordinator.isUpdatingProgrammatically, textView.string != text {
            context.coordinator.isUpdatingProgrammatically = true
            textView.string = text
            context.coordinator.isUpdatingProgrammatically = false
        }

        context.coordinator.applySearchSelection(force: false, scrollToMatch: false)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SearchableEditableTextView
        weak var textView: NSTextView?
        var isUpdatingProgrammatically = false
        private var lastAppliedQuery: String = ""
        private var lastAppliedText: String = ""
        private let highlightColor = NSColor.systemYellow.withAlphaComponent(0.35)

        init(parent: SearchableEditableTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !isUpdatingProgrammatically else { return }
            parent.text = textView.string
            applySearchSelection(force: true, scrollToMatch: false)
        }

        /// Keeps search behavior responsive without forcing selection on every render update.
        func applySearchSelection(force: Bool, scrollToMatch: Bool) {
            guard let textView else { return }
            guard let layoutManager = textView.layoutManager else { return }

            let fullText = textView.string
            let nsText = fullText as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)

            let query = parent.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let queryChanged = query != lastAppliedQuery
            let textChanged = fullText != lastAppliedText
            guard force || queryChanged || textChanged else { return }

            lastAppliedQuery = query
            lastAppliedText = fullText

            // Remove old temporary highlights before applying new ones.
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)

            guard !query.isEmpty else { return }

            var firstMatch: NSRange?
            var searchRange = fullRange

            while searchRange.location < nsText.length {
                let found = nsText.range(
                    of: query,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchRange
                )

                guard found.location != NSNotFound else { break }
                if firstMatch == nil {
                    firstMatch = found
                }

                layoutManager.addTemporaryAttribute(
                    .backgroundColor,
                    value: highlightColor,
                    forCharacterRange: found
                )

                let nextLocation = found.location + max(found.length, 1)
                searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
            }

            guard let firstMatch else { return }

            // Keep the previous "jump to first result" behavior when query changes.
            if queryChanged {
                isUpdatingProgrammatically = true
                textView.setSelectedRange(firstMatch)
                isUpdatingProgrammatically = false

                if scrollToMatch {
                    textView.scrollRangeToVisible(firstMatch)
                }
                textView.showFindIndicator(for: firstMatch)
            }
        }
    }
}

#Preview {
    ClipboardItemRow(
        item: .fromText("Example clipboard value\nwith second line")!,
        onPinTapped: {},
        onSaveEditedText: { _ in },
        onSelected: {}
    )
        .padding()
}
