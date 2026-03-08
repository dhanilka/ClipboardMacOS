import SwiftUI

@main
struct ClipVaultApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var hotkeyManager = AppEnvironment.shared.hotkeyManager
    @ObservedObject private var clipboardViewModel = AppEnvironment.shared.clipboardViewModel

    var body: some Scene {
        Settings {
            SettingsView(
                hotkeyManager: hotkeyManager,
                viewModel: clipboardViewModel
            )
        }
    }
}
