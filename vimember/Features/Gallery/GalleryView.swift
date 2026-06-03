import AVFoundation
import SwiftUI
import UIKit

struct GalleryView: View {
    let diaries: [VideoDiary]
    let albums: [VideoAlbum]
    let onSelectDiary: (VideoDiary) -> Void
    let onCreateAlbum: (_ name: String, _ diaryIDs: [VideoDiary.ID]) -> Void

    @State private var isAddAlbumComposerPresented = false
    @State private var isAlbumVideoPickerPresented = false
    @State private var draftAlbumName = ""
    @State private var selectedAlbumDiaryIDs: [VideoDiary.ID] = []

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
            let albumTop = 121 * yScale
            let videoGridTop = 280 * yScale
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
                        GalleryAlbumBackdrop(height: 226 * yScale)
                            .frame(width: screenWidth, height: 226 * yScale)

                        GallerySectionTitle("Albums", xScale: xScale)
                            .offset(x: 19 * xScale, y: 76 * yScale)

                        GalleryAlbumStrip(
                            diaries: diaries,
                            albums: albums,
                            xScale: xScale,
                            onAddAlbum: {
                                showAddAlbumComposer()
                            }
                        )
                            .frame(width: screenWidth, height: 92 * xScale)
                            .offset(y: albumTop)

                        GallerySectionTitle("All Videos", xScale: xScale)
                            .offset(x: 20 * xScale, y: 239 * yScale)

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
                    .frame(width: 380 * xScale, height: 422 * yScale)
                    .offset(x: 20 * xScale, y: albumTop - 8 * yScale)
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
                                isAddAlbumComposerPresented = true
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
            .frame(width: screenWidth, height: screenHeight)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .animation(.snappy(duration: 0.32), value: isAddAlbumComposerPresented)
        .animation(.snappy(duration: 0.24), value: isAlbumVideoPickerPresented)
    }

    private func showAddAlbumComposer() {
        draftAlbumName = ""
        selectedAlbumDiaryIDs = []
        withAnimation(.snappy(duration: 0.32)) {
            isAddAlbumComposerPresented = true
            isAlbumVideoPickerPresented = false
        }
    }

    private func showAlbumVideoPicker() {
        withAnimation(.snappy(duration: 0.28)) {
            isAddAlbumComposerPresented = false
            isAlbumVideoPickerPresented = true
        }
    }

    private func closeAddAlbumFlow() {
        withAnimation(.snappy(duration: 0.24)) {
            isAddAlbumComposerPresented = false
            isAlbumVideoPickerPresented = false
        }
        draftAlbumName = ""
        selectedAlbumDiaryIDs = []
    }

    private func saveAlbum() {
        guard !selectedAlbumDiaryIDs.isEmpty else {
            return
        }

        onCreateAlbum(draftAlbumName, selectedAlbumDiaryIDs)
        closeAddAlbumFlow()
    }
}

private struct GalleryAlbumBackdrop: View {
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

private struct GallerySectionTitle: View {
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

private struct GalleryAlbumStrip: View {
    let diaries: [VideoDiary]
    let albums: [VideoAlbum]
    let xScale: CGFloat
    let onAddAlbum: () -> Void

    private var albumItems: [GalleryAlbumDisplayItem] {
        let realItems = albums.compactMap { album -> GalleryAlbumDisplayItem? in
            guard let coverID = album.coverDiaryID ?? album.diaryIDs.first,
                  let coverDiary = diaries.first(where: { $0.id == coverID }) else {
                return nil
            }

            return GalleryAlbumDisplayItem(
                id: "album-\(album.id.uuidString)",
                title: album.name,
                coverDiary: coverDiary
            )
        }

        let fillerCount = max(0, 4 - realItems.count)
        let fillerItems = diaries.prefix(fillerCount).map { diary in
            GalleryAlbumDisplayItem(
                id: "diary-\(diary.id.uuidString)",
                title: albumTitle(for: diary),
                coverDiary: diary
            )
        }

        return realItems + fillerItems
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 17 * xScale) {
                GalleryAddAlbumPlaceholder(size: 70 * xScale, action: onAddAlbum)

                ForEach(albumItems) { item in
                    GalleryAlbumItem(
                        title: item.title,
                        coverDiary: item.coverDiary,
                        size: 70 * xScale
                    )
                }
            }
            .padding(.leading, 20 * xScale)
            .padding(.trailing, 20 * xScale)
        }
        .scrollClipDisabled()
    }

