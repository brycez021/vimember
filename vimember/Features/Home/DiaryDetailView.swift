import SwiftUI
import UIKit

struct DiaryDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let onDelete: (_ diary: VideoDiary) async throws -> Void
    let onSaveEdit: (_ diary: VideoDiary, _ title: String, _ body: String) async throws -> VideoDiary

    @State private var currentDiary: VideoDiary
    @State private var panelProgress: CGFloat = 0
    @State private var panelDragStartProgress: CGFloat?
    @State private var panelScrollResetID = 0
    @State private var isDeleteConfirmationPresented = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var isEditing = false
    @State private var sampledBottomColor: Color

    init(
        diary: VideoDiary,
        onDelete: @escaping (_ diary: VideoDiary) async throws -> Void,
        onSaveEdit: @escaping (_ diary: VideoDiary, _ title: String, _ body: String) async throws -> VideoDiary
    ) {
        self.onDelete = onDelete
        self.onSaveEdit = onSaveEdit
        _currentDiary = State(initialValue: diary)
        _sampledBottomColor = State(initialValue: diary.fallbackTint)
    }

    var body: some View {
        GeometryReader { _ in
            let screenSize = UIScreen.main.bounds.size
            let screenWidth = screenSize.width
            let screenHeight = screenSize.height
            let xScale = screenWidth / 420
            let yScale = screenHeight / 912
            let textLayout = DetailTextLayoutMetrics(
                diary: currentDiary,
                screenWidth: screenWidth,
                screenHeight: screenHeight,
                xScale: xScale,
                yScale: yScale
            )
            let videoSurfaceLayout: BlendedVideoSurfaceLayout = currentDiary.isLandscapeVideo ? .centeredLandscapeEdges : .topAnchored
            let detailVideoHeight = screenWidth / max(currentDiary.displayAspectRatio, 0.1)
            let landscapeOpticalLift = 58 * yScale
            let detailVideoYOffset = currentDiary.isLandscapeVideo ? max(0, (screenHeight - detailVideoHeight) / 2 - landscapeOpticalLift) : 0

            ZStack(alignment: .topLeading) {
                BlendedVideoSurface(
                    url: currentDiary.videoURL,
                    aspectRatio: currentDiary.displayAspectRatio,
                    fallbackTint: currentDiary.fallbackTint,
                    isPlaying: true,
                    width: screenWidth,
                    height: screenHeight,
                    videoYOffset: detailVideoYOffset,
                    layout: videoSurfaceLayout,
                    onBottomColorChange: { color in
                        sampledBottomColor = color
                    }
                )
                .ignoresSafeArea()

                BottomBlurPanelBackground(
                    progress: panelProgress,
                    layout: textLayout,
                    screenWidth: screenWidth,
                    screenHeight: screenHeight,
                    yScale: yScale,
                    backgroundColor: sampledBottomColor
                )
                .zIndex(1)

                DetailTextPanel(
                    diary: currentDiary,
                    progress: panelProgress,
                    layout: textLayout,
                    screenWidth: screenWidth,
                    screenHeight: screenHeight,
                    xScale: xScale,
                    yScale: yScale,
                    scrollResetID: panelScrollResetID
                )
                .contentShape(Rectangle())
                .simultaneousGesture(textPanelDragGesture(revealDistance: textLayout.revealDistance, screenHeight: screenHeight))
                .zIndex(1)

                DetailTopControls(
                    screenWidth: screenWidth,
                    xScale: xScale,
                    yScale: yScale,
                    isDeleting: isDeleting,
                    onBack: {
                        dismiss()
                    },
                    onDelete: {
                        isDeleteConfirmationPresented = true
                    },
                    onEdit: {
                        isEditing = true
                    }
                )
                .zIndex(2)

                if let deleteError {
                    Text(deleteError)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.72), in: Capsule())
                        .position(x: screenWidth / 2, y: screenHeight - 60)
                        .zIndex(3)
                }
            }
            .frame(width: screenWidth, height: screenHeight)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .alert("Delete this video diary?", isPresented: $isDeleteConfirmationPresented) {
            Button("Delete", role: .destructive) {
                Task {
                    await deleteDiary()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the local diary and copied video from vimember. It does not delete the original video in Photos.")
        }
        .fullScreenCover(isPresented: $isEditing) {
            EditVideoDiaryFlowView(diary: currentDiary) { title, body in
                let updatedDiary = try await onSaveEdit(currentDiary, title, body)
                await MainActor.run {
                    currentDiary = updatedDiary
                }
            }
        }
    }

    private func textPanelDragGesture(revealDistance: CGFloat, screenHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard shouldTrackPanelDrag(value, screenHeight: screenHeight) else {
                    return
                }

                let startProgress = panelDragStartProgress ?? panelProgress
                panelDragStartProgress = startProgress
                panelProgress = clampedProgress(startProgress - value.translation.height / revealDistance)
            }
            .onEnded { value in
                defer {
                    panelDragStartProgress = nil
                }
                guard let startProgress = panelDragStartProgress else {
                    return
                }

                let predictedProgress = clampedProgress(startProgress - value.predictedEndTranslation.height / revealDistance)
                let targetProgress: CGFloat = predictedProgress >= 0.48 ? 1 : 0
                if targetProgress == 0 {
                    panelScrollResetID += 1
                }
                withAnimation(.interactiveSpring(response: 0.50, dampingFraction: 0.86, blendDuration: 0.12)) {
                    panelProgress = targetProgress
                }
            }
    }

    private func shouldTrackPanelDrag(_ value: DragGesture.Value, screenHeight: CGFloat) -> Bool {
        if panelProgress < 0.98 {
            return true
        }
        if value.translation.height < 0 {
            return true
        }
        return value.startLocation.y < screenHeight * 0.38
    }

    private func clampedProgress(_ progress: CGFloat) -> CGFloat {
        min(max(progress, 0), 1)
    }

    @MainActor
    private func deleteDiary() async {
        guard !isDeleting else { return }
        isDeleting = true
        deleteError = nil

        do {
            try await onDelete(currentDiary)
            dismiss()
        } catch {
            deleteError = "Unable to delete this video diary."
            isDeleting = false
        }
    }
}

