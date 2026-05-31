import Foundation
import SwiftData
import SwiftUI

struct VideoDiary: Identifiable, Equatable {
    let id: UUID
    let title: String
    let dateText: String
    let body: String
    let videoResource: String?
    let localVideoFilename: String?
    let displayAspectRatio: CGFloat
    let fallbackTint: Color

    init(
        id: UUID = UUID(),
        title: String,
        dateText: String,
        body: String,
        videoResource: String,
        displayAspectRatio: CGFloat,
        fallbackTint: Color
    ) {
        self.init(
            id: id,
            title: title,
            dateText: dateText,
            body: body,
            videoResource: videoResource,
            localVideoFilename: nil,
            displayAspectRatio: displayAspectRatio,
            fallbackTint: fallbackTint
        )
    }

    init(
        id: UUID = UUID(),
        title: String,
        dateText: String,
        body: String,
        localVideoFilename: String,
        displayAspectRatio: CGFloat,
        fallbackTint: Color
    ) {
        self.init(
            id: id,
            title: title,
            dateText: dateText,
            body: body,
            videoResource: nil,
            localVideoFilename: localVideoFilename,
            displayAspectRatio: displayAspectRatio,
            fallbackTint: fallbackTint
        )
    }

    private init(
        id: UUID,
        title: String,
        dateText: String,
        body: String,
        videoResource: String?,
        localVideoFilename: String?,
        displayAspectRatio: CGFloat,
        fallbackTint: Color
    ) {
        self.id = id
        self.title = title
        self.dateText = dateText
        self.body = body
        self.videoResource = videoResource
        self.localVideoFilename = localVideoFilename
        self.displayAspectRatio = displayAspectRatio
        self.fallbackTint = fallbackTint
    }

    var videoURL: URL? {
        if let localVideoFilename {
            return VideoFileStore.url(for: localVideoFilename)
        }

        guard let videoResource else {
            return nil
        }

        return Bundle.main.url(forResource: videoResource, withExtension: "mp4")
    }

    var isLandscapeVideo: Bool {
        displayAspectRatio > 1
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

extension VideoDiary {
    static let samples: [VideoDiary] = [
        VideoDiary(
            title: "Evening Walk Home",
            dateText: "20 May, 2026, 21:06",
            body: "The streetlights had just turned on, and the city looked like it was quietly changing scenes.",
            videoResource: "sample-vertical",
            displayAspectRatio: 720 / 1280,
            fallbackTint: Color(red: 0.19, green: 0.20, blue: 0.14)
        ),
        VideoDiary(
            title: "Wide Light Passing By",
            dateText: "20 May, 2026, 18:12",
            body: "The frame was wide and quiet, with just enough movement to make the afternoon feel alive.",
            videoResource: "sample-horizontal",
            displayAspectRatio: 1280 / 720,
            fallbackTint: Color(red: 0.19, green: 0.15, blue: 0.11)
        ),
        VideoDiary(
            title: "Late May on the Road",
            dateText: "20 May, 2026, 10:21",
            body: "A short road moment saved from the day. The scene moved quickly, but the colors stayed soft enough to remember.",
            videoResource: "sample-horizontal",
            displayAspectRatio: 1280 / 720,
            fallbackTint: Color(red: 0.17, green: 0.14, blue: 0.11)
        ),
        VideoDiary(
            title: "A Quiet Cat by the Water",
            dateText: "20 May, 2026, 10:21",
            body: "This afternoon, I saw a cat sitting silently beside the lake. It stayed on the wooden steps, facing the water as the sunlight shimmered on the surface.",
            videoResource: "sample-vertical",
            displayAspectRatio: 720 / 1280,
            fallbackTint: Color(red: 0.23, green: 0.31, blue: 0.40)
        ),
        VideoDiary(
            title: "Snowlight on the Street",
            dateText: "19 May, 2026, 13:48",
            body: "Today the city felt unusually quiet, as if the snow had softened every sound. The streets were bright under a clear blue sky, and the buildings looked clean and gentle.",
            videoResource: "sample-wechat",
            displayAspectRatio: 320 / 568,
            fallbackTint: Color(red: 0.30, green: 0.41, blue: 0.53)
        )
    ]
}
