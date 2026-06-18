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

struct SampleVideoDiarySeed {
    let title: String
    let dateText: String
    let body: String
    let videoResource: String
    let albumID: UUID
    let albumTitle: String
    let displayAspectRatio: CGFloat
    let fallbackTint: Color

    var sourceAssetIdentifier: String {
        "vimember.sample.\(videoResource)"
    }

    var createdAt: Date {
        VideoDiaryRecord.dateFormatter.date(from: dateText) ?? Date()
    }
}

struct BundledImportedVideoDiarySeed {
    let title: String
    let dateText: String
    let body: String
    let videoResource: String
    let displayAspectRatio: CGFloat
    let fallbackTint: Color

    var sourceAssetIdentifier: String {
        "vimember.imported.\(videoResource)"
    }

    var createdAt: Date {
        VideoDiaryRecord.dateFormatter.date(from: dateText) ?? Date()
    }
}

extension SampleVideoDiarySeed {
    static let all: [SampleVideoDiarySeed] = [
        SampleVideoDiarySeed(
            title: "Street Corner Pause",
            dateText: "31 May, 2026, 22:41",
            body: "A quick vertical moment from the street. Nothing dramatic happened, but the frame kept a small piece of the day exactly as it felt. The path was bright in patches, then quiet under the leaves, and every few seconds the light changed enough to make the same wall feel like a different place. I remember the small shake of the phone, the sound of wheels on the pavement, and the way the afternoon kept opening up ahead. It was not an important scene in the usual sense, but it had that strange diary quality where a plain minute becomes more accurate than a polished photograph. Later, when I watched it back, I noticed things I missed while moving through it: the shadow crossing the road, the color on the wall, the slow turn of the handlebar, the tiny pause before the rider passed into sun again.",
            videoResource: "sample-street-vertical",
            albumID: UUID(uuidString: "35E37D7B-02F5-4B65-8D4C-9C3A1F0A0001")!,
            albumTitle: "Street",
            displayAspectRatio: 720.0 / 1280.0,
            fallbackTint: Color(red: 0.22, green: 0.25, blue: 0.23)
        ),
        SampleVideoDiarySeed(
            title: "Campus Voices",
            dateText: "31 May, 2026, 20:53",
            body: "People gathered around the plaza while the afternoon kept moving in the background. The wide frame makes the scene feel almost like a note pinned to a busy public day.",
            videoResource: "sample-campus-wide",
            albumID: UUID(uuidString: "35E37D7B-02F5-4B65-8D4C-9C3A1F0A0002")!,
            albumTitle: "Campus",
            displayAspectRatio: 1920.0 / 1080.0,
            fallbackTint: Color(red: 0.44, green: 0.49, blue: 0.55)
        ),
        SampleVideoDiarySeed(
            title: "City Light Ride",
            dateText: "31 May, 2026, 19:26",
            body: "The phone stayed upright while the city slipped past in layers: reflected lights, moving shadows, and little flashes of color that only make sense when they are played back later. I like how this kind of clip does not explain the whole day. It just saves the rhythm of being there.",
            videoResource: "sample-city-vertical",
            albumID: UUID(uuidString: "35E37D7B-02F5-4B65-8D4C-9C3A1F0A0003")!,
            albumTitle: "City",
            displayAspectRatio: 2160.0 / 3840.0,
            fallbackTint: Color(red: 0.28, green: 0.30, blue: 0.34)
        ),
        SampleVideoDiarySeed(
            title: "Office Table",
            dateText: "31 May, 2026, 18:08",
            body: "Just a few seconds from the room before leaving.",
            videoResource: "sample-office-wide",
            albumID: UUID(uuidString: "35E37D7B-02F5-4B65-8D4C-9C3A1F0A0004")!,
            albumTitle: "Office",
            displayAspectRatio: 1280.0 / 720.0,
            fallbackTint: Color(red: 0.33, green: 0.31, blue: 0.27)
        )
    ]
}

extension BundledImportedVideoDiarySeed {
    static let resourceSubdirectory = "BundledImportedVideos"

