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
    @State private var isAlbumVideoPickerPresented = false
    @State private var draftAlbumName = ""
    @State private var selectedAlbumDiaryIDs: [VideoDiary.ID] = []
    @State private var isAlbumHeaderHidden = false
    @State private var lastHomeScrollOffset: CGFloat?
    @State private var homeScrollAnchorY: CGFloat?

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
            let bottomAddButtonSize: CGFloat = 50 * xScale
            let bottomControlsGap: CGFloat = 10 * xScale
            let bottomControlsHeight: CGFloat = 50 * xScale
            let bottomControlsBottomMargin: CGFloat = 27 * yScale
            let screenEdgeFadeHeight: CGFloat = 250 * yScale
            let albumTop: CGFloat = 121 * yScale
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

                HomeViewModeToggle(
                    isGalleryMode: isGalleryMode,
                    xScale: xScale,
                    onTimeline: {
                        isGalleryMode = false
                        isAlbumHeaderHidden = false
                        resetHomeScrollTracking()
                        activeDiaryID = visibleDiaries.first?.id
                    },
                    onGallery: {
                        isGalleryMode = true
                        isAlbumHeaderHidden = false
                        resetHomeScrollTracking()
                        activeDiaryID = nil
                    }
                )
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
                            withAnimation(.snappy(duration: 0.24)) {
                                selectedAlbumID = nil
                            }
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
                    addAction: {
                        isImportPresented = true
                    }
                )
                    .position(
                        x: screenWidth / 2,
                        y: screenHeight - bottomControlsBottomMargin - bottomControlsHeight / 2
                    )
                    .zIndex(2)

                if isAddAlbumComposerPresented {
                    GalleryAddAlbumComposer(
                        name: $draftAlbumName,
                        xScale: xScale,
                        yScale: yScale,
                        onClose: {
                            closeAddAlbumFlow()
                        },
                        onNext: {
                            showAlbumVideoPicker()
                        }
                    )
                    .frame(width: 380 * xScale, height: 426 * yScale)
                    .position(
                        x: 20 * xScale + 190 * xScale,
                        y: albumTop - 8 * yScale + 213 * yScale
                    )
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.18, anchor: .topLeading).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                    .zIndex(3)
                }

                if isAlbumVideoPickerPresented {
                    GalleryAlbumVideoPicker(
                        diaries: diaries,
                        albumName: draftAlbumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Album" : draftAlbumName,
                        selectedDiaryIDs: $selectedAlbumDiaryIDs,
                        onBack: {
                            withAnimation(.snappy(duration: 0.28)) {
                                isAlbumVideoPickerPresented = false
                                isAddAlbumComposerPresented = editingAlbumID == nil
                            }
                            if editingAlbumID != nil {
                                closeAddAlbumFlow()
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
    private func createAlbum(name: String, diaryIDs: [VideoDiary.ID]) {
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
            isAlbumHeaderHidden = false
            isAddAlbumComposerPresented = true
            isAlbumVideoPickerPresented = false
        }
    }

    @MainActor
    private func showAlbumVideoPicker() {
        withAnimation(.snappy(duration: 0.28)) {
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
            isAlbumHeaderHidden = false
            isAddAlbumComposerPresented = false
            isAlbumVideoPickerPresented = true
        }
    }

    @MainActor
    private func showAlbumVideoPicker(forFallbackDiary diary: VideoDiary) {
        draftAlbumName = fallbackAlbumTitle(for: diary)
        selectedAlbumDiaryIDs = [diary.id]
        editingAlbumID = nil
        withAnimation(.snappy(duration: 0.28)) {
            isAlbumHeaderHidden = false
            isAddAlbumComposerPresented = false
            isAlbumVideoPickerPresented = true
        }
    }

    @MainActor
    private func showSelectedAlbum(_ albumID: VideoAlbum.ID) {
        withAnimation(.snappy(duration: 0.24)) {
            selectedAlbumID = albumID
            isAlbumHeaderHidden = false
            resetHomeScrollTracking()
            activeDiaryID = nil
        }
    }

    @MainActor
    private func closeAddAlbumFlow() {
        withAnimation(.snappy(duration: 0.24)) {
            isAddAlbumComposerPresented = false
            isAlbumVideoPickerPresented = false
        }
        draftAlbumName = ""
        selectedAlbumDiaryIDs = []
        editingAlbumID = nil
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
            createAlbum(name: draftAlbumName, diaryIDs: selectedAlbumDiaryIDs)
            selectedAlbumID = albums.first?.id
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
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .fill(Color.white.opacity(0.65))
                            .blendMode(.plusLighter)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 40 * (size / 44), y: 8 * (size / 44))

                Capsule()
                    .fill(Color(white: 0.46))
                    .frame(width: symbolSize, height: max(1.8, symbolSize * 0.14))
                    .rotationEffect(.degrees(45))

                Capsule()
                    .fill(Color(white: 0.46))
                    .frame(width: symbolSize, height: max(1.8, symbolSize * 0.14))
                    .rotationEffect(.degrees(-45))
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct HomeViewModeToggle: View {
    let isGalleryMode: Bool
    let xScale: CGFloat
    let onTimeline: () -> Void
    let onGallery: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .fill(Color.white.opacity(0.65))
                        .blendMode(.plusLighter)
                )
                .shadow(color: .black.opacity(0.12), radius: 40 * xScale, y: 8 * xScale)

            modeButton(
                systemName: "rectangle.portrait.fill",
                isSelected: !isGalleryMode,
                action: onTimeline
            )
            .frame(width: 40 * xScale, height: 38 * xScale)
            .offset(x: 3 * xScale, y: 3 * xScale)

            modeButton(
                systemName: "square.grid.3x3.fill",
                isSelected: isGalleryMode,
                action: onGallery
            )
            .frame(width: 38 * xScale, height: 38 * xScale)
            .offset(x: 59 * xScale, y: 3 * xScale)
        }
        .frame(width: 100 * xScale, height: 44 * xScale)
    }

    private func modeButton(systemName: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15 * xScale, weight: .semibold))
                .foregroundStyle(Color.black.opacity(isSelected ? 0.88 : 0.40))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(isSelected ? 0.55 : 0.12))
                        .blendMode(.plusLighter)
                )
        }
        .buttonStyle(.plain)
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
