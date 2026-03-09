import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    @AppStorage(appThemeStorageKey) private var appThemeRawValue = AppTheme.dark.rawValue

    let onClosePopover: () -> Void

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .dark
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ClipVault")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            ClipboardListView(
                viewModel: viewModel,
                onItemSelected: onClosePopover
            )
        }
        .padding(12)
        // Keep popover close to requested size for a compact menu bar workflow.
        .frame(width: 350, height: 440)
        .preferredColorScheme(selectedTheme.colorScheme)
    }
}

#Preview {
    MenuBarView(viewModel: ClipboardViewModel(), onClosePopover: {})
}
