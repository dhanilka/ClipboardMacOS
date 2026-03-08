import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: ClipboardViewModel

    let onClosePopover: () -> Void

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
    }
}

#Preview {
    MenuBarView(viewModel: ClipboardViewModel(), onClosePopover: {})
}
