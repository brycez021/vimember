import SwiftUI

struct HomeView: View {
    private let diaries = VideoDiary.samples

    @State private var activeDiaryID: VideoDiary.ID?
    @State private var pendingVisibilityTask: Task<Void, Never>?
    @State private var isSwitcherPresented = false

    var body: some View {
        GeometryReader { geometry in
            let viewport = geometry.size
            let cardWidth = min(viewport.width, 420)
            let initialContentOffset = -cardWidth * (676 / 420)
            let screenSize = UIScreen.main.bounds.size
            let screenWidth = screenSize.width
            let screenHeight = screenSize.height
            let designScreenWidth: CGFloat = 420
            let designScreenHeight: CGFloat = 912
            let xScale = screenWidth / designScreenWidth
            let yScale = screenHeight / designScreenHeight
            let phoneFrameLeft = (viewport.width - cardWidth) / 2
            let topButtonSize: CGFloat = 44 * xScale
            let topButtonTop = 69 * yScale
            let topButtonRight = phoneFrameLeft + cardWidth - (20 * xScale)
            let bottomSearchWidth: CGFloat = 306 * xScale
            let bottomAddButtonSize: CGFloat = 50 * xScale
            let bottomControlsGap: CGFloat = 10 * xScale
            let bottomControlsHeight: CGFloat = 50 * xScale
            let bottomControlsBottomMargin: CGFloat = 27 * yScale

            ZStack(alignment: .topTrailing) {
                Color.white.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(diaries) { diary in
                            VideoDiaryCard(
                                diary: diary,
                                width: cardWidth,
                                isActive: activeDiaryID == diary.id
                            )
                            .id(diary.id)
                            .background(VisibilityReporter(id: diary.id))
                            .onTapGesture {
                                // Detail navigation will be wired once the detail Figma frame is specified.
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, initialContentOffset)
                    .padding(.bottom, 28)
                }
                .coordinateSpace(name: "home-scroll")
                .onPreferenceChange(CardVisibilityPreferenceKey.self) { frames in
                    scheduleActiveCardUpdate(frames: frames, viewport: viewport)
                }

                HomeTopButton(isPresented: $isSwitcherPresented, size: topButtonSize)
                    .position(
                        x: topButtonRight - topButtonSize / 2,
                        y: topButtonTop + topButtonSize / 2
                    )

                HomeBottomControls(
                    searchWidth: bottomSearchWidth,
                    height: bottomControlsHeight,
                    addButtonSize: bottomAddButtonSize,
                    gap: bottomControlsGap
                )
                    .position(
                        x: screenWidth / 2,
                        y: screenHeight - bottomControlsBottomMargin - bottomControlsHeight / 2
                    )

                if isSwitcherPresented {
                    HomeSwitchPanel()
                        .position(
                            x: topButtonRight - 125,
                            y: topButtonTop + topButtonSize + 51
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                        .zIndex(2)
                }
            }
            .ignoresSafeArea()
            .animation(.snappy(duration: 0.22), value: isSwitcherPresented)
            .onAppear {
                activeDiaryID = diaries.first?.id
            }
        }
    }

    private func scheduleActiveCardUpdate(frames: [VideoDiary.ID: CGRect], viewport: CGSize) {
        pendingVisibilityTask?.cancel()

        let candidates = frames
            .filter { _, frame in frame.maxY > 0 && frame.minY < viewport.height }
            .map { id, frame -> (VideoDiary.ID, CGFloat) in
                let visibleHeight = min(frame.maxY, viewport.height) - max(frame.minY, 0)
                let centerDistance = abs(frame.midY - viewport.height * 0.52)
                return (id, centerDistance - visibleHeight * 0.35)
            }
            .sorted { $0.1 < $1.1 }

        guard let bestID = candidates.first?.0 else {
            return
        }

        activeDiaryID = nil
        pendingVisibilityTask = Task {
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                activeDiaryID = bestID
            }
        }
    }
}

private struct VideoDiaryCard: View {
    let diary: VideoDiary
    let width: CGFloat
    let isActive: Bool

    @State private var bottomColor: Color
    @State private var posterImage: UIImage?

    init(diary: VideoDiary, width: CGFloat, isActive: Bool) {
        self.diary = diary
        self.width = width
        self.isActive = isActive
        _bottomColor = State(initialValue: diary.fallbackTint)
    }

    private var videoHeight: CGFloat {
        width / max(diary.displayAspectRatio, 0.1)
    }

    private var cardHeight: CGFloat {
        videoHeight + colorBlockOverflow
    }

    private var colorBlockOverflow: CGFloat {
        diary.isLandscapeVideo ? width * (86 / 420) : 0
    }

    private var blendHeight: CGFloat {
        diary.isLandscapeVideo ? width * (132 / 420) : width * (179 / 420)
    }

