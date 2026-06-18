import AVFoundation
import SwiftUI
import UIKit
import os

private let videoPlayerPerformanceLog = OSLog(
    subsystem: "com.brycez021.vimember",
    category: "VideoPlayerPerformance"
)

struct VideoPlayerSurface: UIViewRepresentable {
    let url: URL?
    let isPlaying: Bool
    let isMuted: Bool
    let videoGravity: AVLayerVideoGravity
    let seekRequest: VideoPlaybackSeekRequest?
    let onProgressChange: ((Double) -> Void)?

    init(
        url: URL?,
        isPlaying: Bool,
        isMuted: Bool = true,
        videoGravity: AVLayerVideoGravity,
        seekRequest: VideoPlaybackSeekRequest? = nil,
        onProgressChange: ((Double) -> Void)? = nil
    ) {
        self.url = url
        self.isPlaying = isPlaying
        self.isMuted = isMuted
        self.videoGravity = videoGravity
        self.seekRequest = seekRequest
        self.onProgressChange = onProgressChange
    }

    func makeUIView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.videoGravity = videoGravity
        view.onProgressChange = onProgressChange
        view.configure(url: url)
        view.setMuted(isMuted)
        view.applySeekRequest(seekRequest)
        view.setPlaying(isPlaying)
        return view
    }

    func updateUIView(_ uiView: PlayerSurfaceView, context: Context) {
        uiView.videoGravity = videoGravity
        uiView.onProgressChange = onProgressChange
        uiView.configure(url: url)
        uiView.setMuted(isMuted)
        uiView.applySeekRequest(seekRequest)
        uiView.setPlaying(isPlaying)
    }
}

struct VideoPlaybackSeekRequest: Equatable {
    let id: Int
    let progress: Double
}

final class PlayerSurfaceView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    private var currentURL: URL?
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var timeObserverToken: Any?
    private var lastAppliedSeekRequestID: Int?
    private var isMuted = true
    private var isPlaying = false
    private static var didConfigureAudiblePlayback = false
    var onProgressChange: ((Double) -> Void)? {
        didSet {
            updateTimeObserverRegistration()
        }
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    var videoGravity: AVLayerVideoGravity = .resizeAspectFill {
        didSet {
            guard playerLayer.videoGravity != videoGravity else {
                return
            }

            playerLayer.videoGravity = videoGravity
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        playerLayer.videoGravity = videoGravity
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removeTimeObserver()
    }

    func configure(url: URL?) {
        guard currentURL != url else {
            return
        }

        currentURL = url
        looper = nil
        removeTimeObserver()
        lastAppliedSeekRequestID = nil
        queuePlayer?.pause()
        queuePlayer = nil
        isPlaying = false
        os_signpost(.event, log: videoPlayerPerformanceLog, name: "VideoPlayer Configure")

        guard let url else {
            playerLayer.player = nil
            onProgressChange?(0)
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        player.isMuted = isMuted
        player.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: player, templateItem: item)
        queuePlayer = player
        playerLayer.player = player
        if !isMuted {
            Self.configureAudiblePlaybackSession()
        }
        updateTimeObserverRegistration()
        onProgressChange?(0)
    }

    func setMuted(_ isMuted: Bool) {
        guard self.isMuted != isMuted else {
            return
        }

        self.isMuted = isMuted
        queuePlayer?.isMuted = isMuted

        if !isMuted {
            Self.configureAudiblePlaybackSession()
        }
    }

    func setPlaying(_ isPlaying: Bool) {
        guard self.isPlaying != isPlaying else {
            return
        }

        self.isPlaying = isPlaying
        if isPlaying {
            os_signpost(.event, log: videoPlayerPerformanceLog, name: "VideoPlayer Play")
            queuePlayer?.play()
        } else {
            os_signpost(.event, log: videoPlayerPerformanceLog, name: "VideoPlayer Pause")
            queuePlayer?.pause()
        }
    }

    func applySeekRequest(_ seekRequest: VideoPlaybackSeekRequest?) {
        guard let seekRequest, lastAppliedSeekRequestID != seekRequest.id else {
            return
        }

        lastAppliedSeekRequestID = seekRequest.id

        guard let player = queuePlayer, let duration = resolvedDuration(for: player) else {
            return
        }

        let targetProgress = min(max(seekRequest.progress, 0), 1)
        let targetTime = CMTime(seconds: duration * targetProgress, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak player] _ in
            guard let self, let player else { return }
            self.reportProgress(time: player.currentTime(), player: player)
        }
    }

    private func installTimeObserver(on player: AVQueuePlayer) {
        guard timeObserverToken == nil else {
            return
        }

        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak player] time in
            guard let self, let player else { return }
            self.reportProgress(time: time, player: player)
        }
    }

    private func updateTimeObserverRegistration() {
        guard let player = queuePlayer else {
            return
        }

        if onProgressChange == nil {
            removeTimeObserver()
        } else {
            installTimeObserver(on: player)
        }
    }

    private func removeTimeObserver() {
        guard let timeObserverToken, let queuePlayer else {
            self.timeObserverToken = nil
            return
        }

        queuePlayer.removeTimeObserver(timeObserverToken)
        self.timeObserverToken = nil
    }

    private static func configureAudiblePlaybackSession() {
        guard !didConfigureAudiblePlayback else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
            didConfigureAudiblePlayback = true
        } catch {
            #if DEBUG
            print("Unable to configure audible video playback: \(error)")
            #endif
        }
    }

    private func reportProgress(time: CMTime, player: AVQueuePlayer) {
        guard let duration = resolvedDuration(for: player) else {
            return
        }

        let currentSeconds = CMTimeGetSeconds(time)
        guard currentSeconds.isFinite else {
            return
        }

        let progress = min(max(currentSeconds / duration, 0), 1)
        onProgressChange?(progress)
    }

    private func resolvedDuration(for player: AVQueuePlayer) -> Double? {
        guard let item = player.currentItem else {
            return nil
        }

        let duration = CMTimeGetSeconds(item.duration)
        return duration.isFinite && duration > 0 ? duration : nil
    }
}
