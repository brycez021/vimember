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

    func replacingText(title: String, body: String) -> VideoDiary {
        if let localVideoFilename {
            return VideoDiary(
                id: id,
                title: title,
                dateText: dateText,
                body: body,
                localVideoFilename: localVideoFilename,
                displayAspectRatio: displayAspectRatio,
                fallbackTint: fallbackTint
            )
        }

        return VideoDiary(
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
            title: "Street Corner Pause",
            dateText: "31 May, 2026, 22:41",
            body: "A quick vertical moment from the street. Nothing dramatic happened, but the frame kept a small piece of the day exactly as it felt. The path was bright in patches, then quiet under the leaves, and every few seconds the light changed enough to make the same wall feel like a different place. I remember the small shake of the phone, the sound of wheels on the pavement, and the way the afternoon kept opening up ahead. It was not an important scene in the usual sense, but it had that strange diary quality where a plain minute becomes more accurate than a polished photograph. Later, when I watched it back, I noticed things I missed while moving through it: the shadow crossing the road, the color on the wall, the slow turn of the handlebar, the tiny pause before the rider passed into sun again.",
            videoResource: "sample-street-vertical",
            displayAspectRatio: 720.0 / 1280.0,
            fallbackTint: Color(red: 0.22, green: 0.25, blue: 0.23)
        ),
        VideoDiary(
            title: "Campus Voices",
            dateText: "31 May, 2026, 20:53",
            body: "People gathered around the plaza while the afternoon kept moving in the background. The wide frame makes the scene feel almost like a note pinned to a busy public day.",
            videoResource: "sample-campus-wide",
            displayAspectRatio: 1920.0 / 1080.0,
            fallbackTint: Color(red: 0.44, green: 0.49, blue: 0.55)
        ),
        VideoDiary(
            title: "City Light Ride",
            dateText: "31 May, 2026, 19:26",
            body: "The phone stayed upright while the city slipped past in layers: reflected lights, moving shadows, and little flashes of color that only make sense when they are played back later. I like how this kind of clip does not explain the whole day. It just saves the rhythm of being there.",
            videoResource: "sample-city-vertical",
            displayAspectRatio: 2160.0 / 3840.0,
            fallbackTint: Color(red: 0.28, green: 0.30, blue: 0.34)
        ),
        VideoDiary(
            title: "Office Table",
            dateText: "31 May, 2026, 18:08",
            body: "Just a few seconds from the room before leaving.",
            videoResource: "sample-office-wide",
            displayAspectRatio: 1280.0 / 720.0,
            fallbackTint: Color(red: 0.33, green: 0.31, blue: 0.27)
        )
    ]
}
