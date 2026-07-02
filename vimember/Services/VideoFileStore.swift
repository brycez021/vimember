import Foundation

enum VideoFileStore {
    private static let directoryName = "ImportedVideos"

    static var videosDirectory: URL {
        get throws {
            let baseURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = baseURL.appending(path: directoryName, directoryHint: .isDirectory)
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            return directory
        }
    }

    static func url(for filename: String) -> URL? {
        try? videosDirectory.appending(path: filename)
    }

    static func copyVideo(from sourceURL: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            let directory = try videosDirectory
            let originalExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
            let filename = "\(UUID().uuidString).\(originalExtension)"
            let destinationURL = directory.appending(path: filename)

            let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return filename
        }.value
    }

    static func deleteVideo(named filename: String) async throws {
        try await Task.detached(priority: .utility) {
            let url = try videosDirectory.appending(path: filename)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return
            }

            try FileManager.default.removeItem(at: url)
        }.value
    }
}
