import SwiftUI
import SwiftData
import UIKit

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VideoDiaryRecord.createdAt, order: .reverse) private var records: [VideoDiaryRecord]

    @State private var activeDiaryID: VideoDiary.ID?
    @State private var pendingVisibilityTask: Task<Void, Never>?
    @State private var isGalleryMode = false
    @State private var isImportPresented = false
    @State private var selectedDiary: VideoDiary?
    @State private var hiddenSampleIDs: Set<VideoDiary.ID> = []
    @State private var sampleOverrides: [VideoDiary.ID: VideoDiary] = [:]
    @State private var albums: [VideoAlbum] = []
    @State private var selectedAlbumID: VideoAlbum.ID?
    @State private var editingAlbumID: VideoAlbum.ID?
    @State private var isAddAlbumComposerPresented = false
    @State private var isAddAlbumComposerContentVisible = false
    @State private var isAlbumVideoPickerPresented = false
    @State private var draftAlbumName = ""
    @State private var selectedAlbumDiaryIDs: [VideoDiary.ID] = []
    @State private var isAlbumHeaderHidden = false
    @State private var lastHomeScrollOffset: CGFloat?
    @State private var homeScrollAnchorY: CGFloat?
    @State private var addAlbumButtonFrame: CGRect?

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
            let bottomSearchWidth: CGFloat = 306 * xScale
            let bottomAddButtonSize: CGFloat = 58 * xScale
            let bottomControlsGap: CGFloat = 10 * xScale
            let bottomControlsHeight: CGFloat = bottomAddButtonSize
            let bottomControlsRightMargin: CGFloat = 28 * xScale
            let bottomControlsBottomMargin: CGFloat = 28 * yScale
            let screenEdgeFadeHeight: CGFloat = 250 * yScale
            let albumTop: CGFloat = 121 * yScale
            let albumHeaderOffsetY: CGFloat = isAlbumHeaderHidden ? -226 * yScale : 0
            let addAlbumFallbackCenter = CGPoint(
                x: 55 * xScale,
                y: albumHeaderOffsetY + 134 * yScale + 35 * xScale
            )
            let addAlbumShellFrame = CGRect(
                x: 20 * xScale,
                y: albumTop,
                width: 380 * xScale,
                height: 416 * yScale
            )
            let addAlbumContentFrame = CGRect(
                x: 20 * xScale,
                y: albumTop - 8 * yScale,
                width: 380 * xScale,
                height: 426 * yScale
            )
            let videoGridTop: CGFloat = 280 * yScale
            let gridGap: CGFloat = 3 * xScale
            let galleryCardWidth = (screenWidth - gridGap * 2) / 3
            let galleryCardHeight = galleryCardWidth * (184 / 138)
            let selectedAlbum = albums.first { $0.id == selectedAlbumID }
            let selectedFallbackDiary = selectedAlbum == nil ? diaries.first { $0.id == selectedAlbumID } : nil
            let isAlbumFilterActive = selectedAlbum != nil || selectedFallbackDiary != nil
            let visibleDiaries = selectedAlbum.map { album in
                album.diaryIDs.compactMap { diaryID in
                    diaries.first { $0.id == diaryID }
                }
            } ?? selectedFallbackDiary.map { [$0] } ?? diaries
            let viewModeSelection = Binding<ViewModeSelection>(
                get: {
                    isGalleryMode ? .gallery : .timeline
                },
                set: { nextSelection in
                    switch nextSelection {
                    case .timeline:
                        isGalleryMode = false
                        isAlbumHeaderHidden = false
                        resetHomeScrollTracking()
                        activeDiaryID = visibleDiaries.first?.id
                    case .gallery:
                        isGalleryMode = true
                        isAlbumHeaderHidden = false
                        resetHomeScrollTracking()
                        activeDiaryID = nil
                    }
                }
            )
            let galleryTitle = selectedAlbum?.name ?? selectedFallbackDiary.map { fallbackAlbumTitle(for: $0) } ?? "All Videos"
            let galleryItemCount = visibleDiaries.count + (isAlbumFilterActive ? 1 : 0)
            let galleryRowCount = max(1, Int(ceil(Double(galleryItemCount) / 3.0)))
            let galleryContentHeight = max(
                screenHeight + 1,
                videoGridTop
                    + CGFloat(galleryRowCount) * galleryCardHeight
                    + CGFloat(max(0, galleryRowCount - 1)) * gridGap
                    + bottomControlsHeight
                    + bottomControlsBottomMargin
                    + 24 * yScale
            )
            let timelineCardSpacing: CGFloat = 2
            let timelineHeights = visibleDiaries.map { diary -> CGFloat in
                let videoHeight = cardWidth / max(diary.displayAspectRatio, 0.1)
                let colorBlockOverflow = diary.isLandscapeVideo ? cardWidth * (86 / 420) : 0
                return videoHeight + colorBlockOverflow
            }
            let timelineContentHeight = max(
                screenHeight + 1,
                videoGridTop
                    + timelineHeights.reduce(0, +)
                    + CGFloat(max(0, visibleDiaries.count - 1)) * timelineCardSpacing
                    + bottomControlsHeight
                    + bottomControlsBottomMargin
                    + 24 * yScale
            )
            let scrollContentHeight = isGalleryMode ? galleryContentHeight : timelineContentHeight

            ZStack(alignment: .topTrailing) {
                Color.white.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: HomeScrollOffsetPreferenceKey.self,
                                value: proxy.frame(in: .global).minY
                            )
                        }
                        .frame(width: screenWidth, height: 1)

                        ZStack(alignment: .topLeading) {
                            GallerySectionTitle(galleryTitle, xScale: xScale)
                                .offset(x: 20 * xScale, y: 239 * yScale)

                            if isGalleryMode {
                                LazyVGrid(
                                    columns: [
                                        GridItem(.fixed(galleryCardWidth), spacing: gridGap),
                                        GridItem(.fixed(galleryCardWidth), spacing: gridGap),
                                        GridItem(.fixed(galleryCardWidth), spacing: 0)
                                    ],
                                    alignment: .leading,
                                    spacing: gridGap
                                ) {
                                    if isAlbumFilterActive {
                                        GalleryAlbumAddVideoCard(
                                            width: galleryCardWidth,
                                            height: galleryCardHeight,
                                            column: 0,
                                            onTap: {
                                                if let selectedAlbum {
                                                    showAlbumVideoPicker(for: selectedAlbum)
                                                } else if let selectedFallbackDiary {
                                                    showAlbumVideoPicker(forFallbackDiary: selectedFallbackDiary)
                                                }
                                            }
                                        )
                                    }

                                    ForEach(Array(visibleDiaries.enumerated()), id: \.element.id) { index, diary in
                                        let cardIndex = isAlbumFilterActive ? index + 1 : index
                                        GalleryVideoCard(
                                            diary: diary,
                                            width: galleryCardWidth,
                                            height: galleryCardHeight,
                                            column: cardIndex % 3,
                                            onTap: {
                                                selectedDiary = diary
                                            }
                                        )
                                    }
                                }
                                .frame(width: screenWidth, alignment: .leading)
                                .offset(y: videoGridTop)
                            } else {
                                LazyVStack(spacing: timelineCardSpacing) {
                                    ForEach(visibleDiaries) { diary in
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
                                .frame(width: cardWidth)
                                .offset(x: phoneFrameLeft, y: videoGridTop)
                            }
                        }
                        .frame(width: screenWidth, height: scrollContentHeight, alignment: .topLeading)
                    }
                }
                .coordinateSpace(name: "home-scroll")
                .onPreferenceChange(CardVisibilityPreferenceKey.self) { frames in
                    guard !isGalleryMode else { return }
                    scheduleActiveCardUpdate(frames: frames, viewport: viewport)
                }
                .onPreferenceChange(HomeScrollOffsetPreferenceKey.self) { scrollOffset in
                    updateAlbumHeaderVisibility(scrollOffset: scrollOffset)
                }

                HomeAlbumHeader(
                    diaries: diaries,
                    albums: albums,
                    selectedAlbumID: selectedAlbumID,
                    screenWidth: screenWidth,
                    xScale: xScale,
                    yScale: yScale,
                    onAddAlbum: {
                        showAddAlbumComposer()
                    },
                    onSelectAlbum: { albumID in
                        showSelectedAlbum(albumID)
                    }
                )
                .frame(width: screenWidth, height: 226 * yScale, alignment: .topLeading)
                .offset(y: isAlbumHeaderHidden ? -226 * yScale : 0)
                .zIndex(2)

                ViewModeSwitch(selection: viewModeSelection, xScale: xScale)
                .position(
                    x: screenWidth - 20 * xScale - 50 * xScale,
                    y: 68 * yScale + 22 * xScale
                )
                .zIndex(3)

                if isAlbumFilterActive {
                    HomeAlbumExitButton(
                        size: 44 * xScale,
                        symbolSize: 18 * xScale,
                        action: {
                            clearSelectedAlbum()
                        }
                    )
                    .position(
                        x: 241 * xScale + 22 * xScale,
                        y: 68 * yScale + 22 * xScale
                    )
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
                    .zIndex(3)
                }

                HomeScreenEdgeFadeOverlay(
                    backgroundColor: .white,
                    width: screenWidth,
                    height: screenEdgeFadeHeight,
                    edge: .bottom
                )
                .position(x: screenWidth / 2, y: screenHeight - screenEdgeFadeHeight / 2)
                .allowsHitTesting(false)
                .zIndex(1)

                HomeBottomControls(
                    searchWidth: bottomSearchWidth,
                    height: bottomControlsHeight,
                    addButtonSize: bottomAddButtonSize,
                    gap: bottomControlsGap,
                    isSearchVisible: false,
                    addAction: {
                        isImportPresented = true
                    }
                )
                    .position(
                        x: screenWidth - bottomControlsRightMargin - bottomAddButtonSize / 2,
                        y: screenHeight - bottomControlsBottomMargin - bottomAddButtonSize / 2
                    )
                    .zIndex(2)

                GalleryAlbumAddMorphOverlay(
                    name: $draftAlbumName,
                    isExpanded: isAddAlbumComposerPresented,
                    contentOpacity: isAddAlbumComposerContentVisible ? 1 : 0,
                    collapsedFrame: addAlbumButtonFrame,
                    fallbackCollapsedCenter: addAlbumFallbackCenter,
                    expandedShellFrame: addAlbumShellFrame,
                    expandedContentFrame: addAlbumContentFrame,
                    xScale: xScale,
                    yScale: yScale,
                    onClose: {
                        closeAddAlbumFlow()
                    },
                    onNext: {
                        showAlbumVideoPicker()
                    }
                )
                .frame(width: screenWidth, height: screenHeight, alignment: .topLeading)
                .zIndex(3)

                if isAlbumVideoPickerPresented {
                    GalleryAlbumVideoPicker(
                        diaries: diaries,
                        albumName: draftAlbumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Album" : draftAlbumName,
                        selectedDiaryIDs: $selectedAlbumDiaryIDs,
                        onBack: {
                            withAnimation(.snappy(duration: 0.28)) {
                                isAlbumVideoPickerPresented = false
                                isAddAlbumComposerPresented = editingAlbumID == nil
                                isAddAlbumComposerContentVisible = false
                            }
                            if editingAlbumID != nil {
                                closeAddAlbumFlow()
                            } else {
                                revealAddAlbumComposerContent()
                            }
                        },
                        onSave: {
                            saveAlbum()
                        }
                    )
                    .transition(.opacity)
                    .zIndex(4)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .onChanged { value in
                        updateAlbumHeaderVisibility(dragTranslation: value.translation)
                    }
            )
            .coordinateSpace(name: GalleryAddAlbumMorphCoordinateSpace.name)
            .onPreferenceChange(GalleryAddAlbumFramePreferenceKey.self) { frame in
                addAlbumButtonFrame = frame
            }
            .ignoresSafeArea()
            .animation(.snappy(duration: 0.24), value: isGalleryMode)
            .animation(.snappy(duration: 0.32), value: isAddAlbumComposerPresented)
            .animation(.snappy(duration: 0.24), value: isAlbumVideoPickerPresented)
            .animation(.snappy(duration: 0.26), value: isAlbumHeaderHidden)
            .onAppear {
                activeDiaryID = isGalleryMode ? nil : visibleDiaries.first?.id
            }
            .onChange(of: diaries.first?.id) { _, _ in
                activeDiaryID = isGalleryMode ? nil : visibleDiaries.first?.id
            }
            .onChange(of: selectedAlbumID) { _, _ in
                activeDiaryID = isGalleryMode ? nil : visibleDiaries.first?.id
            }
            .fullScreenCover(isPresented: $isImportPresented) {
                AddVideoFlowView()
            }
            .fullScreenCover(item: $selectedDiary, onDismiss: {
                activeDiaryID = isGalleryMode ? nil : visibleDiaries.first?.id
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
    private func updateAlbumHeaderVisibility(dragTranslation: CGSize) {
        guard !isAddAlbumComposerPresented && !isAlbumVideoPickerPresented else {
            return
        }

        guard abs(dragTranslation.height) > abs(dragTranslation.width) else {
            return
        }

        if dragTranslation.height < -10 {
            isAlbumHeaderHidden = true
        } else if dragTranslation.height > 6 {
            isAlbumHeaderHidden = false
        }
    }

    @MainActor
    private func updateAlbumHeaderVisibility(scrollOffset anchorY: CGFloat) {
        guard !isAddAlbumComposerPresented && !isAlbumVideoPickerPresented else {
            resetHomeScrollTracking(anchorY: anchorY)
            return
        }

        if homeScrollAnchorY == nil {
            homeScrollAnchorY = anchorY
        }

        let scrollOffset = anchorY - (homeScrollAnchorY ?? anchorY)

        defer {
            lastHomeScrollOffset = scrollOffset
        }

        guard let lastHomeScrollOffset else {
            isAlbumHeaderHidden = false
            return
        }

        if scrollOffset > -6 {
            isAlbumHeaderHidden = false
            return
        }

        let delta = scrollOffset - lastHomeScrollOffset
        if delta < -8, scrollOffset < -18 {
            isAlbumHeaderHidden = true
        } else if delta > 4 {
            isAlbumHeaderHidden = false
        }
    }

    @MainActor
    private func resetHomeScrollTracking(anchorY: CGFloat? = nil) {
        homeScrollAnchorY = anchorY
        lastHomeScrollOffset = nil
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

        removeDiaryFromAlbums(diary.id)

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

    @MainActor
    private func createAlbum(id: VideoAlbum.ID = UUID(), name: String, diaryIDs: [VideoDiary.ID]) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "New Album" : trimmedName
        let orderedIDs = diaryIDs.reduce(into: [VideoDiary.ID]()) { result, id in
            guard !result.contains(id) else { return }
            result.append(id)
        }

        guard let coverID = orderedIDs.first else {
            return
        }

        albums.insert(
            VideoAlbum(
                id: id,
                name: finalName,
                diaryIDs: orderedIDs,
                coverDiaryID: coverID
            ),
            at: 0
        )
    }

    @MainActor
    private func showAddAlbumComposer() {
        draftAlbumName = ""
        selectedAlbumDiaryIDs = []
        editingAlbumID = nil
        withAnimation(.snappy(duration: 0.32)) {
            isAddAlbumComposerContentVisible = false
            isAlbumHeaderHidden = false
            isAddAlbumComposerPresented = true
            isAlbumVideoPickerPresented = false
        }
        revealAddAlbumComposerContent()
    }

    @MainActor
    private func showAlbumVideoPicker() {
        withAnimation(.snappy(duration: 0.28)) {
            isAddAlbumComposerContentVisible = false
            isAddAlbumComposerPresented = false
            isAlbumVideoPickerPresented = true
        }
    }

    @MainActor
    private func showAlbumVideoPicker(for album: VideoAlbum) {
        draftAlbumName = album.name
        selectedAlbumDiaryIDs = album.diaryIDs
        editingAlbumID = album.id
        withAnimation(.snappy(duration: 0.28)) {
            isAddAlbumComposerContentVisible = false
            isAlbumHeaderHidden = false
            isAddAlbumComposerPresented = false
            isAlbumVideoPickerPresented = true
        }
    }

    @MainActor
    private func showAlbumVideoPicker(forFallbackDiary diary: VideoDiary) {
        draftAlbumName = fallbackAlbumTitle(for: diary)
        selectedAlbumDiaryIDs = [diary.id]
        editingAlbumID = diary.id
        withAnimation(.snappy(duration: 0.28)) {
            isAddAlbumComposerContentVisible = false
            isAlbumHeaderHidden = false
            isAddAlbumComposerPresented = false
            isAlbumVideoPickerPresented = true
        }
    }

    @MainActor
    private func showSelectedAlbum(_ albumID: VideoAlbum.ID) {
        guard selectedAlbumID != albumID else {
            clearSelectedAlbum()
            return
        }

        withAnimation(.snappy(duration: 0.24)) {
            selectedAlbumID = albumID
            isAlbumHeaderHidden = false
            resetHomeScrollTracking()
            activeDiaryID = nil
        }
    }

    @MainActor
    private func clearSelectedAlbum() {
        withAnimation(.snappy(duration: 0.24)) {
            selectedAlbumID = nil
        }
    }

    @MainActor
    private func closeAddAlbumFlow() {
        withAnimation(.snappy(duration: 0.24)) {
            isAddAlbumComposerContentVisible = false
            isAddAlbumComposerPresented = false
            isAlbumVideoPickerPresented = false
        }
        draftAlbumName = ""
        selectedAlbumDiaryIDs = []
        editingAlbumID = nil
    }

    @MainActor
    private func revealAddAlbumComposerContent() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard isAddAlbumComposerPresented else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                isAddAlbumComposerContentVisible = true
            }
        }
    }

    @MainActor
    private func saveAlbum() {
        guard !selectedAlbumDiaryIDs.isEmpty else {
            return
        }

        if let editingAlbumID, let albumIndex = albums.firstIndex(where: { $0.id == editingAlbumID }) {
            let orderedIDs = uniqueOrderedIDs(selectedAlbumDiaryIDs)
            albums[albumIndex].diaryIDs = orderedIDs
            albums[albumIndex].coverDiaryID = orderedIDs.first
            selectedAlbumID = editingAlbumID
        } else {
            let newAlbumID = editingAlbumID ?? UUID()
            createAlbum(id: newAlbumID, name: draftAlbumName, diaryIDs: selectedAlbumDiaryIDs)
            selectedAlbumID = newAlbumID
        }

        closeAddAlbumFlow()
    }

    @MainActor
    private func removeDiaryFromAlbums(_ diaryID: VideoDiary.ID) {
        albums = albums.compactMap { album in
            var nextAlbum = album
            nextAlbum.diaryIDs.removeAll { $0 == diaryID }

            if nextAlbum.diaryIDs.isEmpty {
                return nil
            }

            if nextAlbum.coverDiaryID == diaryID {
                nextAlbum.coverDiaryID = nextAlbum.diaryIDs.first
            }

            return nextAlbum
        }

        if let selectedAlbumID, !albums.contains(where: { $0.id == selectedAlbumID }) {
            self.selectedAlbumID = nil
        }
    }

    private func uniqueOrderedIDs(_ diaryIDs: [VideoDiary.ID]) -> [VideoDiary.ID] {
        diaryIDs.reduce(into: [VideoDiary.ID]()) { result, id in
            guard !result.contains(id) else { return }
            result.append(id)
        }
    }

    private func fallbackAlbumTitle(for diary: VideoDiary) -> String {
        let words = diary.title.split(separator: " ")
        guard let first = words.first else {
            return "Album"
        }
        return String(first)
    }
}

