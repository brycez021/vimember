import AVFoundation
import Photos
import QuickLookThumbnailing
import SwiftUI
import UIKit

struct GalleryView: View {
    let diaries: [VideoDiary]
    let albums: [VideoAlbum]
    let onSelectDiary: (VideoDiary) -> Void
    let onCreateAlbum: (_ name: String, _ diaryIDs: [VideoDiary.ID], _ coverImageData: Data?) -> Void

    @State private var isAddAlbumComposerPresented = false
    @State private var isAddAlbumComposerContentVisible = false
    @State private var isAlbumVideoPickerPresented = false
    @State private var isAlbumCoverPickerPresented = false
    @State private var draftAlbumName = ""
    @State private var selectedAlbumDiaryIDs: [VideoDiary.ID] = []
    @State private var draftAlbumCoverImageData: Data?
    @State private var addAlbumButtonFrame: CGRect?

    var body: some View {
        GeometryReader { _ in
            let screenSize = UIScreen.main.bounds.size
            let screenWidth = screenSize.width
            let screenHeight = screenSize.height
            let xScale = screenWidth / 420
            let yScale = screenHeight / 912
            let gridGap = 3 * xScale
            let cardWidth = (screenWidth - gridGap * 2) / 3
            let cardHeight = cardWidth * (184 / 138)
            let albumComposerTop = 121 * yScale
            let albumStripTop = 134 * yScale
            let albumHeaderHeight = 244 * yScale
            let videoGridTop = 287 * yScale
            let addAlbumFallbackCenter = CGPoint(x: 55 * xScale, y: albumStripTop + 35 * xScale)
            let addAlbumShellFrame = CGRect(
                x: 20 * xScale,
                y: albumComposerTop + 13 * yScale,
                width: 380 * xScale,
                height: 416 * yScale
            )
            let addAlbumContentFrame = CGRect(
                x: 20 * xScale,
                y: albumComposerTop + 5 * yScale,
                width: 380 * xScale,
                height: 426 * yScale
            )
            let rowCount = max(1, Int(ceil(Double(diaries.count) / 3.0)))
            let contentHeight = max(
                screenHeight + 1,
                videoGridTop + CGFloat(rowCount) * cardHeight + CGFloat(max(0, rowCount - 1)) * gridGap + 28 * yScale
            )

            ZStack(alignment: .topLeading) {
                Color(red: 0.996, green: 0.996, blue: 0.996)
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        GalleryAlbumBackdrop(height: albumHeaderHeight)
                            .frame(width: screenWidth, height: albumHeaderHeight)

                        GallerySectionTitle("Albums", xScale: xScale)
                            .offset(x: 19 * xScale, y: 76 * yScale)

                        GalleryAlbumStrip(
                            diaries: diaries,
                            albums: albums,
                            selectedAlbumID: nil,
                            xScale: xScale,
                            onAddAlbum: {
                                showAddAlbumComposer()
                            },
                            onSelectAlbum: { _ in }
                        )
                            .frame(width: screenWidth, height: 92 * xScale)
                            .offset(y: albumStripTop)

                        GallerySectionTitle("All Videos", xScale: xScale)
                            .offset(x: 20 * xScale, y: 251 * yScale)

                        LazyVGrid(
                            columns: [
                                GridItem(.fixed(cardWidth), spacing: gridGap),
                                GridItem(.fixed(cardWidth), spacing: gridGap),
                                GridItem(.fixed(cardWidth), spacing: 0)
                            ],
                            alignment: .leading,
                            spacing: gridGap
                        ) {
                            ForEach(Array(diaries.enumerated()), id: \.element.id) { index, diary in
                                GalleryVideoCard(
                                    diary: diary,
                                    width: cardWidth,
                                    height: cardHeight,
                                    column: index % 3,
                                    onTap: {
                                        onSelectDiary(diary)
                                    }
                                )
                            }
                        }
                        .frame(width: screenWidth, alignment: .leading)
                        .offset(y: videoGridTop)
                    }
                    .frame(width: screenWidth, height: contentHeight, alignment: .topLeading)
                }

                GalleryTopPlaceholderButton(size: 44 * xScale)
                    .position(
                        x: screenWidth - 20 * xScale - 22 * xScale,
                        y: 68 * yScale + 22 * xScale
                    )
                    .allowsHitTesting(false)

                GalleryAlbumAddMorphOverlay(
                    name: $draftAlbumName,
                    coverImageData: draftAlbumCoverImageData,
                    coverDiary: nil,
                    collapsedAlbumCoverImageData: nil,
                    collapsedAlbumCoverDiary: nil,
                    title: "New Album",
                    leadingAction: .close,
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
                    onPickCover: {
                        showAlbumCoverPicker()
                    },
                    onNext: {
                        showAlbumVideoPicker()
                    },
                    onDelete: {
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
                                isAddAlbumComposerPresented = true
                                isAddAlbumComposerContentVisible = false
                            }
                            revealAddAlbumComposerContent()
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
            .frame(width: screenWidth, height: screenHeight)
            .coordinateSpace(name: GalleryAddAlbumMorphCoordinateSpace.name)
            .onPreferenceChange(GalleryAddAlbumFramePreferenceKey.self) { frame in
                addAlbumButtonFrame = frame
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .animation(.snappy(duration: 0.32), value: isAddAlbumComposerPresented)
        .animation(.snappy(duration: 0.24), value: isAlbumVideoPickerPresented)
        .animation(.snappy(duration: 0.24), value: isAlbumCoverPickerPresented)
    }

    private func showAddAlbumComposer() {
        draftAlbumName = ""
        selectedAlbumDiaryIDs = []
        draftAlbumCoverImageData = nil
        withAnimation(.snappy(duration: 0.32)) {
            isAddAlbumComposerContentVisible = false
            isAddAlbumComposerPresented = true
            isAlbumVideoPickerPresented = false
            isAlbumCoverPickerPresented = false
        }
        revealAddAlbumComposerContent()
    }

    private func showAlbumVideoPicker() {
        withAnimation(.snappy(duration: 0.28)) {
            isAddAlbumComposerContentVisible = false
            isAddAlbumComposerPresented = false
            isAlbumCoverPickerPresented = false
            isAlbumVideoPickerPresented = true
        }
    }

    private func showAlbumCoverPicker() {
        withAnimation(.snappy(duration: 0.24)) {
            isAlbumCoverPickerPresented = true
        }
    }

    private func closeAlbumCoverPicker() {
        withAnimation(.snappy(duration: 0.24)) {
            isAlbumCoverPickerPresented = false
        }
    }

    private func closeAddAlbumFlow() {
        withAnimation(.snappy(duration: 0.24)) {
            isAddAlbumComposerContentVisible = false
            isAddAlbumComposerPresented = false
            isAlbumVideoPickerPresented = false
            isAlbumCoverPickerPresented = false
        }
        draftAlbumName = ""
        selectedAlbumDiaryIDs = []
        draftAlbumCoverImageData = nil
    }

    private func revealAddAlbumComposerContent() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard isAddAlbumComposerPresented else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                isAddAlbumComposerContentVisible = true
            }
        }
    }

    private func saveAlbum() {
        Task {
            await saveAlbumWithResolvedCover()
        }
    }

    @MainActor
    private func saveAlbumWithResolvedCover() async {
        guard !selectedAlbumDiaryIDs.isEmpty else {
            return
        }

        let coverImageData: Data?
        if let draftAlbumCoverImageData {
            coverImageData = draftAlbumCoverImageData
        } else {
            coverImageData = await automaticCoverImageData()
        }

        onCreateAlbum(draftAlbumName, selectedAlbumDiaryIDs, coverImageData)
        closeAddAlbumFlow()
    }

    @MainActor
    private func automaticCoverImageData() async -> Data? {
        guard
            let firstDiaryID = selectedAlbumDiaryIDs.first,
            let diary = diaries.first(where: { $0.id == firstDiaryID }),
            let url = diary.videoURL
        else {
            return nil
        }

        return try? await AlbumCoverImageRenderer.coverImageData(forVideoAt: url)
    }
}

