import SwiftUI

struct DropShelfView: View {
    @ObservedObject var viewModel: DropShelfViewModel
    let onClose: () -> Void

    @AppStorage(appThemeStorageKey) private var appThemeRawValue = AppTheme.dark.rawValue

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .dark
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("DropShelf", systemImage: "tray.and.arrow.down")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if viewModel.hasItems {
                    Button {
                        viewModel.clearAll()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear shelf")
                }

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close shelf")
            }

            Text("Drop now. Drag out later.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                if viewModel.items.isEmpty {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.1, dash: [6]))
                        .foregroundStyle(viewModel.isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)

                                Text("Drag files, text, links, or images here")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                        }
                        .padding(.top, 8)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.items) { item in
                            DropShelfItemRow(item: item, onRemove: {
                                viewModel.removeItem(item)
                            })
                            .onDrag {
                                viewModel.itemProvider(for: item)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .scrollIndicators(.visible)
        }
        .padding(14)
        .frame(width: 320, height: 360)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.22))
                if viewModel.isDropTargeted {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 0.8)
        )
        .onDrop(of: viewModel.supportedTypeIdentifiers, isTargeted: $viewModel.isDropTargeted) { providers in
            viewModel.handleDrop(providers)
            return true
        }
        .preferredColorScheme(selectedTheme.colorScheme)
    }
}

private struct DropShelfItemRow: View {
    let item: DropShelfItem
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let image = item.imageValue {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else {
                    Image(systemName: item.iconName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text(item.subtitle)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.32))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 0.7)
        )
    }
}

#Preview {
    DropShelfView(viewModel: DropShelfViewModel(), onClose: {})
}
