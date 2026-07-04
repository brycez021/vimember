import AVFoundation
import Photos
import SwiftData
import SwiftUI
import UIKit

struct AddVideoFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var viewModel = VideoSelectionViewModel()
    @State private var selectedItem: PhotoLibraryVideoItem?
    @State private var draft: VideoImportDraft?
    @State private var isPreparingDraft = false
    @State private var importError: String?

    var body: some View {
        ZStack {
            if let draft {
                AddVideoEditorView(
                    draft: draft,
                    onBack: {
                        self.draft = nil
                    },
                    onComplete: { title, body in
                        try await save(draft: draft, title: title, body: body)
                    }
                )
            } else {
                VideoSelectionPage(
                    viewModel: viewModel,
                    selectedItem: $selectedItem,
                    isPreparingDraft: isPreparingDraft,
                    onCancel: {
                        dismiss()
                    },
                    onNext: {
                        Task {
                            await prepareDraft()
                        }
                    }
                )
            }
        }
        .overlay(alignment: .bottom) {
            if let importError {
                Text(importError)
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
    private func prepareDraft() async {
        guard let selectedItem else { return }
        isPreparingDraft = true
        importError = nil

        do {
            let previewURL = try await viewModel.videoURL(for: selectedItem)
            draft = VideoImportDraft(
                sourceAssetIdentifier: selectedItem.asset.localIdentifier,
                previewURL: previewURL,
                aspectRatio: selectedItem.aspectRatio,
                fallbackTint: selectedItem.thumbnail?.averageBottomColor() ?? AddVideoDesign.textPageBackground
            )
        } catch {
            importError = "Unable to load this video."
        }

        isPreparingDraft = false
    }

    @MainActor
    private func save(draft: VideoImportDraft, title: String, body: String) async throws {
        let filename = try await VideoFileStore.copyVideo(from: draft.previewURL)
        let record = VideoDiaryRecord(
            title: title.isEmpty ? "Title" : title,
            body: body,
            localVideoFilename: filename,
            sourceAssetIdentifier: draft.sourceAssetIdentifier,
            displayAspectRatio: Double(draft.aspectRatio),
            fallbackRed: Double(draft.fallbackRGB.red),
            fallbackGreen: Double(draft.fallbackRGB.green),
            fallbackBlue: Double(draft.fallbackRGB.blue)
        )
        modelContext.insert(record)
        try modelContext.save()
        Task(priority: .utility) {
            _ = await VideoDerivedAssetStore.shared.prepareGalleryAssets(
                for: VideoFileStore.url(for: filename),
                fallback: draft.fallbackTint
            )
        }
        dismiss()
    }
}

struct VideoImportDraft: Equatable {
    let sourceAssetIdentifier: String
    let previewURL: URL
    let aspectRatio: CGFloat
    let fallbackTint: Color

    var fallbackRGB: RGBColor {
        fallbackTint.rgbComponents ?? AddVideoDesign.textPageBackgroundRGB
    }
}

struct PhotoLibraryVideoItem: Identifiable, Equatable {
    let asset: PHAsset
    var thumbnail: UIImage?

    static func == (lhs: PhotoLibraryVideoItem, rhs: PhotoLibraryVideoItem) -> Bool {
        lhs.id == rhs.id
    }

    var id: String {
        asset.localIdentifier
    }

    var aspectRatio: CGFloat {
        guard asset.pixelHeight > 0 else { return 1 }
        return CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
    }
}

@MainActor
final class VideoSelectionViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case ready
        case denied
        case empty
        case failed
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var items: [PhotoLibraryVideoItem] = []

    private let imageManager = PHCachingImageManager()
    private var allItems: [PhotoLibraryVideoItem] = []

    func load() async {
        state = .loading
        items = []
        allItems = []

        let status = await requestAuthorizationIfNeeded()
        guard status == .authorized || status == .limited else {
            state = .denied
            return
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType == %d",
            PHAssetMediaType.video.rawValue
        )

        let result = PHAsset.fetchAssets(with: options)
        var nextItems: [PhotoLibraryVideoItem] = []
        result.enumerateObjects { asset, _, _ in
            nextItems.append(PhotoLibraryVideoItem(asset: asset, thumbnail: nil))
        }

        allItems = nextItems
        state = nextItems.isEmpty ? .empty : .loading
        requestThumbnails(for: nextItems)
    }

    func videoURL(for item: PhotoLibraryVideoItem) async throws -> URL {
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
                    continuation.resume(throwing: VideoImportError.unavailableAsset)
                    return
                }

                if let urlAsset = asset as? AVURLAsset {
                    continuation.resume(returning: urlAsset.url)
                    return
                }

                Task {
                    do {
                        continuation.resume(returning: try await Self.exportTemporaryVideo(from: asset))
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

    private func requestThumbnails(for items: [PhotoLibraryVideoItem]) {
        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .opportunistic
        requestOptions.resizeMode = .fast
        requestOptions.isNetworkAccessAllowed = true

        let targetLength = max(320, (UIScreen.main.bounds.width / 3) * UIScreen.main.scale)
        let targetSize = CGSize(width: targetLength, height: targetLength)

        for item in items {
            imageManager.requestImage(
                for: item.asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: requestOptions
            ) { [weak self] image, info in
                guard let self, let image else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                Task { @MainActor in
                    guard let allIndex = self.allItems.firstIndex(where: { $0.id == item.id }) else { return }
                    if self.allItems[allIndex].thumbnail == nil || !isDegraded {
                        self.allItems[allIndex].thumbnail = image
                    }
                    self.items = self.allItems.filter { $0.thumbnail != nil }
                    self.state = self.items.isEmpty ? .loading : .ready
                }
            }
        }
    }

    nonisolated private static func exportTemporaryVideo(from asset: AVAsset) async throws -> URL {
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoImportError.unavailableAsset
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).mov")
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = false

        await exportSession.export()

        if let error = exportSession.error {
            throw error
        }

        guard exportSession.status == .completed else {
            throw VideoImportError.unavailableAsset
        }

        return outputURL
    }
}

private enum VideoImportError: Error {
    case unavailableAsset
}

private struct VideoSelectionPage: View {
    @ObservedObject var viewModel: VideoSelectionViewModel
    @Binding var selectedItem: PhotoLibraryVideoItem?
    let isPreparingDraft: Bool
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
            let gridTopInset = gridItemSize + 2

            ZStack(alignment: .topLeading) {
                Color.white.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        VideoSelectionHeader(
                            width: screenWidth,
                            height: gridTopInset,
                            titleCenterY: buttonCenterY,
                            xScale: xScale
                        )

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.fixed(gridItemSize), spacing: 2), count: 3),
                            spacing: 2
                        ) {
                            ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                                VideoSelectionTile(
                                    item: item,
                                    isSelected: selectedItem?.id == item.id,
                                    size: gridItemSize,
                                    column: index % 3
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedItem = item
                                }
                            }
                        }
                    }
                    .frame(width: screenWidth, alignment: .top)
                }

                if viewModel.state != .ready {
                    selectionStateView
                        .frame(width: screenWidth, height: screenHeight)
                }

                FigmaGlassCircleButton(
                    systemName: "chevron.left",
                    size: buttonSize,
                    foregroundColor: .black,
                    action: onCancel
                )
                .position(x: (20 * xScale) + buttonSize / 2, y: buttonCenterY)

                FigmaGlassCircleButton(
                    systemName: "checkmark",
                    size: buttonSize,
                    foregroundColor: .black,
                    isEnabled: selectedItem != nil && !isPreparingDraft,
                    action: onNext
                )
                .position(x: screenWidth - (20 * xScale) - buttonSize / 2, y: buttonCenterY)

                if isPreparingDraft {
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
            Text("Photo access is needed to choose videos.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.black.opacity(0.72))
                .padding(.horizontal, 30)
                .multilineTextAlignment(.center)
        case .empty:
            Text("No videos found.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.black.opacity(0.72))
        case .failed:
            Text("Unable to load videos.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.black.opacity(0.72))
        case .ready:
            EmptyView()
        }
    }
}

private struct VideoSelectionHeader: View {
    let width: CGFloat
    let height: CGFloat
    let titleCenterY: CGFloat
    let xScale: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("Select Video")
                .font(.system(size: 24 * xScale, weight: .semibold))
                .tracking(24 * xScale * 0.01)
                .foregroundStyle(.black)
                .fixedSize()
                .position(x: width / 2, y: titleCenterY)
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }
}

