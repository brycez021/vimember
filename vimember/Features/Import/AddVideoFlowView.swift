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
            let gridItemSize = (screenWidth - 4) / 3

            ZStack(alignment: .topLeading) {
                Color.white.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(gridItemSize), spacing: 2), count: 3),
                        spacing: 2
                    ) {
                        ForEach(viewModel.items) { item in
                            VideoSelectionTile(
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

                FigmaGlassCircleButton(
                    systemName: "chevron.left",
                    size: buttonSize,
                    foregroundColor: .black,
                    action: onCancel
                )
                .position(x: (20 * xScale) + buttonSize / 2, y: (69 * yScale) + buttonSize / 2)

                FigmaGlassCircleButton(
                    systemName: "checkmark",
                    size: buttonSize,
                    foregroundColor: .black,
                    isEnabled: selectedItem != nil && !isPreparingDraft,
                    action: onNext
                )
                .position(x: screenWidth - (20 * xScale) - buttonSize / 2, y: (69 * yScale) + buttonSize / 2)

                if isPreparingDraft {
                    ProgressView()
                        .tint(.white)
                        .frame(width: buttonSize, height: buttonSize)
                        .background(.black.opacity(0.18), in: Circle())
                        .position(x: screenWidth - (20 * xScale) - buttonSize / 2, y: (69 * yScale) + buttonSize / 2)
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

private struct VideoSelectionTile: View {
    let item: PhotoLibraryVideoItem
    let isSelected: Bool
    let size: CGFloat

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
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

private struct AddVideoEditorView: View {
    let draft: VideoImportDraft
    let onBack: () -> Void
    let onComplete: (_ title: String, _ body: String) async throws -> Void

    @State private var title = ""
    @State private var bodyText = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var videoBackgroundColor: Color
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
            let buttonTop = 52 * yScale
            let buttonSide = 20 * xScale

            ScrollViewReader { proxy in
                ZStack(alignment: .topLeading) {
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
                                    withAnimation(.snappy(duration: 0.38)) {
                                        proxy.scrollTo("text", anchor: .top)
                                    }
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
                                screenWidth: screenWidth,
                                screenHeight: screenHeight,
                                onUp: {
                                    focusedField = nil
                                    withAnimation(.snappy(duration: 0.38)) {
                                        proxy.scrollTo("video", anchor: .top)
                                    }
                                }
                            )
                            .frame(width: screenWidth)
                            .id("text")
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .ignoresSafeArea()
                    .onAppear {
                        DispatchQueue.main.async {
                            proxy.scrollTo("video", anchor: .top)
                            focusedField = nil
                        }
                    }

                    FigmaGlassCircleButton(
                        systemName: "chevron.left",
                        size: buttonSize,
                        action: onBack
                    )
                    .position(x: buttonSide + buttonSize / 2, y: buttonTop + buttonSize / 2)

                    FigmaGlassCircleButton(
                        systemName: "checkmark",
                        size: buttonSize,
                        isEnabled: !isSaving,
                        action: {
                            Task {
                                await complete()
                            }
                        }
                    )
                    .position(x: screenWidth - buttonSide - buttonSize / 2, y: buttonTop + buttonSize / 2)

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
        focusedField = nil
        isSaving = true
        saveError = nil

        do {
            try await onComplete(title.trimmingCharacters(in: .whitespacesAndNewlines), bodyText)
        } catch {
            saveError = "Unable to save this video diary."
            isSaving = false
        }
    }
}

struct EditVideoDiaryFlowView: View {
    @Environment(\.dismiss) private var dismiss

    let diary: VideoDiary
    let onComplete: (_ title: String, _ body: String) async throws -> Void

    @State private var title: String
    @State private var bodyText: String
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var videoBackgroundColor: Color
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
            let buttonTop = 52 * yScale
            let buttonSide = 20 * xScale

            ScrollViewReader { proxy in
                ZStack(alignment: .topLeading) {
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
                                    withAnimation(.snappy(duration: 0.38)) {
                                        proxy.scrollTo("text", anchor: .top)
                                    }
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
                                screenWidth: screenWidth,
                                screenHeight: screenHeight,
                                onUp: {
                                    focusedField = nil
                                    withAnimation(.snappy(duration: 0.38)) {
                                        proxy.scrollTo("video", anchor: .top)
                                    }
                                }
                            )
                            .frame(width: screenWidth)
                            .id("text")
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .ignoresSafeArea()
                    .onAppear {
                        DispatchQueue.main.async {
                            proxy.scrollTo("text", anchor: .top)
                            focusedField = .body
                        }
                    }

                    FigmaGlassCircleButton(
                        systemName: "chevron.left",
                        size: buttonSize,
                        action: {
                            dismiss()
                        }
                    )
                    .position(x: buttonSide + buttonSize / 2, y: buttonTop + buttonSize / 2)

                    FigmaGlassCircleButton(
                        systemName: "checkmark",
                        size: buttonSize,
                        isEnabled: !isSaving,
                        action: {
                            Task {
                                await complete()
                            }
                        }
                    )
                    .position(x: screenWidth - buttonSide - buttonSize / 2, y: buttonTop + buttonSize / 2)

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
        focusedField = nil
        isSaving = true
        saveError = nil

        do {
            try await onComplete(title.trimmingCharacters(in: .whitespacesAndNewlines), bodyText)
            dismiss()
        } catch {
            saveError = "Unable to save this video diary."
            isSaving = false
        }
    }
}

private struct AddTextPage: View {
    @Binding var title: String
    @Binding var bodyText: String
    var focusedField: FocusState<AddVideoEditorField?>.Binding
    let dateText: String
    let backgroundColor: Color
    let screenWidth: CGFloat
    let screenHeight: CGFloat
    let onUp: () -> Void

    var body: some View {
        let xScale = screenWidth / 420
        let yScale = screenHeight / 912
        let textLeft = 23 * xScale
        let textTop = 140 * yScale
        let textWidth = min(384 * xScale, screenWidth - textLeft * 2)
        let dividerWidth = min(374 * xScale, textWidth)
        let buttonSize = 44 * xScale
        let buttonTop = 52 * yScale
        let arrowCenterY = buttonTop + buttonSize / 2

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
                        focusedField.wrappedValue = .body
                    }
                    .frame(height: 36)
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
                    if bodyText.isEmpty {
                        AddTextPlaceholderLabel(
                            text: "Start writing...",
                            labelWidth: textWidth
                        )
                            .allowsHitTesting(false)
                    }

                    AddBodyTextView(
                        text: $bodyText,
                        focusedField: focusedField,
                        preferredWidth: textWidth
                    )
                }
            }
            .frame(width: textWidth, alignment: .leading)
            .padding(.leading, textLeft)
            .padding(.top, textTop)
        }
        .frame(width: screenWidth, alignment: .topLeading)
        .frame(minHeight: screenHeight, alignment: .topLeading)
        .background(backgroundColor.ignoresSafeArea())
    }
}

private enum AddVideoEditorField {
    case title
    case body
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

private struct AddBodyTextView: UIViewRepresentable {
    @Binding var text: String
    var focusedField: FocusState<AddVideoEditorField?>.Binding
    let preferredWidth: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textColor = .white
        textView.tintColor = .white
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false
        textView.alwaysBounceVertical = false
        textView.autocorrectionType = .yes
        textView.autocapitalizationType = .sentences
        textView.keyboardDismissMode = .interactive
        textView.typingAttributes = Self.textAttributes
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self

        if textView.text != text {
            textView.attributedText = NSAttributedString(string: text, attributes: Self.textAttributes)
        }
        textView.typingAttributes = Self.textAttributes

        if focusedField.wrappedValue == .body {
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
        } else if textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? preferredWidth
        let fittingSize = uiView.sizeThatFits(
            CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: max(22, fittingSize.height))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AddBodyTextView

        init(_ parent: AddBodyTextView) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.focusedField.wrappedValue = .body
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.focusedField.wrappedValue == .body {
                parent.focusedField.wrappedValue = nil
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            textView.typingAttributes = AddBodyTextView.textAttributes
        }
    }

    private static var textAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 22
        paragraph.maximumLineHeight = 22
        paragraph.paragraphSpacing = 16
        paragraph.lineBreakMode = .byWordWrapping

        let font = UIFont(name: "PingFangSC-Regular", size: 16)
            ?? .systemFont(ofSize: 16, weight: .regular)

        return [
            .font: font,
            .foregroundColor: UIColor.white,
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
