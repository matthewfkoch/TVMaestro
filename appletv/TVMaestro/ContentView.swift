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
                playbackChrome
            } else {
                IdleView(
                    addresses: app.localAddresses,
                    port: app.port,
                    guidePaired: app.guidePaired,
                    guideSeen: app.guideSeen,
                    problem: app.lastError,
                    onSettings: {
                        showSettings = true
                    }
                )
            }
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
                app.resumeFromForeground()
            }
        }
    }

    @ViewBuilder
    private var playbackChrome: some View {
        VStack(spacing: 0) {
            if app.chromeVisible && (app.streamWarning != nil || app.lastError != nil || app.volumeHUD != nil) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let warning = app.streamWarning {
                            Text(warning)
                                .font(.callout)
                                .foregroundStyle(Theme.warn)
                        }
                        if let err = app.lastError {
                            Text(err)
                                .font(.callout)
                                .foregroundStyle(Theme.warn)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    if let hud = app.volumeHUD {
                        Text(hud)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Theme.bg)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Theme.accent, in: Capsule())
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, 36)
                .padding(.bottom, 28)
                .background(
                    LinearGradient(colors: [.black.opacity(0.72), .clear], startPoint: .top, endPoint: .bottom)
                )
            }

            Spacer()

            if app.chromeVisible {
                HStack(alignment: .bottom, spacing: 32) {
                    Text("Menu stops playback")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                    Spacer(minLength: 0)
                    Button("Settings") {
                        showSettings = true
                        app.flashChrome()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 48)
                .padding(.top, 36)
                .padding(.bottom, 42)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.chromeVisible)
        .animation(.easeInOut(duration: 0.2), value: app.volumeHUD)
    }
}

struct IdleView: View {
    let addresses: [String]
    let port: Int
    let guidePaired: Bool
    let guideSeen: Bool
    let problem: String?
    var onSettings: () -> Void

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Theme.accent.opacity(0.14), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 720
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 36) {
                Image("Wordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 64)
                    .accessibilityLabel("TVMaestro")

                HStack(alignment: .top, spacing: 24) {
                    infoCard(title: "Address") {
                        if addresses.isEmpty {
                            Text("No LAN address yet. Check Ethernet or Wi-Fi.")
                                .font(.title3)
                                .foregroundStyle(Theme.warn)
                        } else {
                            ForEach(addresses, id: \.self) { ip in
                                Text(addressLine(ip))
                                    .font(.title2.monospaced().weight(.semibold))
                                    .foregroundStyle(Theme.text)
                            }
                            Text(addressHint)
                                .font(.callout)
                                .foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    infoCard(title: "Guide") {
                        statusPill
                        Text(streamLine)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        if !guidePaired {
                            Text(problem ?? guideDetail)
                                .font(.callout)
                                .foregroundStyle(problem == nil ? Theme.muted : Theme.warn)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if let problem {
                            Text(problem)
                                .font(.callout)
                                .foregroundStyle(Theme.warn)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Settings", action: onSettings)
                        .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 64)
        }
    }

    private var statusPill: some View {
        Text(guideTitle)
            .font(.headline)
            .foregroundStyle(guidePaired ? Theme.bg : Theme.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(guidePaired ? Theme.accent : Color.white.opacity(0.12), in: Capsule())
    }

    private var streamLine: String {
        let max = ControlServer.multiviewMax
        if max <= 1 { return "1 stream" }
        return "Up to \(max) streams"
    }

    private var addressHint: String {
        if guideSeen {
            return "The guide uses this address to reach the app."
        }
        return "Use this in the guide when you add the device."
    }

    private var guideTitle: String {
        if guidePaired { return "Paired" }
        if guideSeen { return "Not paired" }
        return "Not added"
    }

    private var guideDetail: String {
        if guidePaired {
            return "Waiting for the guide to start a session."
        }
        if guideSeen {
            return "Open Edit device in the guide and enter the PIN shown on this Apple TV."
        }
        return "In the guide, choose + Device, then Apple TV, and enter the address."
    }

    /// Build a String first. `Text("\(port)")` is a localized number and prints `9,093`.
    private func addressLine(_ ip: String) -> String {
        "\(ip):\(port)"
    }

    private func infoCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(Theme.muted)
            content()
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .padding(28)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.panelStroke, lineWidth: 1)
        )
    }
}
