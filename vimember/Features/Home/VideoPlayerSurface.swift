import AVFoundation
import SwiftUI
import UIKit

struct VideoPlayerSurface: UIViewRepresentable {
    let url: URL?
    let isPlaying: Bool
    let videoGravity: AVLayerVideoGravity

    func makeUIView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.videoGravity = videoGravity
        view.configure(url: url)
        view.setPlaying(isPlaying)
        return view
    }

    func updateUIView(_ uiView: PlayerSurfaceView, context: Context) {
        uiView.videoGravity = videoGravity
        uiView.configure(url: url)
        uiView.setPlaying(isPlaying)
    }
}

final class PlayerSurfaceView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    private var currentURL: URL?
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    var videoGravity: AVLayerVideoGravity = .resizeAspectFill {
        didSet {
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

    func configure(url: URL?) {
        guard currentURL != url else {
            return
        }

        currentURL = url
        looper = nil
        queuePlayer?.pause()
        queuePlayer = nil

        guard let url else {
            playerLayer.player = nil
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: player, templateItem: item)
        queuePlayer = player
        playerLayer.player = player
    }

    func setPlaying(_ isPlaying: Bool) {
        if isPlaying {
            queuePlayer?.play()
        } else {
            queuePlayer?.pause()
        }
    }
}
