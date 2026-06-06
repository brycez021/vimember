import SwiftUI

enum BlendedVideoSurfaceLayout {
    case topAnchored
    case centeredLandscapeEdges
    case centeredEdges
}

struct BlendedVideoSurface<Content: View>: View {
    let url: URL?
    let aspectRatio: CGFloat
    let fallbackTint: Color
    let isPlaying: Bool
    let width: CGFloat
    let height: CGFloat?
    let videoYOffset: CGFloat
    let videoMotionYOffset: CGFloat
    let videoBlurRadius: CGFloat
    let layout: BlendedVideoSurfaceLayout
    let onBottomColorChange: ((Color) -> Void)?
    let content: (_ videoHeight: CGFloat, _ isLandscape: Bool, _ videoYOffset: CGFloat) -> Content

    @State private var bottomColor: Color

    init(
        url: URL?,
        aspectRatio: CGFloat,
        fallbackTint: Color,
        isPlaying: Bool,
        width: CGFloat,
        height: CGFloat? = nil,
        videoYOffset: CGFloat = 0,
        videoMotionYOffset: CGFloat = 0,
        videoBlurRadius: CGFloat = 0,
        layout: BlendedVideoSurfaceLayout = .topAnchored,
        onBottomColorChange: ((Color) -> Void)? = nil,
        @ViewBuilder content: @escaping (_ videoHeight: CGFloat, _ isLandscape: Bool, _ videoYOffset: CGFloat) -> Content
    ) {
        self.url = url
        self.aspectRatio = aspectRatio
        self.fallbackTint = fallbackTint
        self.isPlaying = isPlaying
        self.width = width
        self.height = height
        self.videoYOffset = videoYOffset
        self.videoMotionYOffset = videoMotionYOffset
        self.videoBlurRadius = videoBlurRadius
        self.layout = layout
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

    var body: some View {
        ZStack(alignment: .top) {
            bottomColor

            VideoPlayerSurface(url: url, isPlaying: isPlaying, videoGravity: .resizeAspectFill)
                .frame(width: width, height: videoHeight)
                .mask(clearVideoMask)
                .clipped()
                .blur(radius: videoBlurRadius, opaque: true)
                .offset(y: resolvedVideoYOffset + videoMotionYOffset)
                .zIndex(0)

            if usesCenteredEdges {
                centeredLandscapeEdgeBlendLayers
                    .zIndex(1)
            } else {
                pureColorBlendLayer
                    .frame(height: blendMaskHeight)
                    .offset(y: resolvedVideoYOffset + blendTopOffset)
                    .zIndex(1)
            }

            content(videoHeight, isLandscape, resolvedVideoYOffset)
                .zIndex(2)
        }
        .frame(width: width, height: renderHeight)
        .clipShape(Rectangle())
        .task(id: url) {
            guard let url else { return }
            let sample = await VideoColorSampler.shared.sample(for: url, fallback: fallbackTint)
            bottomColor = sample.bottomColor
            onBottomColorChange?(sample.bottomColor)
        }
    }

    private var centeredLandscapeEdgeBlendLayers: some View {
        ZStack(alignment: .top) {
            pureColorBlendLayer
                .frame(height: blendMaskHeight)
                .scaleEffect(y: -1, anchor: .center)
                .offset(y: resolvedVideoYOffset - colorBlockOverflow)

            pureColorBlendLayer
                .frame(height: blendMaskHeight)
                .offset(y: resolvedVideoYOffset + blendTopOffset)
        }
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
                    .init(color: .black.opacity(0.12), location: 0.02),
                    .init(color: .black.opacity(0.50), location: 0.10),
                    .init(color: .black, location: 0.22),
                    .init(color: .black, location: clearVideoFadeStart),
                    .init(color: .black.opacity(0.50), location: 0.90),
                    .init(color: .black.opacity(0.12), location: 0.98),
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
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.62),
                    .init(color: .black.opacity(0.78), location: 0.82),
                    .init(color: .black.opacity(0.34), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

extension BlendedVideoSurface where Content == EmptyView {
    init(
        url: URL?,
        aspectRatio: CGFloat,
        fallbackTint: Color,
        isPlaying: Bool,
        width: CGFloat,
        height: CGFloat? = nil,
        videoYOffset: CGFloat = 0,
        videoMotionYOffset: CGFloat = 0,
        videoBlurRadius: CGFloat = 0,
        layout: BlendedVideoSurfaceLayout = .topAnchored,
        onBottomColorChange: ((Color) -> Void)? = nil
    ) {
        self.init(
            url: url,
            aspectRatio: aspectRatio,
            fallbackTint: fallbackTint,
            isPlaying: isPlaying,
            width: width,
            height: height,
            videoYOffset: videoYOffset,
            videoMotionYOffset: videoMotionYOffset,
            videoBlurRadius: videoBlurRadius,
            layout: layout,
            onBottomColorChange: onBottomColorChange
        ) { _, _, _ in
            EmptyView()
        }
    }
}
