import SwiftUI

let appThemeStorageKey = "clipvault.theme.preference"

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

@main
struct ClipVaultApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var hotkeyManager = AppEnvironment.shared.hotkeyManager
    @ObservedObject private var clipboardViewModel = AppEnvironment.shared.clipboardViewModel

    init() {
        UserDefaults.standard.register(defaults: [
            appThemeStorageKey: AppTheme.dark.rawValue
        ])
    }

    var body: some Scene {
        Settings {
            SettingsView(
                hotkeyManager: hotkeyManager,
                viewModel: clipboardViewModel
            )
        }
    }
}
