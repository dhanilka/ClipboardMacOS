import SwiftUI
import Combine
import AppKit
import Carbon

struct ClipboardListView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    let onItemSelected: () -> Void
    let showsFooter: Bool

    @FocusState private var isSearchFocused: Bool
    @State private var showClearConfirmation = false
    @State private var isSearchExpanded = false
    @State private var isCopyToastVisible = false
    @State private var copyToastWorkItem: DispatchWorkItem?
    @State private var keyboardSelectedItemID: UUID?
    @State private var keyEventMonitor: Any?
    @State private var ocrSourceItem: ClipboardItem?
    @State private var ocrRecognizedText: String = ""
    @State private var ocrErrorMessage: String?
    @State private var isOCRRunning = false
    @State private var ocrTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    toggleSearchBar()
                } label: {
                    Image(systemName: isSearchExpanded ? "xmark.circle.fill" : "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                }
                .buttonStyle(.plain)
                .help(isSearchExpanded ? "Hide search" : "Show search")

                if isSearchExpanded {
                    TextField("Search clipboard history", text: $viewModel.searchText)
                        .textFieldStyle(.roundedBorder)
                        .focused($isSearchFocused)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                Spacer(minLength: 4)

                Menu {
                    ForEach(ClipboardContentFilter.allCases) { filter in
                        Button {
                            viewModel.selectedContentFilter = filter
                        } label: {
                            if viewModel.selectedContentFilter == filter {
                                Label(filter.title, systemImage: "checkmark")
                            } else {
                                Text(filter.title)
                            }
                        }
                    }
                } label: {
                    Label(viewModel.selectedContentFilter.title, systemImage: "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.borderlessButton)
            }
            .animation(.snappy(duration: 0.18), value: isSearchExpanded)

            ScrollViewReader { proxy in
                ScrollView {
                    if !viewModel.hasVisibleItems {
                        ContentUnavailableView(
                            "No Clipboard History",
                            systemImage: "clipboard",
                            description: Text("Copied items will appear here.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if !viewModel.filteredPinnedItems.isEmpty {
                                sectionHeader("Pinned")

                                ForEach(viewModel.filteredPinnedItems) { item in
                                    ClipboardItemRow(
                                        item: item,
                                        isImageSelected: viewModel.isImageSelected(item),
                                        isKeyboardSelected: keyboardSelectedItemID == item.id,
                                        onCopyTapped: { handleCopyButtonTap(for: item) },
                                        onPinTapped: { viewModel.togglePin(for: item) },
                                        onExtractTextTapped: { startOCR(for: item) },
                                        onImageSelectionToggle: { viewModel.toggleImageSelection(for: item) },
                                        onClearImageSelection: { viewModel.clearImageSelection() },
                                        onSaveEditedText: { editedText in
                                            viewModel.saveEditedText(for: item, updatedText: editedText)
                                        },
                                        onImageDragFileURLs: { draggedItem in
                                            viewModel.imageDragFileURLs(for: draggedItem)
                                        },
                                        onSelected: {
                                            viewModel.clearImageSelection()
                                            viewModel.copyItemToClipboard(item)
                                            onItemSelected()
                                        }
                                    )
                                    .id(item.id)
                                }
                            }

                            if !viewModel.filteredHistoryItems.isEmpty {
                                sectionHeader("Recent")

                                ForEach(viewModel.filteredHistoryItems) { item in
                                    ClipboardItemRow(
                                        item: item,
                                        isImageSelected: viewModel.isImageSelected(item),
                                        isKeyboardSelected: keyboardSelectedItemID == item.id,
                                        onCopyTapped: { handleCopyButtonTap(for: item) },
                                        onPinTapped: { viewModel.togglePin(for: item) },
                                        onExtractTextTapped: { startOCR(for: item) },
                                        onImageSelectionToggle: { viewModel.toggleImageSelection(for: item) },
                                        onClearImageSelection: { viewModel.clearImageSelection() },
                                        onSaveEditedText: { editedText in
                                            viewModel.saveEditedText(for: item, updatedText: editedText)
                                        },
                                        onImageDragFileURLs: { draggedItem in
                                            viewModel.imageDragFileURLs(for: draggedItem)
                                        },
                                        onSelected: {
                                            viewModel.clearImageSelection()
                                            viewModel.copyItemToClipboard(item)
                                            onItemSelected()
                                        }
                                    )
                                    .id(item.id)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .onChange(of: keyboardSelectedItemID) { _, selectedID in
                    guard let selectedID else { return }
                    withAnimation(.snappy(duration: 0.14)) {
                        proxy.scrollTo(selectedID, anchor: .center)
                    }
                }
                .background(
                    ScrollViewAppearanceConfigurator()
                )
            }
            .animation(.snappy(duration: 0.2), value: viewModel.searchText)
            .animation(.snappy(duration: 0.2), value: viewModel.selectedContentFilter)
            .animation(.snappy(duration: 0.2), value: viewModel.items.count)

            if showsFooter {
                Divider()

                HStack {
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Clear history")
                    .disabled(!viewModel.hasNonPinnedItems)

                    Spacer()

                    HStack(spacing: 10) {
                        SettingsLink {
                            Image(systemName: "gearshape")
                        }
                        .help("Settings")

                        Button {
                            NSApp.terminate(nil)
                        } label: {
                            Image(systemName: "power")
                        }
                        .buttonStyle(.plain)
                        .help("Quit ClipVault")
                    }
                }
            }
        }
        .padding(14)
        .overlay(alignment: .top) {
            if isCopyToastVisible {
                Text("Copied")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.regularMaterial)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.6)
                    )
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onReceive(viewModel.$searchFocusTrigger.dropFirst()) { _ in
            if !isSearchExpanded {
                withAnimation(.snappy(duration: 0.18)) {
                    isSearchExpanded = true
                }
            }
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .confirmationDialog(
            "Are you sure you want to clear history?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                viewModel.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all non-pinned clipboard items.")
        }
        .animation(.snappy(duration: 0.16), value: isCopyToastVisible)
        .onAppear {
            installKeyEventMonitor()
        }
        .onDisappear {
            removeKeyEventMonitor()
            dismissOCRSheet()
        }
        .onChange(of: viewModel.searchText) { _, _ in
            syncKeyboardSelection()
        }
        .onChange(of: viewModel.selectedContentFilter) { _, _ in
            syncKeyboardSelection()
        }
        .onChange(of: viewModel.items.map(\.id)) { _, _ in
            syncKeyboardSelection()
        }
        .sheet(
            isPresented: Binding(
                get: { ocrSourceItem != nil },
                set: { isPresented in
                    if !isPresented {
                        dismissOCRSheet()
                    }
                }
            )
        ) {
            if let ocrSourceItem {
                ocrResultSheet(for: ocrSourceItem)
            }
        }
    }

    private var orderedVisibleItems: [ClipboardItem] {
        viewModel.filteredPinnedItems + viewModel.filteredHistoryItems
    }

    private func toggleSearchBar() {
        withAnimation(.snappy(duration: 0.18)) {
            isSearchExpanded.toggle()
        }

        if isSearchExpanded {
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        } else {
            isSearchFocused = false
            viewModel.searchText = ""
        }
    }

    private func handleCopyButtonTap(for item: ClipboardItem) {
        viewModel.copyItemToClipboard(item)
        showCopyToast()
    }

    private func installKeyEventMonitor() {
        guard keyEventMonitor == nil else { return }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event) ? nil : event
        }
    }

    private func removeKeyEventMonitor() {
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
            self.keyEventMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard NSApp.isActive else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.keyCode {
        case UInt16(kVK_Tab):
            let hasDisallowedModifiers =
                flags.contains(.command) ||
                flags.contains(.control) ||
                flags.contains(.option)
            guard !hasDisallowedModifiers else { return false }
            moveKeyboardSelection(backward: flags.contains(.shift))
            return true

        case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
            let hasDisallowedModifiers =
                flags.contains(.command) ||
                flags.contains(.control) ||
                flags.contains(.option)
            guard !hasDisallowedModifiers else { return false }
            return activateKeyboardSelection()

        default:
            return false
        }
    }

    private func moveKeyboardSelection(backward: Bool) {
        let items = orderedVisibleItems
        guard !items.isEmpty else {
            keyboardSelectedItemID = nil
            return
        }

        let currentIndex = items.firstIndex { $0.id == keyboardSelectedItemID }
        let nextIndex: Int

        if let currentIndex {
            if backward {
                nextIndex = (currentIndex - 1 + items.count) % items.count
            } else {
                nextIndex = (currentIndex + 1) % items.count
            }
        } else {
            nextIndex = backward ? (items.count - 1) : 0
        }

        keyboardSelectedItemID = items[nextIndex].id
    }

    private func activateKeyboardSelection() -> Bool {
        let items = orderedVisibleItems
        guard !items.isEmpty else { return false }

        let selectedItem =
            items.first(where: { $0.id == keyboardSelectedItemID }) ??
            items.first

        guard let selectedItem else { return false }
        keyboardSelectedItemID = selectedItem.id
        viewModel.clearImageSelection()
        viewModel.copyItemToClipboard(selectedItem)
        onItemSelected()
        return true
    }

    private func syncKeyboardSelection() {
        let items = orderedVisibleItems
        guard !items.isEmpty else {
            keyboardSelectedItemID = nil
            return
        }

        if let keyboardSelectedItemID {
            if items.contains(where: { $0.id == keyboardSelectedItemID }) {
                return
            }
            self.keyboardSelectedItemID = nil
        }
    }

    private func showCopyToast() {
        copyToastWorkItem?.cancel()

        withAnimation(.snappy(duration: 0.14)) {
            isCopyToastVisible = true
        }

        let workItem = DispatchWorkItem {
            withAnimation(.snappy(duration: 0.14)) {
                isCopyToastVisible = false
            }
        }
        copyToastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: workItem)
    }

    private func startOCR(for item: ClipboardItem) {
        guard case .image(let image) = item.content else {
            return
        }

        guard let imageData = image.tiffRepresentation else {
            ocrSourceItem = item
            isOCRRunning = false
            ocrRecognizedText = ""
            ocrErrorMessage = "Unable to read this image for OCR."
            return
        }

        ocrTask?.cancel()
        ocrSourceItem = item
        isOCRRunning = true
        ocrRecognizedText = ""
        ocrErrorMessage = nil

        let sourceItemID = item.id
        ocrTask = Task {
            do {
                let extractedText = try await viewModel.extractTextFromImageData(imageData)
                try Task.checkCancellation()
                await MainActor.run {
                    guard ocrSourceItem?.id == sourceItemID else { return }
                    isOCRRunning = false
                    ocrRecognizedText = extractedText
                }
            } catch is CancellationError {
                // Cancel is expected when the sheet is dismissed or user reruns OCR.
            } catch {
                await MainActor.run {
                    guard ocrSourceItem?.id == sourceItemID else { return }
                    isOCRRunning = false
                    ocrErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func dismissOCRSheet() {
        ocrTask?.cancel()
        ocrTask = nil
        ocrSourceItem = nil
        isOCRRunning = false
        ocrRecognizedText = ""
        ocrErrorMessage = nil
    }

    @ViewBuilder
    private func ocrResultSheet(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Image OCR", systemImage: "text.viewfinder")
                    .font(.headline)

                Spacer()

                Text(item.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isOCRRunning {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Extracting text in background…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let ocrErrorMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Text(ocrErrorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button("Retry OCR") {
                        startOCR(for: item)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                TextEditor(text: $ocrRecognizedText)
                    .font(.system(.body, design: .default))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .frame(minHeight: 260)
            }

            HStack {
                Button("Cancel") {
                    dismissOCRSheet()
                }

                Spacer()

                Button("Copy") {
                    viewModel.copyExtractedTextToClipboard(ocrRecognizedText)
                    showCopyToast()
                }
                .disabled(isOCRRunning || ocrRecognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Save as Text Item") {
                    viewModel.saveExtractedTextAsNewItem(ocrRecognizedText)
                    dismissOCRSheet()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isOCRRunning || ocrRecognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 560, height: 420)
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }
}

private struct ScrollViewAppearanceConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let scrollView = nsView.enclosingScrollView else { return }
            scrollView.scrollerStyle = .overlay
            scrollView.hasVerticalScroller = true
            scrollView.verticalScroller?.controlSize = .small
            scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 2)
            scrollView.drawsBackground = false
            scrollView.backgroundColor = .clear
        }
    }
}

#Preview {
    ClipboardListView(viewModel: ClipboardViewModel(), onItemSelected: {}, showsFooter: true)
        .frame(width: 350, height: 420)
}