struct GalleryAlbumBackdrop: View {
    let height: CGFloat

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: .white.opacity(0.96), location: 0.52),
                .init(color: Color(red: 0.941, green: 0.941, blue: 0.941), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
    }
}

struct GallerySectionTitle: View {
    let title: String
    let xScale: CGFloat

    init(_ title: String, xScale: CGFloat) {
        self.title = title
        self.xScale = xScale
    }

    var body: some View {
        Text(title)
            .font(.system(size: 24 * xScale, weight: .semibold))
            .tracking(24 * xScale * 0.01)
            .foregroundStyle(.black)
            .fixedSize()
    }
}

struct CalligraphSectionTitle: View {
    let title: String
    let xScale: CGFloat

    @State private var renderedTitle: String
    @State private var characters: [CalligraphCharacterItem]
    @State private var nextCharacterID: Int

    init(_ title: String, xScale: CGFloat) {
        self.title = title
        self.xScale = xScale

        let initialCharacters = Array(title).enumerated().map { index, character in
            CalligraphCharacterItem(
                id: index,
                character: character,
                driftX: Self.driftOffsetX(index: index, count: title.count, changeRatio: 1, xScale: xScale)
            )
        }

        _renderedTitle = State(initialValue: title)
        _characters = State(initialValue: initialCharacters)
        _nextCharacterID = State(initialValue: initialCharacters.count)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: letterSpacing) {
            ForEach(characters) { item in
                Text(verbatim: String(item.character))
                    .fixedSize()
                    .transition(characterTransition(for: item))
            }
        }
        .font(.system(size: 24 * xScale, weight: .semibold))
        .foregroundStyle(.black)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .onAppear {
            guard renderedTitle != title else { return }
            updateTitle(title, animated: false)
        }
        .onChange(of: title) { _, newTitle in
            updateTitle(newTitle, animated: true)
        }
    }

    private var letterSpacing: CGFloat {
        24 * xScale * 0.01
    }

    private func updateTitle(_ newTitle: String, animated: Bool) {
        let oldCharacters = Array(renderedTitle)
        let newCharacters = Array(newTitle)
        let result = Self.reconcileCharacters(
            oldCharacters: oldCharacters,
            oldItems: characters,
            newCharacters: newCharacters,
            nextID: nextCharacterID,
            xScale: xScale
        )

        renderedTitle = newTitle
        nextCharacterID = result.nextID

        if animated {
            withAnimation(Self.textAnimation) {
                characters = result.items
            }
        } else {
            characters = result.items
        }
    }

    private func characterTransition(for item: CalligraphCharacterItem) -> AnyTransition {
        let insertionActive = CalligraphCharacterTransitionModifier(
            opacity: 0.35,
            blurRadius: 0.25 * xScale,
            scale: 0.985,
            offsetX: item.driftX
        )
        let removalActive = CalligraphCharacterTransitionModifier(
            opacity: 0,
            blurRadius: 0,
            scale: 1,
            offsetX: 0
        )
        let identity = CalligraphCharacterTransitionModifier(
            opacity: 1,
            blurRadius: 0,
            scale: 1,
            offsetX: 0
        )

        return .asymmetric(
            insertion: .modifier(active: insertionActive, identity: identity),
            removal: .modifier(active: removalActive, identity: identity)
        )
    }

    private static var textAnimation: Animation {
        .timingCurve(0.19, 1, 0.22, 1, duration: 0.38)
    }

    private static func reconcileCharacters(
        oldCharacters: [Character],
        oldItems: [CalligraphCharacterItem],
        newCharacters: [Character],
        nextID: Int,
        xScale: CGFloat
    ) -> (items: [CalligraphCharacterItem], nextID: Int) {
        let matches = longestCommonSubsequencePairs(oldCharacters, newCharacters)
        var matchedOldIDsByNewIndex: [Int: Int] = [:]

        for (oldIndex, newIndex) in matches {
            guard oldItems.indices.contains(oldIndex) else { continue }
            matchedOldIDsByNewIndex[newIndex] = oldItems[oldIndex].id
        }

        let newCount = newCharacters.count - matchedOldIDsByNewIndex.count
        let removedCount = oldCharacters.count - matchedOldIDsByNewIndex.count
        let maxLength = max(oldCharacters.count, newCharacters.count)
        let rawChangeRatio = maxLength > 0 ? CGFloat(newCount + removedCount) / CGFloat(maxLength) : 1
        let changeRatio = min(rawChangeRatio, 1.4)

        var nextID = nextID
        let items = newCharacters.enumerated().map { index, character in
            let id = matchedOldIDsByNewIndex[index] ?? {
                defer { nextID += 1 }
                return nextID
            }()

            return CalligraphCharacterItem(
                id: id,
                character: character,
                driftX: driftOffsetX(index: index, count: newCharacters.count, changeRatio: changeRatio, xScale: xScale)
            )
        }

        return (items, nextID)
    }

    private static func longestCommonSubsequencePairs(
        _ oldCharacters: [Character],
        _ newCharacters: [Character]
    ) -> [(oldIndex: Int, newIndex: Int)] {
        let oldCount = oldCharacters.count
        let newCount = newCharacters.count
        guard oldCount > 0, newCount > 0 else { return [] }

        var lengths = Array(
            repeating: Array(repeating: 0, count: newCount + 1),
            count: oldCount + 1
        )

        for oldIndex in 1...oldCount {
            for newIndex in 1...newCount {
                if oldCharacters[oldIndex - 1] == newCharacters[newIndex - 1] {
                    lengths[oldIndex][newIndex] = lengths[oldIndex - 1][newIndex - 1] + 1
                } else {
                    lengths[oldIndex][newIndex] = max(
                        lengths[oldIndex - 1][newIndex],
                        lengths[oldIndex][newIndex - 1]
                    )
                }
            }
        }

        var pairs: [(oldIndex: Int, newIndex: Int)] = []
        var oldIndex = oldCount
        var newIndex = newCount

        while oldIndex > 0, newIndex > 0 {
            if oldCharacters[oldIndex - 1] == newCharacters[newIndex - 1] {
                pairs.append((oldIndex - 1, newIndex - 1))
                oldIndex -= 1
                newIndex -= 1
            } else if lengths[oldIndex - 1][newIndex] > lengths[oldIndex][newIndex - 1]
                || (lengths[oldIndex - 1][newIndex] == lengths[oldIndex][newIndex - 1] && oldIndex >= newIndex) {
                oldIndex -= 1
            } else {
                newIndex -= 1
            }
        }

        return pairs.reversed()
    }

    private static func driftOffsetX(index: Int, count: Int, changeRatio: CGFloat, xScale: CGFloat) -> CGFloat {
        guard count > 1 else { return 0 }

        let progress = CGFloat(index) / CGFloat(count - 1)
        return (progress - 0.5) * 8 * xScale * changeRatio
    }
}