private struct VideoSelectionTile: View {
    let item: PhotoLibraryVideoItem
    let isSelected: Bool
    let size: CGFloat
    let column: Int

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let thumbnail = item.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color(red: 0.85, green: 0.85, blue: 0.85))
                    .frame(width: size, height: size)
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
        .clipShape(VideoSelectionTileShape(column: column, radius: 3))
    }
}

private struct VideoSelectionTileShape: Shape {
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

private struct AddVideoEditorView: View {
    let draft: VideoImportDraft
    let onBack: () -> Void
    let onComplete: (_ title: String, _ body: String) async throws -> Void

    var body: some View {
        if #available(iOS 18.0, *) {
            AddVideoEditorModernView(
                draft: draft,
                onBack: onBack,
                onComplete: onComplete
            )
        } else {
            AddVideoEditorCompatView(
                draft: draft,
                onBack: onBack,
                onComplete: onComplete
            )
        }
    }
}

@available(iOS 18.0, *)
private struct AddVideoEditorModernView: View {
    let draft: VideoImportDraft
    let onBack: () -> Void
    let onComplete: (_ title: String, _ body: String) async throws -> Void

    @State private var title = ""
    @State private var bodyText = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var videoBackgroundColor: Color
    @State private var keyboardHeight: CGFloat = 0
    @State private var scrollPosition = ScrollPosition()
    @State private var gestureStartOffsetY: CGFloat = 0
    @State private var gestureStartRegion = AddVideoFlowScrollRegion.video
    @State private var didFocusBodyOnAppear = false
    @State private var focusedInputLineY: CGFloat?
    @FocusState private var focusedField: AddVideoEditorField?

    init(
        draft: VideoImportDraft,
        onBack: @escaping () -> Void,
        onComplete: @escaping (_ title: String, _ body: String) async throws -> Void
    ) {
        self.draft = draft
        self.onBack = onBack
        self.onComplete = onComplete
        _videoBackgroundColor = State(initialValue: draft.fallbackTint)
    }

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
            let buttonSide = 20 * xScale

            ScrollViewReader { _ in
                ZStack(alignment: .topLeading) {
                    videoBackgroundColor.ignoresSafeArea()

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            AddVideoPreviewPage(
                                draft: draft,
                                screenWidth: screenWidth,
                                screenHeight: screenHeight,
                                onBottomColorChange: { color in
                                    videoBackgroundColor = color
                                },
                                onDown: {
                                    snapToAddVideoFlowPage(screenHeight, pageHeight: screenHeight)
                                    focusBodyAfterPageSnap()
                                }
                            )
                            .frame(width: screenWidth, height: screenHeight)
                            .id("video")

                            AddTextPage(
                                title: $title,
                                bodyText: $bodyText,
                                focusedField: $focusedField,
                                dateText: VideoDiaryRecord.dateFormatter.string(from: Date()),
                                backgroundColor: videoBackgroundColor,
                                keyboardHeight: keyboardHeight,
                                screenWidth: screenWidth,
                                screenHeight: screenHeight,
                                onUp: {
                                    focusedField = nil
                                    snapToAddVideoFlowPage(0, pageHeight: screenHeight)
                                },
                                onFocusedLineChange: { lineY in
                                    focusedInputLineY = lineY
                                    scrollFocusedInputAboveKeyboard(
                                        screenHeight: screenHeight,
                                        keyboardHeight: keyboardHeight,
                                        focusedLineY: lineY
                                    )
                                }
                            )
                            .frame(width: screenWidth)
                            .id("text")
                        }
                    }
                    .scrollDismissesKeyboard(.never)
                    .scrollPosition($scrollPosition)
                    .scrollTargetBehavior(
                        AddVideoFlowBoundarySnapBehavior(
                            pageHeight: screenHeight,
                            gestureStartRegion: gestureStartRegion
                        )
                    )
                    .onScrollPhaseChange { oldPhase, newPhase, context in
                        if addVideoFlowShouldRecordGestureStart(oldPhase: oldPhase, newPhase: newPhase) {
                            gestureStartOffsetY = context.geometry.contentOffset.y
                            gestureStartRegion = addVideoFlowScrollRegion(
                                for: context.geometry.contentOffset.y,
                                pageHeight: screenHeight
                            )
                        }
                        if addVideoFlowShouldHandleGestureRelease(oldPhase: oldPhase, newPhase: newPhase),
                           let targetY = addVideoFlowReleaseSnapTarget(
                            gestureStartOffsetY: gestureStartOffsetY,
                            gestureStartRegion: gestureStartRegion,
                            currentOffsetY: context.geometry.contentOffset.y,
                            pageHeight: screenHeight
                           ) {
                            let shouldFocusBodyAfterSnap = gestureStartRegion == .video && targetY > screenHeight / 2
                            if gestureStartRegion == .textTop && targetY <= screenHeight / 2 {
                                focusedField = nil
                            }
                            DispatchQueue.main.async {
                                snapToAddVideoFlowPage(targetY, pageHeight: screenHeight)
                                if shouldFocusBodyAfterSnap {
                                    focusBodyAfterPageSnap()
                                }
                            }
                        }
                    }
                    .ignoresSafeArea()
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                        let newKeyboardHeight = keyboardOverlapHeight(from: notification)
                        keyboardHeight = newKeyboardHeight
                        scrollFocusedInputAboveKeyboard(
                            screenHeight: screenHeight,
                            keyboardHeight: newKeyboardHeight
                        )
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                        keyboardHeight = 0
                    }
                    .onChange(of: focusedField) { _, newField in
                        let defaultLineY = addVideoFlowDefaultFocusedInputLineY(
                            for: newField,
                            screenHeight: screenHeight
                        )
                        focusedInputLineY = defaultLineY
                        scrollFocusedInputAboveKeyboard(
                            screenHeight: screenHeight,
                            keyboardHeight: keyboardHeight,
                            focusedLineY: defaultLineY
                        )
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            scrollPosition.scrollTo(y: screenHeight)
                            gestureStartOffsetY = screenHeight
                            gestureStartRegion = .textTop

                            guard !didFocusBodyOnAppear else { return }
                            didFocusBodyOnAppear = true
                            DispatchQueue.main.async {
                                focusedField = .body
                            }
                        }
                    }

                    AddVideoEditorTopControls(
                        screenWidth: screenWidth,
                        xScale: xScale,
                        yScale: yScale,
                        isTrailingButtonEnabled: !isSaving,
                        onBack: onBack,
                        onTrailingAction: {
                            let shouldComplete = focusedField == nil
                            Task {
                                if shouldComplete {
                                    await complete()
                                } else {
                                    await dismissKeyboard()
                                }
                            }
                        }
                    )

                    if isSaving {
                        ProgressView()
                            .tint(.white)
                            .frame(width: buttonSize, height: buttonSize)
                            .position(x: screenWidth - buttonSide - buttonSize / 2, y: buttonTop + buttonSize / 2)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let saveError {
                        Text(saveError)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.72), in: Capsule())
                            .padding(.bottom, 26)
                    }
                }
                .frame(width: screenWidth, height: screenHeight)
                .ignoresSafeArea()
            }
        }
        .ignoresSafeArea()
    }

    @MainActor
    private func complete() async {
        guard !isSaving else { return }
        isSaving = true
        saveError = nil
        focusedField = nil
        await commitCurrentTextInput()

        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalBody = bodyText

        do {
            try await onComplete(finalTitle, finalBody)
        } catch {
            saveError = "Unable to save this video diary."
            isSaving = false
        }
    }

    private func snapToAddVideoFlowPage(_ targetY: CGFloat, pageHeight: CGFloat) {
        let pageY = targetY <= pageHeight / 2 ? CGFloat(0) : pageHeight
        withAnimation(.snappy(duration: addVideoFlowPageSnapDuration)) {
            scrollPosition.scrollTo(y: pageY)
        }
        gestureStartOffsetY = pageY
        gestureStartRegion = addVideoFlowScrollRegion(for: pageY, pageHeight: pageHeight)
    }

    private func focusBodyAfterPageSnap() {
        DispatchQueue.main.asyncAfter(deadline: .now() + addVideoFlowPageSnapDuration) {
            guard gestureStartRegion == .textTop else { return }
            focusedField = .body
        }
    }

    private func scrollFocusedInputAboveKeyboard(
        screenHeight: CGFloat,
        keyboardHeight: CGFloat,
        focusedLineY: CGFloat? = nil
    ) {
        guard let targetY = addVideoFlowKeyboardAwareScrollTargetY(
            pageHeight: screenHeight,
            keyboardHeight: keyboardHeight,
            focusedField: focusedField,
            focusedLineY: focusedLineY ?? focusedInputLineY
        ) else {
            return
        }

        withAnimation(.snappy(duration: addVideoFlowKeyboardScrollDuration)) {
            scrollPosition.scrollTo(y: targetY)
        }
        gestureStartOffsetY = targetY
        gestureStartRegion = addVideoFlowScrollRegion(for: targetY, pageHeight: screenHeight)
    }

    @MainActor
    private func dismissKeyboard() async {
        focusedField = nil
        await commitCurrentTextInput()
    }

}

