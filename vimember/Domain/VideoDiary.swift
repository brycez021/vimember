import Foundation
import SwiftData
import SwiftUI

struct VideoDiary: Identifiable, Equatable {
    let id: UUID
    let title: String
    let dateText: String
    let body: String
    let localVideoFilename: String
    let displayAspectRatio: CGFloat
    let fallbackTint: Color

    init(
        id: UUID = UUID(),
        title: String,
        dateText: String,
        body: String,
        localVideoFilename: String,
        displayAspectRatio: CGFloat,
        fallbackTint: Color
    ) {
        self.id = id
        self.title = title
        self.dateText = dateText
        self.body = body
        self.localVideoFilename = localVideoFilename
        self.displayAspectRatio = displayAspectRatio
        self.fallbackTint = fallbackTint
    }

    var videoURL: URL? {
        VideoFileStore.url(for: localVideoFilename)
    }

    var isLandscapeVideo: Bool {
        displayAspectRatio > 1
    }
}

struct VideoAlbum: Identifiable, Equatable {
    let id: UUID
    var name: String
    var diaryIDs: [VideoDiary.ID]
    var coverDiaryID: VideoDiary.ID?
    var coverImageData: Data?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        diaryIDs: [VideoDiary.ID],
        coverDiaryID: VideoDiary.ID?,
        coverImageData: Data? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.diaryIDs = diaryIDs
        self.coverDiaryID = coverDiaryID
        self.coverImageData = coverImageData
        self.createdAt = createdAt
    }
}

@Model
final class VideoAlbumRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var diaryIDs: [VideoDiary.ID]
    var coverDiaryID: VideoDiary.ID?
    @Attribute(.externalStorage) var coverImageData: Data?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        diaryIDs: [VideoDiary.ID],
        coverDiaryID: VideoDiary.ID?,
        coverImageData: Data? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.diaryIDs = diaryIDs
        self.coverDiaryID = coverDiaryID
        self.coverImageData = coverImageData
        self.createdAt = createdAt
    }

    var album: VideoAlbum {
        VideoAlbum(
            id: id,
            name: name,
            diaryIDs: diaryIDs,
            coverDiaryID: coverDiaryID,
            coverImageData: coverImageData,
            createdAt: createdAt
        )
    }
}

@Model
final class VideoDiaryRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date
    var localVideoFilename: String
    var sourceAssetIdentifier: String?
    var displayAspectRatio: Double
    var fallbackRed: Double
    var fallbackGreen: Double
    var fallbackBlue: Double

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        localVideoFilename: String,
        sourceAssetIdentifier: String?,
        displayAspectRatio: Double,
        fallbackRed: Double,
        fallbackGreen: Double,
        fallbackBlue: Double
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.localVideoFilename = localVideoFilename
        self.sourceAssetIdentifier = sourceAssetIdentifier
        self.displayAspectRatio = displayAspectRatio
        self.fallbackRed = fallbackRed
        self.fallbackGreen = fallbackGreen
        self.fallbackBlue = fallbackBlue
    }

    var diary: VideoDiary {
        VideoDiary(
            id: id,
            title: title,
            dateText: Self.dateFormatter.string(from: createdAt),
            body: body,
            localVideoFilename: localVideoFilename,
            displayAspectRatio: CGFloat(displayAspectRatio),
            fallbackTint: Color(red: fallbackRed, green: fallbackGreen, blue: fallbackBlue)
        )
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM, yyyy, HH:mm"
        return formatter
    }()
}