private struct CalligraphCharacterItem: Identifiable, Equatable {
    let id: Int
    let character: Character
    let driftX: CGFloat
}

private struct CalligraphCharacterTransitionModifier: ViewModifier {
    let opacity: Double
    let blurRadius: CGFloat
    let scale: CGFloat
    let offsetX: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .blur(radius: blurRadius)
            .scaleEffect(scale)
            .offset(x: offsetX)
    }
}

struct GalleryAlbumStrip: View {
    let diaries: [VideoDiary]
    let albums: [VideoAlbum]
    let selectedAlbumID: VideoAlbum.ID?
    var hiddenAlbumID: VideoAlbum.ID? = nil
    let xScale: CGFloat
    let onAddAlbum: () -> Void
    let onSelectAlbum: (VideoAlbum.ID) -> Void
    var onLongPressAlbum: (VideoAlbum.ID) -> Void = { _ in }

    private var albumItems: [GalleryAlbumDisplayItem] {
        albums.map { album -> GalleryAlbumDisplayItem in
            let coverDiary = album.coverDiaryID.flatMap { coverID in
                diaries.first { $0.id == coverID }
            } ?? album.diaryIDs.compactMap { diaryID in
                diaries.first { $0.id == diaryID }
            }.first

            return GalleryAlbumDisplayItem(
                id: "album-\(album.id.uuidString)",
                albumID: album.id,
                title: album.name,
                coverImageData: album.coverImageData,
                coverDiary: coverDiary
            )
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 17 * xScale) {
                GalleryAddAlbumPlaceholder(
                    size: 70 * xScale,
                    action: onAddAlbum
                )

                ForEach(albumItems) { item in
                    let isSelected = item.albumID == selectedAlbumID
                    let isDimmed = selectedAlbumID != nil && item.albumID != selectedAlbumID
                    let isHidden = item.albumID == hiddenAlbumID
                    GalleryAlbumItem(
                        title: item.title,
                        coverImageData: item.coverImageData,
                        coverDiary: item.coverDiary,
                        size: 70 * xScale,
                        isSelected: isSelected,
                        isDimmed: isDimmed,
                        action: {
                            guard let albumID = item.albumID else { return }
                            onSelectAlbum(albumID)
                        },
                        longPressAction: {
                            guard let albumID = item.albumID else { return }
                            onLongPressAlbum(albumID)
                        }
                    )
                    .opacity(isHidden ? 0 : 1)
                    .allowsHitTesting(!isHidden)
                    .background {
                        if let albumID = item.albumID {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: GalleryAlbumFramePreferenceKey.self,
                                    value: [albumID: proxy.frame(in: .named(GalleryAddAlbumMorphCoordinateSpace.name))]
                                )
                            }
                        }
                    }
                }
            }
            .padding(.leading, 20 * xScale)
            .padding(.trailing, 20 * xScale)
        }
        .scrollClipDisabled()
    }

}

private struct GalleryAlbumDisplayItem: Identifiable {
    let id: String
    let albumID: VideoAlbum.ID?
    let title: String
    let coverImageData: Data?
    let coverDiary: VideoDiary?
}

private struct GalleryAddAlbumPlaceholder: View {
    let size: CGFloat
    let action: () -> Void

    private var itemHeight: CGFloat {
        size * (118 / 70)
    }

    var body: some View {
        Button(action: action) {
            Color.clear
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add Album")
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: GalleryAddAlbumFramePreferenceKey.self,
                    value: proxy.frame(in: .named(GalleryAddAlbumMorphCoordinateSpace.name))
                )
            }
        }
        .frame(width: size, height: itemHeight, alignment: .top)
    }
}

enum GalleryAddAlbumMorphCoordinateSpace {
    static let name = "gallery-add-album-morph-space"
}

struct GalleryAddAlbumFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect?

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

struct MorphingAlbumCardShell: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let overlayColor: Color
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        LiquidGlassContainer(spacing: 0) {
            LiquidGlassRoundedSurface(
                width: width,
                height: height,
                cornerRadius: cornerRadius,
                xScale: max(width / 380, 0.1),
                shadowRadius: 0,
                shadowYOffset: 0
            )
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.14), radius: shadowRadius, y: shadowYOffset)
    }
}

private struct GalleryAlbumItem: View {
    let title: String
    let coverImageData: Data?
    let coverDiary: VideoDiary?
    let size: CGFloat
    let isSelected: Bool
    let isDimmed: Bool
    let action: () -> Void
    let longPressAction: () -> Void

    private var coverSize: CGFloat {
        size * (66 / 70)
    }

    private var outerCornerRadius: CGFloat {
        size * (10 / 70)
    }

    private var coverCornerRadius: CGFloat {
        size * (8 / 70)
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                                .fill(Color.white.opacity(0.46))
                                .blendMode(.plusLighter)
                        )
                        .frame(width: size, height: size)
                        .shadow(color: .black.opacity(0.08), radius: 10 * (size / 70), y: 2 * (size / 70))

                    if let coverImageData, let image = UIImage(data: coverImageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: coverSize, height: coverSize)
                            .saturation(isDimmed ? 0.58 : 1)
                            .opacity(isDimmed ? 0.78 : 1)
                            .clipShape(RoundedRectangle(cornerRadius: coverCornerRadius, style: .continuous))
                    } else if let coverDiary {
                        GalleryThumbnailView(
                            url: coverDiary.videoURL,
                            fallbackTint: coverDiary.fallbackTint,
                            targetSize: CGSize(width: coverSize * 2, height: coverSize * 2)
                        )
                        .frame(width: coverSize, height: coverSize)
                        .saturation(isDimmed ? 0.58 : 1)
                        .opacity(isDimmed ? 0.78 : 1)
                        .blur(radius: 0)
                        .clipShape(RoundedRectangle(cornerRadius: coverCornerRadius, style: .continuous))
                    } else {
                        GalleryEmptyAlbumCover(
                            size: coverSize,
                            cornerRadius: coverCornerRadius,
                            isDimmed: isDimmed
                        )
                    }

                    if isDimmed {
                        RoundedRectangle(cornerRadius: coverCornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.16))
                            .frame(width: coverSize, height: coverSize)
                    }

                    if isSelected {
                        RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                            .stroke(Color(red: 0.36, green: 0.62, blue: 1).opacity(0.95), lineWidth: max(1.5, size * (2 / 70)))
                            .frame(width: size, height: size)
                    }
                }
                .frame(width: size, height: size)

                Text(title)
                    .font(.system(size: size * (14 / 70), weight: .regular))
                    .tracking(size * (0.14 / 70))
                    .foregroundStyle(isDimmed ? Color(white: 0.46) : Color(white: 0.24))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: size * (67 / 70), height: size * (22 / 70), alignment: .top)
                    .frame(width: size, height: size * (22 / 70), alignment: .top)
                    .offset(y: size * (2.0 / 70))
            }
            .frame(width: size, height: size * (92 / 70), alignment: .top)

        }
        .frame(width: size, height: size * (118 / 70), alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onLongPressGesture(minimumDuration: 0.30, maximumDistance: 22, perform: longPressAction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityAddTraits(.isButton)
    }
}

