#if os(iOS)
import Foundation
import Photos
import CoreLocation
import GlasshouseCore

/// What your camera roll knows about where you have been.
///
/// The most visceral thing this app can show, and it is fully buildable in the
/// Simulator: a stock iOS 26.2 runtime ships six photos carrying real GPS
/// coordinates and full EXIF, present even on a never-booted device.
///
/// `PHAsset.location` needs no location permission of its own — it arrives with
/// library access, which is exactly the sort of thing people do not expect.
public struct LivePhotoLocationSource: SensorSource {
    public let id: SensorID = "photos.asset_location"

    public init() {}

    public func availability() async -> SensorAvailability {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    public func requestAccess() async -> SensorAvailability {
        Self.map(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    public func read() async -> SensorSample? {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(with: .image, options: options)

        guard assets.count > 0 else { return nil }

        var located = 0
        var earliest: Date?
        var latest: Date?
        var southWest: (lat: Double, lon: Double)?
        var northEast: (lat: Double, lon: Double)?

        assets.enumerateObjects { asset, _, _ in
            if let date = asset.creationDate {
                if earliest == nil || date < earliest! { earliest = date }
                if latest == nil || date > latest! { latest = date }
            }
            // The seeded simulator library includes a -180,-180 sentinel for
            // "no GPS". A latitude of -180 is outside the valid ±90 range, so
            // the validity check already rejects it — no separate case needed.
            guard let coordinate = asset.location?.coordinate,
                  CLLocationCoordinate2DIsValid(coordinate)
            else { return }

            located += 1
            southWest = southWest.map {
                (Swift.min($0.lat, coordinate.latitude), Swift.min($0.lon, coordinate.longitude))
            } ?? (coordinate.latitude, coordinate.longitude)
            northEast = northEast.map {
                (Swift.max($0.lat, coordinate.latitude), Swift.max($0.lon, coordinate.longitude))
            } ?? (coordinate.latitude, coordinate.longitude)
        }

        var fields: [SensorField] = [
            SensorField("Photos", .integer(assets.count)),
            SensorField("With a location", .integer(located)),
            SensorField("Access", .text(status == .limited ? "limited selection" : "whole library")),
        ]

        if let earliest, let latest {
            fields.append(SensorField("Oldest", .time(earliest.timeIntervalSince1970)))
            fields.append(SensorField("Newest", .time(latest.timeIntervalSince1970)))
        }
        if let southWest, let northEast {
            // The bounding box of someone's life, from metadata they never
            // deliberately created.
            fields.append(SensorField("Area covered (SW)",
                                      .coordinate(latitude: southWest.lat, longitude: southWest.lon)))
            fields.append(SensorField("Area covered (NE)",
                                      .coordinate(latitude: northEast.lat, longitude: northEast.lon)))
        }

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: fields)
    }

    static func map(_ status: PHAuthorizationStatus) -> SensorAvailability {
        switch status {
        case .notDetermined: .needsPermission
        case .denied: .denied
        case .restricted: .restricted
        case .limited: .limited
        case .authorized: .ready
        @unknown default: .needsPermission
        }
    }
}

/// The library as a whole: how much of it there is, and what kinds of media.
public struct LivePhotoLibrarySource: SensorSource {
    public let id: SensorID = "photos.library"

    public init() {}

    public func availability() async -> SensorAvailability {
        LivePhotoLocationSource.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    public func requestAccess() async -> SensorAvailability {
        LivePhotoLocationSource.map(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    public func read() async -> SensorSample? {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }

        let images = PHAsset.fetchAssets(with: .image, options: nil)
        let videos = PHAsset.fetchAssets(with: .video, options: nil)

        var favourites = 0
        var screenshots = 0
        images.enumerateObjects { asset, _, _ in
            if asset.isFavorite { favourites += 1 }
            if asset.mediaSubtypes.contains(.photoScreenshot) { screenshots += 1 }
        }

        return SensorSample(sensor: id, timestamp: Date().timeIntervalSince1970, fields: [
            SensorField("Photos", .integer(images.count)),
            SensorField("Videos", .integer(videos.count)),
            SensorField("Favourites", .integer(favourites)),
            SensorField("Screenshots", .integer(screenshots)),
            SensorField("Access", .text(status == .limited ? "limited selection" : "whole library")),
        ])
    }
}
#endif