private struct HomeAlbumHeader: View {
    let diaries: [VideoDiary]
    let albums: [VideoAlbum]
    let selectedAlbumID: VideoAlbum.ID?
    let screenWidth: CGFloat
    let xScale: CGFloat
    let yScale: CGFloat
    let onAddAlbum: () -> Void
    let onSelectAlbum: (VideoAlbum.ID) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            GalleryAlbumBackdrop(height: 226 * yScale)
                .frame(width: screenWidth, height: 226 * yScale)

            GallerySectionTitle("Albums", xScale: xScale)
                .offset(x: 19 * xScale, y: 76 * yScale)

            GalleryAlbumStrip(
                diaries: diaries,
                albums: albums,
                selectedAlbumID: selectedAlbumID,
                xScale: xScale,
                selectedPointerOffsetY: -13 * yScale,
                onAddAlbum: onAddAlbum,
                onSelectAlbum: onSelectAlbum
            )
            .frame(width: screenWidth, height: 92 * xScale)
            .offset(y: 134 * yScale)
        }
        .frame(width: screenWidth, height: 226 * yScale, alignment: .topLeading)
    }
}

private struct HomeAlbumExitButton: View {
    let size: CGFloat
    let symbolSize: CGFloat
    let action: () -> Void

    var body: some View {
        LiquidGlassIconButton(
            systemName: "xmark",
            size: size,
            symbolSize: symbolSize,
            symbolWeight: .semibold,
            foregroundColor: Color.black.opacity(0.72),
            action: action
        )
    }
}

