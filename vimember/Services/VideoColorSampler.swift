import AVFoundation
import CoreGraphics
import Foundation
import SwiftUI
import UIKit

struct VideoFrameSample {
    let bottomColor: Color
    let image: UIImage?
}

actor VideoColorSampler {
    static let shared = VideoColorSampler()

    private var cache: [URL: VideoFrameSample] = [:]

    func sample(for url: URL, fallback: Color) async -> VideoFrameSample {
        if let cached = cache[url] {
            return cached
        }

        guard let sample = await makeSample(for: url, fallback: fallback) else {
            let fallbackSample = VideoFrameSample(bottomColor: fallback, image: nil)
            cache[url] = fallbackSample
            return fallbackSample
        }

        cache[url] = sample
        return sample
    }

    private func makeSample(for url: URL, fallback: Color) async -> VideoFrameSample? {
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 420, height: 747)

            do {
                let cgImage = try generator.copyCGImage(at: CMTime(seconds: 0.8, preferredTimescale: 600), actualTime: nil)
                return VideoFrameSample(
                    bottomColor: Self.averageBottomColor(from: cgImage) ?? fallback,
                    image: UIImage(cgImage: cgImage)
                )
            } catch {
                return nil
            }
        }.value
    }

    fileprivate static func averageBottomColor(from image: CGImage) -> Color? {
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

        guard totalWeight > 0 else {
            return nil
        }

        return Color(
            red: min(max(red / totalWeight / 255, 0), 1),
            green: min(max(green / totalWeight / 255, 0), 1),
            blue: min(max(blue / totalWeight / 255, 0), 1)
        )
    }
}

struct VideoDerivedGalleryAssets {
    let thumbnail: UIImage?
    let bottomColor: Color?
}