struct EditVideoDiaryFlowView: View {
    let diary: VideoDiary
    let onComplete: (_ title: String, _ body: String) async throws -> Void

    var body: some View {
        if #available(iOS 18.0, *) {
            EditVideoDiaryModernFlowView(
                diary: diary,
                onComplete: onComplete
            )
        } else {
            EditVideoDiaryCompatFlowView(
                diary: diary,
                onComplete: onComplete
            )
        }
    }
}

@available(iOS 18.0, *)
private struct EditVideoDiaryModernFlowView: View {
    @Environment(\.dismiss) private var dismiss

    let diary: VideoDiary
    let onComplete: (_ title: String, _ body: String) async throws -> Void

    @State private var title: String
    @State private var bodyText: String
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var videoBackgroundColor: Color
    @State private var keyboardHeight: CGFloat = 0
    @State private var scrollPosition = ScrollPosition()
    @State private var gestureStartOffsetY: CGFloat = 0
    @State private var gestureStartRegion = AddVideoFlowScrollRegion.textTop
    @State private var focusedInputLineY: CGFloat?
    @FocusState private var focusedField: AddVideoEditorField?

    init(
        diary: VideoDiary,
        onComplete: @escaping (_ title: String, _ body: String) async throws -> Void
    ) {
        self.diary = diary
        self.onComplete = onComplete
        _title = State(initialValue: diary.title)
        _bodyText = State(initialValue: diary.body)
        _videoBackgroundColor = State(initialValue: diary.fallbackTint)
    }

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
            let buttonSide = 20 * xScale

            ScrollViewReader { _ in
                ZStack(alignment: .topLeading) {
                    videoBackgroundColor.ignoresSafeArea()

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            AddVideoPreviewPage(
                                videoURL: diary.videoURL,
                                aspectRatio: diary.displayAspectRatio,
                                fallbackTint: diary.fallbackTint,
                                screenWidth: screenWidth,
                                screenHeight: screenHeight,
                                onBottomColorChange: { color in
                                    videoBackgroundColor = color
                                },
                                onDown: {
                                    snapToAddVideoFlowPage(screenHeight, pageHeight: screenHeight)
                                }
                            )
                            .frame(width: screenWidth, height: screenHeight)
                            .id("video")

                            AddTextPage(
                                title: $title,
                                bodyText: $bodyText,
                                focusedField: $focusedField,
                                dateText: diary.dateText,
                                backgroundColor: videoBackgroundColor,
                                keyboardHeight: keyboardHeight,
                                screenWidth: screenWidth,
                                screenHeight: screenHeight,
                                onUp: {
                                    focusedField = nil
                                    snapToAddVideoFlowPage(0, pageHeight: screenHeight)
                                },
                                onFocusedLineChange: { lineY in
                                    focusedInputLineY = lineY
                                    scrollFocusedInputAboveKeyboard(
                                        screenHeight: screenHeight,
                                        keyboardHeight: keyboardHeight,
                                        focusedLineY: lineY
                                    )
                                }
                            )
                            .frame(width: screenWidth)
                            .id("text")
                        }
                    }
                    .scrollDismissesKeyboard(.never)
                    .scrollPosition($scrollPosition)
                    .scrollTargetBehavior(
                        AddVideoFlowBoundarySnapBehavior(
                            pageHeight: screenHeight,
                            gestureStartRegion: gestureStartRegion
                        )
                    )
                    .onScrollPhaseChange { oldPhase, newPhase, context in
                        if addVideoFlowShouldRecordGestureStart(oldPhase: oldPhase, newPhase: newPhase) {
                            gestureStartOffsetY = context.geometry.contentOffset.y
                            gestureStartRegion = addVideoFlowScrollRegion(
                                for: context.geometry.contentOffset.y,
                                pageHeight: screenHeight
                            )
                        }
                        if addVideoFlowShouldHandleGestureRelease(oldPhase: oldPhase, newPhase: newPhase),
                           let targetY = addVideoFlowReleaseSnapTarget(
                            gestureStartOffsetY: gestureStartOffsetY,
                            gestureStartRegion: gestureStartRegion,
                            currentOffsetY: context.geometry.contentOffset.y,
                            pageHeight: screenHeight
                           ) {
                            if gestureStartRegion == .textTop && targetY <= screenHeight / 2 {
                                focusedField = nil
                            }
                            DispatchQueue.main.async {
                                snapToAddVideoFlowPage(targetY, pageHeight: screenHeight)
                            }
                        }
                    }
                    .ignoresSafeArea()
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                        let newKeyboardHeight = keyboardOverlapHeight(from: notification)
                        keyboardHeight = newKeyboardHeight
                        scrollFocusedInputAboveKeyboard(
                            screenHeight: screenHeight,
                            keyboardHeight: newKeyboardHeight
                        )
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                        keyboardHeight = 0
                    }
                    .onChange(of: focusedField) { _, newField in
                        let defaultLineY = addVideoFlowDefaultFocusedInputLineY(
                            for: newField,
                            screenHeight: screenHeight
                        )
                        focusedInputLineY = defaultLineY
                        scrollFocusedInputAboveKeyboard(
                            screenHeight: screenHeight,
                            keyboardHeight: keyboardHeight,
                            focusedLineY: defaultLineY
                        )
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            scrollPosition.scrollTo(y: screenHeight)
                            gestureStartOffsetY = screenHeight
                            gestureStartRegion = .textTop
                            focusedField = nil
                        }
                    }

                    AddVideoEditorTopControls(
                        screenWidth: screenWidth,
                        xScale: xScale,
                        yScale: yScale,
                        isLeadingButtonEnabled: !isSaving,
                        isTrailingButtonVisible: focusedField != nil,
                        isTrailingButtonEnabled: !isSaving,
                        onBack: {
                            Task {
                                await complete()
                            }
                        },
                        onTrailingAction: {
                            Task {
                                await dismissKeyboard()
                            }
                        }
                    )

                    if isSaving {
                        ProgressView()
                            .tint(.white)
                            .frame(width: buttonSize, height: buttonSize)
                            .position(x: screenWidth - buttonSide - buttonSize / 2, y: buttonTop + buttonSize / 2)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let saveError {
                        Text(saveError)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.72), in: Capsule())
                            .padding(.bottom, 26)
                    }
                }
                .frame(width: screenWidth, height: screenHeight)
                .ignoresSafeArea()
            }
        }
        .ignoresSafeArea()
    }

    @MainActor
    private func complete() async {
        guard !isSaving else { return }
        isSaving = true
        saveError = nil
        focusedField = nil
        await commitCurrentTextInput()

        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalBody = bodyText

        do {
            try await onComplete(finalTitle, finalBody)
            dismiss()
        } catch {
            saveError = "Unable to save this video diary."
            isSaving = false
        }
    }

    private func snapToAddVideoFlowPage(_ targetY: CGFloat, pageHeight: CGFloat) {
        let pageY = targetY <= pageHeight / 2 ? CGFloat(0) : pageHeight
        withAnimation(.snappy(duration: addVideoFlowPageSnapDuration)) {
            scrollPosition.scrollTo(y: pageY)
        }
        gestureStartOffsetY = pageY
        gestureStartRegion = addVideoFlowScrollRegion(for: pageY, pageHeight: pageHeight)
    }

    private func scrollFocusedInputAboveKeyboard(
        screenHeight: CGFloat,
        keyboardHeight: CGFloat,
        focusedLineY: CGFloat? = nil
    ) {
        guard let targetY = addVideoFlowKeyboardAwareScrollTargetY(
            pageHeight: screenHeight,
            keyboardHeight: keyboardHeight,
            focusedField: focusedField,
            focusedLineY: focusedLineY ?? focusedInputLineY
        ) else {
            return
        }

        withAnimation(.snappy(duration: addVideoFlowKeyboardScrollDuration)) {
            scrollPosition.scrollTo(y: targetY)
        }
        gestureStartOffsetY = targetY
        gestureStartRegion = addVideoFlowScrollRegion(for: targetY, pageHeight: screenHeight)
    }

    @MainActor
    private func dismissKeyboard() async {
        focusedField = nil
        await commitCurrentTextInput()
    }

}

