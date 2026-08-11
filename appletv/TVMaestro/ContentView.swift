import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @StateObject private var audioTick = AudioTick()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            if let session = app.session, session.slots.contains(where: \.isPlayable) {
                PlayerGridView(session: session, audioTick: audioTick) { message in
                    app.reportPlaybackError(message)
                }
            } else {
                IdleView(
                    status: app.statusLine,
                    addresses: app.localAddresses,
                    port: app.port
                )
            }

            chromeOverlay
        }
        .onPlayPauseCommand {
            // Siri Remote play/pause — show chrome; streams keep running unless stopped from web/Menu.
            app.flashChrome()
        }
        .onExitCommand {
            if app.isPlaying {
                app.stopPlayback()
            } else if showSettings {
                showSettings = false
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(app)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                app.refreshAddresses()
            }
        }
    }

    @ViewBuilder
    private var chromeOverlay: some View {
        VStack(spacing: 0) {
            if app.chromeVisible || !app.isPlaying {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        if app.isPlaying, let title = app.focusTitle {
                            Text(title)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Theme.text)
                        }
                        if let warning = app.streamWarning {
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(Theme.accent)
                        }
                        if let err = app.lastError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    if let hud = app.volumeHUD {
                        Text(hud)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Theme.bg)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Theme.accent, in: Capsule())
                    }
                }
                .padding(28)
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0.65), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            Spacer()

            if app.chromeVisible || !app.isPlaying {
                HStack {
                    if app.isPlaying {
                        Text("Menu · stop   ·   Play/Pause · chrome")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button("Settings") {
                        showSettings = true
                        app.flashChrome()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.bg)
                }
                .padding(28)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.chromeVisible)
        .animation(.easeInOut(duration: 0.2), value: app.volumeHUD)
    }
}

struct IdleView: View {
    let status: String
    let addresses: [String]
    let port: Int

    var body: some View {
        HStack(spacing: 56) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 18) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TVMaestro")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Theme.text)
                        Text("Apple TV client")
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                    }
                }

                Text(status)
                    .font(.title3)
                    .foregroundStyle(Theme.muted)

                Text("Waiting for the web guide to start a session.")
                    .font(.body)
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: 640, alignment: .leading)

            VStack(alignment: .leading, spacing: 14) {
                Text("Register this device")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Text("Web UI → + Device")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)

                if addresses.isEmpty {
                    Text("No LAN IPv4 yet — check Ethernet / Wi‑Fi")
                        .foregroundStyle(.orange)
                } else {
                    ForEach(addresses, id: \.self) { ip in
                        HStack {
                            Text(ip)
                                .font(.body.monospaced())
                                .foregroundStyle(Theme.text)
                            Spacer()
                            Text("\(port)")
                                .font(.body.monospaced())
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Theme.panelStroke, lineWidth: 1)
                        )
                    }
                }

                Text("Prefer HLS stream URLs from Channels DVR.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 8)
            }
            .frame(width: 420, alignment: .leading)
        }
        .padding(56)
    }
}
