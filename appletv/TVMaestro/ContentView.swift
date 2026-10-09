import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @StateObject private var audioTick = AudioTick()
    @FocusState private var playbackFocus: PlaybackFocus?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            if let session = app.session, session.slots.contains(where: \.isPlayable) {
                ZStack {
                    PlayerGridView(session: session, audioTick: audioTick) { message in
                        app.reportPlaybackError(message)
                    }
                    playbackFocusSurface
                    playbackChrome
                }
                .defaultPlaybackFocus(!showSettings, $playbackFocus, chromeVisible: app.chromeVisible)
            } else if !showSettings {
                IdleView(
                    addresses: app.localAddresses,
                    port: app.port,
                    guidePaired: app.guidePaired,
                    guideSeen: app.guideSeen,
                    problem: app.lastError,
                    holdsFocus: !showSettings,
                    onSettings: {
                        showSettings = true
                    }
                )
            }
        }
        .onExitCommand {
            // Menu closes settings. Playback Menu is handled by the focused surface
            // or the Settings button when settings is closed.
            if showSettings {
                showSettings = false
            } else if app.isPlaying {
                app.stopPlayback()
            }
        }
        .overlay {
            ZStack {
                if showSettings {
                    SettingsView(onClose: { showSettings = false })
                        .environmentObject(app)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showSettings)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                app.resumeFromForeground()
            }
        }
        .onChange(of: app.isPlaying) { _, _ in
            syncPlaybackFocus()
        }
        .onChange(of: app.chromeVisible) { _, _ in
            syncPlaybackFocus()
        }
        .onChange(of: showSettings) { _, _ in
            syncPlaybackFocus()
        }
    }

    /// Menu only reaches a focused view. The video panes are not focusable, and the
    /// Settings button leaves the tree when the bar hides, so this surface holds focus
    /// whenever the bar is hidden.
    private var playbackFocusSurface: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .focusable(!app.chromeVisible && !showSettings)
            .focusEffectDisabled()
            .focused($playbackFocus, equals: .surface)
            .onExitCommand {
                if showSettings {
                    showSettings = false
                } else {
                    app.stopPlayback()
                }
            }
            .onPlayPauseCommand { showPlaybackChrome() }
            .onAppear { syncPlaybackFocus() }
    }

    private func showPlaybackChrome() {
        // Play/pause on the remote shows chrome. Streams keep running unless stopped from the guide or Menu.
        app.flashChrome()
    }

    private func syncPlaybackFocus() {
        guard app.isPlaying, !showSettings else { return }
        let target: PlaybackFocus = app.chromeVisible ? .settings : .surface
        playbackFocus = target
        // The surface becomes focusable, or the Settings button enters the tree, in this
        // update. Assign again after that focus target exists.
        Task { @MainActor in
            guard app.isPlaying, !showSettings else { return }
            playbackFocus = app.chromeVisible ? .settings : .surface
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

            if app.isPreview {
                Text(PreviewSession.credit)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .padding(.bottom, app.chromeVisible ? 8 : 36)
            }

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
                    .disabled(showSettings)
                    .focused($playbackFocus, equals: .settings)
                    .onExitCommand {
                        if showSettings {
                            showSettings = false
                        } else {
                            app.stopPlayback()
                        }
                    }
                    .onPlayPauseCommand { showPlaybackChrome() }
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

private enum PlaybackFocus: Hashable {
    case surface
    case settings
}

private enum IdleButton: Hashable {
    case settings
}

struct IdleView: View {
    let addresses: [String]
    let port: Int
    let guidePaired: Bool
    let guideSeen: Bool
    let problem: String?
    var holdsFocus: Bool
    var onSettings: () -> Void

    @FocusState private var focusedButton: IdleButton?

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
                    PanelCard(title: "Address") {
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

                    PanelCard(title: "Guide") {
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

                holdingDefaultFocus {
                    HStack(spacing: 24) {
                        Spacer()
                        Button("Settings", action: onSettings)
                            .buttonStyle(.bordered)
                            .disabled(!holdsFocus)
                            .focused($focusedButton, equals: .settings)
                    }
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
            return "Open Edit device in the guide and enter the PIN shown on this device."
        }
        return "In the guide, choose + Device and enter the address."
    }

    /// Build a String first. `Text("\(port)")` is a localized number and prints `9,093`.
    private func addressLine(_ ip: String) -> String {
        "\(ip):\(port)"
    }

    @ViewBuilder
    private func holdingDefaultFocus<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if holdsFocus {
            content().defaultFocus($focusedButton, .settings)
        } else {
            content()
        }
    }
}

private extension View {
    @ViewBuilder
    func defaultPlaybackFocus(
        _ enabled: Bool,
        _ focus: FocusState<PlaybackFocus?>.Binding,
        chromeVisible: Bool
    ) -> some View {
        if enabled {
            self.defaultFocus(focus, chromeVisible ? .settings : .surface)
        } else {
            self
        }
    }
}