private struct AddVideoEditorCompatView: View {
    let draft: VideoImportDraft
    let onBack: () -> Void
    let onComplete: (_ title: String, _ body: String) async throws -> Void

    @State private var title = ""
    @State private var bodyText = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var videoBackgroundColor: Color
    @State private var keyboardHeight: CGFloat = 0
    @State private var scrollRequest: AddVideoFlowScrollRequest?
    @State private var scrollRequestID = 0
    @State private var gestureStartOffsetY: CGFloat = 0
    @State private var gestureStartRegion = AddVideoFlowScrollRegion.video
    @State private var didFocusBodyOnAppear = false
    @State private var focusedInputLineY: CGFloat?
    @FocusState private var focusedField: AddVideoEditorField?

    init(
        draft: VideoImportDraft,
        onBack: @escaping () -> Void,
        onComplete: @escaping (_ title: String, _ body: String) async throws -> Void
    ) {
        self.draft = draft
        self.onBack = onBack
        self.onComplete = onComplete
        _videoBackgroundColor = State(initialValue: draft.fallbackTint)
    }

    var body: some View {
        GeometryReader { _ in
            let realScreenSize = UIScreen.main.bounds.size
            let screenWidth = realScreenSize.width
            let screenHeight = realScreenSize.height
            let xScale = screenWidth / 420
            let yScale = screenHeight / 912
            let buttonSize = 44 * xScale
            let buttonTop = 52 * yScale + 16 * yScale
            let buttonSide = 20 * xScale

            ZStack(alignment: .topLeading) {
                videoBackgroundColor.ignoresSafeArea()

                AddVideoFlowCompatScrollView(
                    scrollRequest: scrollRequest,
                    onGestureStart: { offsetY in
                        gestureStartOffsetY = offsetY
                        gestureStartRegion = addVideoFlowScrollRegion(for: offsetY, pageHeight: screenHeight)
                    },
                    onGestureRelease: { offsetY in
                        handleGestureRelease(currentOffsetY: offsetY, pageHeight: screenHeight)
                    }
                ) {
                    VStack(spacing: 0) {
                        AddVideoPreviewPage(
                            draft: draft,
                            screenWidth: screenWidth,
                            screenHeight: screenHeight,
                            onBottomColorChange: { color in
                                videoBackgroundColor = color
                            },
                            onDown: {
                                snapToAddVideoFlowPage(screenHeight, pageHeight: screenHeight)
                                focusBodyAfterPageSnap()
                            }
                        )
                        .frame(width: screenWidth, height: screenHeight)

                        AddTextPage(
                            title: $title,
                            bodyText: $bodyText,
                            focusedField: $focusedField,
                            dateText: VideoDiaryRecord.dateFormatter.string(from: Date()),
                            backgroundColor: videoBackgroundColor,
                            keyboardHeight: keyboardHeight,
                            screenWidth: screenWidth,
                            screenHeight: screenHeight,
                            onUp: {
                                focusedField = nil
                                snapToAddVideoFlowPage(0, pageHeight: screenHeight)
                            },
                            onFocusedLineChange: { lineY in
                                focusedInputLineY = lineY
                                scrollFocusedInputAboveKeyboard(
                                    screenHeight: screenHeight,
                                    keyboardHeight: keyboardHeight,
                                    focusedLineY: lineY
                                )
                            }
                        )
                        .frame(width: screenWidth)
                    }
                    .frame(width: screenWidth, alignment: .top)
                }
                .ignoresSafeArea()

                AddVideoEditorTopControls(
                    screenWidth: screenWidth,
                    xScale: xScale,
                    yScale: yScale,
                    isTrailingButtonEnabled: !isSaving,
                    onBack: onBack,
                    onTrailingAction: {
                        let shouldComplete = focusedField == nil
                        Task {
                            if shouldComplete {
                                await complete()
                            } else {
                                await dismissKeyboard()
                            }
                        }
                    }
                )

                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .frame(width: buttonSize, height: buttonSize)
                        .position(x: screenWidth - buttonSide - buttonSize / 2, y: buttonTop + buttonSize / 2)
                }
            }
            .overlay(alignment: .bottom) {
                if let saveError {
                    Text(saveError)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.72), in: Capsule())
                        .padding(.bottom, 26)
                }
            }
            .frame(width: screenWidth, height: screenHeight)
            .ignoresSafeArea()
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                let newKeyboardHeight = keyboardOverlapHeight(from: notification)
                keyboardHeight = newKeyboardHeight
                scrollFocusedInputAboveKeyboard(
                    screenHeight: screenHeight,
                    keyboardHeight: newKeyboardHeight
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardHeight = 0
            }
            .onChange(of: focusedField) { _, newField in
                let defaultLineY = addVideoFlowDefaultFocusedInputLineY(
                    for: newField,
                    screenHeight: screenHeight
                )
                focusedInputLineY = defaultLineY
                scrollFocusedInputAboveKeyboard(
                    screenHeight: screenHeight,
                    keyboardHeight: keyboardHeight,
                    focusedLineY: defaultLineY
                )
            }
            .onAppear {
                DispatchQueue.main.async {
                    requestScroll(to: screenHeight, animated: false)
                    gestureStartOffsetY = screenHeight
                    gestureStartRegion = .textTop

                    guard !didFocusBodyOnAppear else { return }
                    didFocusBodyOnAppear = true
                    DispatchQueue.main.async {
                        focusedField = .body
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    @MainActor
    private func complete() async {
        guard !isSaving else { return }
        isSaving = true
        saveError = nil
        focusedField = nil
        await commitCurrentTextInput()

        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalBody = bodyText

        do {
            try await onComplete(finalTitle, finalBody)
        } catch {
            saveError = "Unable to save this video diary."
            isSaving = false
        }
    }

    private func snapToAddVideoFlowPage(_ targetY: CGFloat, pageHeight: CGFloat) {
        let pageY = targetY <= pageHeight / 2 ? CGFloat(0) : pageHeight
        requestScroll(to: pageY, animated: true)
        gestureStartOffsetY = pageY
        gestureStartRegion = addVideoFlowScrollRegion(for: pageY, pageHeight: pageHeight)
    }

    private func focusBodyAfterPageSnap() {
        DispatchQueue.main.asyncAfter(deadline: .now() + addVideoFlowPageSnapDuration) {
            guard gestureStartRegion == .textTop else { return }
            focusedField = .body
        }
    }

    private func handleGestureRelease(currentOffsetY: CGFloat, pageHeight: CGFloat) {
        guard let targetY = addVideoFlowReleaseSnapTarget(
            gestureStartOffsetY: gestureStartOffsetY,
            gestureStartRegion: gestureStartRegion,
            currentOffsetY: currentOffsetY,
            pageHeight: pageHeight
        ) else {
            return
        }

        let shouldFocusBodyAfterSnap = gestureStartRegion == .video && targetY > pageHeight / 2
        if gestureStartRegion == .textTop && targetY <= pageHeight / 2 {
            focusedField = nil
        }
        snapToAddVideoFlowPage(targetY, pageHeight: pageHeight)
        if shouldFocusBodyAfterSnap {
            focusBodyAfterPageSnap()
        }
    }

    private func scrollFocusedInputAboveKeyboard(
        screenHeight: CGFloat,
        keyboardHeight: CGFloat,
        focusedLineY: CGFloat? = nil
    ) {
        guard let targetY = addVideoFlowKeyboardAwareScrollTargetY(
            pageHeight: screenHeight,
            keyboardHeight: keyboardHeight,
            focusedField: focusedField,
            focusedLineY: focusedLineY ?? focusedInputLineY
        ) else {
            return
        }

        requestScroll(to: targetY, animated: true)
        gestureStartOffsetY = targetY
        gestureStartRegion = addVideoFlowScrollRegion(for: targetY, pageHeight: screenHeight)
    }

    private func requestScroll(to y: CGFloat, animated: Bool) {
        scrollRequestID += 1
        scrollRequest = AddVideoFlowScrollRequest(id: scrollRequestID, y: y, animated: animated)
    }

    @MainActor
    private func dismissKeyboard() async {
        focusedField = nil
        await commitCurrentTextInput()
    }
}

private struct EditVideoDiaryCompatFlowView: View {
    @Environment(\.dismiss) private var dismiss

    let diary: VideoDiary
    let onComplete: (_ title: String, _ body: String) async throws -> Void

    @State private var title: String
    @State private var bodyText: String
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var videoBackgroundColor: Color
    @State private var keyboardHeight: CGFloat = 0
    @State private var scrollRequest: AddVideoFlowScrollRequest?
    @State private var scrollRequestID = 0
    @State private var gestureStartOffsetY: CGFloat = 0
    @State private var gestureStartRegion = AddVideoFlowScrollRegion.textTop
    @State private var focusedInputLineY: CGFloat?
    @FocusState private var focusedField: AddVideoEditorField?

    init(
        diary: VideoDiary,
        onComplete: @escaping (_ title: String, _ body: String) async throws -> Void
    ) {
        self.diary = diary
        self.onComplete = onComplete
        _title = State(initialValue: diary.title)
        _bodyText = State(initialValue: diary.body)
        _videoBackgroundColor = State(initialValue: diary.fallbackTint)
    }

    var body: some View {
        GeometryReader { _ in
            let realScreenSize = UIScreen.main.bounds.size
            let screenWidth = realScreenSize.width
            let screenHeight = realScreenSize.height
            let xScale = screenWidth / 420
            let yScale = screenHeight / 912
            let buttonSize = 44 * xScale
            let buttonTop = 52 * yScale + 16 * yScale
            let buttonSide = 20 * xScale

            ZStack(alignment: .topLeading) {
                videoBackgroundColor.ignoresSafeArea()

                AddVideoFlowCompatScrollView(
                    scrollRequest: scrollRequest,
                    onGestureStart: { offsetY in
                        gestureStartOffsetY = offsetY
                        gestureStartRegion = addVideoFlowScrollRegion(for: offsetY, pageHeight: screenHeight)
                    },
                    onGestureRelease: { offsetY in
                        handleGestureRelease(currentOffsetY: offsetY, pageHeight: screenHeight)
                    }
                ) {
                    VStack(spacing: 0) {
                        AddVideoPreviewPage(
                            videoURL: diary.videoURL,
                            aspectRatio: diary.displayAspectRatio,
                            fallbackTint: diary.fallbackTint,
                            screenWidth: screenWidth,
                            screenHeight: screenHeight,
                            onBottomColorChange: { color in
                                videoBackgroundColor = color
                            },
                            onDown: {
                                snapToAddVideoFlowPage(screenHeight, pageHeight: screenHeight)
                            }
                        )
                        .frame(width: screenWidth, height: screenHeight)

                        AddTextPage(
                            title: $title,
                            bodyText: $bodyText,
                            focusedField: $focusedField,
                            dateText: diary.dateText,
                            backgroundColor: videoBackgroundColor,
                            keyboardHeight: keyboardHeight,
                            screenWidth: screenWidth,
                            screenHeight: screenHeight,
                            onUp: {
                                focusedField = nil
                                snapToAddVideoFlowPage(0, pageHeight: screenHeight)
                            },
                            onFocusedLineChange: { lineY in
                                focusedInputLineY = lineY
                                scrollFocusedInputAboveKeyboard(
                                    screenHeight: screenHeight,
                                    keyboardHeight: keyboardHeight,
                                    focusedLineY: lineY
                                )
                            }
                        )
                        .frame(width: screenWidth)
                    }
                    .frame(width: screenWidth, alignment: .top)
                }
                .ignoresSafeArea()

                AddVideoEditorTopControls(
                    screenWidth: screenWidth,
                    xScale: xScale,
                    yScale: yScale,
                    isLeadingButtonEnabled: !isSaving,
                    isTrailingButtonVisible: focusedField != nil,
                    isTrailingButtonEnabled: !isSaving,
                    onBack: {
                        Task {
                            await complete()
                        }
                    },
                    onTrailingAction: {
                        Task {
                            await dismissKeyboard()
                        }
                    }
                )

                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .frame(width: buttonSize, height: buttonSize)
                        .position(x: screenWidth - buttonSide - buttonSize / 2, y: buttonTop + buttonSize / 2)
                }
            }
            .overlay(alignment: .bottom) {
                if let saveError {
                    Text(saveError)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.72), in: Capsule())
                        .padding(.bottom, 26)
                }
            }
            .frame(width: screenWidth, height: screenHeight)
            .ignoresSafeArea()
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                let newKeyboardHeight = keyboardOverlapHeight(from: notification)
                keyboardHeight = newKeyboardHeight
                scrollFocusedInputAboveKeyboard(
                    screenHeight: screenHeight,
                    keyboardHeight: newKeyboardHeight
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardHeight = 0
            }
            .onChange(of: focusedField) { _, newField in
                let defaultLineY = addVideoFlowDefaultFocusedInputLineY(
                    for: newField,
                    screenHeight: screenHeight
                )
                focusedInputLineY = defaultLineY
                scrollFocusedInputAboveKeyboard(
                    screenHeight: screenHeight,
                    keyboardHeight: keyboardHeight,
                    focusedLineY: defaultLineY
                )
            }
            .onAppear {
                DispatchQueue.main.async {
                    requestScroll(to: screenHeight, animated: false)
                    gestureStartOffsetY = screenHeight
                    gestureStartRegion = .textTop
                    focusedField = nil
                }
            }
        }
        .ignoresSafeArea()
    }

    @MainActor
    private func complete() async {
        guard !isSaving else { return }
        isSaving = true
        saveError = nil
        focusedField = nil
        await commitCurrentTextInput()

        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalBody = bodyText

        do {
            try await onComplete(finalTitle, finalBody)
            dismiss()
        } catch {
            saveError = "Unable to save this video diary."
            isSaving = false
        }
    }

    private func snapToAddVideoFlowPage(_ targetY: CGFloat, pageHeight: CGFloat) {
        let pageY = targetY <= pageHeight / 2 ? CGFloat(0) : pageHeight
        requestScroll(to: pageY, animated: true)
        gestureStartOffsetY = pageY
        gestureStartRegion = addVideoFlowScrollRegion(for: pageY, pageHeight: pageHeight)
    }

    private func handleGestureRelease(currentOffsetY: CGFloat, pageHeight: CGFloat) {
        guard let targetY = addVideoFlowReleaseSnapTarget(
            gestureStartOffsetY: gestureStartOffsetY,
            gestureStartRegion: gestureStartRegion,
            currentOffsetY: currentOffsetY,
            pageHeight: pageHeight
        ) else {
            return
        }

        if gestureStartRegion == .textTop && targetY <= pageHeight / 2 {
            focusedField = nil
        }
        snapToAddVideoFlowPage(targetY, pageHeight: pageHeight)
    }

    private func scrollFocusedInputAboveKeyboard(
        screenHeight: CGFloat,
        keyboardHeight: CGFloat,
        focusedLineY: CGFloat? = nil
    ) {
        guard let targetY = addVideoFlowKeyboardAwareScrollTargetY(
            pageHeight: screenHeight,
            keyboardHeight: keyboardHeight,
            focusedField: focusedField,
            focusedLineY: focusedLineY ?? focusedInputLineY
        ) else {
            return
        }

        requestScroll(to: targetY, animated: true)
        gestureStartOffsetY = targetY
        gestureStartRegion = addVideoFlowScrollRegion(for: targetY, pageHeight: screenHeight)
    }

    private func requestScroll(to y: CGFloat, animated: Bool) {
        scrollRequestID += 1
        scrollRequest = AddVideoFlowScrollRequest(id: scrollRequestID, y: y, animated: animated)
    }

    @MainActor
    private func dismissKeyboard() async {
        focusedField = nil
        await commitCurrentTextInput()
    }
}

