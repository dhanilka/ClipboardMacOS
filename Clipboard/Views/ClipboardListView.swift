import SwiftUI
import Combine
import AppKit

struct ClipboardListView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    let onItemSelected: () -> Void

    @FocusState private var isSearchFocused: Bool
    @State private var showClearConfirmation = false
    @State private var isSearchExpanded = false
    @State private var isCopyToastVisible = false
    @State private var copyToastWorkItem: DispatchWorkItem?

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
                                    onCopyTapped: { handleCopyButtonTap(for: item) },
                                    onPinTapped: { viewModel.togglePin(for: item) },
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
                            }
                        }

                        if !viewModel.filteredHistoryItems.isEmpty {
                            sectionHeader("Recent")

                            ForEach(viewModel.filteredHistoryItems) { item in
                                ClipboardItemRow(
                                    item: item,
                                    isImageSelected: viewModel.isImageSelected(item),
                                    onCopyTapped: { handleCopyButtonTap(for: item) },
                                    onPinTapped: { viewModel.togglePin(for: item) },
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
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .animation(.snappy(duration: 0.2), value: viewModel.searchText)
            .animation(.snappy(duration: 0.2), value: viewModel.selectedContentFilter)
            .animation(.snappy(duration: 0.2), value: viewModel.items.count)

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

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }
}

#Preview {
    ClipboardListView(viewModel: ClipboardViewModel(), onItemSelected: {})
        .frame(width: 350, height: 420)
}
