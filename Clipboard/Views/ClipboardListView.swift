import SwiftUI
import Combine

struct ClipboardListView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    let onItemSelected: () -> Void

    @FocusState private var isSearchFocused: Bool
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(spacing: 12) {
            TextField("Search clipboard history", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)

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
                                    onPinTapped: { viewModel.togglePin(for: item) },
                                    onSaveEditedText: { editedText in
                                        viewModel.saveEditedText(for: item, updatedText: editedText)
                                    },
                                    onSelected: {
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
                                    onPinTapped: { viewModel.togglePin(for: item) },
                                    onSaveEditedText: { editedText in
                                        viewModel.saveEditedText(for: item, updatedText: editedText)
                                    },
                                    onSelected: {
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
        .onAppear {
            isSearchFocused = true
        }
        .onReceive(viewModel.$searchFocusTrigger.dropFirst()) { _ in
            isSearchFocused = true
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