private struct AddVideoFlowScrollRequest: Equatable {
    let id: Int
    let y: CGFloat
    let animated: Bool
}

private struct AddVideoFlowCompatScrollView<Content: View>: UIViewRepresentable {
    let scrollRequest: AddVideoFlowScrollRequest?
    let onGestureStart: (CGFloat) -> Void
    let onGestureRelease: (CGFloat) -> Void
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onGestureStart: onGestureStart,
            onGestureRelease: onGestureRelease
        )
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .clear
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .none
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = context.coordinator

        let hostingController = UIHostingController(rootView: content())
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostingController.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        context.coordinator.hostingController = hostingController
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.onGestureStart = onGestureStart
        context.coordinator.onGestureRelease = onGestureRelease
        context.coordinator.hostingController?.rootView = content()
        context.coordinator.hostingController?.view.invalidateIntrinsicContentSize()
        scrollView.layoutIfNeeded()

        guard let scrollRequest,
              context.coordinator.lastScrollRequestID != scrollRequest.id else {
            return
        }

        DispatchQueue.main.async {
            context.coordinator.apply(scrollRequest, to: scrollView)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<Content>?
        var onGestureStart: (CGFloat) -> Void
        var onGestureRelease: (CGFloat) -> Void
        var lastScrollRequestID: Int?
        private var isProgrammaticScroll = false

        init(
            onGestureStart: @escaping (CGFloat) -> Void,
            onGestureRelease: @escaping (CGFloat) -> Void
        ) {
            self.onGestureStart = onGestureStart
            self.onGestureRelease = onGestureRelease
        }

        func apply(_ request: AddVideoFlowScrollRequest, to scrollView: UIScrollView) {
            scrollView.layoutIfNeeded()
            let maxOffsetY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            let offsetY = min(max(request.y, 0), maxOffsetY)
            lastScrollRequestID = request.id
            isProgrammaticScroll = request.animated
            scrollView.setContentOffset(CGPoint(x: 0, y: offsetY), animated: request.animated)
            if !request.animated {
                isProgrammaticScroll = false
            }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isProgrammaticScroll = false
            onGestureStart(scrollView.contentOffset.y)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !isProgrammaticScroll, !decelerate else { return }
            onGestureRelease(scrollView.contentOffset.y)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            guard !isProgrammaticScroll else { return }
            onGestureRelease(scrollView.contentOffset.y)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            isProgrammaticScroll = false
        }
    }
}