private struct GalleryEmptyAlbumCover: View {
    let size: CGFloat
    let cornerRadius: CGFloat
    let isDimmed: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(white: isDimmed ? 0.86 : 0.90))
            .overlay {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: size * 0.28, weight: .regular))
                    .foregroundStyle(Color(white: isDimmed ? 0.60 : 0.48))
            }
            .frame(width: size, height: size)
            .opacity(isDimmed ? 0.78 : 1)
    }
}

struct GallerySelectedAlbumPointer: Shape {
    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 30
        let scaleY = rect.height / 26
        let shapeTop: CGFloat = 26 * 0.0781

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + x * scaleX,
                y: rect.minY + (shapeTop + y) * scaleY
            )
        }

        var path = Path()

        path.move(to: point(8.65168, 9.95343))
        path.addLine(to: point(13.7635, 1.00772))
        path.addCurve(
            to: point(17.2365, 1.00772),
            control1: point(14.5313, -0.335907),
            control2: point(16.4687, -0.335907)
        )
        path.addLine(to: point(22.3483, 9.95343))
        path.addCurve(
            to: point(25.8213, 11.9689),
            control1: point(23.0605, 11.1997),
            control2: point(24.3859, 11.9689)
        )
        path.addLine(to: point(30, 11.9689))
        path.addLine(to: point(30, 23.9689))
        path.addLine(to: point(0, 23.9689))
        path.addLine(to: point(0, 11.9689))
        path.addLine(to: point(5.17871, 11.9689))
        path.addCurve(
            to: point(8.65168, 9.95343),
            control1: point(6.61414, 11.9689),
            control2: point(7.93951, 11.1997)
        )
        path.closeSubpath()
        return path
    }
}

struct GalleryAlbumFramePreferenceKey: PreferenceKey {
    static var defaultValue: [VideoAlbum.ID: CGRect] = [:]

    static func reduce(value: inout [VideoAlbum.ID: CGRect], nextValue: () -> [VideoAlbum.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

enum GalleryAlbumComposerLeadingAction: Equatable {
    case close
    case delete
}

struct GalleryAlbumAddMorphOverlay: View {
    @Binding var name: String
    let coverImageData: Data?
    let coverDiary: VideoDiary?
    let collapsedAlbumCoverImageData: Data?
    let collapsedAlbumCoverDiary: VideoDiary?
    let title: String
    let leadingAction: GalleryAlbumComposerLeadingAction
    let isExpanded: Bool
    let contentOpacity: Double
    let collapsedFrame: CGRect?
    let fallbackCollapsedCenter: CGPoint
    let expandedShellFrame: CGRect
    let expandedContentFrame: CGRect
    let xScale: CGFloat
    let yScale: CGFloat
    let onClose: () -> Void
    let onPickCover: () -> Void
    let onNext: () -> Void
    let onDelete: () -> Void

    private var collapsedCenter: CGPoint {
        guard let collapsedFrame else {
            return fallbackCollapsedCenter
        }

        return CGPoint(x: collapsedFrame.midX, y: collapsedFrame.midY)
    }

    private var shellCenter: CGPoint {
        isExpanded
            ? CGPoint(x: expandedShellFrame.midX, y: expandedShellFrame.midY)
            : collapsedCenter
    }

    private var shellWidth: CGFloat {
        isExpanded ? expandedShellFrame.width : 70 * xScale
    }

    private var shellHeight: CGFloat {
        isExpanded ? expandedShellFrame.height : 70 * xScale
    }

    private var shellCornerRadius: CGFloat {
        10 * xScale
    }

    private var shellOverlayColor: Color {
        isExpanded
            ? Color(red: 0.966, green: 0.964, blue: 0.982).opacity(0.72)
            : .white.opacity(0.58)
    }

    private var shellShadowRadius: CGFloat {
        isExpanded ? 36 * xScale : 10 * xScale
    }

    private var shellShadowYOffset: CGFloat {
        isExpanded ? 13 * yScale : 1 * xScale
    }

    private var collapsedCoverSize: CGFloat {
        66 * xScale
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            MorphingAlbumCardShell(
                width: shellWidth,
                height: shellHeight,
                cornerRadius: shellCornerRadius,
                overlayColor: shellOverlayColor,
                shadowRadius: shellShadowRadius,
                shadowYOffset: shellShadowYOffset
            )
            .position(shellCenter)
            .allowsHitTesting(false)

            if let collapsedAlbumCoverImageData,
               let image = UIImage(data: collapsedAlbumCoverImageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: collapsedCoverSize, height: collapsedCoverSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8 * xScale, style: .continuous))
                    .position(collapsedCenter)
                    .opacity(isExpanded ? 0 : 1)
                    .allowsHitTesting(false)
            } else if let collapsedAlbumCoverDiary {
                GalleryThumbnailView(
                    url: collapsedAlbumCoverDiary.videoURL,
                    fallbackTint: collapsedAlbumCoverDiary.fallbackTint,
                    targetSize: CGSize(width: collapsedCoverSize * 2, height: collapsedCoverSize * 2)
                )
                .frame(width: collapsedCoverSize, height: collapsedCoverSize)
                .clipShape(RoundedRectangle(cornerRadius: 8 * xScale, style: .continuous))
                .position(collapsedCenter)
                .opacity(isExpanded ? 0 : 1)
                .allowsHitTesting(false)
            } else if leadingAction == .delete {
                GalleryEmptyAlbumCover(
                    size: collapsedCoverSize,
                    cornerRadius: 8 * xScale,
                    isDimmed: false
                )
                .position(collapsedCenter)
                .opacity(isExpanded ? 0 : 1)
                .allowsHitTesting(false)
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 16 * xScale, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.28))
                    .position(collapsedCenter)
                    .opacity(isExpanded ? 0 : 1)
                    .allowsHitTesting(false)
            }