private enum ViewModeSelection: Hashable {
    case timeline
    case gallery
}

private struct ViewModeSwitch: View {
    @Binding var selection: ViewModeSelection
    let xScale: CGFloat
    @State private var bubbleMode: ViewModeSelection?
    @State private var pressedMode: ViewModeSelection?
    @State private var phase: ViewModeSwitchPhase = .idle
    @State private var bubbleScale: CGFloat = 1
    @State private var bubbleScaleX: CGFloat = 1
    @State private var lobeScale: CGFloat = 0.001
    @State private var travelDirection: CGFloat = 0
    @State private var isAnimating = false

    private var switchAnimation: Animation {
        .spring(response: 0.35, dampingFraction: 0.78)
    }

    var body: some View {
        let width = 100 * xScale
        let height = 44 * xScale
        let horizontalInset = 3 * xScale
        let buttonWidth = (width - horizontalInset * 2) / 2
        let indicatorWidth = 37 * xScale
        let indicatorHeight = 35 * xScale
        let visualSelection = bubbleMode ?? selection
        let indicatorCenterX = horizontalInset
            + buttonWidth * (visualSelection == .timeline ? 0.5 : 1.5)
        let indicatorCenterY = height / 2 + (phase == .pressing ? -0.5 * xScale : 0)

        ZStack(alignment: .topLeading) {
            GlassEffectContainer(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    LiquidGlassCapsuleSurface(width: width, height: height, xScale: xScale)

                    LiquidSelectionBlob(
                        width: indicatorWidth,
                        height: indicatorHeight,
                        xScale: xScale,
                        lobeScale: lobeScale,
                        travelDirection: travelDirection
                    )
                        .scaleEffect(x: bubbleScaleX, y: bubbleScale, anchor: .center)
                        .position(x: indicatorCenterX, y: indicatorCenterY)
                        .animation(switchAnimation, value: visualSelection)
                        .animation(.spring(response: 0.20, dampingFraction: 0.72), value: phase)
                        .animation(.spring(response: 0.28, dampingFraction: 0.66), value: bubbleScale)
                        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: bubbleScaleX)
                        .animation(.spring(response: 0.26, dampingFraction: 0.68), value: lobeScale)
                        .allowsHitTesting(false)
                }
                .frame(width: width, height: height)
            }
            .allowsHitTesting(false)

