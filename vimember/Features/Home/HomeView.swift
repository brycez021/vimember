import SwiftUI
import SwiftData
import UIKit
import os

private let homePerformanceLog = OSLog(
    subsystem: "com.brycez021.vimember",
    category: "HomePerformance"
)

private enum AlbumComposerMode: Equatable {
    case add
    case edit
}

private final class HomeScrollRuntime {
    var currentAnchorY: CGFloat = 0
    var anchorY: CGFloat?
    var lastOffset: CGFloat?

    func reset(anchorY: CGFloat? = nil) {
        self.anchorY = anchorY
        lastOffset = nil
        if let anchorY {
            currentAnchorY = anchorY
        }
    }
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VideoDiaryRecord.createdAt, order: .reverse) private var records: [VideoDiaryRecord]
    @Query(sort: \VideoAlbumRecord.createdAt, order: .reverse) private var albumRecords: [VideoAlbumRecord]

    @State private var activeDiaryID: VideoDiary.ID?
    @State private var isTimelinePlaybackSuspended = false
    @State private var pendingVisibilityTask: Task<Void, Never>?
    @State private var galleryAssetBackfillTask: Task<Void, Never>?
    @State private var isGalleryMode = false
    @State private var isImportPresented = false
    @State private var selectedDiary: VideoDiary?
    @State private var pendingDeleteDiary: VideoDiary?
    @State private var editingDiary: VideoDiary?
    @State private var sharePayload: VideoDiarySharePayload?
    @State private var selectedAlbumID: VideoAlbum.ID?
    @State private var editingAlbumID: VideoAlbum.ID?
    @State private var pendingDeleteAlbumID: VideoAlbum.ID?
    @State private var albumComposerMode: AlbumComposerMode = .add
    @State private var albumComposerSourceFrame: CGRect?
    @State private var albumComposerSourceCoverImageData: Data?
    @State private var albumComposerSourceCoverDiary: VideoDiary?
    @State private var isAddAlbumComposerPresented = false
    @State private var isAddAlbumComposerContentVisible = false
    @State private var albumComposerProgress: CGFloat = 0
    @State private var albumComposerTransitionID = 0
    @State private var isAlbumVideoPickerPresented = false
    @State private var isAlbumCoverPickerPresented = false
    @State private var shouldReturnToAlbumComposerAfterVideoPicker = false
    @State private var draftAlbumName = ""
    @State private var selectedAlbumDiaryIDs: [VideoDiary.ID] = []
    @State private var draftAlbumCoverImageData: Data?
    @State private var isAlbumHeaderHidden = false
    @State private var scrollRuntime = HomeScrollRuntime()
    @State private var addAlbumButtonFrame: CGRect?
    @State private var albumFrames: [VideoAlbum.ID: CGRect] = [:]
    @State private var isContentTitleVisibleBelowAlbumHeader = false

    private var diaries: [VideoDiary] {
        records.map(\.diary)
    }

    private var albums: [VideoAlbum] {
        albumRecords.map(\.album)
    }

    private static let homeScrollTopID = "home-scroll-top"
    private static let homeScrollTopThreshold: CGFloat = -6
    private static let albumComposerContentRevealDelayNanoseconds: UInt64 = 220_000_000
    private static let albumComposerResetDelayNanoseconds: UInt64 = 360_000_000

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
            let albumHeaderOffsetY: CGFloat = isAlbumHeaderHidden ? -244 * yScale : 0
            let selectedAlbumPointerTop: CGFloat = 147 * yScale + 104 * xScale - 21.5 * yScale
            let addAlbumFallbackCenter = CGPoint(
                x: 55 * xScale,
                y: albumHeaderOffsetY + 147 * yScale + ((92 * xScale - 118 * xScale) / 2) + 35 * xScale
            )
            let addAlbumShellFrame = CGRect(
                x: 20 * xScale,
                y: albumTop + 13 * yScale,
                width: 380 * xScale,
                height: 416 * yScale
            )
            let addAlbumContentFrame = CGRect(
                x: 20 * xScale,
                y: albumTop + 5 * yScale,
                width: 380 * xScale,
                height: 426 * yScale
            )
            let videoGridTop: CGFloat = 287 * yScale
            let gridGap: CGFloat = 3 * xScale
            let galleryCardWidth = (screenWidth - gridGap * 2) / 3
            let galleryCardHeight = galleryCardWidth * (184 / 138)
            let albumHeaderBottom = 244 * yScale
            let selectedAlbum = albums.first { $0.id == selectedAlbumID }
            let isEditingAlbumComposer = albumComposerMode == .edit
            let albumComposerCollapsedFrame = albumComposerSourceFrame
                ?? addAlbumButtonFrame
            let addAlbumVisualCenter = addAlbumButtonFrame.map { frame in
                CGPoint(x: frame.midX, y: frame.midY)
            } ?? addAlbumFallbackCenter
            let isAlbumFilterActive = selectedAlbum != nil
            let visibleDiaries = selectedAlbum.map { album in
                album.diaryIDs.compactMap { diaryID in
                    diaries.first { $0.id == diaryID }
                }
            } ?? diaries
            let viewModeSelection = Binding<ViewModeSelection>(
                get: {
                    isGalleryMode ? .gallery : .timeline
                },
                set: { nextSelection in
                    switch nextSelection {
                    case .timeline:
                        isGalleryMode = false
                        isAlbumHeaderHidden = false
                        pendingVisibilityTask?.cancel()
                        isTimelinePlaybackSuspended = false
                        resetHomeScrollTracking()
                        activeDiaryID = visibleDiaries.first?.id
                    case .gallery:
                        isGalleryMode = true
                        isAlbumHeaderHidden = false
                        pendingVisibilityTask?.cancel()
                        isTimelinePlaybackSuspended = false
                        resetHomeScrollTracking()
                        activeDiaryID = nil
                    }
                }
            )
            let isGlobalEmptyState = selectedAlbum == nil && diaries.isEmpty
            let galleryTitle = selectedAlbum?.name ?? "All Videos"
            let emptyStateCenterY = albumHeaderBottom
                + (screenHeight - albumHeaderBottom - bottomControlsHeight - bottomControlsBottomMargin) * 0.52
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
            let selectedAlbumFrame = selectedAlbumID.flatMap { albumFrames[$0] }
            let shouldShowSelectedAlbumPointer = selectedAlbumID != nil
                && selectedAlbumFrame != nil
                && !isAlbumHeaderHidden
                && isContentTitleVisibleBelowAlbumHeader

            ScrollViewReader { scrollProxy in
            ZStack(alignment: .topTrailing) {
                Color.white.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: HomeScrollOffsetPreferenceKey.self,
                                value: proxy.frame(in: .named("home-scroll")).minY
                            )
                        }
                        .id(Self.homeScrollTopID)
                        .frame(width: screenWidth, height: 1)

                        ZStack(alignment: .topLeading) {
                            if !isGlobalEmptyState {
                                HStack(alignment: .bottom, spacing: 12 * xScale) {
                                    CalligraphSectionTitle(galleryTitle, xScale: xScale)
                                        .background {
                                            GeometryReader { proxy in
                                                Color.clear.preference(
                                                    key: HomeContentTitleFramePreferenceKey.self,
                                                    value: proxy.frame(in: .named(GalleryAddAlbumMorphCoordinateSpace.name))
                                                )
                                            }
                                        }

                                    Spacer(minLength: 12 * xScale)

                                    if isAlbumFilterActive && visibleDiaries.isEmpty {
                                        HomeEmptyAlbumPrompt(xScale: xScale)
                                            .offset(y: -1.5 * yScale)
                                    }
                                }
                                .frame(width: screenWidth - 40 * xScale, alignment: .leading)
                                .offset(x: 20 * xScale, y: 251 * yScale)
                            }

                            if isGlobalEmptyState {
                                HomeNoVideosEmptyState(xScale: xScale, yScale: yScale)
                                    .frame(width: screenWidth - 40 * xScale)
                                    .position(x: screenWidth / 2, y: emptyStateCenterY)
                            } else if isGalleryMode {
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
                                                }
                                            }
                                        )
                                    }

                                    ForEach(Array(visibleDiaries.enumerated()), id: \.element.id) { index, diary in
                                        let cardIndex = isAlbumFilterActive ? index + 1 : index
                                        HomeContextMenuCard(
                                            diary: diary,
                                            contentRevision: galleryContextMenuRevision(
                                                diary: diary,
                                                width: galleryCardWidth,
                                                height: galleryCardHeight,
                                                column: cardIndex % 3
                                            ),
                                            sourceCornerRadius: 0,
                                            previewTopShadowOpacity: 0.12,
                                            onDelete: { diary in
                                                pendingDeleteDiary = diary
                                            },
                                            onShareVideo: { diary in
                                                shareDiaryVideo(diary)
                                            },
                                            onShareNote: { diary in
                                                shareDiaryNote(diary)
                                            },
                                            onEdit: { diary in
                                                editDiaryFromHome(diary)
                                            }
                                        ) {
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
                                        .frame(width: galleryCardWidth, height: galleryCardHeight)
                                    }
                                }
                                .frame(width: screenWidth, alignment: .leading)
                                .offset(y: videoGridTop)
                            } else {
                                LazyVStack(spacing: timelineCardSpacing) {
                                    ForEach(visibleDiaries) { diary in
                                        let videoHeight = cardWidth / max(diary.displayAspectRatio, 0.1)
                                        let colorBlockOverflow = diary.isLandscapeVideo ? cardWidth * (86 / 420) : 0
                                        let cardHeight = videoHeight + colorBlockOverflow
                                        let isDiaryActive = !isTimelinePlaybackSuspended && activeDiaryID == diary.id

                                        HomeContextMenuCard(
                                            diary: diary,
                                            contentRevision: timelineContextMenuRevision(
                                                diary: diary,
                                                width: cardWidth,
                                                isActive: isDiaryActive
                                            ),
                                            sourceCornerRadius: 0,
                                            onDelete: { diary in
                                                pendingDeleteDiary = diary
                                            },
                                            onShareVideo: { diary in
                                                shareDiaryVideo(diary)
                                            },
                                            onShareNote: { diary in
                                                shareDiaryNote(diary)
                                            },
                                            onEdit: { diary in
                                                editDiaryFromHome(diary)
                                            }
                                        ) {
                                            VideoDiaryCard(
                                                diary: diary,
                                                width: cardWidth,
                                                isActive: isDiaryActive
                                            )
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                pendingVisibilityTask?.cancel()
                                                isTimelinePlaybackSuspended = false
                                                activeDiaryID = nil
                                                selectedDiary = diary
                                            }
                                        }
                                        .frame(width: cardWidth, height: cardHeight)
                                        .id(diary.id)
                                        .background(VisibilityReporter(id: diary.id))
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
                    hiddenAlbumID: isEditingAlbumComposer ? editingAlbumID : nil,
                    screenWidth: screenWidth,
                    xScale: xScale,
                    yScale: yScale,
                    onAddAlbum: {
                        showAddAlbumComposer()
                    },
                    onSelectAlbum: { albumID in
                        showSelectedAlbum(albumID, scrollProxy: scrollProxy)
                    },
                    onLongPressAlbum: { albumID in
                        showEditAlbumComposer(for: albumID)
                    }
                )
                .frame(width: screenWidth, height: 244 * yScale, alignment: .topLeading)
                .offset(y: isAlbumHeaderHidden ? -244 * yScale : 0)
                .zIndex(2)

                if let selectedAlbumFrame {
                    GallerySelectedAlbumPointer()
                        .fill(Color(red: 0.996, green: 0.996, blue: 0.996))
                        .frame(width: 30 * xScale, height: 26 * xScale)
                        .mask(alignment: .top) {
                            Rectangle()
                                .frame(width: 30 * xScale, height: 14 * xScale)
                        }
                        .position(
                            x: selectedAlbumFrame.midX,
                            y: selectedAlbumPointerTop + 13 * xScale
                        )
                        .opacity(shouldShowSelectedAlbumPointer ? 1 : 0)
                        .transaction { transaction in
                            transaction.animation = nil
                            transaction.disablesAnimations = true
                        }
                        .transition(.identity)
                        .allowsHitTesting(false)
                        .zIndex(2.5)
                }

                LiquidGlassDisplayModeToggle(selection: viewModeSelection, xScale: xScale)
                .position(
                    x: screenWidth - 20 * xScale - 50 * xScale,
                    y: 68 * yScale + 22 * xScale
                )
                .zIndex(3)

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
                        os_signpost(.event, log: homePerformanceLog, name: "Home Open Import")
                        isImportPresented = true
                    }
                )
                    .position(
                        x: screenWidth - bottomControlsRightMargin - bottomAddButtonSize / 2,
                        y: screenHeight - bottomControlsBottomMargin - bottomAddButtonSize / 2
                    )
                    .zIndex(2)

                if isEditingAlbumComposer {
                    HomeCollapsedAddAlbumVisual(xScale: xScale)
                        .position(addAlbumVisualCenter)
                        .allowsHitTesting(false)
                        .zIndex(2.9)
                }

                if isAddAlbumComposerPresented {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            closeAddAlbumFlow()
                        }
                        .zIndex(2.8)
                }

                GalleryAlbumAddMorphOverlay(
                    name: $draftAlbumName,
                    coverImageData: draftAlbumCoverImageData,
                    coverDiary: isEditingAlbumComposer ? albumComposerSourceCoverDiary : nil,
                    collapsedAlbumCoverImageData: albumComposerSourceCoverImageData,
                    collapsedAlbumCoverDiary: albumComposerSourceCoverDiary,
                    title: isEditingAlbumComposer ? "Edit Album" : "New Album",
                    leadingAction: isEditingAlbumComposer ? .delete : .close,
                    isExpanded: isAddAlbumComposerPresented,
                    progress: albumComposerProgress,
                    contentOpacity: isAddAlbumComposerContentVisible ? 1 : 0,
                    collapsedFrame: albumComposerCollapsedFrame,
                    fallbackCollapsedCenter: addAlbumFallbackCenter,
                    expandedShellFrame: addAlbumShellFrame,
                    expandedContentFrame: addAlbumContentFrame,
                    xScale: xScale,
                    yScale: yScale,
                    onClose: {
                        closeAddAlbumFlow()
                    },
                    onPickCover: {
                        showAlbumCoverPicker()
                    },
                    onNext: {
                        showAlbumVideoPicker()
                    },
                    onDelete: {
                        if let editingAlbumID {
                            pendingDeleteAlbumID = editingAlbumID
                        }
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
                            let shouldReturnToComposer = shouldReturnToAlbumComposerAfterVideoPicker
                            albumComposerTransitionID += 1
                            let transitionID = albumComposerTransitionID
                            withAnimation(.snappy(duration: 0.28)) {
                                isAlbumVideoPickerPresented = false
                                isAddAlbumComposerPresented = shouldReturnToComposer
                                albumComposerProgress = shouldReturnToComposer ? 1 : 0
                                isAddAlbumComposerContentVisible = false
                            }
                            if shouldReturnToComposer {
                                revealAddAlbumComposerContent(transitionID: transitionID)
                            } else {
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

                if isAlbumCoverPickerPresented {
                    GalleryAlbumCoverPicker(
                        onBack: {
                            closeAlbumCoverPicker()
                        },
                        onSelectCover: { imageData in
                            draftAlbumCoverImageData = imageData
                            closeAlbumCoverPicker()
                        }
                    )
                    .transition(.opacity)
                    .zIndex(5)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .onChanged { value in
                        updateAlbumHeaderVisibility(dragTranslation: value.translation)
                    }
                    .onEnded { value in
                        exitSelectedAlbumIfNeeded(
                            dragValue: value,
                            screenWidth: screenWidth
                        )
                    }
            )
            .coordinateSpace(name: GalleryAddAlbumMorphCoordinateSpace.name)
            .onPreferenceChange(GalleryAddAlbumFramePreferenceKey.self) { frame in
                addAlbumButtonFrame = frame
            }
            .onPreferenceChange(GalleryAlbumFramePreferenceKey.self) { frames in
                albumFrames = frames
            }
            .onPreferenceChange(HomeContentTitleFramePreferenceKey.self) { frame in
                updateContentTitleVisibility(
                    frame: frame,
                    albumHeaderBottom: albumHeaderBottom,
                    screenHeight: screenHeight
                )
            }
            .ignoresSafeArea()
            .animation(.snappy(duration: 0.24), value: isGalleryMode)
            .animation(.snappy(duration: 0.32), value: isAddAlbumComposerPresented)
            .animation(.snappy(duration: 0.24), value: isAlbumVideoPickerPresented)
            .animation(.snappy(duration: 0.24), value: isAlbumCoverPickerPresented)
            .animation(.snappy(duration: 0.26), value: isAlbumHeaderHidden)
            .onAppear {
                os_signpost(.event, log: homePerformanceLog, name: "Home Appeared")
                isTimelinePlaybackSuspended = false
                activeDiaryID = isGalleryMode ? nil : visibleDiaries.first?.id
            }
            .task {
                scheduleGalleryAssetBackfill(for: records.map(\.diary))
            }
            .onChange(of: diaries.first?.id) { _, _ in
                isTimelinePlaybackSuspended = false
                activeDiaryID = isGalleryMode ? nil : visibleDiaries.first?.id
            }
            .onChange(of: records.map(\.id)) { _, _ in
                scheduleGalleryAssetBackfill(for: records.map(\.diary))
            }
            .onChange(of: selectedAlbumID) { _, _ in
                isTimelinePlaybackSuspended = false
                activeDiaryID = isGalleryMode ? nil : visibleDiaries.first?.id
            }
            .fullScreenCover(isPresented: $isImportPresented) {
                AddVideoFlowView()
            }
            .sheet(item: $sharePayload) { payload in
                VideoDiaryShareSheet(activityItems: payload.activityItems)
            }
            .alert("Delete this video diary?", isPresented: deleteConfirmationBinding) {
                Button("Delete", role: .destructive) {
                    confirmPendingDelete()
                }

                Button("Cancel", role: .cancel) {
                    pendingDeleteDiary = nil
                }
            } message: {
                Text("This removes the local diary and copied video from Vimo. It does not delete the original video in Photos.")
            }
            .alert(deleteAlbumConfirmationTitle, isPresented: deleteAlbumConfirmationBinding) {
                Button("Delete Album", role: .destructive) {
                    confirmPendingAlbumDelete()
                }

                Button("Cancel", role: .cancel) {
                    pendingDeleteAlbumID = nil
                }
            } message: {
                Text("Videos in this album will stay in All Videos.")
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
            .fullScreenCover(item: $editingDiary, onDismiss: {
                activeDiaryID = isGalleryMode ? nil : visibleDiaries.first?.id
            }) { diary in
                EditVideoDiaryFlowView(diary: diary) { title, body in
                    _ = try await saveEditedDiary(
                        diary: diary,
                        title: title,
                        body: body,
                        presentDetailAfterSave: false
                    )
                }
            }
            }
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: {
                pendingDeleteDiary != nil
            },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteDiary = nil
                }
            }
        )
    }

    private var deleteAlbumConfirmationBinding: Binding<Bool> {
        Binding(
            get: {
                pendingDeleteAlbumID != nil
            },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteAlbumID = nil
                }
            }
        )
    }

    private var deleteAlbumConfirmationTitle: String {
        guard
            let pendingDeleteAlbumID,
            let album = albums.first(where: { $0.id == pendingDeleteAlbumID })
        else {
            return "Delete Album?"
        }

        return "Delete “\(album.name)”?"
    }

    @MainActor
    private func confirmPendingDelete() {
        guard let diary = pendingDeleteDiary else {
            return
        }

        pendingDeleteDiary = nil
        Task {
            try? await deleteDiary(diary)
        }
    }

    @MainActor
    private func confirmPendingAlbumDelete() {
        guard let albumID = pendingDeleteAlbumID else {
            return
        }

        pendingDeleteAlbumID = nil
        if let albumRecord = albumRecords.first(where: { $0.id == albumID }) {
            modelContext.delete(albumRecord)
            try? modelContext.save()
        }

        albumComposerTransitionID += 1
        let transitionID = albumComposerTransitionID

        withAnimation(.easeOut(duration: 0.12)) {
            isAddAlbumComposerContentVisible = false
        }
        withAnimation(.snappy(duration: 0.32)) {
            isAddAlbumComposerPresented = false
            albumComposerProgress = 0
            isAlbumVideoPickerPresented = false
            isAlbumCoverPickerPresented = false
            if selectedAlbumID == albumID {
                selectedAlbumID = nil
            }
        }

        resetAlbumComposerDraftAfterCollapse(transitionID: transitionID)
    }

    @MainActor
    private func shareDiaryVideo(_ diary: VideoDiary) {
        guard let videoURL = diary.videoURL else {
            return
        }

        sharePayload = VideoDiarySharePayload(activityItems: [
            VideoDiaryVideoActivityItemSource(url: videoURL)
        ])
    }

    @MainActor
    private func shareDiaryNote(_ diary: VideoDiary) {
        Task { @MainActor in
            let textImage = await VideoDiaryShareImageRenderer.makeImage(for: diary)
            sharePayload = VideoDiarySharePayload(activityItems: [
                VideoDiaryTextImageActivityItemSource(image: textImage)
            ])
        }
    }

    @MainActor
    private func editDiaryFromHome(_ diary: VideoDiary) {
        pendingVisibilityTask?.cancel()
        isTimelinePlaybackSuspended = false
        activeDiaryID = nil
        selectedDiary = nil
        editingDiary = diary
    }

    private func scheduleActiveCardUpdate(frames: [VideoDiary.ID: CGRect], viewport: CGSize) {
        pendingVisibilityTask?.cancel()

        var bestID: VideoDiary.ID?
        var bestScore = CGFloat.greatestFiniteMagnitude
        let targetY = viewport.height * 0.52

        for (id, frame) in frames {
            guard frame.maxY > 0, frame.minY < viewport.height else {
                continue
            }

            let visibleHeight = min(frame.maxY, viewport.height) - max(frame.minY, 0)
            let centerDistance = abs(frame.midY - targetY)
            let score = centerDistance - visibleHeight * 0.35

            if score < bestScore {
                bestScore = score
                bestID = id
            }
        }

        guard let bestID else {
            return
        }

        if !isTimelinePlaybackSuspended {
            isTimelinePlaybackSuspended = true
        }

        pendingVisibilityTask = Task {
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                os_signpost(.event, log: homePerformanceLog, name: "Home Active Video")
                activeDiaryID = bestID
                isTimelinePlaybackSuspended = false
            }
        }
    }

    @MainActor
    private func scheduleGalleryAssetBackfill(for diaries: [VideoDiary]) {
        galleryAssetBackfillTask?.cancel()

        let snapshot = diaries
        galleryAssetBackfillTask = Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await VideoDerivedAssetStore.shared.prepareGalleryAssets(for: snapshot)
        }
    }

    @MainActor
    private func updateAlbumHeaderVisibility(dragTranslation: CGSize) {
        guard !isAddAlbumComposerPresented && !isAlbumVideoPickerPresented && !isAlbumCoverPickerPresented else {
            return
        }

        guard abs(dragTranslation.height) > abs(dragTranslation.width) else {
            return
        }

        if dragTranslation.height < -10 {
            setAlbumHeaderHidden(true)
        } else if dragTranslation.height > 6 {
            setAlbumHeaderHidden(false)
        }
    }

    @MainActor
    private func updateAlbumHeaderVisibility(scrollOffset anchorY: CGFloat) {
        scrollRuntime.currentAnchorY = anchorY
        let isAtTop = anchorY >= Self.homeScrollTopThreshold
        if isAtTop {
            setAlbumHeaderHidden(false)
        }

        guard !isAddAlbumComposerPresented && !isAlbumVideoPickerPresented && !isAlbumCoverPickerPresented else {
            resetHomeScrollTracking(anchorY: anchorY)
            return
        }

        if scrollRuntime.anchorY == nil {
            scrollRuntime.anchorY = anchorY
        }

        let scrollOffset = anchorY - (scrollRuntime.anchorY ?? anchorY)

        defer {
            scrollRuntime.lastOffset = scrollOffset
        }

        guard let lastOffset = scrollRuntime.lastOffset else {
            setAlbumHeaderHidden(false)
            return
        }

        if scrollOffset > Self.homeScrollTopThreshold {
            setAlbumHeaderHidden(false)
            return
        }

        let delta = scrollOffset - lastOffset
        if delta < -8, scrollOffset < -18 {
            setAlbumHeaderHidden(true)
        } else if delta > 4 {
            setAlbumHeaderHidden(false)
        }
    }

    @MainActor
    private func resetHomeScrollTracking(anchorY: CGFloat? = nil) {
        scrollRuntime.reset(anchorY: anchorY)
    }

    @MainActor
    private func setAlbumHeaderHidden(_ hidden: Bool) {
        guard isAlbumHeaderHidden != hidden else {
            return
        }

        isAlbumHeaderHidden = hidden
    }

    @MainActor
    private func updateContentTitleVisibility(frame: CGRect?, albumHeaderBottom: CGFloat, screenHeight: CGFloat) {
        let nextValue = frame.map { frame in
            frame.minY >= albumHeaderBottom - 1
                && frame.maxY > albumHeaderBottom
                && frame.minY < screenHeight
        } ?? false

        guard isContentTitleVisibleBelowAlbumHeader != nextValue else {
            return
        }

        isContentTitleVisibleBelowAlbumHeader = nextValue
    }

    private func albumCoverDiary(for album: VideoAlbum) -> VideoDiary? {
        album.coverDiaryID.flatMap { coverID in
            diaries.first { $0.id == coverID }
        } ?? album.diaryIDs.compactMap { diaryID in
            diaries.first { $0.id == diaryID }
        }.first
    }

    @MainActor
    private func deleteDiary(_ diary: VideoDiary) async throws {
        guard let record = records.first(where: { $0.id == diary.id }) else {
            return
        }

        try await VideoFileStore.deleteVideo(named: record.localVideoFilename)
        modelContext.delete(record)
        removeDiaryFromAlbums(diary.id)
        try modelContext.save()

        selectedDiary = nil
        if activeDiaryID == diary.id {
            activeDiaryID = diaries.first?.id
        }
    }

    @MainActor
    private func saveEditedDiary(
        diary: VideoDiary,
        title: String,
        body: String,
        presentDetailAfterSave: Bool = true
    ) async throws -> VideoDiary {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmedTitle.isEmpty ? "Title" : trimmedTitle

        if let record = records.first(where: { $0.id == diary.id }) {
            record.title = finalTitle
            record.body = body
            record.updatedAt = Date()
            try modelContext.save()

            let updatedDiary = record.diary
            if presentDetailAfterSave {
                selectedDiary = updatedDiary
            }
            return updatedDiary
        }

        return diary
    }

    @MainActor
    private func createAlbum(
        id: VideoAlbum.ID = UUID(),
        name: String,
        diaryIDs: [VideoDiary.ID],
        coverImageData: Data?
    ) -> VideoAlbumRecord? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "New Album" : trimmedName
        let orderedIDs = uniqueOrderedIDs(diaryIDs)

        let albumRecord = VideoAlbumRecord(
            id: id,
            name: finalName,
            diaryIDs: orderedIDs,
            coverDiaryID: orderedIDs.first,
            coverImageData: coverImageData
        )
        modelContext.insert(albumRecord)
        return albumRecord
    }

    @MainActor
    private func showAddAlbumComposer() {
        albumComposerTransitionID += 1
        let transitionID = albumComposerTransitionID
        albumComposerMode = .add
        albumComposerSourceFrame = addAlbumButtonFrame
        albumComposerSourceCoverImageData = nil
        albumComposerSourceCoverDiary = nil
        draftAlbumName = ""
        selectedAlbumDiaryIDs = []
        draftAlbumCoverImageData = nil
        editingAlbumID = nil
        shouldReturnToAlbumComposerAfterVideoPicker = false
        albumComposerProgress = 0
        withAnimation(.snappy(duration: 0.32)) {
            isAddAlbumComposerContentVisible = false
            isAlbumHeaderHidden = false
            isAddAlbumComposerPresented = true
            albumComposerProgress = 1
            isAlbumVideoPickerPresented = false
            isAlbumCoverPickerPresented = false
        }
        revealAddAlbumComposerContent(transitionID: transitionID)
    }

    @MainActor
    private func showEditAlbumComposer(for albumID: VideoAlbum.ID) {
        guard
            let album = albums.first(where: { $0.id == albumID }),
            let sourceFrame = albumFrames[albumID].map(albumCoverFrame(from:))
        else {
            return
        }

        albumComposerMode = .edit
        albumComposerSourceFrame = pressedAlbumCoverFrame(from: sourceFrame)
        albumComposerSourceCoverImageData = album.coverImageData
        albumComposerSourceCoverDiary = albumCoverDiary(for: album)
        draftAlbumName = album.name
        selectedAlbumDiaryIDs = album.diaryIDs
        draftAlbumCoverImageData = album.coverImageData
        editingAlbumID = albumID
        pendingDeleteAlbumID = nil
        shouldReturnToAlbumComposerAfterVideoPicker = false
        albumComposerProgress = 0
        albumComposerTransitionID += 1
        let transitionID = albumComposerTransitionID
        isAddAlbumComposerContentVisible = false
        isAlbumHeaderHidden = false
        isAddAlbumComposerPresented = false
        isAlbumVideoPickerPresented = false
        isAlbumCoverPickerPresented = false

        withAnimation(.snappy(duration: 0.32)) {
            isAddAlbumComposerPresented = true
            albumComposerProgress = 1
        }
        restoreAlbumComposerSourceFrame(sourceFrame, for: albumID, transitionID: transitionID)
        revealAddAlbumComposerContent(transitionID: transitionID)
    }

    @MainActor
    private func showAlbumVideoPicker() {
        shouldReturnToAlbumComposerAfterVideoPicker = true
        albumComposerTransitionID += 1
        withAnimation(.snappy(duration: 0.28)) {
            isAddAlbumComposerContentVisible = false
            isAddAlbumComposerPresented = false
            albumComposerProgress = 0
            isAlbumCoverPickerPresented = false
            isAlbumVideoPickerPresented = true
        }
    }

    @MainActor
    private func showAlbumCoverPicker() {
        withAnimation(.snappy(duration: 0.24)) {
            isAlbumCoverPickerPresented = true
        }
    }

    @MainActor
    private func closeAlbumCoverPicker() {
        withAnimation(.snappy(duration: 0.24)) {
            isAlbumCoverPickerPresented = false
        }
    }

    @MainActor
    private func showAlbumVideoPicker(for album: VideoAlbum) {
        albumComposerTransitionID += 1
        draftAlbumName = album.name
        selectedAlbumDiaryIDs = album.diaryIDs
        draftAlbumCoverImageData = album.coverImageData
        editingAlbumID = album.id
        shouldReturnToAlbumComposerAfterVideoPicker = false
        withAnimation(.snappy(duration: 0.28)) {
            isAddAlbumComposerContentVisible = false
            isAlbumHeaderHidden = false
            isAddAlbumComposerPresented = false
            albumComposerProgress = 0
            isAlbumCoverPickerPresented = false
            isAlbumVideoPickerPresented = true
        }
    }

    @MainActor
    private func showSelectedAlbum(_ albumID: VideoAlbum.ID, scrollProxy: ScrollViewProxy) {
        guard selectedAlbumID != albumID else {
            clearSelectedAlbum()
            return
        }

        let shouldScrollToTop = scrollRuntime.currentAnchorY < Self.homeScrollTopThreshold
        withAnimation(.snappy(duration: 0.24)) {
            selectedAlbumID = albumID
            isAlbumHeaderHidden = false
            resetHomeScrollTracking()
            activeDiaryID = nil
        }

        if shouldScrollToTop {
            withAnimation(.snappy(duration: 0.24)) {
                scrollProxy.scrollTo(Self.homeScrollTopID, anchor: .top)
            }
        }
    }

    @MainActor
    private func clearSelectedAlbum() {
        withAnimation(.snappy(duration: 0.24)) {
            selectedAlbumID = nil
        }
    }

    @MainActor
    private func exitSelectedAlbumIfNeeded(dragValue: DragGesture.Value, screenWidth: CGFloat) {
        guard selectedAlbumID != nil else {
            return
        }

        guard !isAddAlbumComposerPresented && !isAlbumVideoPickerPresented && !isAlbumCoverPickerPresented else {
            return
        }

        let edgeStartWidth = min(max(screenWidth * 0.35, 88), 140)
        guard dragValue.startLocation.x <= edgeStartWidth else {
            return
        }

        let horizontalDistance = dragValue.translation.width
        let verticalDistance = abs(dragValue.translation.height)
        let projectedHorizontalDistance = dragValue.predictedEndTranslation.width
        let rightwardDistance = max(horizontalDistance, projectedHorizontalDistance)

        guard rightwardDistance > 64, rightwardDistance > verticalDistance * 1.35 else {
            return
        }

        clearSelectedAlbum()
    }

    @MainActor
    private func closeAddAlbumFlow() {
        let shouldDelayReset = isAddAlbumComposerPresented || isAlbumVideoPickerPresented || isAlbumCoverPickerPresented
        albumComposerTransitionID += 1
        let transitionID = albumComposerTransitionID
        withAnimation(.easeOut(duration: 0.12)) {
            isAddAlbumComposerContentVisible = false
        }
        withAnimation(.snappy(duration: 0.32)) {
            isAddAlbumComposerPresented = false
            albumComposerProgress = 0
            isAlbumVideoPickerPresented = false
            isAlbumCoverPickerPresented = false
        }
        if shouldDelayReset {
            resetAlbumComposerDraftAfterCollapse(transitionID: transitionID)
        } else {
            resetAlbumComposerDraft()
        }
    }

    @MainActor
    private func resetAlbumComposerDraftAfterCollapse(transitionID: Int? = nil) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.albumComposerResetDelayNanoseconds)
            if let transitionID, albumComposerTransitionID != transitionID {
                return
            }
            guard !isAddAlbumComposerPresented && !isAlbumVideoPickerPresented && !isAlbumCoverPickerPresented else {
                return
            }
            resetAlbumComposerDraft()
        }
    }

    @MainActor
    private func resetAlbumComposerDraft() {
        draftAlbumName = ""
        selectedAlbumDiaryIDs = []
        draftAlbumCoverImageData = nil
        editingAlbumID = nil
        pendingDeleteAlbumID = nil
        albumComposerMode = .add
        albumComposerSourceFrame = nil
        albumComposerSourceCoverImageData = nil
        albumComposerSourceCoverDiary = nil
        shouldReturnToAlbumComposerAfterVideoPicker = false
    }

    private func albumCoverFrame(from itemFrame: CGRect) -> CGRect {
        let coverSize = itemFrame.width
        return CGRect(
            x: itemFrame.minX,
            y: itemFrame.minY,
            width: coverSize,
            height: coverSize
        )
    }

    private func pressedAlbumCoverFrame(from sourceFrame: CGRect) -> CGRect {
        let pressedScale: CGFloat = 0.965
        let horizontalInset = sourceFrame.width * (1 - pressedScale) / 2
        let verticalInset = sourceFrame.height * (1 - pressedScale) / 2
        return sourceFrame.insetBy(dx: horizontalInset, dy: verticalInset)
    }

    @MainActor
    private func restoreAlbumComposerSourceFrame(_ sourceFrame: CGRect, for albumID: VideoAlbum.ID, transitionID: Int) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard albumComposerTransitionID == transitionID,
                  editingAlbumID == albumID,
                  albumComposerMode == .edit,
                  isAddAlbumComposerPresented
            else {
                return
            }
            albumComposerSourceFrame = sourceFrame
        }
    }

    @MainActor
    private func revealAddAlbumComposerContent(transitionID: Int) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.albumComposerContentRevealDelayNanoseconds)
            guard isAddAlbumComposerPresented && albumComposerTransitionID == transitionID else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                isAddAlbumComposerContentVisible = true
            }
        }
    }

    @MainActor
    private func saveAlbum() {
        Task {
            await saveAlbumWithResolvedCover()
        }
    }

    @MainActor
    private func saveAlbumWithResolvedCover() async {
        let resolvedCoverImageData: Data?
        if let draftAlbumCoverImageData {
            resolvedCoverImageData = draftAlbumCoverImageData
        } else if let existingCoverImageData = existingCoverImageDataForEditingAlbum() {
            resolvedCoverImageData = existingCoverImageData
        } else {
            resolvedCoverImageData = await automaticCoverImageData(for: selectedAlbumDiaryIDs)
        }

        if let editingAlbumID, let albumRecord = albumRecords.first(where: { $0.id == editingAlbumID }) {
            let trimmedName = draftAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName = trimmedName.isEmpty ? "New Album" : trimmedName
            let orderedIDs = uniqueOrderedIDs(selectedAlbumDiaryIDs)
            albumRecord.name = finalName
            albumRecord.diaryIDs = orderedIDs
            albumRecord.coverDiaryID = orderedIDs.first
            albumRecord.coverImageData = resolvedCoverImageData
            selectedAlbumID = editingAlbumID
        } else {
            let newAlbumID = editingAlbumID ?? UUID()
            _ = createAlbum(
                id: newAlbumID,
                name: draftAlbumName,
                diaryIDs: selectedAlbumDiaryIDs,
                coverImageData: resolvedCoverImageData
            )
            selectedAlbumID = newAlbumID
        }

        try? modelContext.save()
        closeAddAlbumFlow()
    }

    @MainActor
    private func existingCoverImageDataForEditingAlbum() -> Data? {
        guard
            let editingAlbumID,
            let album = albums.first(where: { $0.id == editingAlbumID })
        else {
            return nil
        }

        return album.coverImageData
    }

    @MainActor
    private func automaticCoverImageData(for diaryIDs: [VideoDiary.ID]) async -> Data? {
        let orderedIDs = uniqueOrderedIDs(diaryIDs)
        guard
            let firstDiaryID = orderedIDs.first,
            let diary = diaries.first(where: { $0.id == firstDiaryID }),
            let url = diary.videoURL
        else {
            return nil
        }

        return try? await AlbumCoverImageRenderer.coverImageData(forVideoAt: url)
    }

    @MainActor
    private func removeDiaryFromAlbums(_ diaryID: VideoDiary.ID) {
        for albumRecord in albumRecords {
            albumRecord.diaryIDs.removeAll { $0 == diaryID }

            if let coverID = albumRecord.coverDiaryID {
                if !albumRecord.diaryIDs.contains(coverID) {
                    albumRecord.coverDiaryID = albumRecord.diaryIDs.first
                }
            } else {
                albumRecord.coverDiaryID = albumRecord.diaryIDs.first
            }
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

    private func galleryContextMenuRevision(
        diary: VideoDiary,
        width: CGFloat,
        height: CGFloat,
        column: Int
    ) -> String {
        [
            diary.id.uuidString,
            diary.title,
            diary.localVideoFilename,
            stableLayoutToken(diary.displayAspectRatio),
            stableLayoutToken(width),
            stableLayoutToken(height),
            "\(column)"
        ].joined(separator: "|")
    }

    private func timelineContextMenuRevision(diary: VideoDiary, width: CGFloat, isActive: Bool) -> String {
        [
            diary.id.uuidString,
            diary.title,
            "\(stableTextHash(diary.body))",
            diary.localVideoFilename,
            stableLayoutToken(diary.displayAspectRatio),
            stableLayoutToken(width),
            isActive ? "active" : "inactive"
        ].joined(separator: "|")
    }

    private func stableLayoutToken(_ value: CGFloat) -> String {
        "\(Int((value * 100).rounded()))"
    }

    private func stableTextHash(_ text: String) -> Int {
        var hasher = Hasher()
        hasher.combine(text)
        return hasher.finalize()
    }

}

private struct HomeContextMenuCard<Content: View>: UIViewControllerRepresentable {
    let diary: VideoDiary
    let contentRevision: String
    let sourceCornerRadius: CGFloat
    let previewTopShadowOpacity: Double
    let onDelete: (VideoDiary) -> Void
    let onShareVideo: (VideoDiary) -> Void
    let onShareNote: (VideoDiary) -> Void
    let onEdit: (VideoDiary) -> Void
    private let content: () -> Content

    init(
        diary: VideoDiary,
        contentRevision: String,
        sourceCornerRadius: CGFloat,
        previewTopShadowOpacity: Double = 0,
        onDelete: @escaping (VideoDiary) -> Void,
        onShareVideo: @escaping (VideoDiary) -> Void,
        onShareNote: @escaping (VideoDiary) -> Void,
        onEdit: @escaping (VideoDiary) -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.diary = diary
        self.contentRevision = contentRevision
        self.sourceCornerRadius = sourceCornerRadius
        self.previewTopShadowOpacity = previewTopShadowOpacity
        self.onDelete = onDelete
        self.onShareVideo = onShareVideo
        self.onShareNote = onShareNote
        self.onEdit = onEdit
        self.content = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let controller = UIHostingController(rootView: content())
        controller.view.backgroundColor = .clear
        controller.view.isOpaque = false
        controller.view.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))
        context.coordinator.renderedContentRevision = contentRevision
        return controller
    }

    func updateUIViewController(_ uiViewController: UIHostingController<Content>, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.renderedContentRevision != contentRevision else {
            return
        }

        uiViewController.rootView = content()
        context.coordinator.renderedContentRevision = contentRevision
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiViewController: UIHostingController<Content>,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else {
            return nil
        }

        return CGSize(width: width, height: height)
    }

    final class Coordinator: NSObject, UIContextMenuInteractionDelegate {
        var parent: HomeContextMenuCard
        var renderedContentRevision: String?

        init(parent: HomeContextMenuCard) {
            self.parent = parent
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            configurationForMenuAtLocation location: CGPoint
        ) -> UIContextMenuConfiguration? {
            let sourceView = interaction.view
            let configuration = UIContextMenuConfiguration(
                identifier: NSString(string: parent.diary.id.uuidString),
                previewProvider: { [weak self, weak sourceView] in
                    self?.makePreviewController(sourceView: sourceView)
                },
                actionProvider: { [weak self] _ in
                    self?.makeMenu() ?? UIMenu(children: [])
                }
            )
            configuration.preferredMenuElementOrder = .fixed
            return configuration
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration
        ) -> UITargetedPreview? {
            makeTargetedPreview(for: interaction)
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration
        ) -> UITargetedPreview? {
            makeTargetedPreview(for: interaction)
        }

        private func makeMenu() -> UIMenu {
            let diary = parent.diary
            let deleteAction = UIAction(
                title: "Delete",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.parent.onDelete(diary)
                }
            }

            let shareVideoAttributes: UIMenuElement.Attributes = diary.videoURL == nil ? .disabled : []
            let shareVideoAction = UIAction(
                title: "Share Video",
                image: UIImage(systemName: "film"),
                attributes: shareVideoAttributes
            ) { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.parent.onShareVideo(diary)
                }
            }

            let shareNoteAction = UIAction(
                title: "Share Note",
                image: UIImage(systemName: "note.text")
            ) { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.parent.onShareNote(diary)
                }
            }

            let editAction = UIAction(
                title: "Edit",
                image: UIImage(systemName: "pencil")
            ) { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.parent.onEdit(diary)
                }
            }

            return UIMenu(children: [deleteAction, shareVideoAction, shareNoteAction, editAction])
        }

        private func makeTargetedPreview(for interaction: UIContextMenuInteraction) -> UITargetedPreview? {
            guard let sourceView = interaction.view, sourceView.window != nil else { return nil }
            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .clear
            if parent.sourceCornerRadius > 0 {
                parameters.visiblePath = UIBezierPath(
                    roundedRect: sourceView.bounds,
                    cornerRadius: parent.sourceCornerRadius
                )
            } else {
                parameters.visiblePath = UIBezierPath(rect: sourceView.bounds)
            }
            return UITargetedPreview(view: sourceView, parameters: parameters)
        }

        private func makePreviewController(sourceView: UIView?) -> UIViewController {
            let metrics = makePreviewMetrics(sourceView: sourceView)
            let controller = UIHostingController(
                rootView: HomeContextMenuPreviewCard(
                    diary: parent.diary,
                    outerSize: metrics.outerSize,
                    cardSize: metrics.cardSize,
                    cornerRadius: metrics.cornerRadius,
                    topShadowOpacity: parent.previewTopShadowOpacity
                )
            )
            controller.view.backgroundColor = .clear
            controller.view.isOpaque = false
            controller.view.clipsToBounds = false
            controller.view.layer.masksToBounds = false
            controller.view.frame = CGRect(origin: .zero, size: metrics.outerSize)
            controller.preferredContentSize = metrics.outerSize
            return controller
        }

        private func makePreviewMetrics(sourceView: UIView?) -> (outerSize: CGSize, cardSize: CGSize, cornerRadius: CGFloat) {
            let fallbackSize = sourceView?.bounds.size ?? CGSize(width: 420, height: 912)
            let windowSize = sourceView?.window?.bounds.size ?? fallbackSize
            let baseWidth = min(max(windowSize.width, 1), 420)
            let horizontalSafetyInset = parent.diary.isLandscapeVideo ? 0 : min(max(baseWidth * (8 / 420), 5), 10)
            let naturalCardWidth = max(1, baseWidth - horizontalSafetyInset * 2)
            let videoHeight = naturalCardWidth / max(parent.diary.displayAspectRatio, 0.1)
            let colorBlockOverflow = parent.diary.isLandscapeVideo ? naturalCardWidth * (86 / 420) : 0
            let naturalCardHeight = max(1, videoHeight + colorBlockOverflow)
            let verticalSafetyInset = parent.diary.isLandscapeVideo ? 0 : min(max(baseWidth * (18 / 420), 12), 20)
            let naturalOuterHeight = naturalCardHeight + verticalSafetyInset * 2
            let maxHeight = max(160, windowSize.height * 0.70)
            let scale = min(1, maxHeight / naturalOuterHeight)
            let scaledHorizontalInset = horizontalSafetyInset * scale
            let scaledInset = verticalSafetyInset * scale
            let cardSize = CGSize(width: naturalCardWidth * scale, height: naturalCardHeight * scale)
            let outerSize = CGSize(width: cardSize.width + scaledHorizontalInset * 2, height: cardSize.height + scaledInset * 2)
            let cornerRadius = min(30 * scale, cardSize.width * 0.12)
            return (outerSize, cardSize, cornerRadius)
        }
    }
}

