import CoreImage
import SwiftUI
import UIKit

struct DiaryDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let onDelete: (_ diary: VideoDiary) async throws -> Void
    let onSaveEdit: (_ diary: VideoDiary, _ title: String, _ body: String) async throws -> VideoDiary

    @State private var currentDiary: VideoDiary
    @State private var panelProgress: CGFloat = 0
    @State private var panelDragStartProgress: CGFloat?
    @State private var portraitPullDownProgress: CGFloat = 0
    @State private var portraitPullDownDragStartProgress: CGFloat?
    @State private var portraitTopEdgeBlendHold: CGFloat = 0
    @State private var portraitTopEdgeReleaseID = 0
    @State private var isPortraitPullDownGestureActive = false
    @State private var panelScrollResetID = 0
    @State private var playbackProgress: Double = 0
    @State private var pendingSeekProgress: Double?
    @State private var pendingSeekRequestID = 0
    @State private var isScrubbingPlayback = false
    @State private var isDeleteConfirmationPresented = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var isEditing = false
    @State private var isShareMenuMounted = false
    @State private var isShareMenuExpanded = false
    @State private var isShareMenuContentVisible = false
    @State private var shareButtonFrame: CGRect?
    @State private var sharePayload: VideoDiarySharePayload?
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
            let effectivePullDownProgress = currentDiary.isLandscapeVideo ? 0 : portraitPullDownProgress
            let portraitCenteredVideoYOffset = currentDiary.isLandscapeVideo ? 0 : max(0, (screenHeight - detailVideoHeight) / 2)
            let detailVideoPullDownMotionProgress = smoothStep(normalizedProgress(effectivePullDownProgress, from: 0.07, to: 1))
            let detailVideoPullDownYOffset = portraitCenteredVideoYOffset * detailVideoPullDownMotionProgress
            let detailVideoMotionYOffset = -(textLayout.revealDistance * panelProgress / 3) + detailVideoPullDownYOffset
            let detailVideoBlurRadius = 32 * yScale * smoothStep(panelProgress)
            let detailVideoEdgeBlendProgress = currentDiary.isLandscapeVideo ? 0 : smoothStep(effectivePullDownProgress)
            let detailVideoTopEdgeBlendProgress = currentDiary.isLandscapeVideo ? 0 : max(
                isPortraitPullDownGestureActive ? topEdgePreparationProgress(effectivePullDownProgress) : 0,
                portraitTopEdgeBlendHold
            )
            let isDetailVideoPlaying = panelProgress < 0.98 && !isScrubbingPlayback
            let seekRequest = pendingSeekProgress.map {
                VideoPlaybackSeekRequest(id: pendingSeekRequestID, progress: $0)
            }

            ZStack(alignment: .topLeading) {
                BlendedVideoSurface(
                    url: currentDiary.videoURL,
                    aspectRatio: currentDiary.displayAspectRatio,
                    fallbackTint: currentDiary.fallbackTint,
                    isPlaying: isDetailVideoPlaying,
                    isMuted: false,
                    width: screenWidth,
                    height: screenHeight,
                    videoYOffset: detailVideoYOffset,
                    videoMotionYOffset: detailVideoMotionYOffset,
                    videoBlurRadius: detailVideoBlurRadius,
                    edgeBlendProgress: detailVideoEdgeBlendProgress,
                    topEdgeBlendProgress: detailVideoTopEdgeBlendProgress,
                    layout: videoSurfaceLayout,
                    seekRequest: seekRequest,
                    onPlaybackProgressChange: { progress in
                        guard !isScrubbingPlayback else { return }
                        playbackProgress = progress
                    },
                    onBottomColorChange: { color in
                        sampledBottomColor = color
                    }
                )
                .ignoresSafeArea()

                BottomBlurPanelBackground(
                    progress: panelProgress,
                    pullDownProgress: effectivePullDownProgress,
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
                    pullDownProgress: effectivePullDownProgress,
                    layout: textLayout,
                    screenWidth: screenWidth,
                    screenHeight: screenHeight,
                    xScale: xScale,
                    yScale: yScale,
                    scrollResetID: panelScrollResetID,
                    playbackProgress: $playbackProgress,
                    pendingSeekProgress: $pendingSeekProgress,
                    pendingSeekRequestID: $pendingSeekRequestID,
                    isScrubbingPlayback: $isScrubbingPlayback
                )
                .contentShape(Rectangle())
                .simultaneousGesture(
                    textPanelDragGesture(
                        revealDistance: textLayout.revealDistance,
                        pullDownDistance: textLayout.pullDownDistance,
                        screenHeight: screenHeight
                    )
                )
                .zIndex(1)

                DetailTopControls(
                    progress: panelProgress,
                    screenWidth: screenWidth,
                    xScale: xScale,
                    yScale: yScale,
                    isDeleting: isDeleting,
                    isShareButtonHidden: isShareMenuMounted,
                    onBack: {
                        dismiss()
                    },
                    onDelete: {
                        isDeleteConfirmationPresented = true
                    },
                    onShare: {
                        showShareMenu()
                    },
                    onEdit: {
                        isEditing = true
                    }
                )
                .zIndex(2)

                if isShareMenuMounted {
                    DetailShareMenuOverlay(
                        isExpanded: isShareMenuExpanded,
                        contentOpacity: isShareMenuContentVisible ? 1 : 0,
                        collapsedFrame: shareButtonFrame,
                        fallbackCollapsedFrame: fallbackShareButtonFrame(
                            screenWidth: screenWidth,
                            xScale: xScale,
                            yScale: yScale
                        ),
                        expandedFrame: shareMenuExpandedFrame(
                            screenWidth: screenWidth,
                            xScale: xScale,
                            yScale: yScale
                        ),
                        xScale: xScale,
                        yScale: yScale,
                        canShareVideo: currentDiary.videoURL != nil,
                        onDismiss: {
                            closeShareMenu()
                        },
                        onShareVideo: {
                            closeShareMenu()
                            shareCurrentDiaryVideo()
                        },
                        onShareNote: {
                            closeShareMenu()
                            shareCurrentDiaryNote()
                        }
                    )
                    .frame(width: screenWidth, height: screenHeight, alignment: .topLeading)
                    .zIndex(3)
                }

                if let deleteError {
                    Text(deleteError)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.72), in: Capsule())
                        .position(x: screenWidth / 2, y: screenHeight - 60)
                        .zIndex(4)
                }
            }
            .frame(width: screenWidth, height: screenHeight)
            .onPreferenceChange(DetailShareButtonFramePreferenceKey.self) { frame in
                shareButtonFrame = frame
            }
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
        .sheet(item: $sharePayload) { payload in
            VideoDiaryShareSheet(activityItems: payload.activityItems)
        }
    }

    private func textPanelDragGesture(
        revealDistance: CGFloat,
        pullDownDistance: CGFloat,
        screenHeight: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard !isScrubbingPlayback else {
                    return
                }

                guard shouldTrackPanelDrag(value, screenHeight: screenHeight) else {
                    return
                }

                let startPanelProgress = panelDragStartProgress ?? panelProgress
                let startPullDownProgress = portraitPullDownDragStartProgress ?? portraitPullDownProgress
                panelDragStartProgress = startPanelProgress
                portraitPullDownDragStartProgress = startPullDownProgress

                let updatedProgress = detailDragProgress(
                    translationHeight: value.translation.height,
                    startPanelProgress: startPanelProgress,
                    startPullDownProgress: startPullDownProgress,
                    revealDistance: revealDistance,
                    pullDownDistance: pullDownDistance
                )
                panelProgress = updatedProgress.panel
                portraitPullDownProgress = updatedProgress.pullDown
                isPortraitPullDownGestureActive = isTrackingPortraitPullDownGesture(
                    translationHeight: value.translation.height,
                    startPanelProgress: startPanelProgress,
                    startPullDownProgress: startPullDownProgress,
                    updatedPullDownProgress: updatedProgress.pullDown
                )
                updatePortraitTopEdgeHold(for: updatedProgress.pullDown)
            }
            .onEnded { value in
                defer {
                    panelDragStartProgress = nil
                    portraitPullDownDragStartProgress = nil
                }
                guard let startPanelProgress = panelDragStartProgress,
                      let startPullDownProgress = portraitPullDownDragStartProgress else {
                    return
                }

                let predictedProgress = detailDragProgress(
                    translationHeight: value.predictedEndTranslation.height,
                    startPanelProgress: startPanelProgress,
                    startPullDownProgress: startPullDownProgress,
                    revealDistance: revealDistance,
                    pullDownDistance: pullDownDistance
                )
                let targetPanelProgress: CGFloat = predictedProgress.panel >= 0.48 ? 1 : 0
                let targetPullDownProgress: CGFloat = targetPanelProgress > 0
                    ? 0
                    : (predictedProgress.pullDown >= 0.48 ? 1 : 0)
                if targetPanelProgress == 0 {
                    panelScrollResetID += 1
                }
                withAnimation(.interactiveSpring(response: 0.50, dampingFraction: 0.86, blendDuration: 0.12)) {
                    panelProgress = targetPanelProgress
                    portraitPullDownProgress = targetPullDownProgress
                }
                isPortraitPullDownGestureActive = false
                updatePortraitTopEdgeHold(for: targetPullDownProgress)
                schedulePortraitTopEdgeReleaseIfNeeded(
                    targetPanelProgress: targetPanelProgress,
                    targetPullDownProgress: targetPullDownProgress
                )
            }
    }

    private func shouldTrackPanelDrag(_ value: DragGesture.Value, screenHeight: CGFloat) -> Bool {
        if panelProgress < 0.98 {
            return true
        }
        if value.translation.height < 0 {
            return true
        }
        return value.startLocation.y < screenHeight * 0.68
    }

    private func isTrackingPortraitPullDownGesture(
        translationHeight: CGFloat,
        startPanelProgress: CGFloat,
        startPullDownProgress: CGFloat,
        updatedPullDownProgress: CGFloat
    ) -> Bool {
        guard !currentDiary.isLandscapeVideo, startPanelProgress <= 0.001 else {
            return false
        }
        return translationHeight > 0
            || startPullDownProgress > 0.001
            || updatedPullDownProgress > 0.001
    }

    private func detailDragProgress(
        translationHeight: CGFloat,
        startPanelProgress: CGFloat,
        startPullDownProgress: CGFloat,
        revealDistance: CGFloat,
        pullDownDistance: CGFloat
    ) -> (panel: CGFloat, pullDown: CGFloat) {
        guard !currentDiary.isLandscapeVideo else {
            return (
                clampedProgress(startPanelProgress - translationHeight / revealDistance),
                0
            )
        }

        guard startPanelProgress <= 0.001 else {
            return (
                clampedProgress(startPanelProgress - translationHeight / revealDistance),
                0
            )
        }

        if startPullDownProgress > 0.001 {
            let rawPullDownProgress = startPullDownProgress + translationHeight / pullDownDistance
            return (0, clampedProgress(rawPullDownProgress))
        }

        if translationHeight > 0 {
            return (
                0,
                clampedProgress(translationHeight / pullDownDistance)
            )
        }

        return (
            clampedProgress(-translationHeight / revealDistance),
            0
        )
    }

    private func clampedProgress(_ progress: CGFloat) -> CGFloat {
        min(max(progress, 0), 1)
    }

    private func smoothStep(_ progress: CGFloat) -> CGFloat {
        let normalized = clampedProgress(progress)
        return normalized * normalized * (3 - 2 * normalized)
    }

    private func normalizedProgress(_ progress: CGFloat, from start: CGFloat, to end: CGFloat) -> CGFloat {
        guard end > start else {
            return progress >= end ? 1 : 0
        }
        return clampedProgress((progress - start) / (end - start))
    }

    private func topEdgePreparationProgress(_ progress: CGFloat) -> CGFloat {
        guard progress > 0 else {
            return 0
        }
        return progress < 0.008 ? smoothStep(progress / 0.008) : 1
    }

    private func updatePortraitTopEdgeHold(for pullDownProgress: CGFloat) {
        guard !currentDiary.isLandscapeVideo else {
            portraitTopEdgeBlendHold = 0
            portraitTopEdgeReleaseID += 1
            return
        }

        portraitTopEdgeReleaseID += 1
        if pullDownProgress > 0.008 {
            portraitTopEdgeBlendHold = 1
        }
    }

    private func schedulePortraitTopEdgeReleaseIfNeeded(
        targetPanelProgress: CGFloat,
        targetPullDownProgress: CGFloat
    ) {
        guard !currentDiary.isLandscapeVideo else {
            return
        }

        portraitTopEdgeReleaseID += 1
        let releaseID = portraitTopEdgeReleaseID

        if targetPullDownProgress > 0.001 {
            portraitTopEdgeBlendHold = 1
            return
        }

        guard targetPanelProgress <= 0.001, portraitTopEdgeBlendHold > 0 else {
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            while portraitPullDownProgress > 0.14 {
                guard releaseID == portraitTopEdgeReleaseID,
                      panelProgress <= 0.001 else {
                    return
                }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }

            guard releaseID == portraitTopEdgeReleaseID,
                  panelProgress <= 0.001 else {
                return
            }

            withAnimation(.easeOut(duration: 0.14)) {
                portraitTopEdgeBlendHold = 0
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

    @MainActor
    private func showShareMenu() {
        guard !isShareMenuExpanded else {
            closeShareMenu()
            return
        }

        isShareMenuMounted = true
        isShareMenuContentVisible = false
        isShareMenuExpanded = false

        Task { @MainActor in
            await Task.yield()
            withAnimation(.snappy(duration: 0.32)) {
                isShareMenuExpanded = true
            }

            try? await Task.sleep(nanoseconds: 180_000_000)
            guard isShareMenuMounted && isShareMenuExpanded else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                isShareMenuContentVisible = true
            }
        }
    }

    @MainActor
    private func closeShareMenu() {
        guard isShareMenuMounted else { return }

        withAnimation(.easeOut(duration: 0.10)) {
            isShareMenuContentVisible = false
        }
        withAnimation(.snappy(duration: 0.24)) {
            isShareMenuExpanded = false
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !isShareMenuExpanded else { return }
            isShareMenuMounted = false
        }
    }

    private func fallbackShareButtonFrame(screenWidth: CGFloat, xScale: CGFloat, yScale: CGFloat) -> CGRect {
        let buttonSize = 44 * xScale
        let buttonGap = 10 * xScale
        let editWidth = 68 * xScale
        let centerY = (52 * yScale) + buttonSize / 2 + 16 * yScale
        let smoothProgress = smoothStep(panelProgress)
        let morphingActionWidth = buttonSize + (editWidth - buttonSize) * smoothProgress
        let morphingActionRightEdge = screenWidth - 20 * xScale
        let shareButtonCenterX = morphingActionRightEdge - morphingActionWidth - buttonGap - buttonSize / 2
        return CGRect(
            x: shareButtonCenterX - buttonSize / 2,
            y: centerY - buttonSize / 2,
            width: buttonSize,
            height: buttonSize
        )
    }

    private func shareMenuExpandedFrame(screenWidth: CGFloat, xScale: CGFloat, yScale: CGFloat) -> CGRect {
        let width = min(188 * xScale, screenWidth - 40 * xScale)
        let rowHeight = 50 * xScale
        let collapsedFrame = shareButtonFrame ?? fallbackShareButtonFrame(
            screenWidth: screenWidth,
            xScale: xScale,
            yScale: yScale
        )
        return CGRect(
            x: collapsedFrame.maxX - width,
            y: collapsedFrame.minY,
            width: width,
            height: rowHeight * 2
        )
    }

    @MainActor
    private func shareCurrentDiaryVideo() {
        let diary = currentDiary
        guard let videoURL = diary.videoURL else {
            return
        }

        sharePayload = VideoDiarySharePayload(activityItems: [
            VideoDiaryVideoActivityItemSource(url: videoURL)
        ])
    }

    @MainActor
    private func shareCurrentDiaryNote() {
        let diary = currentDiary
        Task { @MainActor in
            let textImage = await VideoDiaryShareImageRenderer.makeImage(for: diary)
            sharePayload = VideoDiarySharePayload(activityItems: [
                VideoDiaryTextImageActivityItemSource(image: textImage)
            ])
        }
    }
}

struct VideoDiarySharePayload: Identifiable {
    let id = UUID()
    let activityItems: [Any]
}

final class VideoDiaryVideoActivityItemSource: NSObject, UIActivityItemSource {
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        "public.movie"
    }
}