private struct DetailTextLayoutMetrics {
    let diary: VideoDiary
    let screenWidth: CGFloat
    let screenHeight: CGFloat
    let xScale: CGFloat
    let yScale: CGFloat

    private var textLeft: CGFloat {
        23 * xScale
    }

    private var textWidth: CGFloat {
        min(384 * xScale, screenWidth - textLeft * 2)
    }

    private var bottomInset: CGFloat {
        textLeft
    }

    private var maxTitleDistanceFromBottom: CGFloat {
        280 * yScale
    }

    var collapsedTextTop: CGFloat {
        max(screenHeight - bottomInset - textContentHeight, screenHeight - maxTitleDistanceFromBottom)
    }

    var expandedTextTop: CGFloat {
        140 * yScale
    }

    var revealDistance: CGFloat {
        max(collapsedTextTop - expandedTextTop, 1)
    }

    private var textContentHeight: CGFloat {
        36
            + 7
            + 22
            + 8
            + max(0.5, 0.5 * xScale)
            + 14
            + bodyHeight
    }

    private var bodyHeight: CGFloat {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.attributedText = Self.bodyAttributedText(
            diary.body,
            fontSize: 16,
            lineHeight: 22,
            letterSpacing: 0.16,
            paragraphSpacing: 16
        )

        return ceil(
            label.sizeThatFits(
                CGSize(width: textWidth, height: .greatestFiniteMagnitude)
            ).height
        )
    }