            GalleryAddAlbumComposerContent(
                name: $name,
                coverImageData: coverImageData,
                coverDiary: coverDiary,
                title: title,
                leadingAction: leadingAction,
                xScale: xScale,
                yScale: yScale,
                onClose: onClose,
                onPickCover: onPickCover,
                onNext: onNext,
                onDelete: onDelete
            )
            .frame(width: expandedContentFrame.width, height: expandedContentFrame.height, alignment: .topLeading)
            .position(x: expandedContentFrame.midX, y: expandedContentFrame.midY)
            .opacity(contentOpacity)
            .allowsHitTesting(isExpanded && contentOpacity > 0.5)
        }
    }
}

struct GalleryAddAlbumComposerContent: View {
    @Binding var name: String
    let coverImageData: Data?
    let coverDiary: VideoDiary?
    let title: String
    let leadingAction: GalleryAlbumComposerLeadingAction
    let xScale: CGFloat
    let yScale: CGFloat
    let onClose: () -> Void
    let onPickCover: () -> Void
    let onNext: () -> Void
    let onDelete: () -> Void
    @FocusState private var isNameFocused: Bool

    var body: some View {
        let cardWidth = 380 * xScale
        let cardHeight = 426 * yScale
        let closeSize = 40 * xScale
        let saveWidth = 71 * xScale
        let saveHeight = 40 * xScale
        let coverSize = 200 * xScale
        let coverCornerRadius = 30 * xScale
        let coverShape = RoundedRectangle(cornerRadius: coverCornerRadius, style: .continuous)
        let inputWidth = 310 * xScale
        let inputHeight = 50 * xScale

        ZStack(alignment: .topLeading) {
            switch leadingAction {
            case .close:
                GalleryGlassCircleActionButton(
                    systemName: "xmark",
                    size: closeSize,
                    symbolSize: 17 * xScale,
                    action: onClose
                )
                .position(x: 35 * xScale, y: 43 * yScale)
            case .delete:
                GalleryGlassCircleActionButton(
                    systemName: "trash",
                    size: closeSize,
                    symbolSize: 16 * xScale,
                    foregroundColor: Color(red: 1, green: 0.231, blue: 0.188),
                    action: onDelete
                )
                .position(x: 35 * xScale, y: 43 * yScale)
            }

            Text(title)
                .font(.system(size: 20 * xScale, weight: .medium))
                .tracking(0.2 * xScale)
                .foregroundStyle(.black)
                .frame(width: cardWidth, height: 24 * yScale)
                .position(x: cardWidth / 2, y: 41 * yScale)

            GalleryGlassPillActionButton(
                title: "Save",
                width: saveWidth,
                height: saveHeight,
                backgroundColor: Color(red: 0, green: 0.478, blue: 1),
                foregroundColor: .white,
                isEnabled: true,
                action: {
                    isNameFocused = false
                    onNext()
                }
            )
            .position(x: 329.5 * xScale, y: 43 * yScale)

            Button(action: onPickCover) {
                ZStack {
                    coverShape
                        .fill(Color(red: 0.855, green: 0.852, blue: 0.874))

                    if let coverImageData, let image = UIImage(data: coverImageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: coverSize, height: coverSize)
                            .clipShape(coverShape)
                    } else if let coverDiary {
                        GalleryThumbnailView(
                            url: coverDiary.videoURL,
                            fallbackTint: coverDiary.fallbackTint,
                            targetSize: CGSize(width: coverSize * 2, height: coverSize * 2)
                        )
                        .frame(width: coverSize, height: coverSize)
                        .clipShape(coverShape)
                    } else {
                        Text("Add Cover")
                            .font(.system(size: 16 * xScale, weight: .medium))
                            .tracking(0.16 * xScale)
                            .foregroundStyle(Color(red: 0, green: 0.478, blue: 1))
                            .frame(width: coverSize, alignment: .center)
                            .offset(y: -0.5 * yScale)
                    }
                }
                .frame(width: coverSize, height: coverSize)
                .contentShape(coverShape)
            }
            .buttonStyle(.plain)
            .position(x: (90 + 100) * xScale, y: (103 + 100) * yScale)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white)

                TextField(
                    "",
                    text: $name,
                    prompt: Text("Add Name")
                        .foregroundStyle(Color(red: 0, green: 0.478, blue: 1))
                )
                .font(.system(size: 16 * xScale, weight: .medium))
                .tracking(0.16 * xScale)
                .foregroundStyle(.black)
                .tint(Color(red: 0, green: 0.478, blue: 1))
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($isNameFocused)
                .onSubmit {
                    isNameFocused = false
                }
                .padding(.leading, 20 * xScale)
                .padding(.trailing, 28 * xScale)
                .frame(width: inputWidth, height: inputHeight, alignment: .leading)
                .offset(y: -0.5 * yScale)
            }
            .frame(width: inputWidth, height: inputHeight)
            .position(x: (35 + 155) * xScale, y: (337 + 25 + 1) * yScale)
        }
        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
    }
}

struct GalleryAlbumCoverPicker: View {
    @StateObject private var viewModel = AlbumCoverSelectionViewModel()
    @State private var selectedItem: PhotoLibraryCoverItem?
    @State private var isPreparingCover = false
    @State private var coverError: String?

    let onBack: () -> Void
    let onSelectCover: (Data) -> Void

    var body: some View {
        AlbumCoverSelectionPage(
            viewModel: viewModel,
            selectedItem: $selectedItem,
            isPreparingCover: isPreparingCover,
            onCancel: onBack,
            onNext: {
                Task {
                    await prepareCover()
                }
            }
        )
        .overlay(alignment: .bottom) {
            if let coverError {
                Text(coverError)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.72), in: Capsule())
                    .padding(.bottom, 26)
                    .transition(.opacity)
            }
        }
        .task {
            await viewModel.load()
        }
    }

    @MainActor
    private func prepareCover() async {
        guard let selectedItem else { return }
        isPreparingCover = true
        coverError = nil

        do {
            let imageData = try await viewModel.coverImageData(for: selectedItem)
            onSelectCover(imageData)
        } catch {
            coverError = "Unable to load this cover."
        }

        isPreparingCover = false
    }
}

struct PhotoLibraryCoverItem: Identifiable, Equatable {
    let asset: PHAsset

    static func == (lhs: PhotoLibraryCoverItem, rhs: PhotoLibraryCoverItem) -> Bool {
        lhs.id == rhs.id
    }

    var id: String {
        asset.localIdentifier
    }

    var isVideo: Bool {
        asset.mediaType == .video
    }
}

