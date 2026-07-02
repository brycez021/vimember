import AVFoundation
import SwiftUI

enum BlendedVideoSurfaceLayout {
    case topAnchored
    case centeredLandscapeEdges
    case centeredEdges
}

enum BlendedVideoColorSamplingPolicy: Hashable {
    case sampleVideoFrame
    case preferDerivedAssetCache
}

struct BlendedVideoSurface<Content: View>: View {
    let url: URL?
    let aspectRatio: CGFloat
    let fallbackTint: Color
    let isPlaying: Bool
    let isMuted: Bool
    let width: CGFloat
    let height: CGFloat?
    let videoYOffset: CGFloat
    let videoMotionYOffset: CGFloat
    let videoBlurRadius: CGFloat
    let edgeBlendProgress: CGFloat
    let topEdgeBlendProgress: CGFloat
    let videoGravity: AVLayerVideoGravity
    let layout: BlendedVideoSurfaceLayout
    let colorSamplingPolicy: BlendedVideoColorSamplingPolicy
    let seekRequest: VideoPlaybackSeekRequest?
    let onPlaybackProgressChange: ((Double) -> Void)?
    let onBottomColorChange: ((Color) -> Void)?
    let content: (_ videoHeight: CGFloat, _ isLandscape: Bool, _ videoYOffset: CGFloat) -> Content

    @State private var bottomColor: Color

    init(
        url: URL?,
        aspectRatio: CGFloat,
        fallbackTint: Color,
        isPlaying: Bool,
        isMuted: Bool = true,
        width: CGFloat,
        height: CGFloat? = nil,
        videoYOffset: CGFloat = 0,
        videoMotionYOffset: CGFloat = 0,
        videoBlurRadius: CGFloat = 0,
        edgeBlendProgress: CGFloat = 0,
        topEdgeBlendProgress: CGFloat = 0,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        layout: BlendedVideoSurfaceLayout = .topAnchored,
        colorSamplingPolicy: BlendedVideoColorSamplingPolicy = .sampleVideoFrame,
        seekRequest: VideoPlaybackSeekRequest? = nil,
        onPlaybackProgressChange: ((Double) -> Void)? = nil,
        onBottomColorChange: ((Color) -> Void)? = nil,
        @ViewBuilder content: @escaping (_ videoHeight: CGFloat, _ isLandscape: Bool, _ videoYOffset: CGFloat) -> Content
    ) {
        self.url = url
        self.aspectRatio = aspectRatio
        self.fallbackTint = fallbackTint
        self.isPlaying = isPlaying
        self.isMuted = isMuted
        self.width = width
        self.height = height
        self.videoYOffset = videoYOffset
        self.videoMotionYOffset = videoMotionYOffset
        self.videoBlurRadius = videoBlurRadius
        self.edgeBlendProgress = edgeBlendProgress
        self.topEdgeBlendProgress = topEdgeBlendProgress
        self.videoGravity = videoGravity
        self.layout = layout
        self.colorSamplingPolicy = colorSamplingPolicy
        self.seekRequest = seekRequest
        self.onPlaybackProgressChange = onPlaybackProgressChange
        self.onBottomColorChange = onBottomColorChange
        self.content = content
        _bottomColor = State(initialValue: fallbackTint)
    }

    private var isLandscape: Bool {
        aspectRatio > 1
    }

    private var videoHeight: CGFloat {
        width / max(aspectRatio, 0.1)
    }

    private var colorBlockOverflow: CGFloat {
        isLandscape ? width * (86 / 420) : 0
    }

    private var naturalHeight: CGFloat {
        videoHeight + colorBlockOverflow
    }

    private var renderHeight: CGFloat {
        height ?? naturalHeight
    }

    private var blendHeight: CGFloat {
        usesCompactEdgeBlend ? width * (96 / 420) : width * (260 / 420)
    }

    private var usesCenteredEdges: Bool {
        layout == .centeredLandscapeEdges || layout == .centeredEdges
    }

    private var usesCompactEdgeBlend: Bool {
        isLandscape || layout == .centeredEdges
    }