            HStack(spacing: 0) {
                modeButton(
                    systemName: "rectangle.portrait.fill",
                    mode: .timeline,
                    visualSelection: visualSelection
                )
                .frame(width: buttonWidth, height: height)

                modeButton(
                    systemName: "square.grid.3x3.fill",
                    mode: .gallery,
                    visualSelection: visualSelection
                )
                .frame(width: buttonWidth, height: height)
            }
            .padding(.horizontal, horizontalInset)
            .zIndex(2)
        }
        .frame(width: width, height: height)
        .contentShape(Capsule())
        .onAppear {
            bubbleMode = selection
        }
        .onChange(of: selection) { _, newValue in
            guard !isAnimating else { return }
            withAnimation(switchAnimation) {
                bubbleMode = newValue
                phase = .settling
                bubbleScale = 1
                bubbleScaleX = 1
                lobeScale = 0.001
                travelDirection = 0
            }
        }
    }

    private func modeButton(
        systemName: String,
        mode: ViewModeSelection,
        visualSelection: ViewModeSelection
    ) -> some View {
        let isSelected = visualSelection == mode
        let isPressedTarget = pressedMode == mode
        let iconScale = isSelected ? 1 : (isPressedTarget ? 1.08 : 0.9)
        let iconColor = isSelected
            ? Color.black
            : Color(white: isPressedTarget ? 0.42 : 0.56)

        return Button {
            animateSelection(to: mode)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15.5 * xScale, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(iconColor)
                .scaleEffect(iconScale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .animation(.spring(response: 0.24, dampingFraction: 0.76), value: isSelected)
                .animation(.spring(response: 0.18, dampingFraction: 0.7), value: isPressedTarget)
        }
        .buttonStyle(.plain)
    }

    private func animateSelection(to mode: ViewModeSelection) {
        let visualSelection = bubbleMode ?? selection
        guard mode != visualSelection else {
            pulseCurrentMode(mode)
            return
        }
        guard !isAnimating else { return }

        isAnimating = true
        pressedMode = mode
        phase = .pressing
        travelDirection = mode == .gallery ? 1 : -1

        withAnimation(.spring(response: 0.18, dampingFraction: 0.72)) {
            bubbleScale = 1.16
            bubbleScaleX = 1.10
            lobeScale = 0.28
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000)

            selection = mode
            phase = .traveling
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                bubbleMode = mode
                bubbleScale = 1.12
                bubbleScaleX = 1.32
                lobeScale = 0.96
            }

            try? await Task.sleep(nanoseconds: 270_000_000)

            phase = .settling
            withAnimation(.spring(response: 0.26, dampingFraction: 0.66)) {
                bubbleScale = 1
                bubbleScaleX = 1
                lobeScale = 0.001
                pressedMode = nil
            }

            try? await Task.sleep(nanoseconds: 120_000_000)
            phase = .idle
            travelDirection = 0
            isAnimating = false
        }
    }

    private func pulseCurrentMode(_ mode: ViewModeSelection) {
        pressedMode = mode
        phase = .pressing
        travelDirection = 0
        withAnimation(.spring(response: 0.18, dampingFraction: 0.72)) {
            bubbleScale = 1.15
            bubbleScaleX = 1.10
            lobeScale = 0.22
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            phase = .settling
            withAnimation(.spring(response: 0.24, dampingFraction: 0.68)) {
                bubbleScale = 1
                bubbleScaleX = 1
                lobeScale = 0.001
                pressedMode = nil
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            phase = .idle
            travelDirection = 0
        }
    }
}

