import SwiftUI

enum MenuBarPresentationStyle {
    case popover
    case quickPicker
}

struct MenuBarView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    @AppStorage(appThemeStorageKey) private var appThemeRawValue = AppTheme.dark.rawValue

    let onClosePopover: () -> Void
    let presentationStyle: MenuBarPresentationStyle

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .dark
    }

    private var showsTitle: Bool {
        presentationStyle == .popover
    }

    private var showsFooter: Bool {
        presentationStyle == .popover
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.42),
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 0.8)

            VStack(alignment: .leading, spacing: 10) {
                if showsTitle {
                    Text("ClipVault")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                ClipboardListView(
                    viewModel: viewModel,
                    onItemSelected: onClosePopover,
                    showsFooter: showsFooter
                )
            }
            .padding(12)
        }
        // Keep popover close to requested size for a compact menu bar workflow.
        .frame(width: 350, height: 440)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 18, x: 0, y: 8)
        .preferredColorScheme(selectedTheme.colorScheme)
    }
}

#Preview {
    MenuBarView(
        viewModel: ClipboardViewModel(),
        onClosePopover: {},
        presentationStyle: .popover
    )
}