private struct AddVideoEditorTopControls: View {
    let screenWidth: CGFloat
    let xScale: CGFloat
    let yScale: CGFloat
    var isLeadingButtonEnabled = true
    var isTrailingButtonVisible = true
    var isTrailingButtonEnabled = true
    let onBack: () -> Void
    let onTrailingAction: () -> Void

    private var buttonSize: CGFloat {
        44 * xScale
    }

    private var centerY: CGFloat {
        52 * yScale + buttonSize / 2 + 16 * yScale
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LiquidGlassContainer(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    Circle()
                        .fill(.clear)
                        .frame(width: buttonSize, height: buttonSize)
                        .vimemberInteractiveGlass(in: Circle())
                        .position(x: leadingButtonCenterX, y: centerY)

                    if isTrailingButtonVisible {
                        Circle()
                            .fill(.clear)
                            .frame(width: buttonSize, height: buttonSize)
                            .vimemberInteractiveGlass(in: Circle())
                            .position(x: trailingButtonCenterX, y: centerY)
                    }
                }
                .frame(width: screenWidth, height: centerY + buttonSize / 2, alignment: .topLeading)
            }
            .allowsHitTesting(false)

            AddVideoEditorGlassIconButton(
                systemName: "chevron.left",
                size: buttonSize,
                isEnabled: isLeadingButtonEnabled,
                action: onBack
            )
            .position(x: leadingButtonCenterX, y: centerY)

            if isTrailingButtonVisible {
                AddVideoEditorGlassIconButton(
                    systemName: "checkmark",
                    size: buttonSize,
                    isEnabled: isTrailingButtonEnabled,
                    action: onTrailingAction
                )
                .position(x: trailingButtonCenterX, y: centerY)
            }
        }
        .frame(width: screenWidth, height: centerY + buttonSize / 2, alignment: .topLeading)
    }

    private var leadingButtonCenterX: CGFloat {
        20 * xScale + buttonSize / 2
    }

    private var trailingButtonCenterX: CGFloat {
        screenWidth - 20 * xScale - buttonSize / 2
    }
}