private enum ViewModeSwitchPhase {
    case idle
    case pressing
    case traveling
    case settling
}

private struct LiquidSelectionBlob: View {
    let width: CGFloat
    let height: CGFloat
    let xScale: CGFloat
    let lobeScale: CGFloat
    let travelDirection: CGFloat

    private var lobeOffset: CGFloat {
        guard travelDirection != 0 else { return 0 }
        return -travelDirection * width * 0.42
    }

    var body: some View {
        let stroke = max(0.6, 0.8 * xScale)
        let darkStroke = max(0.4, 0.5 * xScale)

        return ZStack {
            ZStack {
                Capsule()
                    .fill(.clear)
                    .frame(width: height * 0.78, height: height * 0.86)
                    .glassEffect(.regular.tint(.white.opacity(0.42)).interactive(), in: Capsule())
                    .overlay(
                        Capsule()
                            .fill(lobeOverlay)
                            .blendMode(.plusLighter)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.62), lineWidth: stroke)
                    )
                    .scaleEffect(x: max(lobeScale, 0.001), y: max(lobeScale * 0.9, 0.001))
                    .offset(x: lobeOffset)

                Capsule()
                    .fill(.clear)
                    .frame(width: width, height: height)
                    .glassEffect(.regular.tint(.white.opacity(0.50)).interactive(), in: Capsule())
                    .overlay(
                        Capsule()
                            .fill(mainOverlay)
                            .blendMode(.plusLighter)
                    )
                    .overlay(alignment: .topLeading) {
                        Capsule()
                            .fill(Color.white.opacity(0.78))
                            .frame(width: width * 0.56, height: height * 0.22)
                            .blur(radius: 3.5 * xScale)
                            .offset(x: 6 * xScale, y: 3 * xScale)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .stroke(Color.cyan.opacity(0.14), lineWidth: max(0.6, 1.2 * xScale))
                            .frame(width: height * 0.58, height: height * 0.58)
                            .blur(radius: 0.8 * xScale)
                            .offset(x: 2 * xScale, y: 2 * xScale)
                    }
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.94), lineWidth: stroke)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.black.opacity(0.07), lineWidth: darkStroke)
                            .blur(radius: 0.35 * xScale)
                    )
            }
            .frame(width: width + height * 0.44, height: height + 10 * xScale)
            .shadow(color: .black.opacity(0.16), radius: 18 * xScale, y: 5 * xScale)
        }
        .frame(width: width + height * 0.44, height: height + 10 * xScale)
        .allowsHitTesting(false)
    }

    private var mainOverlay: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.58),
                Color.white.opacity(0.24),
                Color.white.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var lobeOverlay: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.46),
                Color.cyan.opacity(0.12),
                Color.white.opacity(0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
        LiquidGlassIconButton(
            systemName: "ellipsis",
            size: size,
            symbolSize: max(17, size * 0.43),
            symbolWeight: .semibold,
            foregroundColor: Color.black.opacity(0.82),
            action: {
                isPresented.toggle()
            }
        )
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
        let fadeScale = edge == .bottom ? 0.62 : 1.0

        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.16 * fadeScale)
                .mask(
                    smoothMask(
                        transparentUntil: 0.20,
                        softPoint: 0.56,
                        softOpacity: 0.20
                    )
                )

            Rectangle()
                .fill(.thinMaterial)
                .opacity(0.18 * fadeScale)
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
                    .init(color: backgroundColor.opacity(0.04 * fadeScale), location: 0.50),
                    .init(color: backgroundColor.opacity(0.14 * fadeScale), location: 0.74),
                    .init(color: backgroundColor.opacity(0.32 * fadeScale), location: 0.92),
                    .init(color: backgroundColor.opacity(0.42 * fadeScale), location: 1)
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
    let isSearchVisible: Bool
    let addAction: () -> Void

    private var width: CGFloat {
        isSearchVisible ? searchWidth + gap + addButtonSize : addButtonSize
    }

    var body: some View {
        let glassScale = height / 50
        let visibleGap = isSearchVisible ? gap : 0

        ZStack {
            GlassEffectContainer(spacing: visibleGap) {
                HStack(spacing: visibleGap) {
                    if isSearchVisible {
                        LiquidGlassCapsuleSurface(width: searchWidth, height: height, xScale: glassScale)
                            .frame(width: searchWidth, height: height)
                    }

                    LiquidGlassCapsuleSurface(
                        width: addButtonSize,
                        height: addButtonSize,
                        xScale: addButtonSize / 50
                    )
                    .frame(width: addButtonSize, height: addButtonSize)
                }
            }
            .allowsHitTesting(false)

            HStack(spacing: visibleGap) {
                if isSearchVisible {
                    ZStack {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .regular))

                            Text("Search")
                                .font(.system(size: 17, weight: .regular))

                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 18)
                    }
                    .frame(width: searchWidth, height: height)
                }

                Button(action: addAction) {
                    ZStack {
                        Image(systemName: "plus")
                            .font(.system(size: max(20, addButtonSize * 0.44), weight: .semibold))
                            .foregroundStyle(Color.black)
                    }
                    .frame(width: addButtonSize, height: addButtonSize)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add video diary")
            }
        }
        .frame(width: width, height: max(height, addButtonSize))
    }
}

private struct HomeSwitchPanel: View {
    let onGallery: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeSwitchAction(icon: "calendar", title: "Date")
            HomeSwitchAction(icon: "square.grid.2x2", title: "Gallery", action: onGallery)
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
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 20, weight: .regular))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.black.opacity(0.90))
            .frame(height: 42)
            .padding(.horizontal, 26)
        }
        .buttonStyle(.plain)
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

private struct HomeScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