@MainActor
final class AlbumCoverSelectionViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case ready
        case denied
        case empty
        case failed
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var items: [PhotoLibraryCoverItem] = []

    private let imageManager = PHCachingImageManager()

    func load() async {
        state = .loading
        items = []

        let status = await requestAuthorizationIfNeeded()
        guard status == .authorized || status == .limited else {
            state = .denied
            return
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue),
            NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        ])

        let result = PHAsset.fetchAssets(with: options)
        var nextItems: [PhotoLibraryCoverItem] = []
        result.enumerateObjects { asset, _, _ in
            nextItems.append(PhotoLibraryCoverItem(asset: asset))
        }

        items = nextItems
        state = nextItems.isEmpty ? .empty : .ready
    }

    func coverImageData(for item: PhotoLibraryCoverItem) async throws -> Data {
        if item.isVideo {
            return try await videoCoverImageData(for: item)
        }

        let image = try await photoCoverImage(for: item)
        return try AlbumCoverImageRenderer.coverImageData(from: image)
    }

    private func photoCoverImage(for item: PhotoLibraryCoverItem) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true

            imageManager.requestImageDataAndOrientation(for: item.asset, options: options) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data, let image = UIImage(data: data) else {
                    continuation.resume(throwing: AlbumCoverSelectionError.unavailableAsset)
                    return
                }

                continuation.resume(returning: image)
            }
        }
    }

    private func videoCoverImageData(for item: PhotoLibraryCoverItem) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            imageManager.requestAVAsset(forVideo: item.asset, options: options) { asset, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let asset else {
                    continuation.resume(throwing: AlbumCoverSelectionError.unavailableAsset)
                    return
                }

                Task {
                    do {
                        let imageData = try await AlbumCoverImageRenderer.coverImageData(from: asset)
                        continuation.resume(returning: imageData)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func requestAuthorizationIfNeeded() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .notDetermined else {
            return current
        }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

}

enum AlbumCoverImageRenderer {
    static func coverImageData(forVideoAt url: URL) async throws -> Data {
        let asset = AVURLAsset(url: url)
        return try await coverImageData(from: asset)
    }

    static func coverImageData(from asset: AVAsset) async throws -> Data {
        let image = try await videoCoverImage(from: asset)
        return try coverImageData(from: image)
    }

    static func coverImageData(from image: UIImage) throws -> Data {
        guard let imageData = image.albumCoverJPEGData() else {
            throw AlbumCoverSelectionError.unavailableAsset
        }

        return imageData
    }

    private static func videoCoverImage(from asset: AVAsset) async throws -> UIImage {
        let duration = (try? await asset.load(.duration)) ?? .zero
        let durationSeconds = CMTimeGetSeconds(duration)
        let upperBound = max(0, durationSeconds.isFinite ? durationSeconds - min(0.05, durationSeconds * 0.1) : 0)
        let seconds = upperBound > 0 ? min(0.8, upperBound) : 0

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.maximumSize = CGSize(width: 1200, height: 1200)

        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let result = try await generator.image(at: time)
        return UIImage(cgImage: result.image)
    }
}

private enum AlbumCoverSelectionError: Error {
    case unavailableAsset
}

private struct AlbumCoverSelectionPage: View {
    @ObservedObject var viewModel: AlbumCoverSelectionViewModel
    @Binding var selectedItem: PhotoLibraryCoverItem?
    let isPreparingCover: Bool
    let onCancel: () -> Void
    let onNext: () -> Void

    var body: some View {
        GeometryReader { _ in
            let realScreenSize = UIScreen.main.bounds.size
            let screenWidth = realScreenSize.width
            let screenHeight = realScreenSize.height
            let designWidth: CGFloat = 420
            let designHeight: CGFloat = 912
            let xScale = screenWidth / designWidth
            let yScale = screenHeight / designHeight
            let buttonSize = 44 * xScale
            let buttonTop = 52 * yScale + 16 * yScale
            let buttonCenterY = buttonTop + buttonSize / 2
            let gridItemSize = (screenWidth - 4) / 3

            ZStack(alignment: .topLeading) {
                Color.white.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(gridItemSize), spacing: 2), count: 3),
                        spacing: 2
                    ) {
                        ForEach(viewModel.items) { item in
                            AlbumCoverSelectionTile(
                                item: item,
                                isSelected: selectedItem?.id == item.id,
                                size: gridItemSize
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedItem = item
                            }
                        }
                    }
                    .padding(.top, 0)
                    .frame(width: screenWidth, alignment: .top)
                }

                if viewModel.state != .ready {
                    selectionStateView
                        .frame(width: screenWidth, height: screenHeight)
                }

                GalleryGlassCircleActionButton(
                    systemName: "chevron.left",
                    size: buttonSize,
                    symbolSize: 20 * xScale,
                    action: onCancel
                )
                .position(x: (20 * xScale) + buttonSize / 2, y: buttonCenterY)

                GalleryGlassCircleActionButton(
                    systemName: "checkmark",
                    size: buttonSize,
                    symbolSize: 20 * xScale,
                    isEnabled: selectedItem != nil && !isPreparingCover,
                    action: onNext
                )
                .position(x: screenWidth - (20 * xScale) - buttonSize / 2, y: buttonCenterY)

                if isPreparingCover {
                    ProgressView()
                        .tint(.white)
                        .frame(width: buttonSize, height: buttonSize)
                        .background(.black.opacity(0.18), in: Circle())
                        .position(x: screenWidth - (20 * xScale) - buttonSize / 2, y: buttonCenterY)
                }
            }
            .frame(width: screenWidth, height: screenHeight)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var selectionStateView: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .tint(.white)
        case .denied:
            Text("Photo access is needed to choose a cover.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.black.opacity(0.72))
                .padding(.horizontal, 30)
                .multilineTextAlignment(.center)
        case .empty:
            Text("No photos or videos found.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.black.opacity(0.72))
        case .failed:
            Text("Unable to load photos.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.black.opacity(0.72))
        case .ready:
            EmptyView()
        }
    }
}

private struct AlbumCoverSelectionTile: View {
    let item: PhotoLibraryCoverItem
    let isSelected: Bool
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AlbumCoverThumbnailView(
                asset: item.asset,
                size: size
            )

            if item.isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 20)
                    .background(.black.opacity(0.34), in: Capsule())
                    .padding(.leading, 8)
                    .padding(.bottom, 8)
                    .frame(width: size, height: size, alignment: .bottomLeading)
            }

            if isSelected {
                Rectangle()
                    .fill(Color(red: 0.93, green: 0.92, blue: 0.92).opacity(0.76))
                    .frame(width: size, height: size)

                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color(red: 0, green: 0.54, blue: 1))
                    .font(.system(size: 23, weight: .semibold))
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

private struct AlbumCoverThumbnailView: View {
    let asset: PHAsset
    let size: CGFloat

    @State private var thumbnail: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(red: 0.85, green: 0.85, blue: 0.85))

            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .onAppear {
            requestThumbnailIfNeeded()
        }
        .onDisappear {
            cancelThumbnailRequest()
        }
        .onChange(of: asset.localIdentifier) { _, _ in
            cancelThumbnailRequest()
            thumbnail = nil
            requestThumbnailIfNeeded()
        }
    }

    private func requestThumbnailIfNeeded() {
        guard thumbnail == nil, requestID == nil else {
            return
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        let targetLength = max(220, size * UIScreen.main.scale)
        requestID = PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: targetLength, height: targetLength),
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            let isCancelled = (info?[PHImageCancelledKey] as? Bool) == true
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true

            Task { @MainActor in
                guard !isCancelled, let image else {
                    requestID = nil
                    return
                }

                thumbnail = image
                if !isDegraded {
                    requestID = nil
                }
            }
        }
    }

    private func cancelThumbnailRequest() {
        guard let requestID else {
            return
        }

        PHImageManager.default().cancelImageRequest(requestID)
        self.requestID = nil
    }
}