private struct AddVideoEditorGlassIconButton: View {
    let systemName: String
    let size: CGFloat
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: max(18, size * 0.42), weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
                .opacity(isEnabled ? 1 : 0.42)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct AddTextPage: View {
    @Binding var title: String
    @Binding var bodyText: String
    var focusedField: FocusState<AddVideoEditorField?>.Binding
    let dateText: String
    let backgroundColor: Color
    let keyboardHeight: CGFloat
    let screenWidth: CGFloat
    let screenHeight: CGFloat
    let onUp: () -> Void
    let onFocusedLineChange: (CGFloat) -> Void

    @State private var measuredBodyTextHeight: CGFloat = 0

    var body: some View {
        let xScale = screenWidth / 420
        let yScale = screenHeight / 912
        let textLeft = 23 * xScale
        let textTop = 140 * yScale
        let textWidth = min(384 * xScale, screenWidth - textLeft * 2)
        let dividerWidth = min(374 * xScale, textWidth)
        let buttonSize = 44 * xScale
        let buttonTop = 52 * yScale + 16 * yScale
        let arrowCenterY = buttonTop + buttonSize / 2
        let titleHitVerticalPadding = 12 * yScale
        let bodyMinimumHeight = max(240 * yScale, screenHeight - textTop - 260 * yScale)
        let bodyEditorHeight = max(bodyMinimumHeight, measuredBodyTextHeight + 28 * yScale)
        let textPageBottomMargin = focusedField.wrappedValue == .body && keyboardHeight > 0
            ? keyboardHeight + 24 * yScale
            : 0
        let bodyEditorOffsetX = -5 * xScale
        let bodyEditorOffsetY = -9 * yScale
        let titleFocusLineY = textTop + 34 * yScale
        let bodyFocusLineY = textTop + 92 * yScale

        ZStack(alignment: .topLeading) {
            Button(action: onUp) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 35, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .white.opacity(0.25), radius: 4, y: 4)
                    .frame(width: 50, height: 44)
            }
            .buttonStyle(.plain)
            .position(x: screenWidth / 2, y: arrowCenterY)

            VStack(alignment: .leading, spacing: 0) {
                TextField(
                    "",
                    text: $title,
                    prompt: Text("Title")
                        .foregroundStyle(.white)
                )
                    .font(.custom("PingFangSC-Semibold", size: 30))
                    .tracking(0.3)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused(focusedField, equals: .title)
                    .submitLabel(.next)
                    .onSubmit {
                        onFocusedLineChange(bodyFocusLineY)
                        focusedField.wrappedValue = .body
                    }
                    .frame(height: 36)
                    .padding(.vertical, titleHitVerticalPadding)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onFocusedLineChange(titleFocusLineY)
                        focusedField.wrappedValue = .title
                    }
                    .padding(.vertical, -titleHitVerticalPadding)
                    .offset(y: -4)
                    .padding(.bottom, 2)

                Text(dateText)
                    .font(.custom("PingFangSC-Medium", size: 16))
                    .tracking(0.16)
                    .foregroundStyle(.white)
                    .frame(height: 22, alignment: .topLeading)
                    .offset(y: -6)
                    .padding(.bottom, 4)

                Rectangle()
                    .fill(.white.opacity(0.68))
                    .frame(width: dividerWidth, height: max(0.5, 0.5 * xScale))
                    .padding(.bottom, 14)

                ZStack(alignment: .topLeading) {
                    Text(bodyText.isEmpty ? " " : bodyText + "\n")
                        .font(.custom("PingFangSC-Regular", size: 16))
                        .tracking(0.16)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: textWidth, alignment: .topLeading)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: AddTextBodyHeightPreferenceKey.self,
                                    value: proxy.size.height
                                )
                            }
                        )
                        .hidden()

                    AddTextPlaceholderLabel(
                        text: "Start writing...",
                        labelWidth: textWidth
                    )
                    .opacity(bodyText.isEmpty ? 1 : 0)
                    .allowsHitTesting(false)

                    GeometryReader { proxy in
                        TextEditor(text: $bodyText)
                            .font(.custom("PingFangSC-Regular", size: 16))
                            .tracking(0.16)
                            .lineSpacing(3)
                            .foregroundStyle(.white)
                            .tint(.white)
                            .focused(focusedField, equals: .body)
                            .scrollContentBackground(.hidden)
                            .scrollDisabled(true)
                            .contentMargins(.top, 0, for: .scrollContent)
                            .contentMargins(.horizontal, 0, for: .scrollContent)
                            .contentMargins(.bottom, 0, for: .scrollContent)
                            .background(Color.clear)
                            .frame(
                                minWidth: textWidth,
                                maxWidth: textWidth,
                                minHeight: bodyEditorHeight,
                                maxHeight: bodyEditorHeight,
                                alignment: .topLeading
                            )
                            .simultaneousGesture(
                                SpatialTapGesture()
                                    .onEnded { value in
                                        focusedField.wrappedValue = .body
                                        let lineY = proxy.frame(in: .named(addTextPageCoordinateSpaceName)).minY
                                            + value.location.y
                                        DispatchQueue.main.async {
                                            onFocusedLineChange(lineY)
                                        }
                                    }
                            )
                    }
                    .frame(
                        minWidth: textWidth,
                        maxWidth: textWidth,
                        minHeight: bodyEditorHeight,
                        maxHeight: bodyEditorHeight,
                        alignment: .topLeading
                    )
                    .offset(x: bodyEditorOffsetX, y: bodyEditorOffsetY)
                }
                .frame(
                    minWidth: textWidth,
                    maxWidth: textWidth,
                    minHeight: bodyEditorHeight,
                    alignment: .topLeading
                )
                .offset(y: -4 * yScale)
            }
            .frame(width: textWidth, alignment: .leading)
            .padding(.leading, textLeft)
            .padding(.top, textTop)
            .padding(.bottom, textPageBottomMargin)
            .onPreferenceChange(AddTextBodyHeightPreferenceKey.self) { height in
                measuredBodyTextHeight = height
            }
        }
        .coordinateSpace(name: addTextPageCoordinateSpaceName)
        .frame(width: screenWidth, alignment: .topLeading)
        .frame(minHeight: screenHeight, alignment: .topLeading)
        .background(backgroundColor.ignoresSafeArea())
    }
}

@MainActor
private func commitCurrentTextInput() async {
    await Task.yield()
    try? await Task.sleep(nanoseconds: 30_000_000)
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
        .first(where: \.isKeyWindow)?
        .endEditing(true)
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
    await Task.yield()
    try? await Task.sleep(nanoseconds: 30_000_000)
}

private func keyboardOverlapHeight(from notification: Notification) -> CGFloat {
    guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
        return 0
    }
    return max(0, UIScreen.main.bounds.height - endFrame.minY)
}

private func addVideoFlowDefaultFocusedInputLineY(
    for field: AddVideoEditorField?,
    screenHeight: CGFloat
) -> CGFloat? {
    guard let field else {
        return nil
    }

    let yScale = screenHeight / 912
    let textTop = 140 * yScale

    switch field {
    case .title:
        return textTop + 34 * yScale
    case .body:
        return textTop + 92 * yScale
    }
}

private func addVideoFlowKeyboardAwareScrollTargetY(
    pageHeight: CGFloat,
    keyboardHeight: CGFloat,
    focusedField: AddVideoEditorField?,
    focusedLineY: CGFloat?
) -> CGFloat? {
    guard keyboardHeight > 0,
          let focusedField,
          let focusedLineY = focusedLineY
            ?? addVideoFlowDefaultFocusedInputLineY(for: focusedField, screenHeight: pageHeight) else {
        return nil
    }

    let yScale = pageHeight / 912
    let visibleBottomY = pageHeight - keyboardHeight - 24 * yScale
    let focusedLineBottomY = focusedLineY + 30 * yScale
    let textPageOffsetY = max(0, focusedLineBottomY - visibleBottomY)

    return pageHeight + textPageOffsetY
}

private enum AddVideoEditorField: Hashable {
    case title
    case body
}

private struct AddTextBodyHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum AddVideoFlowScrollRegion {
    case video
    case textTop
    case textBody
}

private let addVideoFlowPageSnapDuration: TimeInterval = 0.38
private let addVideoFlowKeyboardScrollDuration: TimeInterval = 0.24
private let addTextPageCoordinateSpaceName = "addTextPage"

@available(iOS 18.0, *)
private struct AddVideoFlowBoundarySnapBehavior: ScrollTargetBehavior {
    let pageHeight: CGFloat
    let gestureStartRegion: AddVideoFlowScrollRegion

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let maxOffsetY = max(0, context.contentSize.height - context.containerSize.height)
        guard let targetY = addVideoFlowBoundarySnapTarget(
            gestureStartRegion: gestureStartRegion,
            targetOffsetY: target.rect.minY,
            pageHeight: pageHeight
        ) else {
            return
        }

        target.rect.origin.y = min(max(targetY, 0), maxOffsetY)
        target.anchor = .top
    }
}

@available(iOS 18.0, *)
private func addVideoFlowShouldRecordGestureStart(oldPhase: ScrollPhase, newPhase: ScrollPhase) -> Bool {
    (oldPhase == .idle && (newPhase == .tracking || newPhase == .interacting))
        || (oldPhase == .decelerating && newPhase == .interacting)
}

