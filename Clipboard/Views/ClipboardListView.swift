import SwiftUI
import Combine

struct ClipboardListView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    let onItemSelected: () -> Void

    @FocusState private var isSearchFocused: Bool
    @State private var showClearConfirmation = false
    @State private var isSearchExpanded = false

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

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .padding(14)
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