    private var blurRadius: CGFloat {
        diary.isLandscapeVideo ? 22 : 30
    }

    private var textTopOffset: CGFloat {
        let figmaOffset: CGFloat = diary.isLandscapeVideo ? 28 : 114
        return videoHeight - width * (figmaOffset / 420)
    }

    var body: some View {
        ZStack(alignment: .top) {
            bottomColor

            if let posterImage {
                Image(uiImage: posterImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: videoHeight)
                    .clipped()
            }

            VideoPlayerSurface(url: diary.videoURL, isPlaying: isActive, videoGravity: .resizeAspectFill)
                .frame(width: width, height: videoHeight)
                .clipped()

            if let posterImage {
                Image(uiImage: posterImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: blendHeight)
                    .blur(radius: blurRadius)
                    .opacity(0.82)
                    .mask(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.45), .black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .offset(y: max(0, videoHeight - blendHeight))
                    .clipped()
            }

            LinearGradient(
                colors: [.clear, bottomColor.opacity(0.18), bottomColor.opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: blendHeight + colorBlockOverflow)
            .offset(y: max(0, videoHeight - blendHeight))

            DiaryTextBlock(diary: diary)
                .padding(.horizontal, 18)
                .frame(width: width, alignment: .leading)
                .offset(y: textTopOffset)
        }
        .frame(width: width, height: cardHeight)
        .clipShape(Rectangle())
        .task(id: diary.videoURL) {
            guard let url = diary.videoURL else { return }
            let sample = await VideoColorSampler.shared.sample(for: url, fallback: diary.fallbackTint)
            bottomColor = sample.bottomColor
            posterImage = sample.image
        }
    }
}

private struct DiaryTextBlock: View {
    let diary: VideoDiary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(diary.title)
                .font(.system(size: 25, weight: .semibold, design: .default))
                .lineLimit(1)
                .foregroundStyle(.white)

            Text(diary.dateText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.top, 2)

            Rectangle()
                .fill(.white.opacity(0.72))
                .frame(height: 1 / UIScreen.main.scale)
                .padding(.top, 4)
                .padding(.bottom, 7)

            Text(diary.body)
                .font(.system(size: 16, weight: .regular))
                .lineSpacing(0)
                .lineLimit(2)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct HomeTopButton: View {
    @Binding var isPresented: Bool
    let size: CGFloat

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: max(17, size * 0.43), weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.82))
                .frame(width: size, height: size)
                .glassButtonShape()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch settings")
    }
}

private struct HomeBottomControls: View {
    let searchWidth: CGFloat
    let height: CGFloat
    let addButtonSize: CGFloat
    let gap: CGFloat

    private var width: CGFloat {
        searchWidth + gap + addButtonSize
    }

    var body: some View {
        HStack(spacing: gap) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .regular))

                Text("Search")
                    .font(.system(size: 17, weight: .regular))

                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.black.opacity(0.86))
            .padding(.horizontal, 18)
            .frame(width: searchWidth, height: height)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(Color.white.opacity(0.65))
                            .blendMode(.plusLighter)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 40, y: 8)
            )

            Button {
                // Import flow will be wired after the import/editor Figma frames are specified.
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: max(20, addButtonSize * 0.44), weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.84))
                    .frame(width: addButtonSize, height: addButtonSize)
                    .glassButtonShape()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add video diary")
        }
        .frame(width: width, height: max(height, addButtonSize))
    }
}

private struct HomeSwitchPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeSwitchAction(icon: "calendar", title: "Date")
            HomeSwitchAction(icon: "square.grid.2x2", title: "Gallery")
        }
        .padding(.vertical, 7.5)
        .frame(width: 250)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Color.white.opacity(0.60))
                        .blendMode(.plusLighter)
                )
                .shadow(color: .black.opacity(0.12), radius: 40, y: 8)
        )
    }
}

private struct HomeSwitchAction: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .regular))
                .frame(width: 20)

            Text(title)
                .font(.system(size: 20, weight: .regular))
                .lineLimit(1)
        }
        .foregroundStyle(Color.black.opacity(0.90))
        .frame(height: 42)
        .padding(.horizontal, 26)
    }
}

private struct VisibilityReporter: View {
    let id: VideoDiary.ID

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: CardVisibilityPreferenceKey.self,
                value: [id: proxy.frame(in: .named("home-scroll"))]
            )
        }
    }
}

private struct CardVisibilityPreferenceKey: PreferenceKey {
    static var defaultValue: [VideoDiary.ID: CGRect] = [:]

    static func reduce(value: inout [VideoDiary.ID: CGRect], nextValue: () -> [VideoDiary.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private extension View {
    func glassButtonShape() -> some View {
        background(
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .fill(Color.white.opacity(0.65))
                        .blendMode(.plusLighter)
                )
                .shadow(color: .black.opacity(0.12), radius: 40, y: 8)
        )
    }
}