    private var resolvedVideoYOffset: CGFloat {
        guard usesCenteredEdges else {
            return videoYOffset
        }

        let centeredYOffset = (renderHeight - videoHeight) / 2
        return layout == .centeredLandscapeEdges ? max(0, centeredYOffset) : centeredYOffset
    }

    private var visualVideoYOffset: CGFloat {
        resolvedVideoYOffset + videoMotionYOffset
    }

    private var blendTopOffset: CGFloat {
        if isLandscape {
            return max(0, videoHeight - blendHeight)
        }

        let textTopOffset = videoHeight - width * (114 / 420)
        return max(0, textTopOffset - width * (220 / 420))
    }

    private var blendMaskHeight: CGFloat {
        videoHeight - blendTopOffset + colorBlockOverflow
    }

    private var clearVideoFadeStart: CGFloat {
        usesCompactEdgeBlend ? 0.78 : 1
    }

    private var clampedEdgeBlendProgress: CGFloat {
        min(max(edgeBlendProgress, 0), 1)
    }

    private var clampedTopEdgeBlendProgress: CGFloat {
        min(max(topEdgeBlendProgress, 0), 1)
    }

    private var colorSamplingTaskID: ColorSamplingTaskID {
        ColorSamplingTaskID(url: url, policy: colorSamplingPolicy)
    }

    var body: some View {
        ZStack(alignment: .top) {
            bottomColor

            VideoPlayerSurface(
                url: url,
                isPlaying: isPlaying,
                isMuted: isMuted,
                videoGravity: videoGravity,
                seekRequest: seekRequest,
                onProgressChange: onPlaybackProgressChange
            )
                .frame(width: width, height: videoHeight)
                .blur(radius: videoBlurRadius, opaque: true)
                .mask(clearVideoMask)
                .clipped()
                .offset(y: visualVideoYOffset)
                .zIndex(0)

            if !usesCenteredEdges {
                pureColorBlendLayer
                    .frame(height: blendMaskHeight)
                    .offset(y: visualVideoYOffset + blendTopOffset)
                    .opacity(1 - Double(clampedEdgeBlendProgress))
                    .zIndex(1)
            }

            content(videoHeight, isLandscape, visualVideoYOffset)
                .zIndex(2)
        }
        .frame(width: width, height: renderHeight)
        .clipShape(Rectangle())
        .task(id: colorSamplingTaskID) {
            await updateBottomColor()
        }
    }

    private func updateBottomColor() async {
        guard let url else {
            bottomColor = fallbackTint
            onBottomColorChange?(fallbackTint)
            return
        }

        switch colorSamplingPolicy {
        case .sampleVideoFrame:
            let sample = await VideoColorSampler.shared.sample(for: url, fallback: fallbackTint)
            bottomColor = sample.bottomColor
            onBottomColorChange?(sample.bottomColor)
        case .preferDerivedAssetCache:
            let derivedColor = await cachedDerivedBottomColorWhenReady(for: url)
            let resolvedColor = derivedColor ?? fallbackTint
            bottomColor = resolvedColor
            onBottomColorChange?(resolvedColor)
        }
    }

    private func cachedDerivedBottomColorWhenReady(for url: URL) async -> Color? {
        let retryDelays: [UInt64] = [0, 180_000_000, 360_000_000, 720_000_000, 1_200_000_000]

        for delay in retryDelays {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }

            guard !Task.isCancelled else {
                return nil
            }

            let assets = await VideoDerivedAssetStore.shared.cachedGalleryAssets(for: url, fallback: fallbackTint)
            if let bottomColor = assets.bottomColor {
                return bottomColor
            }
        }

