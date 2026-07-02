import SwiftData
import SwiftUI

@main
struct VimemberApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(for: [VideoDiaryRecord.self, VideoAlbumRecord.self])
    }
}