final class VideoDiaryTextImageActivityItemSource: NSObject, UIActivityItemSource {
    private let image: UIImage

    init(image: UIImage) {
        self.image = image
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        image
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        image
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        "public.png"
    }
}

struct VideoDiaryShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct DetailShareButtonFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect?

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

private struct DetailShareMenuOverlay: View {
    let isExpanded: Bool
    let contentOpacity: Double
    let collapsedFrame: CGRect?
    let fallbackCollapsedFrame: CGRect
    let expandedFrame: CGRect
    let xScale: CGFloat
    let yScale: CGFloat
    let canShareVideo: Bool
    let onDismiss: () -> Void
    let onShareVideo: () -> Void
    let onShareNote: () -> Void

    private var currentFrame: CGRect {
        isExpanded ? expandedFrame : (collapsedFrame ?? fallbackCollapsedFrame)
    }

    private var shellCornerRadius: CGFloat {
        (collapsedFrame ?? fallbackCollapsedFrame).height / 2
    }

    private var shellShadowRadius: CGFloat {
        isExpanded ? 36 * xScale : 10 * xScale
    }

    private var shellShadowYOffset: CGFloat {
        isExpanded ? 13 * yScale : 1 * xScale
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
                .allowsHitTesting(isExpanded)

            LiquidGlassContainer(spacing: 0) {
                if isExpanded {
                    LiquidGlassRoundedSurface(
                        width: currentFrame.width,
                        height: currentFrame.height,
                        cornerRadius: shellCornerRadius,
                        xScale: xScale,
                        shadowRadius: shellShadowRadius,
                        shadowYOffset: shellShadowYOffset
                    )
                } else {
                    Circle()
                        .fill(.clear)
                        .frame(width: currentFrame.width, height: currentFrame.height)
                        .vimemberInteractiveGlass(in: Circle())
                }
            }
            .frame(width: currentFrame.width, height: currentFrame.height)
            .clipShape(RoundedRectangle(cornerRadius: shellCornerRadius, style: .continuous))
            .position(x: currentFrame.midX, y: currentFrame.midY)
            .allowsHitTesting(false)

            Image(systemName: "square.and.arrow.up")
                .font(.system(size: max(18, (collapsedFrame ?? fallbackCollapsedFrame).height * 0.42), weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
                .offset(y: -1 * xScale)
                .position(x: collapsedCenter.x, y: collapsedCenter.y)
                .opacity(isExpanded ? 0 : 1)
                .allowsHitTesting(false)

            DetailShareMenuContent(
                xScale: xScale,
                cornerRadius: shellCornerRadius,
                canShareVideo: canShareVideo,
                onShareVideo: onShareVideo,
                onShareNote: onShareNote
            )
            .frame(width: expandedFrame.width, height: expandedFrame.height, alignment: .topLeading)
            .position(x: expandedFrame.midX, y: expandedFrame.midY)
            .opacity(contentOpacity)
            .allowsHitTesting(isExpanded && contentOpacity > 0.5)
        }
    }

    private var collapsedCenter: CGPoint {
        let frame = collapsedFrame ?? fallbackCollapsedFrame
        return CGPoint(x: frame.midX, y: frame.midY)
    }
}

private struct DetailShareMenuContent: View {
    let xScale: CGFloat
    let cornerRadius: CGFloat
    let canShareVideo: Bool
    let onShareVideo: () -> Void
    let onShareNote: () -> Void

