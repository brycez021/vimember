import SwiftUI
import UIKit

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
    @State private var posterImage: UIImage?

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

    private var blurredPosterRenderHeight: CGFloat {
        isLandscape ? naturalHeight : videoHeight
    }

    private var clearVideoFadeStart: CGFloat {
        isLandscape ? 0.62 : 1
    }

    var body: some View {
        ZStack(alignment: .top) {
            bottomColor

            if let posterImage {
                Image(uiImage: posterImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: videoHeight)
                    .mask(clearVideoMask)
                    .clipped()
                    .offset(y: videoYOffset)
            }

            VideoPlayerSurface(url: url, isPlaying: isPlaying, videoGravity: .resizeAspectFill)
                .frame(width: width, height: videoHeight)
                .mask(clearVideoMask)
                .clipped()
                .offset(y: videoYOffset)

            if let posterImage {
                blurredPosterLayer(
                    posterImage,
                    radius: isLandscape ? 8 : 7,
                    opacity: 0.24,
                    visibleFrom: isLandscape ? 0.10 : 0,
                    fullFrom: isLandscape ? 0.36 : 0.18
                )

                blurredPosterLayer(
                    posterImage,
                    radius: isLandscape ? 18 : 14,
                    opacity: isLandscape ? 0.48 : 0.46,
                    visibleFrom: isLandscape ? 0.30 : 0.08,
                    fullFrom: isLandscape ? 0.58 : 0.34
                )

                blurredPosterLayer(
                    posterImage,
                    radius: isLandscape ? 36 : 27,
                    opacity: isLandscape ? 0.68 : 0.62,
                    visibleFrom: isLandscape ? 0.50 : 0.26,
                    fullFrom: isLandscape ? 0.80 : 0.62
                )

                blurredPosterLayer(
                    posterImage,
                    radius: isLandscape ? 60 : 42,
                    opacity: isLandscape ? 0.88 : 0.80,
                    visibleFrom: isLandscape ? 0.68 : 0.55,
                    fullFrom: isLandscape ? 1 : 0.92
                )
            }

            LinearGradient(
                colors: [.clear, bottomColor.opacity(0.18), bottomColor.opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: blendMaskHeight)
            .offset(y: videoYOffset + blendTopOffset)

            content(videoHeight, isLandscape, videoYOffset)
        }
        .frame(width: width, height: renderHeight)
        .clipShape(Rectangle())
        .task(id: url) {
            guard let url else { return }
            let sample = await VideoColorSampler.shared.sample(for: url, fallback: fallbackTint)
            bottomColor = sample.bottomColor
            posterImage = sample.image
        }
    }

    private func blurredPosterLayer(
        _ posterImage: UIImage,
        radius: CGFloat,
        opacity: Double,
        visibleFrom: CGFloat,
        fullFrom: CGFloat
    ) -> some View {
        Image(uiImage: posterImage)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: videoHeight)
            .blur(radius: radius)
            .opacity(opacity)
            .frame(width: width, height: blurredPosterRenderHeight, alignment: .top)
            .mask(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: visibleFrom),
                        .init(color: .black, location: fullFrom),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: width, height: blendMaskHeight)
                .offset(y: blendTopOffset)
            }
            .clipped()
            .offset(y: videoYOffset)
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