    private func albumTitle(for diary: VideoDiary) -> String {
        let words = diary.title.split(separator: " ")
        guard let first = words.first else {
            return "Album"
        }
        return String(first)
    }
}

private struct GalleryAlbumDisplayItem: Identifiable {
    let id: String
    let title: String
    let coverDiary: VideoDiary
}

private struct GalleryAddAlbumPlaceholder: View {
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .fill(Color.white.opacity(0.58))
                            .blendMode(.plusLighter)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 28, y: 10)

                Image(systemName: "plus")
                    .font(.system(size: size * 0.28, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.28))
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
    }
}

private struct GalleryAlbumItem: View {
    let title: String
    let coverDiary: VideoDiary
    let size: CGFloat

    private var coverSize: CGFloat {
        size * (64 / 70)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .fill(Color.white.opacity(0.46))
                            .blendMode(.plusLighter)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 28, y: 10)

                GalleryThumbnailView(
                    url: coverDiary.videoURL,
                    fallbackTint: coverDiary.fallbackTint,
                    targetSize: CGSize(width: coverSize * 2, height: coverSize * 2)
                )
                .frame(width: coverSize, height: coverSize)
                .clipShape(Circle())
            }
            .frame(width: size, height: size)

            Text(title)
                .font(.system(size: size * (14 / 70), weight: .regular))
                .tracking(size * (0.14 / 70))
                .foregroundStyle(Color(white: 0.24))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: size * (67 / 70), height: size * (22 / 70), alignment: .top)
                .frame(width: size, height: size * (22 / 70), alignment: .top)
                .offset(y: size * (2.5 / 70))
        }
        .frame(width: size, height: size * (92 / 70), alignment: .top)
    }
}

private struct GalleryAddAlbumComposer: View {
    @Binding var name: String
    let xScale: CGFloat
    let yScale: CGFloat
    let onClose: () -> Void
    let onNext: () -> Void

    var body: some View {
        let cardWidth = 380 * xScale
        let cardHeight = 426 * yScale
        let closeSize = 40 * xScale
        let saveWidth = 71 * xScale
        let saveHeight = 40 * xScale
        let coverSize = 192 * xScale
        let inputWidth = 310 * xScale
        let inputHeight = 50 * xScale

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 27 * xScale, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 27 * xScale, style: .continuous)
                        .fill(Color(red: 0.966, green: 0.964, blue: 0.982).opacity(0.72))
                        .blendMode(.plusLighter)
                )
                .frame(width: cardWidth, height: cardHeight - 4 * yScale)
                .offset(y: 4 * yScale)
                .shadow(color: .black.opacity(0.08), radius: 36 * xScale, y: 13 * yScale)

            GalleryGlassCircleActionButton(
                systemName: "xmark",
                size: closeSize,
                symbolSize: 17 * xScale,
                action: onClose
            )
            .position(x: 35 * xScale, y: 39 * yScale)

            Text("New Album")
                .font(.system(size: 20 * xScale, weight: .medium))
                .tracking(0.2 * xScale)
                .foregroundStyle(.black)
                .frame(width: cardWidth, height: 24 * yScale)
                .position(x: cardWidth / 2, y: 37 * yScale)

            GalleryGlassPillActionButton(
                title: "Save",
                width: saveWidth,
                height: saveHeight,
                isEnabled: true,
                action: onNext
            )
            .position(x: 329.5 * xScale, y: 39 * yScale)

            Button(action: {}) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.855, green: 0.852, blue: 0.874))

                    Text("Add Cover")
                        .font(.system(size: 16 * xScale, weight: .medium))
                        .tracking(0.16 * xScale)
                        .foregroundStyle(Color(red: 0, green: 0.478, blue: 1))
                        .frame(width: coverSize, alignment: .center)
                        .offset(y: -0.5 * yScale)
                }
                .frame(width: coverSize, height: coverSize)
            }
            .buttonStyle(.plain)
            .position(x: (94 + 96) * xScale, y: (97 + 96 + 4) * yScale)

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
                .padding(.leading, 20 * xScale)
                .padding(.trailing, 28 * xScale)
                .frame(width: inputWidth, height: inputHeight, alignment: .leading)
                .offset(y: -0.5 * yScale)
            }
            .frame(width: inputWidth, height: inputHeight)
            .position(x: (35 + 155) * xScale, y: (337 + 25 + 4) * yScale)
        }
        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
    }
}

