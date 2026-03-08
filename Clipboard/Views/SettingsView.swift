import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    @ObservedObject var hotkeyManager: GlobalHotkeyManager

    @State private var isRecording = false
    @State private var keyMonitor: Any?
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
}

#Preview {
    SettingsView(hotkeyManager: GlobalHotkeyManager())
}