    private static func bodyAttributedText(
        _ text: String,
        fontSize: CGFloat,
        lineHeight: CGFloat,
        letterSpacing: CGFloat,
        paragraphSpacing: CGFloat
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.paragraphSpacing = paragraphSpacing
        paragraph.lineBreakMode = .byWordWrapping

        let font = UIFont(name: "PingFangSC-Regular", size: fontSize)
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

private struct BottomBlurPanelBackground: View {
    let progress: CGFloat
    let layout: DetailTextLayoutMetrics
    let screenWidth: CGFloat
    let screenHeight: CGFloat
    let yScale: CGFloat
    let backgroundColor: Color

    private var clampedProgress: CGFloat {
        min(max(progress, 0), 1)
    }

    private var topFadeBand: CGFloat {
        104 * yScale
    }

    private var panelTop: CGFloat {
        interpolate(layout.collapsedTextTop - topFadeBand, -topFadeBand)
    }

    private var panelHeight: CGFloat {
        min(screenHeight + topFadeBand, max(topFadeBand, screenHeight - panelTop))
    }

    private var clarityProgress: Double {
        smoothStep(from: 0.08, to: 1.0)
    }

    var body: some View {
        panelBackground
            .frame(width: screenWidth, height: panelHeight)
            .mask(panelMask(height: panelHeight))
            .offset(y: panelTop)
            .frame(width: screenWidth, height: screenHeight, alignment: .topLeading)
            .allowsHitTesting(false)
    }

    private var panelBackground: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(interpolate(0.10, 0.54))

            Rectangle()
                .fill(.regularMaterial)
                .opacity(interpolate(0.02, 0.30))

            LinearGradient(
                stops: [
                    .init(color: backgroundColor.opacity(0), location: 0),
                    .init(color: backgroundColor.opacity(interpolate(0.03, 0.16)), location: 0.24),
                    .init(color: backgroundColor.opacity(interpolate(0.16, 0.34)), location: 0.56),
                    .init(color: backgroundColor.opacity(interpolate(0.58, 0.88)), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                stops: [
                    .init(color: .white.opacity(interpolate(0.03, 0.10)), location: 0.18),
                    .init(color: .white.opacity(0), location: 0.68)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.plusLighter)

            Rectangle()
                .fill(.regularMaterial)
                .opacity(0.18 * clarityProgress)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0),
                    .init(color: .black.opacity(0.03 * clarityProgress), location: 0.20),
                    .init(color: .black.opacity(0.10 * clarityProgress), location: 0.58),
                    .init(color: .black.opacity(0.06 * clarityProgress), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func panelMask(height: CGFloat) -> some View {
        let fadeEnd = min(max(topFadeBand / max(height, 1), 0.10), 0.34)
        let solidStart = min(fadeEnd + 0.18, 0.54)

        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.08), location: fadeEnd * 0.30),
                .init(color: .white.opacity(0.46), location: fadeEnd),
                .init(color: .white, location: solidStart),
                .init(color: .white, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func interpolate(_ collapsedValue: CGFloat, _ expandedValue: CGFloat) -> CGFloat {
        collapsedValue + (expandedValue - collapsedValue) * clampedProgress
    }

    private func interpolate(_ collapsedValue: Double, _ expandedValue: Double) -> Double {
        collapsedValue + (expandedValue - collapsedValue) * Double(clampedProgress)
    }

    private func smoothStep(from start: CGFloat, to end: CGFloat) -> Double {
        guard end > start else {
            return clampedProgress >= end ? 1 : 0
        }

        let normalized = min(max((clampedProgress - start) / (end - start), 0), 1)
        return Double(normalized * normalized * (3 - 2 * normalized))
    }
}

private struct DetailTextPanel: View {
    let diary: VideoDiary
    let progress: CGFloat
    let layout: DetailTextLayoutMetrics
    let screenWidth: CGFloat
    let screenHeight: CGFloat
    let xScale: CGFloat
    let yScale: CGFloat
    let scrollResetID: Int

    private let scrollOriginID = "detail-text-scroll-origin"

    private var clampedProgress: CGFloat {
        min(max(progress, 0), 1)
    }

    private var textLeft: CGFloat {
        23 * xScale
    }

    private var textWidth: CGFloat {
        min(384 * xScale, screenWidth - textLeft * 2)
    }

    private var textTop: CGFloat {
        interpolate(layout.collapsedTextTop, layout.expandedTextTop)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: 1)
                        .id(scrollOriginID)

                    Color.clear
                        .frame(height: max(textTop - 1, 0))

                    textContent
                        .padding(.bottom, 120 * yScale)
                }
                .frame(width: screenWidth, alignment: .topLeading)
            }
            .id(scrollResetID)
            .scrollDisabled(clampedProgress < 0.98)
            .onChange(of: clampedProgress) { _, newProgress in
                guard newProgress < 0.98 else { return }
                proxy.scrollTo(scrollOriginID, anchor: .top)
            }
            .onChange(of: scrollResetID) { _, _ in
                proxy.scrollTo(scrollOriginID, anchor: .top)
            }
        }
        .frame(width: screenWidth, height: screenHeight, alignment: .topLeading)
        .clipped()
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailSingleLineTextLabel(
                text: diary.title,
                fontName: "PingFangSC-Semibold",
                fontSize: 30,
                lineHeight: 36,
                letterSpacing: 0.3,
                labelWidth: textWidth,
                labelHeight: 36
            )
            .offset(y: -4)
            .padding(.bottom, 2)

            DetailSingleLineTextLabel(
                text: diary.dateText,
                fontName: "PingFangSC-Medium",
                fontSize: 16,
                lineHeight: 22,
                letterSpacing: 0.16,
                labelWidth: textWidth,
                labelHeight: 22
            )
            .offset(y: -6)
            .padding(.bottom, 4)

            Rectangle()
                .fill(.white.opacity(0.68))
                .frame(width: min(374 * xScale, textWidth), height: max(0.5, 0.5 * xScale))

            DetailBodyTextLabel(
                text: diary.body,
                fontSize: 16,
                lineHeight: 22,
                letterSpacing: 0.16,
                paragraphSpacing: 16,
                labelWidth: textWidth
            )
            .offset(y: interpolate(0, -4 * yScale))
            .padding(.top, 14)
        }
        .frame(width: textWidth, alignment: .topLeading)
        .padding(.leading, textLeft)
        .shadow(color: .black.opacity(interpolate(0.36, 0.18)), radius: 7 * xScale, y: 2 * yScale)
    }

