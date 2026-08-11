import AVFoundation
import AVKit
import SwiftUI

struct PlayerGridView: View {
    let session: PlaybackSession
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
                            SlotPlayerView(slot: slots[index], paneIndex: index, onError: onError)
                        } else {
                            Color.black
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct SlotPlayerView: View {
    let slot: SessionSlot
    let paneIndex: Int
    var onError: (String) -> Void

    @StateObject private var model = SlotPlayerModel()

    var body: some View {
        ZStack {
            Color.black
            if slot.isPlayable {
                VideoPlayer(player: model.player)
                    .disabled(true)
            }
        }
        .onAppear { model.configure(slot: slot, paneIndex: paneIndex, onError: onError) }
        .onChange(of: slot) { _, newValue in
            model.configure(slot: newValue, paneIndex: paneIndex, onError: onError)
        }
        .onDisappear { model.teardown() }
    }
}

@MainActor
final class SlotPlayerModel: ObservableObject {
    let player = AVPlayer()
    private var observer: NSObjectProtocol?
    private var paneIndex = 0
    private var onError: ((String) -> Void)?

    func configure(slot: SessionSlot, paneIndex: Int, onError: @escaping (String) -> Void) {
        self.paneIndex = paneIndex
        self.onError = onError
        teardown(keepPlayer: true)

        guard let urlString = slot.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty,
              let url = URL(string: urlString)
        else {
            player.replaceCurrentItem(with: nil)
            return
        }

        let item = AVPlayerItem(url: url)
        observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] note in
            let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
                ?? "playback failed"
            self?.onError?("Pane \(paneIndex + 1): \(message)")
        }
        player.replaceCurrentItem(with: item)
        player.isMuted = !slot.audio
        player.volume = slot.audio ? 1 : 0
        player.play()
    }

    func teardown(keepPlayer: Bool = false) {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        player.pause()
        if !keepPlayer {
            player.replaceCurrentItem(with: nil)
        }
    }

    deinit {
        // NotificationCenter cleanup; player released with model.
    }
}