private extension UIImage {
    func albumCoverJPEGData(maxPixel: CGFloat = 1000) -> Data? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }

        let side = min(max(size.width, size.height), maxPixel)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let image = renderer.image { _ in
            let aspectRatio = size.width / size.height
            let drawSize: CGSize
            if aspectRatio > 1 {
                drawSize = CGSize(width: side * aspectRatio, height: side)
            } else {
                drawSize = CGSize(width: side, height: side / aspectRatio)
            }

            let drawRect = CGRect(
                x: (side - drawSize.width) / 2,
                y: (side - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            draw(in: drawRect)
        }

        return image.jpegData(compressionQuality: 0.88)
    }
}

private struct GalleryAlbumAddMorphTransitionDemo: View {
    @State private var isExpanded = false
    @State private var contentVisible = false

    var body: some View {
        let collapsedCenter = CGPoint(x: 55, y: 156)
        let expandedShellFrame = CGRect(x: 20, y: 121, width: 380, height: 416)
        let shellWidth = isExpanded ? expandedShellFrame.width : 70
        let shellHeight = isExpanded ? expandedShellFrame.height : 70
        let shellCornerRadius: CGFloat = 35
        let shellCenter = isExpanded
            ? CGPoint(x: expandedShellFrame.midX, y: expandedShellFrame.midY)
            : collapsedCenter

        ZStack(alignment: .topLeading) {
            Color.white.ignoresSafeArea()

            MorphingAlbumCardShell(
                width: shellWidth,
                height: shellHeight,
                cornerRadius: shellCornerRadius,
                overlayColor: isExpanded
                    ? Color(red: 0.966, green: 0.964, blue: 0.982).opacity(0.72)
                    : .white.opacity(0.58),
                shadowRadius: isExpanded ? 36 : 28,
                shadowYOffset: isExpanded ? 13 : 10
            )
            .position(shellCenter)

            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.28))
                .position(collapsedCenter)
                .opacity(isExpanded ? 0 : 1)

            Text("New Album")
                .font(.system(size: 20, weight: .medium))
                .frame(width: 380, height: 24)
                .position(x: 210, y: 154)
                .opacity(contentVisible ? 1 : 0)

            Button(isExpanded ? "Collapse" : "Expand") {
                withAnimation(.snappy(duration: 1.1)) {
                    contentVisible = false
                    isExpanded.toggle()
                }

                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 770_000_000)
                    guard isExpanded else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        contentVisible = true
                    }
                }
            }
            .position(x: 210, y: 590)
        }
    }
}

#Preview("Album Add Card Morph Demo") {
    GalleryAlbumAddMorphTransitionDemo()
}

struct GalleryAlbumVideoPicker: View {
    let diaries: [VideoDiary]
    let albumName: String
    @Binding var selectedDiaryIDs: [VideoDiary.ID]
    let onBack: () -> Void
    let onSave: () -> Void

    var body: some View {
        GeometryReader { _ in
            let screenSize = UIScreen.main.bounds.size
            let screenWidth = screenSize.width
            let screenHeight = screenSize.height
            let xScale = screenWidth / 420
            let yScale = screenHeight / 912
            let gridGap = 3 * xScale
            let cardWidth = (screenWidth - gridGap * 2) / 3
            let cardHeight = cardWidth * (184 / 138)
            let gridTop = 130 * yScale
            let topControlSize = 44 * xScale
            let topControlSide = 20 * xScale
            let topControlCenterY = (52 * yScale) + topControlSize / 2 + 16 * yScale

            ZStack(alignment: .topLeading) {
                Color(red: 0.996, green: 0.996, blue: 0.996)
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: [
                            GridItem(.fixed(cardWidth), spacing: gridGap),
                            GridItem(.fixed(cardWidth), spacing: gridGap),
                            GridItem(.fixed(cardWidth), spacing: 0)
                        ],
                        alignment: .leading,
                        spacing: gridGap
                    ) {
                        ForEach(Array(diaries.enumerated()), id: \.element.id) { index, diary in
                            GallerySelectableVideoCard(
                                diary: diary,
                                width: cardWidth,
                                height: cardHeight,
                                column: index % 3,
                                isSelected: selectedDiaryIDs.contains(diary.id),
                                onTap: {
                                    toggleSelection(diary.id)
                                }
                            )
                        }
                    }
                    .frame(width: screenWidth, alignment: .leading)
                    .padding(.top, gridTop)
                    .padding(.bottom, 28 * yScale)
                }
                .frame(width: screenWidth, height: screenHeight)

                Text(albumName)
                    .font(.system(size: 24 * xScale, weight: .semibold))
                    .tracking(24 * xScale * 0.01)
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .frame(width: screenWidth, alignment: .center)
                    .offset(y: 76 * yScale)

                GalleryGlassCircleActionButton(
                    systemName: "chevron.left",
                    size: topControlSize,
                    symbolSize: 20 * xScale,
                    action: onBack
                )
                .position(x: topControlSide + topControlSize / 2, y: topControlCenterY)

                GalleryGlassPillActionButton(
                    title: "Save",
                    width: 71 * xScale,
                    height: topControlSize,
                    backgroundColor: Color(red: 0, green: 0.478, blue: 1),
                    foregroundColor: .white,
                    isEnabled: !selectedDiaryIDs.isEmpty,
                    action: onSave
                )
                .position(x: screenWidth - topControlSide - (71 * xScale) / 2, y: topControlCenterY)
            }
            .frame(width: screenWidth, height: screenHeight)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    private func toggleSelection(_ diaryID: VideoDiary.ID) {
        if let index = selectedDiaryIDs.firstIndex(of: diaryID) {
            selectedDiaryIDs.remove(at: index)
        } else {
            selectedDiaryIDs.append(diaryID)
        }
    }
}

private struct GallerySelectableVideoCard: View {
    let diary: VideoDiary
    let width: CGFloat
    let height: CGFloat
    let column: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GalleryVideoCard(
                diary: diary,
                width: width,
                height: height,
                column: column,
                onTap: onTap
            )

            if isSelected {
                GallerySelectionOverlay(column: column, radius: width * (3 / 138))
                    .frame(width: width, height: height)
                    .allowsHitTesting(false)

                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color(red: 0, green: 0.54, blue: 1))
                    .font(.system(size: width * (24 / 138), weight: .semibold))
                    .padding(.top, width * (8 / 138))
                    .padding(.trailing, width * (8 / 138))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height)
    }
}

private struct GallerySelectionOverlay: View {
    let column: Int
    let radius: CGFloat

    var body: some View {
        Color.white.opacity(0.20)
            .clipShape(GalleryCardShape(column: column, radius: radius))
    }
}

struct GalleryVideoCard: View {
    let diary: VideoDiary
    let width: CGFloat
    let height: CGFloat
    let column: Int
    let onTap: () -> Void

