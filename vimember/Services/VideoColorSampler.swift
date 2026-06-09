import AVFoundation
import CoreGraphics
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

    private static func averageBottomColor(from image: CGImage) -> Color? {
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