actor VideoDerivedAssetStore {
    static let shared = VideoDerivedAssetStore()

    private struct ColorMetadata: Codable {
        let red: Double
        let green: Double
        let blue: Double
    }

    private struct CacheKey: Hashable {
        let value: String
    }

    private static let directoryName = "VideoDerivedAssets"
    private static let galleryThumbnailPixelLength: CGFloat = 420

    private var memoryCache: [CacheKey: VideoDerivedGalleryAssets] = [:]
    private var inFlightTasks: [CacheKey: Task<VideoDerivedGalleryAssets?, Never>] = [:]

    func cachedGalleryAssets(for url: URL?, fallback: Color) async -> VideoDerivedGalleryAssets {
        guard let url, let key = cacheKey(for: url) else {
            return VideoDerivedGalleryAssets(thumbnail: nil, bottomColor: nil)
        }

        if let cached = memoryCache[key] {
            return cached
        }

        let assets = await readAssets(for: key)
        memoryCache[key] = assets
        return assets
    }

    func prepareGalleryAssets(for diaries: [VideoDiary]) async {
        for diary in diaries {
            guard !Task.isCancelled else {
                return
            }

            guard let url = diary.videoURL else { continue }
            _ = await prepareGalleryAssets(for: url, fallback: diary.fallbackTint)
            await Task.yield()
        }
    }

    func prepareGalleryAssets(for url: URL?, fallback: Color) async -> VideoDerivedGalleryAssets? {
        guard let url, let key = cacheKey(for: url) else {
            return nil
        }

        let existing = await readAssets(for: key)
        if existing.thumbnail != nil, existing.bottomColor != nil {
            memoryCache[key] = existing
            return existing
        }

        if let inFlightTask = inFlightTasks[key] {
            return await inFlightTask.value
        }

        let task = Task<VideoDerivedGalleryAssets?, Never>(priority: .utility) {
            await Self.generateAssets(for: url, key: key, fallback: fallback)
        }
        inFlightTasks[key] = task

        let assets = await task.value
        inFlightTasks[key] = nil
        if let assets {
            memoryCache[key] = assets
        }
        return assets
    }

    private func readAssets(for key: CacheKey) async -> VideoDerivedGalleryAssets {
        await Task.detached(priority: .utility) {
            let thumbnail = Self.readThumbnail(for: key)
            let bottomColor = Self.readBottomColor(for: key)
            return VideoDerivedGalleryAssets(thumbnail: thumbnail, bottomColor: bottomColor)
        }.value
    }

    private nonisolated static func generateAssets(for url: URL, key: CacheKey, fallback: Color) async -> VideoDerivedGalleryAssets? {
        await Task.detached(priority: .utility) {
            guard let cgImage = makeGalleryCGImage(for: url) else {
                return nil
            }

            let thumbnail = UIImage(cgImage: cgImage)
            let bottomColor = VideoColorSampler.averageBottomColor(from: cgImage) ?? fallback
            writeThumbnail(thumbnail, for: key)
            writeBottomColor(bottomColor, for: key)
            return VideoDerivedGalleryAssets(thumbnail: thumbnail, bottomColor: bottomColor)
        }.value
    }

    private nonisolated func cacheKey(for url: URL) -> CacheKey? {
        guard url.isFileURL else {
            return CacheKey(value: sanitizedCacheName(from: url.absoluteString))
        }

        let path = url.path
        guard FileManager.default.isReadableFile(atPath: path) else {
            return nil
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modifiedAt = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let rawKey = "\(url.lastPathComponent)-\(fileSize)-\(Int(modifiedAt))"
        return CacheKey(value: sanitizedCacheName(from: rawKey))
    }

    private nonisolated static func makeGalleryCGImage(for url: URL) -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.maximumSize = CGSize(
            width: galleryThumbnailPixelLength,
            height: galleryThumbnailPixelLength
        )

        for seconds in galleryCandidateSeconds(for: asset) {
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                return cgImage
            }
        }

        return nil
    }

    private nonisolated static func galleryCandidateSeconds(for asset: AVAsset) -> [Double] {
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration.isFinite, duration > 0 else {
            return [0]
        }

        let endPadding = min(0.05, duration * 0.1)
        let upperBound = max(0, duration - endPadding)
        let candidates = [
            min(0.8, upperBound),
            duration / 2,
            duration * 0.25,
            duration * 0.75,
            0
        ]

        return candidates.reduce(into: [Double]()) { result, seconds in
            let clamped = min(max(0, seconds), upperBound)
            guard !result.contains(where: { abs($0 - clamped) < 0.01 }) else { return }
            result.append(clamped)
        }
    }

    private nonisolated static func readThumbnail(for key: CacheKey) -> UIImage? {
        let url = thumbnailURL(for: key)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return UIImage(data: data)
    }

    private nonisolated static func writeThumbnail(_ image: UIImage, for key: CacheKey) {
        guard let data = image.jpegData(compressionQuality: 0.82) else {
            return
        }

        try? ensureDirectory()
        try? data.write(to: thumbnailURL(for: key), options: Data.WritingOptions.atomic)
    }

    private nonisolated static func readBottomColor(for key: CacheKey) -> Color? {
        let url = metadataURL(for: key)
        guard
            let data = try? Data(contentsOf: url),
            let metadata = try? JSONDecoder().decode(ColorMetadata.self, from: data)
        else {
            return nil
        }

        return Color(red: metadata.red, green: metadata.green, blue: metadata.blue)
    }

    private nonisolated static func writeBottomColor(_ color: Color, for key: CacheKey) {
        guard let rgb = rgbComponents(from: color) else {
            return
        }

        let metadata = ColorMetadata(
            red: rgb.red,
            green: rgb.green,
            blue: rgb.blue
        )

        guard let data = try? JSONEncoder().encode(metadata) else {
            return
        }

        try? ensureDirectory()
        try? data.write(to: metadataURL(for: key), options: Data.WritingOptions.atomic)
    }

    private nonisolated static func rgbComponents(from color: Color) -> (red: Double, green: Double, blue: Double)? {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        return (Double(red), Double(green), Double(blue))
    }

    private nonisolated static func thumbnailURL(for key: CacheKey) -> URL {
        directoryURL().appendingPathComponent("\(key.value)-gallery.jpg", isDirectory: false)
    }

    private nonisolated static func metadataURL(for key: CacheKey) -> URL {
        directoryURL().appendingPathComponent("\(key.value)-color.json", isDirectory: false)
    }

    private nonisolated static func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: directoryURL(),
            withIntermediateDirectories: true
        )
    }

    private nonisolated static func directoryURL() -> URL {
        let baseURL = (try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory

        return baseURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    private nonisolated func sanitizedCacheName(from value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let name = String(scalars)
        return name.isEmpty ? UUID().uuidString : name
    }
}
