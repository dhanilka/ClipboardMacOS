import SwiftUI

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let onPinTapped: () -> Void
    let onSelected: () -> Void

    @State private var isHovered = false
    @State private var showsLargeImagePreview = false
    @State private var showsLargeTextPreview = false
    @State private var hoverPreviewTask: DispatchWorkItem?
    @State private var dismissPreviewTask: DispatchWorkItem?
    @State private var isPreviewPopoverHovered = false

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

    private var hoverTextPreview: String? {
        guard case .text(let text) = item.content else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
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
            if let hoverTextPreview {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Text Preview")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    ScrollView(.vertical) {
                        Text(hoverTextPreview)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                    }
                    .frame(width: 520, height: 300)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )

                    Text("Select any part to copy")
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

            if hoverTextPreview != nil {
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
}

#Preview {
    ClipboardItemRow(item: .fromText("Example clipboard value\nwith second line")!, onPinTapped: {}, onSelected: {})
        .padding()
}