    private var rowHeight: CGFloat {
        50 * xScale
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailShareMenuRow(
                title: "Share Video",
                systemName: "film",
                rowHeight: rowHeight,
                isEnabled: canShareVideo,
                action: onShareVideo
            )

            Rectangle()
                .fill(Color.black.opacity(0.10))
                .frame(height: 1 / UIScreen.main.scale)
                .padding(.leading, 48 * xScale)

            DetailShareMenuRow(
                title: "Share Note",
                systemName: "note.text",
                rowHeight: rowHeight,
                isEnabled: true,
                action: onShareNote
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct DetailShareMenuRow: View {
    let title: LocalizedStringKey
    let systemName: String
    let rowHeight: CGFloat
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 22)

                Text(title)
                    .font(.system(size: 16, weight: .regular))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.black.opacity(isEnabled ? 0.92 : 0.38))
            .padding(.horizontal, 16)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
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

    var playbackDividerBottomOffsetFromTextTop: CGFloat {
        36
            + 2
            + 22
            + 4
            + max(0.5, 0.5 * xScale)
    }

    var pullDownHeaderTextTop: CGFloat {
        screenHeight - 46 * yScale - playbackDividerBottomOffsetFromTextTop
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

    var pullDownTextTop: CGFloat {
        screenHeight - bottomInset - playbackDividerBottomOffsetFromTextTop
    }

    var pullDownDistance: CGFloat {
        max(pullDownTextTop - collapsedTextTop, 1)
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

@MainActor
enum VideoDiaryShareImageRenderer {
    static func makeImage(for diary: VideoDiary) async -> UIImage {
        let screenSize = UIScreen.main.bounds.size
        let sample: VideoFrameSample?
        if let videoURL = diary.videoURL {
            sample = await VideoColorSampler.shared.sample(for: videoURL, fallback: diary.fallbackTint)
        } else {
            sample = nil
        }

        return renderImage(
            for: diary,
            sampleImage: sample?.image,
            backgroundColor: sample?.bottomColor ?? diary.fallbackTint,
            screenSize: screenSize
        )
    }

    private static func renderImage(
        for diary: VideoDiary,
        sampleImage: UIImage?,
        backgroundColor: Color,
        screenSize: CGSize
    ) -> UIImage {
        let layout = DetailShareImageLayout(diary: diary, screenSize: screenSize)
        let backgroundUIColor = UIColor(backgroundColor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true
        let imageScale = format.scale

        return UIGraphicsImageRenderer(size: layout.imageSize, format: format).image { context in
            let rect = CGRect(origin: .zero, size: layout.imageSize)
            backgroundUIColor.setFill()
            context.fill(rect)

            let cgContext = context.cgContext
            if let sampleImage {
                if layout.isLandscape {
                    drawLandscapeVideoBlend(
                        sampleImage,
                        backgroundColor: backgroundUIColor,
                        in: layout,
                        scale: imageScale
                    )
                } else {
                    drawFadedVideoCover(sampleImage, in: layout, cgContext: cgContext)
                }
            } else {
                backgroundUIColor.setFill()
                context.fill(layout.videoRect)
            }

            drawColorBlend(
                backgroundUIColor,
                in: layout,
                cgContext: cgContext
            )

            layout.titleAttributedText.draw(
                with: layout.titleRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
                context: nil
            )
            layout.dateAttributedText.draw(
                with: layout.dateRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
                context: nil
            )

            UIColor.white.withAlphaComponent(0.68).setFill()
            context.fill(layout.dividerRect)

            layout.bodyAttributedText.draw(
                with: layout.bodyRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        }
    }

    private static func drawAspectFill(_ image: UIImage, in rect: CGRect) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return
        }

        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawRect = CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: drawRect)
    }

    private static func drawFadedVideoCover(
        _ image: UIImage,
        in layout: DetailShareImageLayout,
        cgContext: CGContext
    ) {
        let steps = 96
        for index in 0..<steps {
            let start = CGFloat(index) / CGFloat(steps)
            let end = CGFloat(index + 1) / CGFloat(steps)
            let midpoint = (start + end) / 2
            let alpha = videoMaskAlpha(at: midpoint, isLandscape: layout.isLandscape)
            let strip = CGRect(
                x: layout.videoRect.minX,
                y: layout.videoRect.minY + layout.videoRect.height * start,
                width: layout.videoRect.width,
                height: layout.videoRect.height * (end - start) + 1
            )

            cgContext.saveGState()
            cgContext.clip(to: strip)
            cgContext.setAlpha(alpha)
            drawAspectFill(image, in: layout.videoRect)
            cgContext.restoreGState()
        }
    }

    private static func drawLandscapeVideoBlend(
        _ image: UIImage,
        backgroundColor: UIColor,
        in layout: DetailShareImageLayout,
        scale: CGFloat
    ) {
        if let blurredImage = blurredLandscapeBridgeImage(
            image,
            backgroundColor: backgroundColor,
            in: layout,
            scale: scale
        ) {
            drawAlphaMaskedLayer(
                in: layout.landscapeBridgeRect,
                scale: scale,
                maskStops: [
                    (0, 0),
                    (0.12, 0.30),
                    (0.34, 0.92),
                    (0.54, 0.98),
                    (0.78, 0.68),
                    (1, 0.26)
                ]
            ) {
                blurredImage.draw(
                    in: CGRect(
                        x: -layout.landscapeBridgeRect.minX,
                        y: -layout.landscapeBridgeRect.minY,
                        width: layout.baseCardSize.width,
                        height: layout.baseCardSize.height
                    )
                )
            }
        }

        drawAlphaMaskedLayer(
            in: layout.videoRect,
            scale: scale,
            maskStops: [
                (0, 1),
                (0.70, 1),
                (0.82, 0.70),
                (0.92, 0.25),
                (0.965, 0)
            ]
        ) {
            drawAspectFill(
                image,
                in: CGRect(origin: .zero, size: layout.videoRect.size)
            )
        }
    }

    private static func blurredLandscapeBridgeImage(
        _ image: UIImage,
        backgroundColor: UIColor,
        in layout: DetailShareImageLayout,
        scale: CGFloat
    ) -> UIImage? {
        guard layout.isLandscape else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let baseImage = UIGraphicsImageRenderer(size: layout.baseCardSize, format: format).image { context in
            backgroundColor.setFill()
            context.fill(layout.baseCardRect)
            drawAspectFill(image, in: layout.videoRect)
        }

        guard let inputImage = CIImage(image: baseImage) else {
            return nil
        }

        let blurredImage = inputImage
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 24 * layout.xScale * scale])
        let ciContext = CIContext(options: nil)
        guard let outputImage = ciContext.createCGImage(blurredImage, from: inputImage.extent) else {
            return nil
        }

        return UIImage(cgImage: outputImage, scale: scale, orientation: .up)
    }

    private static func drawAlphaMaskedLayer(
        in rect: CGRect,
        scale: CGFloat,
        maskStops: [(location: CGFloat, alpha: CGFloat)],
        drawContent: @escaping () -> Void
    ) {
        guard rect.width > 0, rect.height > 0 else {
            return
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let maskedImage = UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
            drawContent()

            context.cgContext.saveGState()
            context.cgContext.setBlendMode(.destinationIn)
            drawAlphaGradient(
                in: CGRect(origin: .zero, size: rect.size),
                cgContext: context.cgContext,
                stops: maskStops
            )
            context.cgContext.restoreGState()
        }

        maskedImage.draw(in: rect)
    }

    private static func drawColorBlend(
        _ color: UIColor,
        in layout: DetailShareImageLayout,
        cgContext: CGContext
    ) {
        drawGradient(
            in: layout.blendRect,
            cgContext: cgContext,
            colors: [
                color.withAlphaComponent(0),
                color.withAlphaComponent(layout.isLandscape ? 0.05 : 0.16),
                color.withAlphaComponent(layout.isLandscape ? 0.20 : 0.62),
                color.withAlphaComponent(layout.isLandscape ? 0.60 : 0.98)
            ],
            locations: layout.isLandscape ? [0, 0.22, 0.54, 1] : [0, 0.18, 0.64, 1]
        )

        drawGradient(
            in: layout.blendRect,
            cgContext: cgContext,
            colors: [
                UIColor.white.withAlphaComponent(0),
                UIColor.white.withAlphaComponent(layout.isLandscape ? 0.05 : 0.04),
                UIColor.white.withAlphaComponent(0)
            ],
            locations: [0, 0.42, 0.72]
        )
    }

    private static func drawGradient(
        in rect: CGRect,
        cgContext: CGContext,
        colors: [UIColor],
        locations: [CGFloat]
    ) {
        guard rect.height > 0,
              let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors.map(\.cgColor) as CFArray,
                locations: locations
              )
        else {
            return
        }

        cgContext.saveGState()
        cgContext.clip(to: rect)
        cgContext.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.minY),
            end: CGPoint(x: rect.midX, y: rect.maxY),
            options: []
        )
        cgContext.restoreGState()
    }

    private static func drawAlphaGradient(
        in rect: CGRect,
        cgContext: CGContext,
        stops: [(location: CGFloat, alpha: CGFloat)]
    ) {
        drawGradient(
            in: rect,
            cgContext: cgContext,
            colors: stops.map { UIColor.white.withAlphaComponent($0.alpha) },
            locations: stops.map(\.location)
        )
    }

    private static func videoMaskAlpha(at location: CGFloat, isLandscape: Bool) -> CGFloat {
        if isLandscape {
            return interpolatedAlpha(
                at: location,
                stops: [
                    (0, 1),
                    (0.78, 1),
                    (0.90, 0.50),
                    (0.98, 0.12),
                    (1, 0)
                ]
            )
        }

        return interpolatedAlpha(
            at: location,
            stops: [
                (0, 1),
                (0.62, 1),
                (0.82, 0.78),
                (1, 0.34)
            ]
        )
    }

    private static func interpolatedAlpha(
        at location: CGFloat,
        stops: [(location: CGFloat, alpha: CGFloat)]
    ) -> CGFloat {
        guard let first = stops.first else {
            return 1
        }

        if location <= first.location {
            return first.alpha
        }

        for index in 1..<stops.count {
            let previous = stops[index - 1]
            let next = stops[index]
            guard location <= next.location else {
                continue
            }

            let span = max(next.location - previous.location, 0.0001)
            let progress = (location - previous.location) / span
            return previous.alpha + (next.alpha - previous.alpha) * progress
        }

        return stops.last?.alpha ?? 1
    }
}

