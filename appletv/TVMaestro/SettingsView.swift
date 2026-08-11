import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var portText: String = ""
    @State private var tokenText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Control API") {
                    TextField("Port", text: $portText)
                    SecureField("Auth token (optional)", text: $tokenText)
                    Text("Must match the device token in the TVMaestro web UI if set.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("This Apple TV") {
                    ForEach(app.localAddresses, id: \.self) { ip in
                        Text(ip)
                    }
                    if app.localAddresses.isEmpty {
                        Text("No LAN IPv4 address yet")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("Use HLS URLs from Channels DVR. Raw MPEG-TS often fails on AVPlayer.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
            }
        }
    }
}
