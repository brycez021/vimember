import Foundation
import SwiftUI

struct VideoDiary: Identifiable, Equatable {
    let id: UUID
    let title: String
    let dateText: String
    let body: String
    let videoResource: String
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
        self.id = id
        self.title = title
        self.dateText = dateText
        self.body = body
        self.videoResource = videoResource
        self.displayAspectRatio = displayAspectRatio
        self.fallbackTint = fallbackTint
    }

    var videoURL: URL? {
        Bundle.main.url(forResource: videoResource, withExtension: "mp4")
    }

    var isLandscapeVideo: Bool {
        displayAspectRatio > 1
    }
}

extension VideoDiary {
    static let samples: [VideoDiary] = [
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
            title: "Wide Light Passing By",
            dateText: "20 May, 2026, 18:12",
            body: "The frame was wide and quiet, with just enough movement to make the afternoon feel alive.",
            videoResource: "sample-horizontal",
            displayAspectRatio: 1280 / 720,
            fallbackTint: Color(red: 0.19, green: 0.15, blue: 0.11)
        ),
        VideoDiary(
            title: "Evening Walk Home",
            dateText: "20 May, 2026, 21:06",
            body: "The streetlights had just turned on, and the city looked like it was quietly changing scenes.",
            videoResource: "sample-vertical",
            displayAspectRatio: 720 / 1280,
            fallbackTint: Color(red: 0.19, green: 0.20, blue: 0.14)
        )
    ]
}
