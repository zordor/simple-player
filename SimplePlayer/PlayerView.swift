import SwiftUI
import AVKit

/// Native, chrome-free playback. Resolves the stream with yt-dlp, builds an AVPlayerItem
/// (merging separate video+audio tracks when needed) and shows it in an AVPlayerView with
/// floating controls. No YouTube UI whatsoever.
struct PlayerView: View {
    @EnvironmentObject var model: AppModel
    let videoID: String

    @State private var player: AVPlayer?
    @State private var errorText: String?
    @State private var showBackButton = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                PlayerSurface(player: player)
                    .ignoresSafeArea()
            } else if let errorText {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 34))
                    Text("No se pudo reproducir el vídeo")
                        .font(.headline)
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }
                .foregroundStyle(.white)
            } else {
                ProgressView("Cargando vídeo…")
                    .controlSize(.large)
                    .tint(.white)
                    .foregroundStyle(.white)
            }

            VStack {
                HStack {
                    Button {
                        model.backToBrowse()
                    } label: {
                        Label("Volver", systemImage: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .help("Volver a YouTube (Esc)")
                    Spacer()
                }
                Spacer()
            }
            .padding(16)
            .opacity(showBackButton ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: showBackButton)
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active:
                revealBackButton()
            case .ended:
                hideTask?.cancel()
                showBackButton = false
            }
        }
        .task(id: videoID) { await load() }
        .onExitCommand { model.backToBrowse() }
        .onDisappear {
            hideTask?.cancel()
            player?.pause()
            player = nil
        }
    }

    /// Shows the back button and schedules it to fade out after a short idle, matching the
    /// native floating controls.
    private func revealBackButton() {
        hideTask?.cancel()
        showBackButton = true
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled {
                showBackButton = false
            }
        }
    }

    @MainActor
    private func load() async {
        player = nil
        errorText = nil

        let cookies = await CookieExporter.export(from: model.webView)
        let id = videoID
        do {
            let streams = try await Task.detached(priority: .userInitiated) {
                try StreamResolver.resolve(videoID: id, cookiesFile: cookies)
            }.value
            let item = try await makePlayerItem(from: streams)
            let player = AVPlayer(playerItem: item)
            // Start as soon as the first bytes are in rather than pre-buffering — faster perceived start.
            player.automaticallyWaitsToMinimizeStalling = false
            self.player = player
            player.play()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Combined stream → direct item. Separate video+audio → AVMutableComposition merge.
    private func makePlayerItem(from streams: StreamURLs) async throws -> AVPlayerItem {
        guard let audioURL = streams.audio else {
            return AVPlayerItem(url: streams.video)
        }

        let videoAsset = AVURLAsset(url: streams.video)
        let audioAsset = AVURLAsset(url: audioURL)

        // Load video duration + both track lists concurrently (3 parallel round-trips instead
        // of 3 sequential ones) so playback can begin sooner.
        async let durationLoad = videoAsset.load(.duration)
        async let videoTracksLoad = videoAsset.loadTracks(withMediaType: .video)
        async let audioTracksLoad = audioAsset.loadTracks(withMediaType: .audio)
        let (duration, videoTracks, audioTracks) = try await (durationLoad, videoTracksLoad, audioTracksLoad)

        guard let videoTrack = videoTracks.first, let audioTrack = audioTracks.first else {
            // Couldn't read separate tracks — fall back to the video stream alone.
            return AVPlayerItem(url: streams.video)
        }

        let composition = AVMutableComposition()
        let range = CMTimeRange(start: .zero, duration: duration)

        if let v = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try v.insertTimeRange(range, of: videoTrack, at: .zero)
        }
        if let a = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try a.insertTimeRange(range, of: audioTrack, at: .zero)
        }

        return AVPlayerItem(asset: composition)
    }
}

/// AVPlayerView with native, auto-hiding floating controls.
private struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
