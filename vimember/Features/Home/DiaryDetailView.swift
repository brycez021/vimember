import SwiftUI
import UIKit

struct DiaryDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let onDelete: (_ diary: VideoDiary) async throws -> Void
    let onSaveEdit: (_ diary: VideoDiary, _ title: String, _ body: String) async throws -> VideoDiary

    @State private var currentDiary: VideoDiary
    @State private var isTextExpanded = false
    @State private var textDragOffset: CGFloat = 0
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
            let collapsedTextTop = textLayout.collapsedTextTop
            let panelY = (isTextExpanded ? 0 : collapsedTextTop) + textDragOffset

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

                DetailTextPanel(
                    diary: currentDiary,
                    isExpanded: isTextExpanded,
                    screenWidth: screenWidth,
                    screenHeight: screenHeight,
                    xScale: xScale,
                    yScale: yScale,
                    backgroundColor: sampledBottomColor
                )
                .offset(y: panelY)
                .contentShape(Rectangle())
                .simultaneousGesture(textPanelDragGesture(collapsedTextTop: collapsedTextTop, screenHeight: screenHeight))
                .animation(.snappy(duration: 0.36), value: isTextExpanded)
                .zIndex(1)

                if textLayout.isCollapsedTextOverflowing && !isTextExpanded {
                    DetailBottomTextFadeOverlay(
                        backgroundColor: sampledBottomColor,
                        width: screenWidth,
                        height: textLayout.bottomFadeHeight
                    )
                    .position(x: screenWidth / 2, y: screenHeight - textLayout.bottomFadeHeight / 2)
                    .allowsHitTesting(false)
                    .zIndex(1.5)
                }

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

    private func textPanelDragGesture(collapsedTextTop: CGFloat, screenHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if isTextExpanded {
                    textDragOffset = min(max(value.translation.height, 0), collapsedTextTop)
                } else {
                    textDragOffset = max(min(value.translation.height, 0), -collapsedTextTop)
                }
            }
            .onEnded { value in
                let shouldExpand = !isTextExpanded
                    && (value.translation.height < -44 || value.predictedEndTranslation.height < -100)
                let shouldCollapse = isTextExpanded
                    && value.startLocation.y < screenHeight * 0.38
                    && (value.translation.height > 110 || value.predictedEndTranslation.height > 190)

                withAnimation(.snappy(duration: 0.36)) {
                    if shouldExpand {
                        isTextExpanded = true
                    } else if shouldCollapse {
                        isTextExpanded = false
                    }
                    textDragOffset = 0
                }
            }
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

    var bottomFadeHeight: CGFloat {
        250 * yScale
    }

    var collapsedTextTop: CGFloat {
        max(screenHeight - bottomInset - textContentHeight, screenHeight - maxTitleDistanceFromBottom)
    }

    var isCollapsedTextOverflowing: Bool {
        textContentHeight > maxTitleDistanceFromBottom - bottomInset
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

private struct DetailTextPanel: View {
    let diary: VideoDiary
    let isExpanded: Bool
    let screenWidth: CGFloat
    let screenHeight: CGFloat
    let xScale: CGFloat
    let yScale: CGFloat
    let backgroundColor: Color

    private var textLeft: CGFloat {
        23 * xScale
    }

    private var textWidth: CGFloat {
        min(384 * xScale, screenWidth - textLeft * 2)
    }

    private var expandedTopPadding: CGFloat {
        140 * yScale
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isExpanded {
                backgroundColor
                    .opacity(0.96)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            if isExpanded {
                ScrollView(.vertical, showsIndicators: false) {
                    textContent
                        .padding(.top, expandedTopPadding)
                        .padding(.bottom, 120 * yScale)
                }
            } else {
                textContent
            }
        }
        .frame(width: screenWidth, height: screenHeight, alignment: .topLeading)
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
            .padding(.top, 14)
        }
        .frame(width: textWidth, alignment: .topLeading)
        .padding(.leading, textLeft)
    }
}

private struct DetailBottomTextFadeOverlay: View {
    let backgroundColor: Color
    let width: CGFloat
    let height: CGFloat

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
                    .init(color: backgroundColor.opacity(0.08), location: 0.50),
                    .init(color: backgroundColor.opacity(0.28), location: 0.74),
                    .init(color: backgroundColor.opacity(0.70), location: 0.92),
                    .init(color: backgroundColor.opacity(0.86), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
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
        (52 * yScale) + buttonSize / 2
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