    @State private var bottomColor: Color
    @State private var thumbnail: UIImage?
    @State private var requestedURL: URL?

    init(diary: VideoDiary, width: CGFloat, height: CGFloat, column: Int, onTap: @escaping () -> Void) {
        self.diary = diary
        self.width = width
        self.height = height
        self.column = column
        self.onTap = onTap
        _bottomColor = State(initialValue: diary.fallbackTint)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                bottomColor

                ZStack {
                    diary.fallbackTint

                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: width, height: width)
                .mask(videoFadeMask)
                .clipped()

                GalleryCardBlend(color: bottomColor)
                    .frame(width: width, height: width * 0.46)
                    .offset(y: width * 0.54)

                GalleryCardTitleLabel(
                    text: diary.title,
                    fontSize: width * (16 / 138),
                    lineHeight: width * (18 / 138),
                    letterSpacing: width * (0.16 / 138),
                    labelWidth: width * (128 / 138),
                    labelHeight: width * (46 / 138)
                )
                .offset(x: width * (5 / 138), y: width * (141 / 138))
            }
            .frame(width: width, height: height, alignment: .topLeading)
            .clipShape(GalleryCardShape(column: column, radius: width * (3 / 138)))
            .contentShape(Rectangle())
        }
        .buttonStyle(GalleryStaticButtonStyle())
        .task(id: diary.videoURL) {
            if requestedURL != diary.videoURL {
                requestedURL = diary.videoURL
                thumbnail = nil
                bottomColor = diary.fallbackTint
            }

            let assets = await cachedGalleryAssetsWhenReady(
                for: diary.videoURL,
                fallback: diary.fallbackTint,
                isReady: { $0.thumbnail != nil && $0.bottomColor != nil }
            )

            thumbnail = assets.thumbnail
            if let derivedColor = assets.bottomColor {
                bottomColor = derivedColor
            }
        }
    }

    private var videoFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.66),
                .init(color: .black.opacity(0.72), location: 0.80),
                .init(color: .black.opacity(0.16), location: 0.96),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct GalleryStaticButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

struct GalleryAlbumAddVideoCard: View {
    let width: CGFloat
    let height: CGFloat
    let column: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Color(red: 0.85, green: 0.85, blue: 0.85)

                Image(systemName: "plus")
                    .font(.system(size: width * (34 / 138), weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.30))
            }
            .frame(width: width, height: height)
            .clipShape(GalleryCardShape(column: column, radius: width * (3 / 138)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct GalleryCardBlend: View {
    let color: Color

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: color.opacity(0.08), location: 0.22),
                    .init(color: color.opacity(0.36), location: 0.58),
                    .init(color: color.opacity(0.72), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.05), location: 0.38),
                    .init(color: .clear, location: 0.74)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.plusLighter)
        }
    }
}

private struct GalleryCardShape: Shape {
    let column: Int
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radii = RectangleCornerRadii(
            topLeading: column == 0 ? 0 : radius,
            bottomLeading: column == 0 ? 0 : radius,
            bottomTrailing: column == 2 ? 0 : radius,
            topTrailing: column == 2 ? 0 : radius
        )

        return UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
            .path(in: rect)
    }
}

private struct GalleryThumbnailView: View {
    let url: URL?
    let fallbackTint: Color
    let targetSize: CGSize

    @State private var thumbnail: UIImage?
    @State private var requestedURL: URL?

    var body: some View {
        ZStack {
            fallbackTint

            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipped()
        .task(id: url) {
            if requestedURL != url {
                requestedURL = url
                thumbnail = nil
            }

            let assets = await cachedGalleryAssetsWhenReady(
                for: url,
                fallback: fallbackTint,
                isReady: { $0.thumbnail != nil }
            )
            thumbnail = assets.thumbnail
        }
    }
}

private func cachedGalleryAssetsWhenReady(
    for url: URL?,
    fallback: Color,
    isReady: (VideoDerivedGalleryAssets) -> Bool
) async -> VideoDerivedGalleryAssets {
    let retryDelays: [UInt64] = [0, 180_000_000, 360_000_000, 720_000_000, 1_200_000_000]
    var latest = VideoDerivedGalleryAssets(thumbnail: nil, bottomColor: nil)

    for delay in retryDelays {
        if delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }

        guard !Task.isCancelled else {
            return latest
        }

        latest = await VideoDerivedAssetStore.shared.cachedGalleryAssets(for: url, fallback: fallback)
        if isReady(latest) {
            return latest
        }
    }

    return latest
}

private struct GalleryCardTitleLabel: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let letterSpacing: CGFloat
    let labelWidth: CGFloat
    let labelHeight: CGFloat

    func makeUIView(context: Context) -> UILabel {
        let label = GalleryTopAlignedLabel()
        label.backgroundColor = .clear
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.textAlignment = .center
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
        paragraph.alignment = .center

        let font = UIFont(name: "PingFangSC-Semibold", size: fontSize)
            ?? .systemFont(ofSize: fontSize, weight: .semibold)

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

private final class GalleryTopAlignedLabel: UILabel {
    override func drawText(in rect: CGRect) {
        let fittingSize = sizeThatFits(CGSize(width: rect.width, height: .greatestFiniteMagnitude))
        let drawingRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: min(rect.height, fittingSize.height)
        )
        super.drawText(in: drawingRect)
    }
}

private struct GalleryGlassCircleActionButton: View {
    let systemName: String
    let size: CGFloat
    let symbolSize: CGFloat
    var foregroundColor: Color = .black
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        LiquidGlassIconButton(
            systemName: systemName,
            size: size,
            symbolSize: symbolSize,
            symbolWeight: .medium,
            foregroundColor: foregroundColor,
            isEnabled: isEnabled,
            action: action
        )
    }
}

private struct GalleryGlassPillActionButton: View {
    let title: String
    let width: CGFloat
    let height: CGFloat
    var backgroundColor: Color?
    var foregroundColor: Color = .black
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        if let backgroundColor {
            Button(action: action) {
                ZStack {
                    Capsule()
                        .fill(backgroundColor.opacity(isEnabled ? 0.82 : 0.34))
                        .frame(width: width, height: height)
                        .vimemberInteractiveGlass(in: Capsule())
                        .allowsHitTesting(false)

                    Text(title)
                        .font(.system(size: 16 * (height / 40), weight: .medium))
                        .tracking(0.16 * (height / 40))
                        .foregroundStyle(foregroundColor)
                        .opacity(isEnabled ? 1 : 0.42)
                }
                .frame(width: width, height: height)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
        } else {
            LiquidGlassPillButton(
                width: width,
                height: height,
                title: title,
                foregroundColor: foregroundColor,
                isEnabled: isEnabled,
                action: action
            )
        }
    }
}

private struct GalleryTopPlaceholderButton: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: max(17, size * 0.43), weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.80))
            .frame(width: size, height: size)
            .contentShape(Circle())
            .vimemberRegularGlass(in: Circle())
    }
}