    private func interpolate(_ collapsedValue: CGFloat, _ expandedValue: CGFloat) -> CGFloat {
        collapsedValue + (expandedValue - collapsedValue) * clampedProgress
    }
}

private struct DetailSingleLineTextLabel: UIViewRepresentable {
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
        label.numberOfLines = 1
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

private struct DetailBodyTextLabel: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let letterSpacing: CGFloat
    let paragraphSpacing: CGFloat
    let labelWidth: CGFloat

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.backgroundColor = .clear
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.textColor = .white
        label.isUserInteractionEnabled = false
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.preferredMaxLayoutWidth = labelWidth
        label.attributedText = attributedText
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let size = uiView.sizeThatFits(
            CGSize(width: labelWidth, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: labelWidth, height: ceil(size.height))
    }

    private var attributedText: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.paragraphSpacing = paragraphSpacing
        paragraph.lineBreakMode = .byWordWrapping

        let font = UIFont(name: "PingFangSC-Regular", size: fontSize)
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

private struct DetailTopControls: View {
    let screenWidth: CGFloat
    let xScale: CGFloat
    let yScale: CGFloat
    let isDeleting: Bool
    let onBack: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void

    private var buttonSize: CGFloat {
        44 * xScale
    }

    private var editWidth: CGFloat {
        68 * xScale
    }

    private var centerY: CGFloat {
        (52 * yScale) + buttonSize / 2 + 16 * yScale
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            DetailGlassIconButton(
                systemName: "chevron.left",
                size: buttonSize,
                action: onBack
            )
            .position(x: (20 * xScale) + buttonSize / 2, y: centerY)

            DetailGlassIconButton(
                systemName: "trash",
                size: buttonSize,
                isEnabled: !isDeleting,
                action: onDelete
            )
            .position(
                x: editCenterX - editWidth / 2 - (10 * xScale) - buttonSize / 2,
                y: centerY
            )

            DetailGlassPillButton(
                systemName: "pencil",
                width: editWidth,
                height: buttonSize,
                action: onEdit
            )
            .position(x: editCenterX, y: centerY)
        }
        .frame(width: screenWidth, height: centerY + buttonSize / 2, alignment: .topLeading)
    }

    private var editCenterX: CGFloat {
        screenWidth - (20 * xScale) - editWidth / 2
    }
}

private struct DetailGlassIconButton: View {
    let systemName: String
    let size: CGFloat
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        LiquidGlassIconButton(
            systemName: systemName,
            size: size,
            symbolSize: max(18, size * 0.42),
            symbolWeight: .semibold,
            foregroundColor: .white,
            isEnabled: isEnabled,
            action: action
        )
    }
}

private struct DetailGlassPillButton: View {
    let systemName: String
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        LiquidGlassPillButton(
            width: width,
            height: height,
            systemName: systemName,
            symbolSize: max(18, height * 0.40),
            foregroundColor: .white,
            action: action
        )
    }
}
