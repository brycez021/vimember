import SwiftUI
import SwiftData
import UIKit

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VideoDiaryRecord.createdAt, order: .reverse) private var records: [VideoDiaryRecord]

    @State private var activeDiaryID: VideoDiary.ID?
    @State private var pendingVisibilityTask: Task<Void, Never>?
    @State private var isSwitcherPresented = false
    @State private var isImportPresented = false
    @State private var selectedDiary: VideoDiary?
    @State private var hiddenSampleIDs: Set<VideoDiary.ID> = []
    @State private var sampleOverrides: [VideoDiary.ID: VideoDiary] = [:]

    private var diaries: [VideoDiary] {
        records.map(\.diary) + VideoDiary.samples.compactMap { diary in
            guard !hiddenSampleIDs.contains(diary.id) else { return nil }
            return sampleOverrides[diary.id] ?? diary
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let viewport = geometry.size
            let cardWidth = min(viewport.width, 420)
            let screenSize = UIScreen.main.bounds.size
            let screenWidth = screenSize.width
            let screenHeight = screenSize.height
            let designScreenWidth: CGFloat = 420
            let designScreenHeight: CGFloat = 912
            let xScale = screenWidth / designScreenWidth
            let yScale = screenHeight / designScreenHeight
            let phoneFrameLeft = (viewport.width - cardWidth) / 2
            let topButtonSize: CGFloat = 44 * xScale
            let topButtonTop = 52 * yScale
            let topButtonRight = phoneFrameLeft + cardWidth - (20 * xScale)
            let bottomSearchWidth: CGFloat = 306 * xScale
            let bottomAddButtonSize: CGFloat = 50 * xScale
            let bottomControlsGap: CGFloat = 10 * xScale
            let bottomControlsHeight: CGFloat = 50 * xScale
            let bottomControlsBottomMargin: CGFloat = 27 * yScale
            let screenEdgeFadeHeight: CGFloat = 250 * yScale

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
                                activeDiaryID = nil
                                selectedDiary = diary
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 28)
                }
                .coordinateSpace(name: "home-scroll")
                .onPreferenceChange(CardVisibilityPreferenceKey.self) { frames in
                    scheduleActiveCardUpdate(frames: frames, viewport: viewport)
                }

                HomeScreenEdgeFadeOverlay(
                    backgroundColor: .white,
                    width: screenWidth,
                    height: screenEdgeFadeHeight,
                    edge: .top
                )
                .position(x: screenWidth / 2, y: screenEdgeFadeHeight / 2)
                .allowsHitTesting(false)

                HomeScreenEdgeFadeOverlay(
                    backgroundColor: .white,
                    width: screenWidth,
                    height: screenEdgeFadeHeight,
                    edge: .bottom
                )
                .position(x: screenWidth / 2, y: screenHeight - screenEdgeFadeHeight / 2)
                .allowsHitTesting(false)

                HomeTopButton(isPresented: $isSwitcherPresented, size: topButtonSize)
                    .position(
                        x: topButtonRight - topButtonSize / 2,
                        y: topButtonTop + topButtonSize / 2
                    )

                HomeBottomControls(
                    searchWidth: bottomSearchWidth,
                    height: bottomControlsHeight,
                    addButtonSize: bottomAddButtonSize,
                    gap: bottomControlsGap,
                    addAction: {
                        isImportPresented = true
                    }
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
            .onChange(of: diaries.first?.id) { _, newValue in
                activeDiaryID = newValue
            }
            .fullScreenCover(isPresented: $isImportPresented) {
                AddVideoFlowView()
            }
            .fullScreenCover(item: $selectedDiary, onDismiss: {
                activeDiaryID = diaries.first?.id
            }) { diary in
                DiaryDetailView(
                    diary: diary,
                    onDelete: { diary in
                        try await deleteDiary(diary)
                    },
                    onSaveEdit: { diary, title, body in
                        try await saveEditedDiary(diary: diary, title: title, body: body)
                    }
                )
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

    @MainActor
    private func deleteDiary(_ diary: VideoDiary) async throws {
        if let record = records.first(where: { $0.id == diary.id }) {
            try await VideoFileStore.deleteVideo(named: record.localVideoFilename)
            modelContext.delete(record)
            try modelContext.save()
        } else {
            hiddenSampleIDs.insert(diary.id)
            sampleOverrides[diary.id] = nil
        }

        selectedDiary = nil
        if activeDiaryID == diary.id {
            activeDiaryID = diaries.first?.id
        }
    }

    @MainActor
    private func saveEditedDiary(diary: VideoDiary, title: String, body: String) async throws -> VideoDiary {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmedTitle.isEmpty ? "Title" : trimmedTitle

        if let record = records.first(where: { $0.id == diary.id }) {
            record.title = finalTitle
            record.body = body
            record.updatedAt = Date()
            try modelContext.save()

            let updatedDiary = record.diary
            selectedDiary = updatedDiary
            return updatedDiary
        }

        let updatedDiary = diary.replacingText(title: finalTitle, body: body)
        sampleOverrides[diary.id] = updatedDiary
        selectedDiary = updatedDiary
        return updatedDiary
    }
}

private struct VideoDiaryCard: View {
    let diary: VideoDiary
    let width: CGFloat
    let isActive: Bool

    private var videoHeight: CGFloat {
        width / max(diary.displayAspectRatio, 0.1)
    }

    private var cardHeight: CGFloat {
        videoHeight + colorBlockOverflow
    }

    private var colorBlockOverflow: CGFloat {
        diary.isLandscapeVideo ? width * (86 / 420) : 0
    }

    var body: some View {
        BlendedVideoSurface(
            url: diary.videoURL,
            aspectRatio: diary.displayAspectRatio,
            fallbackTint: diary.fallbackTint,
            isPlaying: isActive,
            width: width
        ) { _, _, _ in
            DiaryTextBlock(
                diary: diary,
                width: width,
                cardHeight: cardHeight,
                isLandscapeVideo: diary.isLandscapeVideo
            )
        }
        .frame(width: width, height: cardHeight)
    }
}

private struct DiaryTextBlock: View {
    let diary: VideoDiary
    let width: CGFloat
    let cardHeight: CGFloat
    let isLandscapeVideo: Bool

    var body: some View {
        HomeDiaryTextOverlay(
            diary: diary,
            width: width,
            cardHeight: cardHeight,
            layout: isLandscapeVideo ? .landscape : .vertical
        )
    }
}

private struct HomeDiaryTextOverlay: View {
    let diary: VideoDiary
    let width: CGFloat
    let cardHeight: CGFloat
    let layout: Layout

    enum Layout {
        case vertical
        case landscape

        var titleX: CGFloat {
            switch self {
            case .vertical:
                return 23
            case .landscape:
                return 23
            }
        }

        var dateX: CGFloat {
            switch self {
            case .vertical:
                return 23
            case .landscape:
                return 23
            }
        }

        var dividerX: CGFloat {
            switch self {
            case .vertical:
                return 23
            case .landscape:
                return 23
            }
        }

        var bodyX: CGFloat {
            switch self {
            case .vertical:
                return 23
            case .landscape:
                return 23
            }
        }

        var titleTopFromBottom: CGFloat {
            switch self {
            case .vertical:
                return 125
            case .landscape:
                return 125
            }
        }

        var dateTopFromBottom: CGFloat {
            switch self {
            case .vertical:
                return 91.5
            case .landscape:
                return 91.5
            }
        }

        var dividerTopFromBottom: CGFloat {
            switch self {
            case .vertical:
                return 66
            case .landscape:
                return 66
            }
        }

        var bodyTopFromBottom: CGFloat {
            switch self {
            case .vertical:
                return 60.5
            case .landscape:
                return 60.5
            }
        }

        var titleWidth: CGFloat {
            switch self {
            case .vertical:
                return 376
            case .landscape:
                return 376
            }
        }

        var dateWidth: CGFloat {
            switch self {
            case .vertical:
                return 376
            case .landscape:
                return 376
            }
        }

        var bodyWidth: CGFloat {
            switch self {
            case .vertical:
                return 376
            case .landscape:
                return 376
            }
        }

        var titleSize: CGFloat {
            switch self {
            case .vertical:
                return 24
            case .landscape:
                return 24
            }
        }

        var groupYOffset: CGFloat {
            switch self {
            case .vertical:
                return 0
            case .landscape:
                return 0
            }
        }
    }

    private let designWidth: CGFloat = 420

    private var scale: CGFloat {
        width / designWidth
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        value * scale
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HomeSingleLineTextLabel(
                text: diary.title,
                fontName: "PingFangSC-Semibold",
                fontSize: scaled(layout.titleSize),
                letterSpacing: scaled(layout.titleSize * 0.01),
                labelWidth: scaled(layout.titleWidth),
                labelHeight: scaled(22)
            )
            .offset(
                x: scaled(layout.titleX),
                y: cardHeight - scaled(layout.titleTopFromBottom)
            )

            HomeSingleLineTextLabel(
                text: diary.dateText,
                fontName: "PingFangSC-Medium",
                fontSize: scaled(14),
                letterSpacing: scaled(0.14),
                labelWidth: scaled(layout.dateWidth),
                labelHeight: scaled(22)
            )
            .offset(
                x: scaled(layout.dateX),
                y: cardHeight - scaled(layout.dateTopFromBottom)
            )

            Rectangle()
                .fill(.white)
                .frame(width: scaled(374), height: scaled(0.5))
                .offset(
                    x: scaled(layout.dividerX),
                    y: cardHeight - scaled(layout.dividerTopFromBottom)
                )

            HomeBodyTextLabel(
                text: diary.body,
                fontName: "PingFangSC-Regular",
                fontSize: scaled(16),
                lineHeight: scaled(20),
                letterSpacing: scaled(0.16),
                labelWidth: scaled(layout.bodyWidth),
                labelHeight: scaled(42)
            )
            .offset(
                x: scaled(layout.bodyX),
                y: cardHeight - scaled(layout.bodyTopFromBottom)
            )
        }
        .frame(width: width, height: cardHeight, alignment: .topLeading)
        .offset(y: scaled(layout.groupYOffset))
    }
}