        return nil
    }

    private var pureColorBlendLayer: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: bottomColor.opacity(usesCompactEdgeBlend ? 0.05 : 0.16), location: usesCompactEdgeBlend ? 0.22 : 0.18),
                    .init(color: bottomColor.opacity(usesCompactEdgeBlend ? 0.20 : 0.62), location: usesCompactEdgeBlend ? 0.54 : 0.64),
                    .init(color: bottomColor.opacity(usesCompactEdgeBlend ? 0.60 : 0.96), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(usesCompactEdgeBlend ? 0.05 : 0.04), location: 0.42),
                    .init(color: .clear, location: 0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.plusLighter)
        }
    }

    @ViewBuilder
    private var clearVideoMask: some View {
        if usesCenteredEdges {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.08), location: 0.04),
                    .init(color: .black.opacity(0.32), location: 0.10),
                    .init(color: .black.opacity(0.70), location: 0.18),
                    .init(color: .black, location: 0.30),
                    .init(color: .black, location: 0.70),
                    .init(color: .black.opacity(0.70), location: 0.82),
                    .init(color: .black.opacity(0.32), location: 0.90),
                    .init(color: .black.opacity(0.08), location: 0.96),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if isLandscape {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: clearVideoFadeStart),
                    .init(color: .black.opacity(0.50), location: 0.90),
                    .init(color: .black.opacity(0.12), location: 0.98),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(interpolateTopEdgeOpacity(1, 0)), location: 0),
                    .init(color: .black.opacity(interpolateTopEdgeOpacity(1, 0.08)), location: 0.04),
                    .init(color: .black.opacity(interpolateTopEdgeOpacity(1, 0.32)), location: 0.10),
                    .init(color: .black.opacity(interpolateTopEdgeOpacity(1, 0.70)), location: 0.18),
                    .init(color: .black, location: 0.30),
                    .init(color: .black, location: 0.62),
                    .init(color: .black.opacity(interpolateEdgeOpacity(0.91, 1)), location: 0.70),
                    .init(color: .black.opacity(interpolateEdgeOpacity(0.78, 0.70)), location: 0.82),
                    .init(color: .black.opacity(interpolateEdgeOpacity(0.58, 0.32)), location: 0.90),
                    .init(color: .black.opacity(interpolateEdgeOpacity(0.44, 0.08)), location: 0.96),
                    .init(color: .black.opacity(interpolateEdgeOpacity(0.34, 0)), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func interpolateEdgeOpacity(_ collapsedValue: Double, _ centeredValue: Double) -> Double {
        collapsedValue + (centeredValue - collapsedValue) * Double(clampedEdgeBlendProgress)
    }

    private func interpolateTopEdgeOpacity(_ collapsedValue: Double, _ centeredValue: Double) -> Double {
        collapsedValue + (centeredValue - collapsedValue) * Double(clampedTopEdgeBlendProgress)
    }

    private struct ColorSamplingTaskID: Hashable {
        let url: URL?
        let policy: BlendedVideoColorSamplingPolicy
    }
}

extension BlendedVideoSurface where Content == EmptyView {
    init(
        url: URL?,
        aspectRatio: CGFloat,
        fallbackTint: Color,
        isPlaying: Bool,
        isMuted: Bool = true,
        width: CGFloat,
        height: CGFloat? = nil,
        videoYOffset: CGFloat = 0,
        videoMotionYOffset: CGFloat = 0,
        videoBlurRadius: CGFloat = 0,
        edgeBlendProgress: CGFloat = 0,
        topEdgeBlendProgress: CGFloat = 0,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        layout: BlendedVideoSurfaceLayout = .topAnchored,
        colorSamplingPolicy: BlendedVideoColorSamplingPolicy = .sampleVideoFrame,
        seekRequest: VideoPlaybackSeekRequest? = nil,
        onPlaybackProgressChange: ((Double) -> Void)? = nil,
        onBottomColorChange: ((Color) -> Void)? = nil
    ) {
        self.init(
            url: url,
            aspectRatio: aspectRatio,
            fallbackTint: fallbackTint,
            isPlaying: isPlaying,
            isMuted: isMuted,
            width: width,
            height: height,
            videoYOffset: videoYOffset,
            videoMotionYOffset: videoMotionYOffset,
            videoBlurRadius: videoBlurRadius,
            edgeBlendProgress: edgeBlendProgress,
            topEdgeBlendProgress: topEdgeBlendProgress,
            videoGravity: videoGravity,
            layout: layout,
            colorSamplingPolicy: colorSamplingPolicy,
            seekRequest: seekRequest,
            onPlaybackProgressChange: onPlaybackProgressChange,
            onBottomColorChange: onBottomColorChange
        ) { _, _, _ in
            EmptyView()
        }
    }
}
