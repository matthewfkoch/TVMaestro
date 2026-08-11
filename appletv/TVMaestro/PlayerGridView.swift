import AVFoundation
import AVKit
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

        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            ForEach(0..<rows, id: \.self) { row in
                GridRow {
                    ForEach(0..<cols, id: \.self) { col in
                        let index = row * cols + col
                        if index < slots.count {
                            SlotPlayerView(
                                slot: slots[index],
                                paneIndex: index,
                                audioTick: audioTick,
                                onError: onError
                            )
                        } else {
                            Theme.bg
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
    @ObservedObject var audioTick: AudioTick
    var onError: (String) -> Void

    @StateObject private var model = SlotPlayerModel()

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Theme.bg
            if slot.isPlayable {
                PlayerLayerView(player: model.player)
            } else {
                Color.black.opacity(0.35)
            }

            if let title = slot.title, slot.isPlayable {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                    .padding(12)
            }
        }
        .onAppear {
            model.configure(slot: slot, paneIndex: paneIndex, onError: onError)
        }
        .onChange(of: slot) { _, newValue in
            model.configure(slot: newValue, paneIndex: paneIndex, onError: onError)
        }
        .onChange(of: audioTick.generation) { _, _ in
            model.applyVolume(slotHasAudio: slot.audio)
        }
        .onDisappear { model.teardown() }
    }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView(player: player)
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .black
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

@MainActor
final class SlotPlayerModel: ObservableObject {
    let player = AVPlayer()
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var errorObservation: NSKeyValueObservation?
    private var paneIndex = 0
    private var onError: ((String) -> Void)?
    private var startTask: Task<Void, Never>?
    private var slotHasAudio = false

    func configure(slot: SessionSlot, paneIndex: Int, onError: @escaping (String) -> Void) {
        self.paneIndex = paneIndex
        self.onError = onError
        self.slotHasAudio = slot.audio
        startTask?.cancel()
        teardown(keepPlayer: true)

        guard let urlString = slot.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty,
              let url = URL(string: urlString)
        else {
            player.replaceCurrentItem(with: nil)
            return
        }

        if StreamURL.looksLikeMpegTS(urlString) {
            onError("Pane \(paneIndex + 1): MPEG-TS may fail — use HLS from Channels DVR")
        }

        let item = AVPlayerItem(url: url)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] note in
            let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription ?? "playback failed"
            Task { @MainActor in
                self?.onError?("Pane \(paneIndex + 1): \(message)")
            }
        }
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "failed to load"
            Task { @MainActor in
                self?.onError?("Pane \(paneIndex + 1): \(message)")
            }
        }
        errorObservation = item.observe(\.error, options: [.new]) { [weak self] item, _ in
            guard let err = item.error else { return }
            Task { @MainActor in
                self?.onError?("Pane \(paneIndex + 1): \(err.localizedDescription)")
            }
        }

        player.replaceCurrentItem(with: item)
        applyVolume(slotHasAudio: slot.audio)
        updateNowPlaying(title: slot.title)

        let delay = UInt64(paneIndex) * 250_000_000
        startTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            player.play()
        }
    }

    func applyVolume(slotHasAudio: Bool) {
        self.slotHasAudio = slotHasAudio
        let vol = AudioController.shared.effectiveVolume(slotHasAudioFocus: slotHasAudio)
        player.volume = vol
        player.isMuted = vol <= 0.0001
    }

    func teardown(keepPlayer: Bool = false) {
        startTask?.cancel()
        startTask = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        errorObservation?.invalidate()
        errorObservation = nil
        player.pause()
        if !keepPlayer {
            player.replaceCurrentItem(with: nil)
        }
    }

    private func updateNowPlaying(title: String?) {
        guard slotHasAudio else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title ?? "TVMaestro",
            MPMediaItemPropertyArtist: "TVMaestro",
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
