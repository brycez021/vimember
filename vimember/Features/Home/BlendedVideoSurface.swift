import SwiftUI

struct BlendedVideoSurface<Content: View>: View {
    let url: URL?
    let aspectRatio: CGFloat
    let fallbackTint: Color
    let isPlaying: Bool
    let width: CGFloat
    let height: CGFloat?
    let videoYOffset: CGFloat
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
        @ViewBuilder content: @escaping (_ videoHeight: CGFloat, _ isLandscape: Bool, _ videoYOffset: CGFloat) -> Content
    ) {
        self.url = url
        self.aspectRatio = aspectRatio
        self.fallbackTint = fallbackTint
        self.isPlaying = isPlaying
        self.width = width
        self.height = height
        self.videoYOffset = videoYOffset
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
        isLandscape ? width * (132 / 420) : width * (260 / 420)
    }

    private var blendTopOffset: CGFloat {
        if isLandscape {
            return max(0, videoHeight - blendHeight)
        }

        let textTopOffset = videoHeight - width * (114 / 420)
        return max(0, textTopOffset - width * (44 / 420))
    }

    private var blendMaskHeight: CGFloat {
        videoHeight - blendTopOffset + colorBlockOverflow
    }

    private var clearVideoFadeStart: CGFloat {
        isLandscape ? 0.62 : 1
    }

    var body: some View {
        ZStack(alignment: .top) {
            bottomColor

            VideoPlayerSurface(url: url, isPlaying: isPlaying, videoGravity: .resizeAspectFill)
                .frame(width: width, height: videoHeight)
                .mask(clearVideoMask)
                .clipped()
                .offset(y: videoYOffset)
                .zIndex(0)

            pureColorBlendLayer
                .frame(height: blendMaskHeight)
                .offset(y: videoYOffset + blendTopOffset)
                .zIndex(1)

            content(videoHeight, isLandscape, videoYOffset)
                .zIndex(2)
        }
        .frame(width: width, height: renderHeight)
        .clipShape(Rectangle())
        .task(id: url) {
            guard let url else { return }
            let sample = await VideoColorSampler.shared.sample(for: url, fallback: fallbackTint)
            bottomColor = sample.bottomColor
        }
    }

    private var pureColorBlendLayer: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: bottomColor.opacity(isLandscape ? 0.10 : 0.08), location: isLandscape ? 0.30 : 0.20),
                    .init(color: bottomColor.opacity(isLandscape ? 0.42 : 0.34), location: isLandscape ? 0.66 : 0.62),
                    .init(color: bottomColor.opacity(0.96), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(isLandscape ? 0.05 : 0.04), location: 0.42),
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
        if isLandscape {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: clearVideoFadeStart),
                    .init(color: .black.opacity(0.56), location: 0.80),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            Rectangle()
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
        videoYOffset: CGFloat = 0
    ) {
        self.init(
            url: url,
            aspectRatio: aspectRatio,
            fallbackTint: fallbackTint,
            isPlaying: isPlaying,
            width: width,
            height: height,
            videoYOffset: videoYOffset
        ) { _, _, _ in
            EmptyView()
        }
    }
}
