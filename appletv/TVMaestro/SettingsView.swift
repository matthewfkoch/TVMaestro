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
                        .foregroundStyle(Theme.dim)
                }

                Section("This device") {
                    LabeledContent("System", value: UIDevice.current.systemVersion)
                    LabeledContent("Playback", value: Self.streamLine)
                    ForEach(app.localAddresses, id: \.self) { ip in
                        LabeledContent("Address", value: "\(ip):\(app.port)")
                    }
                    if app.localAddresses.isEmpty {
                        Text("No LAN address yet")
                            .foregroundStyle(Theme.dim)
                    }
                }

                Section("Guide") {
                    LabeledContent(
                        "Status",
                        value: app.guidePaired ? "Paired" : (app.guideSeen ? "Not paired" : "Not added")
                    )
                    Text(guideHelp)
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                }

                Section("Volume") {
                    Text("Volume and mute change the level of the stream that has audio. The remote still controls the television.")
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                    Button("Test volume up") {
                        app.testVolumeUp()
                        let pct = Int((AudioController.shared.gain * 100).rounded())
                        testMessage = AudioController.shared.isMuted ? "Muted" : "Volume \(pct)%"
                    }
                    if let testMessage {
                        Text(testMessage)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .navigationTitle("Settings")
            .tint(Theme.accent)
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

    private static var streamLine: String {
        let max = ControlServer.multiviewMax
        if max <= 1 { return "1 stream" }
        return "Up to \(max) streams"
    }

    private var guideHelp: String {
        if app.guidePaired {
            return "The guide can open this app. The device itself still has to be awake. Menu on the remote stops playback."
        }
        if app.guideSeen {
            return "In the guide, open Edit device and enter the PIN shown on this device."
        }
        return "In the guide, choose + Device and enter the address above."
    }
}