private struct DetailShareImageLayout {
    let diary: VideoDiary
    let screenSize: CGSize

    var screenWidth: CGFloat {
        screenSize.width
    }

    var xScale: CGFloat {
        screenSize.width / 420
    }

    var yScale: CGFloat {
        screenSize.height / 912
    }

    var imageSize: CGSize {
        CGSize(width: screenWidth, height: ceil(max(baseCardHeight, bodyRect.maxY + bottomPadding)))
    }

    var isLandscape: Bool {
        diary.isLandscapeVideo
    }

    var videoHeight: CGFloat {
        screenWidth / max(diary.displayAspectRatio, 0.1)
    }

    var colorBlockOverflow: CGFloat {
        isLandscape ? screenWidth * (86 / 420) : 0
    }

    var baseCardHeight: CGFloat {
        videoHeight + colorBlockOverflow
    }

    var baseCardSize: CGSize {
        CGSize(width: screenWidth, height: baseCardHeight)
    }

    var baseCardRect: CGRect {
        CGRect(origin: .zero, size: baseCardSize)
    }

    var videoRect: CGRect {
        CGRect(x: 0, y: 0, width: screenWidth, height: videoHeight)
    }

    var blendRect: CGRect {
        CGRect(
            x: 0,
            y: blendTop,
            width: screenWidth,
            height: max(1, baseCardHeight - blendTop)
        )
    }