private struct GalleryAlbumVideoPicker: View {
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
            let rowCount = max(1, Int(ceil(Double(diaries.count) / 3.0)))
            let contentHeight = max(
                screenHeight + 1,
                gridTop + CGFloat(rowCount) * cardHeight + CGFloat(max(0, rowCount - 1)) * gridGap + 28 * yScale
            )

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
                }
                .frame(width: screenWidth, height: contentHeight)

                Text(albumName)
                    .font(.system(size: 24 * xScale, weight: .semibold))
                    .tracking(24 * xScale * 0.01)
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .frame(width: 250 * xScale, alignment: .leading)
                    .offset(x: 20 * xScale, y: 76 * yScale)

                GalleryGlassCircleActionButton(
                    systemName: "chevron.left",
                    size: 44 * xScale,
                    symbolSize: 20 * xScale,
                    action: onBack
                )
                .position(x: 20 * xScale + 22 * xScale, y: 52 * yScale + 22 * xScale)

                GalleryGlassPillActionButton(
                    title: "Save",
                    width: 71 * xScale,
                    height: 40 * xScale,
                    isEnabled: !selectedDiaryIDs.isEmpty,
                    action: onSave
                )
                .position(x: screenWidth - 20 * xScale - 35.5 * xScale, y: 54 * yScale + 20 * xScale)
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

private struct GalleryVideoCard: View {
    let diary: VideoDiary
    let width: CGFloat
    let height: CGFloat
    let column: Int
    let onTap: () -> Void

    @State private var bottomColor: Color

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

                GalleryThumbnailView(
                    url: diary.videoURL,
                    fallbackTint: diary.fallbackTint,
                    targetSize: CGSize(width: width * 2, height: width * 2)
                )
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
        .buttonStyle(.plain)
        .task(id: diary.videoURL) {
            guard let url = diary.videoURL else { return }
            let sample = await VideoColorSampler.shared.sample(for: url, fallback: diary.fallbackTint)
            bottomColor = sample.bottomColor
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
            thumbnail = nil
            thumbnail = await GalleryThumbnailLoader.shared.thumbnail(
                for: url,
                targetSize: targetSize
            )
        }
    }
}

private actor GalleryThumbnailLoader {
    static let shared = GalleryThumbnailLoader()

    private var cache: [URL: UIImage] = [:]

    func thumbnail(for url: URL?, targetSize: CGSize) async -> UIImage? {
        guard let url else {
            return nil
        }

        if let cached = cache[url] {
            return cached
        }

        let image = await Task.detached(priority: .utility) { () -> UIImage? in
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration)) ?? .zero
            let durationSeconds = CMTimeGetSeconds(duration)
            let seconds = durationSeconds.isFinite ? max(0, durationSeconds / 2) : 0
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(
                width: max(320, targetSize.width),
                height: max(320, targetSize.height)
            )

            guard let cgImage = try? generator.copyCGImage(
                at: CMTime(seconds: seconds, preferredTimescale: 600),
                actualTime: nil
            ) else {
                return nil
            }

            return UIImage(cgImage: cgImage)
        }.value

        if let image {
            cache[url] = image
        }
        return image
    }
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
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .fill(Color.white.opacity(isEnabled ? 0.54 : 0.28))
                                .blendMode(.plusLighter)
                        )
                        .shadow(color: .black.opacity(0.10), radius: size * 0.45, y: size * 0.12)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.58)
    }
}

private struct GalleryGlassPillActionButton: View {
    let title: String
    let width: CGFloat
    let height: CGFloat
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16 * (height / 40), weight: .medium))
                .tracking(0.16 * (height / 40))
                .foregroundStyle(.white)
                .frame(width: width, height: height)
                .background(
                    Capsule()
                        .fill(Color(red: 0, green: 0.54, blue: 1).opacity(isEnabled ? 0.96 : 0.38))
                        .overlay(
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .blendMode(.plusLighter)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct GalleryTopPlaceholderButton: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: max(17, size * 0.43), weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.80))
            .frame(width: size, height: size)
            .background(
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
