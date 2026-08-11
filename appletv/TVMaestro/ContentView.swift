import AVKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: AppModel
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let session = app.session, session.slots.contains(where: \.isPlayable) {
                PlayerGridView(session: session) { message in
                    app.reportPlaybackError(message)
                }
            } else {
                IdleView(status: app.statusLine, addresses: app.localAddresses, port: app.port)
            }

            VStack {
                Spacer()
                HStack {
                    if let err = app.lastError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("Settings") { showSettings = true }
                        .buttonStyle(.bordered)
                }
                .padding(24)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(app)
        }
    }
}

struct IdleView: View {
    let status: String
    let addresses: [String]
    let port: Int

    var body: some View {
        VStack(spacing: 28) {
            Text("TVMaestro")
                .font(.largeTitle.weight(.bold))
            Text(status)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 900)

            if !addresses.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Register in the web UI")
                        .font(.headline)
                    ForEach(addresses, id: \.self) { ip in
                        Text("\(ip)  ·  port \(port)")
                            .font(.body.monospaced())
                    }
                }
                .padding(24)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            }

            Text("Prefer HLS stream URLs from Channels DVR on Apple TV.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(48)
    }
}