@available(iOS 18.0, *)
private func addVideoFlowShouldHandleGestureRelease(oldPhase: ScrollPhase, newPhase: ScrollPhase) -> Bool {
    (oldPhase == .tracking || oldPhase == .interacting) && (newPhase == .decelerating || newPhase == .idle)
}

private func addVideoFlowScrollRegion(for offsetY: CGFloat, pageHeight: CGFloat) -> AddVideoFlowScrollRegion {
    guard pageHeight > 0 else {
        return .video
    }

    let textTop = pageHeight
    let tolerance = addVideoFlowBoundaryTolerance(pageHeight: pageHeight)

    if abs(offsetY - textTop) <= tolerance {
        return .textTop
    }
    if offsetY > textTop + tolerance {
        return .textBody
    }
    return .video
}

private func addVideoFlowBoundarySnapTarget(
    gestureStartRegion: AddVideoFlowScrollRegion,
    targetOffsetY: CGFloat,
    pageHeight: CGFloat
) -> CGFloat? {
    guard pageHeight > 0 else {
        return nil
    }

    let textTop = pageHeight
    let textTopCatchRange = addVideoFlowTextTopCatchRange(pageHeight: pageHeight)

    switch gestureStartRegion {
    case .video, .textTop:
        return nil

    case .textBody:
        return targetOffsetY <= textTop + textTopCatchRange ? textTop : nil
    }
}

private func addVideoFlowReleaseSnapTarget(
    gestureStartOffsetY: CGFloat,
    gestureStartRegion: AddVideoFlowScrollRegion,
    currentOffsetY: CGFloat,
    pageHeight: CGFloat
) -> CGFloat? {
    guard pageHeight > 0 else {
        return nil
    }

    let textTop = pageHeight
    let snapThreshold = addVideoFlowBoundarySnapThreshold(pageHeight: pageHeight)
    let textTopCatchRange = addVideoFlowTextTopCatchRange(pageHeight: pageHeight)

    switch gestureStartRegion {
    case .video:
        return currentOffsetY > gestureStartOffsetY + snapThreshold ? textTop : 0

    case .textTop:
        if currentOffsetY < textTop - snapThreshold {
            return 0
        }
        if currentOffsetY < textTop {
            return textTop
        }
        return nil

    case .textBody:
        return currentOffsetY <= textTop + textTopCatchRange ? textTop : nil
    }
}

private func addVideoFlowBoundaryTolerance(pageHeight: CGFloat) -> CGFloat {
    min(36, max(16, pageHeight * 0.04))
}

private func addVideoFlowBoundarySnapThreshold(pageHeight: CGFloat) -> CGFloat {
    min(32, max(24, pageHeight * 0.03))
}

private func addVideoFlowTextTopCatchRange(pageHeight: CGFloat) -> CGFloat {
    min(120, max(64, pageHeight * 0.1))
}

private struct AddTextPlaceholderLabel: UIViewRepresentable {
    let text: String
    let labelWidth: CGFloat

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.backgroundColor = .clear
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.preferredMaxLayoutWidth = labelWidth
        label.attributedText = attributedText
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        CGSize(width: labelWidth, height: 22)
    }

    private var attributedText: NSAttributedString {
        NSAttributedString(string: text, attributes: Self.textAttributes)
    }

    private static var textAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 22
        paragraph.maximumLineHeight = 22
        paragraph.lineBreakMode = .byWordWrapping

        let font = UIFont(name: "PingFangSC-Regular", size: 16)
            ?? .systemFont(ofSize: 16, weight: .regular)

        return [
            .font: font,
            .foregroundColor: UIColor.white.withAlphaComponent(0.92),
            .kern: 0.16,
            .paragraphStyle: paragraph
        ]
    }
}

private struct AddVideoPreviewPage: View {
    let videoURL: URL?
    let aspectRatio: CGFloat
    let fallbackTint: Color
    let screenWidth: CGFloat
    let screenHeight: CGFloat
    let onBottomColorChange: ((Color) -> Void)?
    let onDown: () -> Void

    init(
        draft: VideoImportDraft,
        screenWidth: CGFloat,
        screenHeight: CGFloat,
        onBottomColorChange: ((Color) -> Void)? = nil,
        onDown: @escaping () -> Void
    ) {
        self.videoURL = draft.previewURL
        self.aspectRatio = draft.aspectRatio
        self.fallbackTint = draft.fallbackTint
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.onBottomColorChange = onBottomColorChange
        self.onDown = onDown
    }

    init(
        videoURL: URL?,
        aspectRatio: CGFloat,
        fallbackTint: Color,
        screenWidth: CGFloat,
        screenHeight: CGFloat,
        onBottomColorChange: ((Color) -> Void)? = nil,
        onDown: @escaping () -> Void
    ) {
        self.videoURL = videoURL
        self.aspectRatio = aspectRatio
        self.fallbackTint = fallbackTint
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.onBottomColorChange = onBottomColorChange
        self.onDown = onDown
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            BlendedVideoSurface(
                url: videoURL,
                aspectRatio: aspectRatio,
                fallbackTint: fallbackTint,
                isPlaying: true,
                isMuted: false,
                width: screenWidth,
                height: screenHeight,
                layout: .centeredEdges,
                onBottomColorChange: onBottomColorChange
            )
            .ignoresSafeArea()

            Button(action: onDown) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 35, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .white.opacity(0.25), radius: 4, y: 4)
                    .frame(width: 50, height: 44)
            }
            .buttonStyle(.plain)
            .position(x: screenWidth / 2, y: screenHeight - 37)
        }
    }
}

private struct FigmaGlassCircleButton: View {
    let systemName: String
    let size: CGFloat
    var foregroundColor: Color = .white
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        LiquidGlassIconButton(
            systemName: systemName,
            size: size,
            symbolSize: max(18, size * 0.43),
            symbolWeight: .semibold,
            foregroundColor: foregroundColor,
            isEnabled: isEnabled,
            action: action
        )
    }
}

private enum AddVideoDesign {
    static let textPageBackgroundRGB = RGBColor(red: 0.47, green: 0.64, blue: 0.84)
    static let textPageBackground = Color(
        red: textPageBackgroundRGB.red,
        green: textPageBackgroundRGB.green,
        blue: textPageBackgroundRGB.blue
    )
}

struct RGBColor: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
}

private extension UIImage {
    func averageBottomColor() -> Color? {
        guard let cgImage else { return nil }
        return VideoColorSamplerAverage.averageBottomColor(from: cgImage)
    }
}

private enum VideoColorSamplerAverage {
    static func averageBottomColor(from image: CGImage) -> Color? {
        let width = min(72, image.width)
        let height = max(10, min(24, image.height / 7))
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let sourceRect = CGRect(
            x: 0,
            y: CGFloat(image.height - height),
            width: CGFloat(image.width),
            height: CGFloat(height)
        )

        guard let cropped = image.cropping(to: sourceRect) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

        var red: Double = 0
        var green: Double = 0
        var blue: Double = 0
        var totalWeight: Double = 0

        for y in 0..<height {
            let rowWeight = 0.55 + (Double(y) / Double(max(height - 1, 1))) * 0.9
            for x in 0..<width {
                let index = (y * width + x) * bytesPerPixel
                red += Double(pixels[index]) * rowWeight
                green += Double(pixels[index + 1]) * rowWeight
                blue += Double(pixels[index + 2]) * rowWeight
                totalWeight += rowWeight
            }
        }

        guard totalWeight > 0 else { return nil }

        return Color(
            red: min(max(red / totalWeight / 255, 0), 1),
            green: min(max(green / totalWeight / 255, 0), 1),
            blue: min(max(blue / totalWeight / 255, 0), 1)
        )
    }
}

private extension Color {
    var rgbComponents: RGBColor? {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        return RGBColor(red: red, green: green, blue: blue)
    }
}