private struct HomeBodyTextLabel: UIViewRepresentable {
    let text: String
    let fontName: String
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let letterSpacing: CGFloat
    let labelWidth: CGFloat
    let labelHeight: CGFloat

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.backgroundColor = .clear
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.textColor = .white
        label.isUserInteractionEnabled = false
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.preferredMaxLayoutWidth = labelWidth
        label.attributedText = attributedText
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        CGSize(width: labelWidth, height: labelHeight)
    }

    private var attributedText: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byTruncatingTail

        let font = UIFont(name: fontName, size: fontSize)
            ?? .systemFont(ofSize: fontSize, weight: .regular)

        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: UIColor.white,
                .kern: letterSpacing,
                .paragraphStyle: paragraph
            ]
        )
    }
}

private struct HomeSingleLineTextLabel: View {
    let text: String
    let fontName: String
    let fontSize: CGFloat
    let letterSpacing: CGFloat
    let labelWidth: CGFloat
    let labelHeight: CGFloat

    var body: some View {
        Text(text)
            .font(.custom(fontName, size: fontSize))
            .tracking(letterSpacing)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: labelWidth, height: visualHeight, alignment: .topLeading)
            .allowsHitTesting(false)
    }

    private var visualHeight: CGFloat {
        max(labelHeight, fontSize * 1.2)
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

private struct HomeScreenEdgeFadeOverlay: View {
    enum FadeEdge {
        case top
        case bottom
    }

    let backgroundColor: Color
    let width: CGFloat
    let height: CGFloat
    let edge: FadeEdge

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.16)
                .mask(
                    smoothMask(
                        transparentUntil: 0.20,
                        softPoint: 0.56,
                        softOpacity: 0.20
                    )
                )

            Rectangle()
                .fill(.thinMaterial)
                .opacity(0.18)
                .mask(
                    smoothMask(
                        transparentUntil: 0.42,
                        softPoint: 0.76,
                        softOpacity: 0.22
                    )
                )

            LinearGradient(
                stops: [
                    .init(color: backgroundColor.opacity(0), location: 0),
                    .init(color: backgroundColor.opacity(0), location: 0.24),
                    .init(color: backgroundColor.opacity(0.04), location: 0.50),
                    .init(color: backgroundColor.opacity(0.14), location: 0.74),
                    .init(color: backgroundColor.opacity(0.32), location: 0.92),
                    .init(color: backgroundColor.opacity(0.42), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .scaleEffect(y: edge == .top ? -1 : 1, anchor: .center)
        .frame(width: width, height: height)
    }

    private func smoothMask(
        transparentUntil: CGFloat,
        softPoint: CGFloat,
        softOpacity: Double
    ) -> some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: transparentUntil),
                .init(color: .white.opacity(softOpacity), location: softPoint),
                .init(color: .white, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct HomeBottomControls: View {
    let searchWidth: CGFloat
    let height: CGFloat
    let addButtonSize: CGFloat
    let gap: CGFloat
    let addAction: () -> Void

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

            Button(action: addAction) {
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