private struct HomeContextMenuPreviewCard: View {
    let diary: VideoDiary
    let outerSize: CGSize
    let cardSize: CGSize
    let cornerRadius: CGFloat
    let topShadowOpacity: Double

    var body: some View {
        ZStack {
            Color.clear

            BlendedVideoSurface(
                url: diary.videoURL,
                aspectRatio: diary.displayAspectRatio,
                fallbackTint: diary.fallbackTint,
                isPlaying: false,
                width: cardSize.width,
                height: cardSize.height,
                videoGravity: .resizeAspect
            ) { _, _, _ in
                HomeDiaryTextOverlay(
                    diary: diary,
                    width: cardSize.width,
                    cardHeight: cardSize.height,
                    layout: diary.isLandscapeVideo ? .landscape : .vertical
                )
            }
            .frame(width: cardSize.width, height: cardSize.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: .black.opacity(topShadowOpacity),
                radius: topShadowOpacity > 0 ? 18 : 0,
                x: 0,
                y: topShadowOpacity > 0 ? -8 : 0
            )
        }
        .frame(width: outerSize.width, height: outerSize.height)
    }
}

private struct HomeEmptyAlbumPrompt: View {
    let xScale: CGFloat

    var body: some View {
        Text(
            "No videos in this album yet",
            comment: "Empty state shown after opening an album that has no video diary cards."
        )
        .font(.system(size: 16 * xScale, weight: .medium))
        .foregroundStyle(.black.opacity(0.36))
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct HomeNoVideosEmptyState: View {
    let xScale: CGFloat
    let yScale: CGFloat

    var body: some View {
        VStack(spacing: 20 * xScale) {
            HomeNoVideosEmptyStateLogo(size: 58 * xScale)
                .offset(y: -4 * yScale)

            VStack(spacing: 5 * xScale) {
                Text(
                    "No videos",
                    comment: "Empty state title shown when the user has not added any video diaries."
                )
                .font(.system(size: 24 * xScale, weight: .semibold))
                .tracking(24 * xScale * 0.01)
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .offset(y: -6 * yScale)

                Text(
                    "Tap the button to add a video",
                    comment: "Empty state instruction shown when the user has not added any video diaries."
                )
                .font(.system(size: 14 * xScale, weight: .regular))
                .foregroundStyle(.black.opacity(0.42))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .offset(y: -5 * yScale)
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

private struct HomeNoVideosEmptyStateLogo: View {
    let size: CGFloat

    var body: some View {
        Image("NoVideosEmptyStateLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct HomeAlbumHeader: View {
    let diaries: [VideoDiary]
    let albums: [VideoAlbum]
    let selectedAlbumID: VideoAlbum.ID?
    let hiddenAlbumID: VideoAlbum.ID?
    let screenWidth: CGFloat
    let xScale: CGFloat
    let yScale: CGFloat
    let onAddAlbum: () -> Void
    let onSelectAlbum: (VideoAlbum.ID) -> Void
    let onLongPressAlbum: (VideoAlbum.ID) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            GalleryAlbumBackdrop(height: 244 * yScale)
                .frame(width: screenWidth, height: 244 * yScale)

            GallerySectionTitle(albums.isEmpty ? "Add your first album" : "Albums", xScale: xScale)
                .offset(x: 19 * xScale, y: 76 * yScale)

            GalleryAlbumStrip(
                diaries: diaries,
                albums: albums,
                selectedAlbumID: selectedAlbumID,
                hiddenAlbumID: hiddenAlbumID,
                xScale: xScale,
                onAddAlbum: onAddAlbum,
                onSelectAlbum: onSelectAlbum,
                onLongPressAlbum: onLongPressAlbum
            )
            .frame(width: screenWidth, height: 92 * xScale)
            .offset(y: 147 * yScale)
        }
        .frame(width: screenWidth, height: 244 * yScale, alignment: .topLeading)
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

private struct LiquidGlassDisplayModeToggle: View {
    @Binding var selection: ViewModeSelection
    let xScale: CGFloat

    private let widthBase: CGFloat = 100
    private let heightBase: CGFloat = 44
    private let horizontalInsetBase: CGFloat = 4
    private let selectionHeightBase: CGFloat = 36

    var body: some View {
        let width = widthBase * xScale
        let height = heightBase * xScale
        let horizontalInset = horizontalInsetBase * xScale
        let buttonWidth = (width - horizontalInset * 2) / 2
        let selectionWidth = buttonWidth
        let selectionHeight = selectionHeightBase * xScale
        let selectionCenterX = horizontalInset
            + buttonWidth * (selection == .timeline ? 0.5 : 1.5)

        ZStack(alignment: .topLeading) {
            LiquidGlassContainer(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(.clear)
                        .frame(width: width, height: height)
                        .vimemberInteractiveGlass(in: Capsule())

                    Capsule()
                        .fill(.clear)
                        .frame(width: selectionWidth, height: selectionHeight)
                        .vimemberRegularGlass(in: Capsule())
                        .position(x: selectionCenterX, y: height / 2)
                        .animation(.snappy(duration: 0.24), value: selection)
                        .allowsHitTesting(false)
                }
                .frame(width: width, height: height)
            }
            .allowsHitTesting(false)

            HStack(spacing: 0) {
                modeButton(systemName: "rectangle.portrait.fill", mode: .timeline)
                .frame(width: buttonWidth, height: height)

                modeButton(systemName: "square.grid.3x3.fill", mode: .gallery)
                .frame(width: buttonWidth, height: height)
            }
            .padding(.horizontal, horizontalInset)
            .zIndex(2)
        }
        .frame(width: width, height: height)
        .contentShape(Capsule())
    }

    private func modeButton(systemName: String, mode: ViewModeSelection) -> some View {
        let isSelected = selection == mode

        return Button {
            withAnimation(.snappy(duration: 0.24)) {
                selection = mode
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15.5 * xScale, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .animation(.snappy(duration: 0.18), value: isSelected)
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
            width: width,
            colorSamplingPolicy: .preferDerivedAssetCache
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
        let label = TopAlignedUILabel()
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

private final class TopAlignedUILabel: UILabel {
    override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let textRect = super.textRect(forBounds: bounds, limitedToNumberOfLines: numberOfLines)
        return CGRect(
            x: textRect.minX,
            y: bounds.minY,
            width: textRect.width,
            height: textRect.height
        )
    }

    override func drawText(in rect: CGRect) {
        let textRect = self.textRect(forBounds: rect, limitedToNumberOfLines: numberOfLines)
        super.drawText(in: textRect)
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

private struct HomeCollapsedAddAlbumVisual: View {
    let xScale: CGFloat

    var body: some View {
        ZStack {
            MorphingAlbumCardShell(
                width: 70 * xScale,
                height: 70 * xScale,
                cornerRadius: 10 * xScale,
                overlayColor: .white.opacity(0.58),
                shadowRadius: 10 * xScale,
                shadowYOffset: 1 * xScale
            )

            Image(systemName: "plus")
                .font(.system(size: 16 * xScale, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.28))
        }
        .frame(width: 70 * xScale, height: 70 * xScale)
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
        let visibleGap = isSearchVisible ? gap : 0

        HStack(spacing: visibleGap) {
            if isSearchVisible {
                ZStack {
                    Capsule()
                        .fill(.clear)
                        .frame(width: searchWidth, height: height)
                        .vimemberInteractiveGlass(in: Capsule())
                        .allowsHitTesting(false)

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

            LiquidGlassAddButton(size: addButtonSize, action: addAction)
        }
        .frame(width: width, height: max(height, addButtonSize))
    }
}

private struct LiquidGlassAddButton: View {
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: max(20, size * 0.44), weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .contentShape(Circle())
                .vimemberInteractiveGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add video diary")
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

private struct HomeContentTitleFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect?

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}