    var landscapeBridgeRect: CGRect {
        guard isLandscape else {
            return .zero
        }

        return CGRect(
            x: 0,
            y: blendTop,
            width: screenWidth,
            height: max(1, baseCardHeight - blendTop)
        )
    }

    var titleRect: CGRect {
        CGRect(
            x: textLeft,
            y: baseCardHeight - 125 * xScale,
            width: textWidth,
            height: max(22 * xScale, 24 * xScale * 1.2)
        )
    }

    var dateRect: CGRect {
        CGRect(
            x: textLeft,
            y: baseCardHeight - 91.5 * xScale,
            width: textWidth,
            height: 22 * xScale
        )
    }

    var dividerRect: CGRect {
        CGRect(
            x: textLeft,
            y: baseCardHeight - 66 * xScale,
            width: min(374 * xScale, textWidth),
            height: max(0.5, 0.5 * xScale)
        )
    }

    var bodyRect: CGRect {
        CGRect(
            x: textLeft,
            y: baseCardHeight - 60.5 * xScale,
            width: textWidth,
            height: bodyHeight
        )
    }

    var titleAttributedText: NSAttributedString {
        DetailShareImageTextStyle.singleLineAttributedText(
            diary.title,
            fontName: "PingFangSC-Semibold",
            fontSize: 24 * xScale,
            lineHeight: 29 * xScale,
            letterSpacing: 0.24 * xScale
        )
    }

