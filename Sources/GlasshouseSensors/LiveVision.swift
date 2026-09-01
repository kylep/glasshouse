#if os(iOS)
import Foundation
import Vision
import Photos
import UIKit
import GlasshouseCore

/// What a computer can read out of your photographs.
///
/// Vision itself needs no permission of any kind — it is pure computation, and
/// the framework will happily analyse any image an app can already reach. The
/// photo-library permission is the only gate, and people grant it thinking they
/// are sharing pictures rather than their contents.
///
/// So an app with photo access can read every word visible in your camera roll:
/// documents, whiteboards, prescription labels, screenshots of private
/// conversations. And it can do it on-device, silently, with nothing to
/// distinguish it from an app that merely displays your photos.
enum PhotoAnalysis {
    /// Runs `work` over the most recent `limit` images.
    ///
    /// Deliberately capped and deliberately recent: the point is to demonstrate
    /// what is possible, not to index somebody's entire life on a refresh.
    static func overRecentPhotos<T: Sendable>(
        limit: Int,
        _ work: @escaping @Sendable (CGImage) async -> T?
    ) async -> [T] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return [] }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        let assets = PHAsset.fetchAssets(with: .image, options: options)

        var results: [T] = []
        for index in 0..<assets.count {
            guard let image = await loadImage(assets[index]) else { continue }
            if let outcome = await work(image) { results.append(outcome) }
        }
        return results
    }

    private static func loadImage(_ asset: PHAsset) async -> CGImage? {
        await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
            let once = SingleResume(continuation)

            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = false   // never fetch from iCloud
            options.resizeMode = .fast

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 1024, height: 1024),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                once.resume(image?.cgImage)
            }
        }
    }
}

/// Every word visible in your recent photographs.
public struct LiveVisionTextSource: SensorSource {
    public let id: SensorID = "vision.text"

    public init() {}

    /// Vision needs nothing; the photo library does. Reported as the library's
    /// state, because that is the gate a person actually encounters.
    public func availability() async -> SensorAvailability {
        LivePhotoLocationSource.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    public func requestAccess() async -> SensorAvailability {
        LivePhotoLocationSource.map(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    public func read() async -> SensorSample? {
        let findings: [[String]] = await PhotoAnalysis.overRecentPhotos(limit: 12) { image in
            var request = RecognizeTextRequest()
            request.recognitionLevel = .fast
            guard let observations = try? await request.perform(on: image) else { return nil }
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            return lines.isEmpty ? nil : lines
        }

        let photosWithText = findings.count
        let allLines = findings.flatMap { $0 }
        let words = allLines.flatMap { $0.split(separator: " ") }.count

        var fields: [SensorField] = [
            SensorField("Recent photos scanned", .integer(12)),
            SensorField("Containing readable text", .integer(photosWithText)),
            SensorField("Words extracted", .integer(words)),
            SensorField("Permission Vision required", .text("none — the photo library is the only gate")),
        ]

        // A sample rather than the lot. The demonstration lands with a handful
        // of phrases; dumping everything readable from a camera roll into a
        // scrollable list would be gratuitous.
        if let sample = allLines.first(where: { $0.count > 3 }) {
            fields.append(SensorField("For example", .text(sample)))
        }

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: fields)
    }
}

/// How many people are in your recent photographs.
public struct LiveVisionFacesSource: SensorSource {
    public let id: SensorID = "vision.faces"

    public init() {}

    public func availability() async -> SensorAvailability {
        LivePhotoLocationSource.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    public func requestAccess() async -> SensorAvailability {
        LivePhotoLocationSource.map(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    public func read() async -> SensorSample? {
        let counts: [Int] = await PhotoAnalysis.overRecentPhotos(limit: 12) { image in
            let request = DetectFaceRectanglesRequest()
            guard let faces = try? await request.perform(on: image) else { return nil }
            return faces.count
        }

        let withFaces = counts.filter { $0 > 0 }.count
        let total = counts.reduce(0, +)

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
            SensorField("Recent photos scanned", .integer(12)),
            SensorField("Containing people", .integer(withFaces)),
            SensorField("Faces found", .integer(total)),
            SensorField("Ran entirely on device", .boolean(true)),
            // Measured in a Simulator: every neural-engine-backed Vision
            // request fails there while text recognition works, so a zero here
            // on a phone means no faces rather than no capability.
            SensorField("Permission Vision required", .text("none")),
        ])
    }
}
#endif
