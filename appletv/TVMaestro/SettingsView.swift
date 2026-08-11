import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var portText: String = ""
    @State private var tokenText: String = ""
    @State private var testMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Control API") {
                    TextField("Port", text: $portText)
                    TextField("Auth token (optional)", text: $tokenText)
                    Text("If set, the web UI device token must match (`X-Auth-Token`).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("This Apple TV") {
                    LabeledContent("tvOS", value: UIDevice.current.systemVersion)
                    LabeledContent("Multiview", value: "up to \(ControlServer.multiviewMax)")
                    LabeledContent("Streams", value: "HLS preferred")
                    ForEach(app.localAddresses, id: \.self) { ip in
                        LabeledContent("LAN", value: "\(ip):\(app.port)")
                    }
                    if app.localAddresses.isEmpty {
                        Text("No LAN IPv4 address yet")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Volume / CEC") {
                    Text(
                        "Wake/Sleep is not available from this app. Volume and mute adjust in-app gain on the audio-focus stream (Siri Remote still controls TV HDMI volume separately)."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    Button("Test volume up") {
                        app.testVolumeUp()
                        let pct = Int((AudioController.shared.gain * 100).rounded())
                        testMessage = AudioController.shared.isMuted ? "Muted" : "Gain \(pct)%"
                    }
                    if let testMessage {
                        Text(testMessage)
                            .foregroundStyle(Theme.accent)
                    }
                }

                Section("Tips") {
                    Text("Leave TVMaestro open so the control API stays reachable.")
                    Text("Channels DVR: prefer HLS (`format=hls`) over MPEG-TS.")
                    Text("Menu on the Siri Remote stops the current session.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        app.saveSettings(port: Int(portText) ?? app.port, token: tokenText)
                        dismiss()
                    }
                }
            }
            .onAppear {
                portText = String(app.port)
                tokenText = app.authToken
                app.refreshAddresses()
            }
        }
    }
}
