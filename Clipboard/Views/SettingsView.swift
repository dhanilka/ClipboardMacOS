import AppKit
import Carbon
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var hotkeyManager: GlobalHotkeyManager
    @ObservedObject var viewModel: ClipboardViewModel
    @AppStorage(appThemeStorageKey) private var appThemeRawValue = AppTheme.dark.rawValue

    @State private var isRecording = false
    @State private var keyMonitor: Any?
    @State private var dataStatusMessage: String?
    @State private var dataStatusIsError = false
    @State private var isDataActionRunning = false

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .dark
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appThemeRawValue) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Global Shortcut") {
                HStack {
                    Text("Current")
                    Spacer()
                    Text(hotkeyManager.shortcutDisplayText)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button(isRecording ? "Press new shortcut..." : "Record Shortcut") {
                        if isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    }

                    Button("Reset Default") {
                        hotkeyManager.resetToDefault()
                    }
                }

                Text("Press Esc to cancel recording. Shortcuts need at least one modifier key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Capture Blacklist") {
                Text("ClipVault will ignore clipboard captures while these apps are active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(viewModel.captureBlacklist.enumerated()), id: \.offset) { index, appName in
                    HStack {
                        Text(appName)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            viewModel.removeCaptureBlacklistEntry(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove app")
                    }
                }

                Button {
                    chooseBlacklistApps()
                } label: {
                    Label("Choose Apps…", systemImage: "plus")
                }
            }

            Section("Data") {
                HStack(spacing: 10) {
                    Button("Export Encrypted JSON") {
                        exportHistory()
                    }
                    .disabled(isDataActionRunning)

                    Button("Import Encrypted JSON") {
                        importHistory()
                    }
                    .disabled(isDataActionRunning)
                }

                Text("History is encrypted. Only this app installation can decrypt exported files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let dataStatusMessage {
                    Text(dataStatusMessage)
                        .font(.caption)
                        .foregroundStyle(dataStatusIsError ? .red : .secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding(16)
        .preferredColorScheme(selectedTheme.colorScheme)
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        guard keyMonitor == nil else { return }
        isRecording = true

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }

            guard let shortcut = GlobalHotkeyManager.shortcut(from: event) else {
                NSSound.beep()
                return nil
            }

            hotkeyManager.updateShortcut(shortcut)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func exportHistory() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "ClipVault-History.encjson"
        panel.title = "Export Clipboard History"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        isDataActionRunning = true
        Task {
            do {
                try await viewModel.exportHistory(to: url)
                await MainActor.run {
                    isDataActionRunning = false
                    dataStatusIsError = false
                    dataStatusMessage = "Exported successfully."
                }
            } catch {
                await MainActor.run {
                    isDataActionRunning = false
                    dataStatusIsError = true
                    dataStatusMessage = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func importHistory() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Clipboard History"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        isDataActionRunning = true
        Task {
            do {
                try await viewModel.importHistory(from: url)
                await MainActor.run {
                    isDataActionRunning = false
                    dataStatusIsError = false
                    dataStatusMessage = "Imported successfully."
                }
            } catch {
                await MainActor.run {
                    isDataActionRunning = false
                    dataStatusIsError = true
                    dataStatusMessage = "Import failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func chooseBlacklistApps() {
        let panel = NSOpenPanel()
        panel.title = "Choose Apps to Ignore"
        panel.message = "Select one or more apps from Applications."
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        guard panel.runModal() == .OK else {
            return
        }

        let selectedApps = panel.urls.compactMap(appDisplayName(from:))
        viewModel.addCaptureBlacklistEntries(selectedApps)
    }

    private func appDisplayName(from appURL: URL) -> String? {
        guard appURL.pathExtension.lowercased() == "app" else {
            return nil
        }

        if let bundle = Bundle(url: appURL) {
            if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
               !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return displayName
            }
            if let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
               !bundleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return bundleName
            }
        }

        let fallback = appURL.deletingPathExtension().lastPathComponent
        return fallback.isEmpty ? nil : fallback
    }
}

#Preview {
    SettingsView(
        hotkeyManager: GlobalHotkeyManager(),
        viewModel: ClipboardViewModel()
    )
}
