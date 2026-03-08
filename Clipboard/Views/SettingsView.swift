import AppKit
import Carbon
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var hotkeyManager: GlobalHotkeyManager
    @ObservedObject var viewModel: ClipboardViewModel

    @State private var isRecording = false
    @State private var keyMonitor: Any?
    @State private var dataStatusMessage: String?
    @State private var dataStatusIsError = false
    @State private var isDataActionRunning = false
    @AppStorage("clipvault.previewDelayMs") private var previewDelayMs: Double = 300

    var body: some View {
        Form {
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

            Section("Preview") {
                HStack {
                    Text("Hover Delay")
                    Spacer()
                    Text("\(Int(previewDelayMs)) ms")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                }

                Slider(value: $previewDelayMs, in: 0...2000, step: 50) {
                    Text("Hover Delay")
                } minimumValueLabel: {
                    Text("0")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("2000")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Reset to Default (300 ms)") {
                    previewDelayMs = 300
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
}

#Preview {
    SettingsView(
        hotkeyManager: GlobalHotkeyManager(),
        viewModel: ClipboardViewModel()
    )
}