    static let all: [BundledImportedVideoDiarySeed] = [
        BundledImportedVideoDiarySeed(
            title: "Balloon Shadow",
            dateText: "6 Jun, 2026, 21:16",
            body: "The basket lifted slowly enough that the whole place seemed to wait for it. I kept the phone pointed up from underneath the balloon, half watching the flame and half watching the desert pull away below. It was only a few seconds, but it has that suspended feeling I like in a video diary: a little fear, a lot of air, and the strange calm that comes when the ground becomes texture instead of a place to stand.",
            videoResource: "11319086-hd_1080_1920_30fps",
            displayAspectRatio: 1080.0 / 1920.0,
            fallbackTint: Color(red: 0.54, green: 0.39, blue: 0.32)
        ),
        BundledImportedVideoDiarySeed(
            title: "Empty Garden Chairs",
            dateText: "6 Jun, 2026, 20:02",
            body: "Two chairs under the tree, no one in them. The quiet made the table feel recently abandoned, like somebody had stepped inside for water and would be back before the shade moved.",
            videoResource: "12145227_2160_3840_30fps",
            displayAspectRatio: 2160.0 / 3840.0,
            fallbackTint: Color(red: 0.38, green: 0.40, blue: 0.30)
        ),
        BundledImportedVideoDiarySeed(
            title: "Sunflowers Looking Up",
            dateText: "6 Jun, 2026, 18:44",
            body: "The sunflowers were doing the whole performance without needing anyone to notice. Blue sky, yellow petals, a little wind, then the same simple motion again.",
            videoResource: "13415877_3840_2160_30fps",
            displayAspectRatio: 3840.0 / 2160.0,
            fallbackTint: Color(red: 0.78, green: 0.66, blue: 0.21)
        ),
        BundledImportedVideoDiarySeed(
            title: "Stone Path",
            dateText: "6 Jun, 2026, 17:31",
            body: "A narrow path through rocks, with one person moving carefully through the middle. The frame feels rough around the edges in a good way, like a memory that still has dust on it.",
            videoResource: "13880522_3840_2160_25fps",
            displayAspectRatio: 3840.0 / 2160.0,
            fallbackTint: Color(red: 0.39, green: 0.40, blue: 0.36)
        ),
        BundledImportedVideoDiarySeed(
            title: "Garage Glow",
            dateText: "5 Jun, 2026, 23:18",
            body: "Late light from a small screen, orange walls, a drink on the table, and the feeling that the day had finally narrowed down to one corner of the room.",
            videoResource: "14351106_3840_2160_60fps",
            displayAspectRatio: 3840.0 / 2160.0,
            fallbackTint: Color(red: 0.55, green: 0.30, blue: 0.16)
        ),
        BundledImportedVideoDiarySeed(
            title: "Counter Cat",
            dateText: "5 Jun, 2026, 22:06",
            body: "The cat jumped onto the counter as if it owned the whole apartment, then paused in exactly the patch of light that made the scene look staged. It was not staged. That is the best part. The bottles, the small kitchen shadows, the way the animal looked both proud and completely uninterested in being recorded: all of it makes the room feel more honest than a clean photo would have.",
            videoResource: "15117571_3840_2160_30fps",
            displayAspectRatio: 3840.0 / 2160.0,
            fallbackTint: Color(red: 0.48, green: 0.38, blue: 0.25)
        ),
        BundledImportedVideoDiarySeed(
            title: "Sunset Hoods",
            dateText: "5 Jun, 2026, 20:39",
            body: "We stayed facing the water until the sky turned pink enough that nobody had anything useful to say. That was fine.",
            videoResource: "15328714_3840_2160_25fps",
            displayAspectRatio: 3840.0 / 2160.0,
            fallbackTint: Color(red: 0.70, green: 0.44, blue: 0.32)
        ),
        BundledImportedVideoDiarySeed(
            title: "Skyline Sit",
            dateText: "5 Jun, 2026, 19:52",
            body: "The city looked far away and very awake. Three people sat at the edge of the water, small against all those windows, and the whole skyline kept shimmering like it was trying not to hold still.",
            videoResource: "15370645_3840_2160_30fps",
            displayAspectRatio: 3840.0 / 2160.0,
            fallbackTint: Color(red: 0.21, green: 0.23, blue: 0.28)
        ),
        BundledImportedVideoDiarySeed(
            title: "Sofa Stretch",
            dateText: "5 Jun, 2026, 16:10",
            body: "A sleepy cat, a folded blanket, a very serious patch of afternoon light.",
            videoResource: "15372912_2160_3840_30fps",
            displayAspectRatio: 2160.0 / 3840.0,
            fallbackTint: Color(red: 0.45, green: 0.39, blue: 0.34)
        ),
        BundledImportedVideoDiarySeed(
            title: "Blue Dive",
            dateText: "4 Jun, 2026, 21:42",
            body: "Everything turned blue the second the camera went under. The boat became a shadow above, the diver became a small moving line, and for a moment the whole clip forgot about the surface. I like how underwater videos make time feel thicker. Every motion seems slower, every direction less obvious. Watching it later, the memory is not about what happened next. It is about that first quiet second when the world changed color.",
            videoResource: "15586186_1920_1080_25fps",
            displayAspectRatio: 1920.0 / 1080.0,
            fallbackTint: Color(red: 0.12, green: 0.33, blue: 0.56)
        ),
        BundledImportedVideoDiarySeed(
            title: "After Rain",
            dateText: "4 Jun, 2026, 20:25",
            body: "Wet pavement, blue evening, and traffic lights drawing long lines across the road.",
            videoResource: "15764044_2160_3840_50fps",
            displayAspectRatio: 2160.0 / 3840.0,
            fallbackTint: Color(red: 0.10, green: 0.20, blue: 0.33)
        ),
        BundledImportedVideoDiarySeed(
            title: "窗帘后的小猫",
            dateText: "4 Jun, 2026, 18:07",
            body: "它一直躲在窗帘后面，只露出一点点轮廓，好像在认真观察房间里发生的所有事情。其实什么也没有发生，暖气片很安静，光也很安静，但我还是把手机举起来拍了几秒。后来再看这段视频的时候，反而觉得这种没有情节的时刻最像生活本身：不用解释，不用完成什么，只是有一只猫、一层薄薄的白色窗帘，还有下午慢慢停下来的声音。",
            videoResource: "15798732_2160_3840_30fps",
            displayAspectRatio: 2160.0 / 3840.0,
            fallbackTint: Color(red: 0.72, green: 0.68, blue: 0.61)
        ),
        BundledImportedVideoDiarySeed(
            title: "Snow Road Walk",
            dateText: "3 Jun, 2026, 22:14",
            body: "A road through snow and dark hills, with one person walking into the cold open space ahead. The clouds were catching a little last light, just enough to make the scene feel less empty than it should have.",
            videoResource: "15848590_1920_1080_30fps",
            displayAspectRatio: 1920.0 / 1080.0,
            fallbackTint: Color(red: 0.42, green: 0.47, blue: 0.50)
        ),
        BundledImportedVideoDiarySeed(
            title: "Lake Crossing",
            dateText: "3 Jun, 2026, 20:33",
            body: "A few people crossed the stones by the water. No one rushed. That made it better.",
            videoResource: "15900786_3840_2160_30fps",
            displayAspectRatio: 3840.0 / 2160.0,
            fallbackTint: Color(red: 0.40, green: 0.52, blue: 0.43)
        ),
        BundledImportedVideoDiarySeed(
            title: "Fishing Line",
            dateText: "3 Jun, 2026, 18:56",
            body: "The rod cut across the pale sky while the water stayed almost flat. It felt like waiting without being impatient.",
            videoResource: "16007287_1080_1920_60fps",
            displayAspectRatio: 1080.0 / 1920.0,
            fallbackTint: Color(red: 0.62, green: 0.55, blue: 0.47)
        ),
        BundledImportedVideoDiarySeed(
            title: "Studio Table",
            dateText: "3 Jun, 2026, 16:22",
            body: "Two people at a messy table, color tests everywhere, and the easy concentration that happens when nobody is trying to make the room look finished.",
            videoResource: "5670949-uhd_3840_2160_30fps",
            displayAspectRatio: 3840.0 / 2160.0,
            fallbackTint: Color(red: 0.62, green: 0.55, blue: 0.49)
        ),
        BundledImportedVideoDiarySeed(
            title: "Painter's Corner",
            dateText: "3 Jun, 2026, 14:40",
            body: "The studio had the good kind of clutter: brushes, cups, boards, paper, and one person keeping their attention on the canvas while the rest of the room quietly explained how many attempts came before this one.",
            videoResource: "7098293-uhd_2160_3840_25fps",
            displayAspectRatio: 2160.0 / 3840.0,
            fallbackTint: Color(red: 0.68, green: 0.58, blue: 0.40)
        ),
        BundledImportedVideoDiarySeed(
            title: "Room Presentation",
            dateText: "3 Jun, 2026, 11:18",
            body: "A small presentation in a bright room. The chairs, the board, the person standing near the screen: all of it had that slightly nervous energy before people start asking questions.",
            videoResource: "7647824-hd_1920_1080_30fps",
            displayAspectRatio: 1920.0 / 1080.0,
            fallbackTint: Color(red: 0.55, green: 0.58, blue: 0.58)
        )
    ]
}
