import KSPlayer
import KSPlayerUI
import MediaPlayer
import SwiftUI

struct PlayerGridView: View {
    let session: PlaybackSession
    @ObservedObject var audioTick: AudioTick
    var onError: (String) -> Void

    private var geometry: (rows: Int, cols: Int) {
        LayoutGeometry.dims(session.layout)
    }

    var body: some View {
        let rows = geometry.rows
        let cols = geometry.cols
        let capacity = rows * cols
        let slots = Array(session.slots.prefix(capacity))
        let showChrome = slots.filter(\.isPlayable).count > 1

        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(0..<rows, id: \.self) { row in
                GridRow {
                    ForEach(0..<cols, id: \.self) { col in
                        let index = row * cols + col
                        if index < slots.count {
                            SlotPlayerView(
                                slot: slots[index],
                                paneIndex: index,
                                showChrome: showChrome,
                                audioTick: audioTick,
                                onError: onError
                            )
                        } else {
                            Color.white.opacity(0.04)
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Cheap observable so slot players re-apply gain when CEC volume changes.
final class AudioTick: ObservableObject {
    @Published private(set) var generation = 0
    private var listener: UUID?

    init() {
        listener = AudioController.shared.addListener { [weak self] in
            DispatchQueue.main.async {
                self?.generation += 1
            }
        }
    }

    deinit {
        if let listener {
            AudioController.shared.removeListener(listener)
        }
    }
}

struct SlotPlayerView: View {
    let slot: SessionSlot
    let paneIndex: Int
    let showChrome: Bool
    @ObservedObject var audioTick: AudioTick
    var onError: (String) -> Void

    @StateObject private var coordinator = KSVideoPlayer.Coordinator()
    @State private var options = SlotPlayerView.makeOptions()
    @State private var armed = false
    @State private var failed = false
    @State private var startToken = UUID()

    private var playURL: URL? {
        guard slot.isPlayable,
              let raw = slot.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        return URL(string: raw)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Theme.bg
            if armed, let playURL {
                KSVideoPlayer(coordinator: coordinator, url: playURL, options: options)
                    .onStateChanged { _, state in
                        if state == .error {
                            fail("Pane \(paneIndex + 1): playback failed")
                        }
                    }
                    .onFinish { _, error in
                        if let error {
                            fail("Pane \(paneIndex + 1): \(error.localizedDescription)")
                        }
                    }
            } else if playURL == nil {
                Color.white.opacity(0.04)
            }
            if failed {
                Text("Couldn't play")
                    .font(.headline)
                    .foregroundStyle(Theme.warn)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.45))
            }
            paneCaption
        }
        .overlay {
            if showChrome {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(slot.audio && slot.isPlayable ? Theme.accent : Color.white.opacity(0.12), lineWidth: slot.audio ? 4 : 1)
            }
        }
        .onAppear {
            scheduleStart()
            applyVolume()
            updateNowPlaying()
        }
        .onChange(of: slot) { _, _ in
            failed = false
            scheduleStart()
            applyVolume()
            updateNowPlaying()
        }
        .onChange(of: armed) { _, isArmed in
            if isArmed { applyVolume() }
        }
        .onChange(of: audioTick.generation) { _, _ in
            applyVolume()
        }
    }

    @ViewBuilder
    private var paneCaption: some View {
        let title = slot.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let showSpeaker = showChrome && slot.audio && slot.isPlayable
        if showSpeaker || !title.isEmpty {
            HStack(spacing: 8) {
                if showSpeaker {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                        .padding(8)
                        .background(Theme.panel.opacity(0.92), in: Circle())
                }
                if !title.isEmpty {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.panel.opacity(0.92), in: Capsule())
                }
            }
            .padding(12)
        }
    }

    /// MPEG-2 (typical ATSC) has no VideoToolbox decoder on tvOS, so decode in software.
    private static func makeOptions() -> KSOptions {
        let options = KSOptions()
        options.videoDecodeType = .software
        options.registerRemoteControll = false
        options.isAutoPlay = true
        options.subtitleDisable = true
        options.preferredForwardBufferDuration = 1
        return options
    }

    private func scheduleStart() {
        let token = UUID()
        startToken = token
        guard playURL != nil else {
            armed = false
            return
        }
        let delay = showChrome ? paneIndex * 350 : 0
        if delay == 0 {
            armed = true
            return
        }
        armed = false
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) {
            if startToken == token {
                armed = true
            }
        }
    }

    private func fail(_ message: String) {
        failed = true
        onError(message)
    }

    private func applyVolume() {
        let vol = AudioController.shared.effectiveVolume(slotHasAudioFocus: slot.audio)
        coordinator.playbackVolume = vol
        coordinator.isMuted = vol <= 0.0001
    }

    private func updateNowPlaying() {
        guard slot.audio, slot.isPlayable else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: slot.title ?? "TVMaestro",
            MPMediaItemPropertyArtist: "TVMaestro",
        ]
    }
}