    var dateAttributedText: NSAttributedString {
        DetailShareImageTextStyle.singleLineAttributedText(
            diary.dateText,
            fontName: "PingFangSC-Medium",
            fontSize: 14 * xScale,
            lineHeight: 22 * xScale,
            letterSpacing: 0.14 * xScale
        )
    }

    var bodyAttributedText: NSAttributedString {
        DetailShareImageTextStyle.bodyAttributedText(
            diary.body,
            fontSize: 16 * xScale,
            lineHeight: 20 * xScale,
            letterSpacing: 0.16 * xScale,
            paragraphSpacing: 0
        )
    }

    private var textLeft: CGFloat {
        23 * xScale
    }

    private var textWidth: CGFloat {
        376 * xScale
    }

    private var bottomPadding: CGFloat {
        23 * xScale
    }

    private var bodyHeight: CGFloat {
        DetailShareImageTextStyle.height(for: bodyAttributedText, width: textWidth)
    }

    private var blendTop: CGFloat {
        if isLandscape {
            return max(0, videoHeight - screenWidth * (96 / 420))
        }

        let textTopOffset = videoHeight - screenWidth * (114 / 420)
        return max(0, textTopOffset - screenWidth * (220 / 420))
    }
}

private enum DetailShareImageTextStyle {
    static func singleLineAttributedText(
        _ text: String,
        fontName: String,
        fontSize: CGFloat,
        lineHeight: CGFloat,
        letterSpacing: CGFloat
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
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

    static func bodyAttributedText(
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

    static func height(for attributedText: NSAttributedString, width: CGFloat) -> CGFloat {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.attributedText = attributedText
        return ceil(
            label.sizeThatFits(
                CGSize(width: width, height: .greatestFiniteMagnitude)
            ).height
        )
    }
}

private struct BottomBlurPanelBackground: View {
    let progress: CGFloat
    let pullDownProgress: CGFloat
    let layout: DetailTextLayoutMetrics
    let screenWidth: CGFloat
    let screenHeight: CGFloat
    let yScale: CGFloat
    let backgroundColor: Color

    private var clampedProgress: CGFloat {
        min(max(progress, 0), 1)
    }

    private var clampedPullDownProgress: CGFloat {
        min(max(pullDownProgress, 0), 1)
    }

    private var topFadeBand: CGFloat {
        104 * yScale
    }

    private var panelTop: CGFloat {
        let collapsedTop = layout.collapsedTextTop - topFadeBand
        let pulledTop = layout.pullDownTextTop - topFadeBand
        let restingTop = collapsedTop + (pulledTop - collapsedTop) * clampedPullDownProgress
        return restingTop + (-topFadeBand - restingTop) * clampedProgress
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
    let pullDownProgress: CGFloat
    let layout: DetailTextLayoutMetrics
    let screenWidth: CGFloat
    let screenHeight: CGFloat
    let xScale: CGFloat
    let yScale: CGFloat
    let scrollResetID: Int
    @Binding var playbackProgress: Double
    @Binding var pendingSeekProgress: Double?
    @Binding var pendingSeekRequestID: Int
    @Binding var isScrubbingPlayback: Bool

    private let scrollOriginID = "detail-text-scroll-origin"

    private var clampedProgress: CGFloat {
        min(max(progress, 0), 1)
    }

    private var clampedPullDownProgress: CGFloat {
        min(max(pullDownProgress, 0), 1)
    }

    private var textLeft: CGFloat {
        23 * xScale
    }

    private var textWidth: CGFloat {
        min(384 * xScale, screenWidth - textLeft * 2)
    }

    private var headerTextTop: CGFloat {
        interpolatedTextTop(pullDownTextTop: layout.pullDownHeaderTextTop)
    }

    private var bodyAnchorTextTop: CGFloat {
        interpolatedTextTop(pullDownTextTop: layout.pullDownTextTop)
    }

    private var bodyAnchorOffset: CGFloat {
        bodyAnchorTextTop - headerTextTop
    }

    private var bodyPullDownOvershoot: CGFloat {
        28 * yScale * clampedPullDownProgress
    }

    private func interpolatedTextTop(pullDownTextTop: CGFloat) -> CGFloat {
        let restingTop = layout.collapsedTextTop
            + (pullDownTextTop - layout.collapsedTextTop) * clampedPullDownProgress
        return restingTop + (layout.expandedTextTop - restingTop) * clampedProgress
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: 1)
                        .id(scrollOriginID)

                    Color.clear
                        .frame(height: max(headerTextTop - 1, 0))

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
            .onChange(of: clampedPullDownProgress) { _, _ in
                guard clampedProgress < 0.98 else { return }
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

            DetailPlaybackDivider(
                progress: playbackProgress,
                width: min(374 * xScale, textWidth),
                baseHeight: max(0.5, 0.5 * xScale),
                progressHeight: max(3, 3 * xScale),
                onScrubBegan: {
                    isScrubbingPlayback = true
                },
                onScrubChanged: { progress in
                    playbackProgress = progress
                },
                onScrubEnded: { progress in
                    playbackProgress = progress
                    pendingSeekRequestID += 1
                    pendingSeekProgress = progress
                    isScrubbingPlayback = false
                }
            )

            DetailBodyTextLabel(
                text: diary.body,
                fontSize: 16,
                lineHeight: 22,
                letterSpacing: 0.16,
                paragraphSpacing: 16,
                labelWidth: textWidth
            )
            .offset(y: interpolate(0, -4 * yScale) + bodyAnchorOffset + bodyPullDownOvershoot)
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

private struct DetailPlaybackDivider: View {
    let progress: Double
    let width: CGFloat
    let baseHeight: CGFloat
    let progressHeight: CGFloat
    let onScrubBegan: () -> Void
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: (Double) -> Void

    @State private var scrubProgress: Double?

    private var visibleProgress: Double {
        scrubProgress ?? progress
    }

    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.68))
            .frame(width: width, height: baseHeight)
            .overlay(alignment: .bottomLeading) {
                Rectangle()
                    .fill(.white)
                    .frame(width: width * CGFloat(clamped(visibleProgress)), height: progressHeight)
            }
            .overlay {
                Color.clear
                    .frame(width: width, height: max(32, 32 * progressHeight / 3))
                    .contentShape(Rectangle())
                    .highPriorityGesture(scrubGesture)
            }
            .allowsHitTesting(true)
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if scrubProgress == nil {
                    onScrubBegan()
                }

                let newProgress = progress(for: value.location.x)
                scrubProgress = newProgress
                onScrubChanged(newProgress)
            }
            .onEnded { value in
                let finalProgress = progress(for: value.location.x)
                scrubProgress = nil
                onScrubEnded(finalProgress)
            }
    }

    private func progress(for xLocation: CGFloat) -> Double {
        guard width > 0 else {
            return 0
        }

        return clamped(Double(xLocation / width))
    }

    private func clamped(_ progress: Double) -> Double {
        min(max(progress, 0), 1)
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
    let progress: CGFloat
    let screenWidth: CGFloat
    let xScale: CGFloat
    let yScale: CGFloat
    let isDeleting: Bool
    let isShareButtonHidden: Bool
    let onBack: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void
    let onEdit: () -> Void

    private var buttonSize: CGFloat {
        44 * xScale
    }

    private var buttonGap: CGFloat {
        10 * xScale
    }

    private var editWidth: CGFloat {
        68 * xScale
    }

    private var centerY: CGFloat {
        (52 * yScale) + buttonSize / 2 + 16 * yScale
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LiquidGlassContainer(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    Circle()
                        .fill(.clear)
                        .frame(width: buttonSize, height: buttonSize)
                        .vimemberInteractiveGlass(in: Circle())
                        .position(x: backButtonCenterX, y: centerY)

                    Circle()
                        .fill(.clear)
                        .frame(width: buttonSize, height: buttonSize)
                        .vimemberInteractiveGlass(in: Circle())
                        .position(x: shareButtonCenterX, y: centerY)
                        .opacity(isShareButtonHidden ? 0 : 1)
                        .transaction { transaction in
                            if isShareButtonHidden {
                                transaction.animation = nil
                                transaction.disablesAnimations = true
                            }
                        }

                    Capsule()
                        .fill(.clear)
                        .frame(width: morphingActionWidth, height: buttonSize)
                        .vimemberInteractiveGlass(in: Capsule())
                        .opacity(isMorphingActionGlassEnabled ? 1 : 0.48)
                        .position(x: morphingActionCenterX, y: centerY)
                }
                .frame(width: screenWidth, height: centerY + buttonSize / 2, alignment: .topLeading)
            }
            .allowsHitTesting(false)

            DetailGlassIconButton(
                systemName: "chevron.left",
                size: buttonSize,
                action: onBack
            )
            .position(x: backButtonCenterX, y: centerY)

            DetailGlassIconButton(
                systemName: "square.and.arrow.up",
                size: buttonSize,
                symbolOffsetY: -1 * xScale,
                action: onShare
            )
            .position(x: shareButtonCenterX, y: centerY)
            .opacity(isShareButtonHidden ? 0 : 1)
            .allowsHitTesting(!isShareButtonHidden)
            .accessibilityHidden(isShareButtonHidden)
            .transaction { transaction in
                if isShareButtonHidden {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
            .preference(
                key: DetailShareButtonFramePreferenceKey.self,
                value: CGRect(
                    x: shareButtonCenterX - buttonSize / 2,
                    y: centerY - buttonSize / 2,
                    width: buttonSize,
                    height: buttonSize
                )
            )

            DetailMorphingActionButton(
                progress: progress,
                collapsedSize: buttonSize,
                expandedWidth: editWidth,
                isEnabled: !isDeleting,
                onDelete: onDelete,
                onEdit: onEdit
            )
            .position(x: morphingActionCenterX, y: centerY)
        }
        .frame(width: screenWidth, height: centerY + buttonSize / 2, alignment: .topLeading)
    }

    private var morphingActionCenterX: CGFloat {
        morphingActionRightEdge - morphingActionWidth / 2
    }

    private var backButtonCenterX: CGFloat {
        (20 * xScale) + buttonSize / 2
    }

    private var shareButtonCenterX: CGFloat {
        morphingActionRightEdge - morphingActionWidth - buttonGap - buttonSize / 2
    }

    private var morphingActionWidth: CGFloat {
        let clampedProgress = min(max(progress, 0), 1)
        let smoothProgress = clampedProgress * clampedProgress * (3 - 2 * clampedProgress)
        return buttonSize + (editWidth - buttonSize) * smoothProgress
    }

    private var isMorphingActionGlassEnabled: Bool {
        let clampedProgress = min(max(progress, 0), 1)
        let isDeleteMode = clampedProgress < 0.5
        return isDeleteMode ? !isDeleting : true
    }

    private var morphingActionRightEdge: CGFloat {
        screenWidth - 20 * xScale
    }
}

private struct DetailGlassIconButton: View {
    let systemName: String
    let size: CGFloat
    var isEnabled = true
    var symbolOffsetY: CGFloat = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: max(18, size * 0.42), weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
                .opacity(isEnabled ? 1 : 0.42)
                .offset(y: symbolOffsetY)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct DetailMorphingActionButton: View {
    let progress: CGFloat
    let collapsedSize: CGFloat
    let expandedWidth: CGFloat
    let isEnabled: Bool
    let onDelete: () -> Void
    let onEdit: () -> Void

    private var clampedProgress: CGFloat {
        min(max(progress, 0), 1)
    }

    private var smoothProgress: CGFloat {
        clampedProgress * clampedProgress * (3 - 2 * clampedProgress)
    }

    private var width: CGFloat {
        collapsedSize + (expandedWidth - collapsedSize) * smoothProgress
    }

    private var isDeleteMode: Bool {
        clampedProgress < 0.5
    }

    private var isButtonEnabled: Bool {
        isDeleteMode ? isEnabled : true
    }

    var body: some View {
        Button {
            if isDeleteMode {
                onDelete()
            } else {
                onEdit()
            }
        } label: {
            ZStack {
                Image(systemName: "trash")
                    .font(.system(size: max(18, collapsedSize * 0.42), weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary)
                    .opacity((1 - Double(smoothProgress)) * (isButtonEnabled ? 1 : 0.42))

                Image(systemName: "pencil")
                    .font(.system(size: max(18, collapsedSize * 0.40), weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary)
                    .opacity(Double(smoothProgress) * (isButtonEnabled ? 1 : 0.42))
            }
            .frame(width: width, height: collapsedSize)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isButtonEnabled)
        .accessibilityLabel(isDeleteMode ? "Delete" : "Edit")
    }
}
