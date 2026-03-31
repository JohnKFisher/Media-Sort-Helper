import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

final class DiskLibraryService: @unchecked Sendable {
    let defaultRootPath = "/Users/jkfisher/Resilio Sync/Quickswap/Amy Photos/"
    let currentSortFolderName = "Current Sort"
    let keepFolderName = "Keep"
    let deleteFolderName = "Delete"

    private let fileManager = FileManager.default

    func validateRootFolder(path: String) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ReviewError.missingRootFolder
        }

        let rootURL = URL(fileURLWithPath: trimmed, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) else {
            throw ReviewError.rootFolderDoesNotExist
        }

        guard isDirectory.boolValue else {
            throw ReviewError.rootFolderNotDirectory
        }

        return rootURL
    }

    func currentSortURL(for rootFolderURL: URL) -> URL {
        rootFolderURL.appendingPathComponent(currentSortFolderName, isDirectory: true)
    }

    func keepURL(for rootFolderURL: URL) -> URL {
        rootFolderURL.appendingPathComponent(keepFolderName, isDirectory: true)
    }

    func deleteURL(for rootFolderURL: URL) -> URL {
        rootFolderURL.appendingPathComponent(deleteFolderName, isDirectory: true)
    }

    func loadCurrentSortItems(rootFolderURL: URL) async throws -> DiskScanListing {
        let sourceFolder = currentSortURL(for: rootFolderURL)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceFolder.path, isDirectory: &isDirectory) else {
            throw ReviewError.missingCurrentSortFolder
        }

        guard isDirectory.boolValue else {
            throw ReviewError.missingCurrentSortFolder
        }

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isHiddenKey,
            .nameKey,
            .typeIdentifierKey,
            .contentTypeKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey
        ]

        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: sourceFolder,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants]
            )
        } catch {
            throw ReviewError.unreadableCurrentSortFolder
        }

        var items: [DiskItem] = []
        var skippedHiddenCount = 0
        var skippedUnsupportedCount = 0

        for url in urls.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            let values = try? url.resourceValues(forKeys: keys)

            if values?.isDirectory == true {
                continue
            }

            if values?.isHidden == true {
                skippedHiddenCount += 1
                continue
            }

            guard
                let mediaKind = mediaKind(for: url, resourceValues: values),
                let typeIdentifier = resolvedTypeIdentifier(for: url, resourceValues: values)
            else {
                skippedUnsupportedCount += 1
                continue
            }

            let fallbackCreationDate = values?.creationDate
            let fallbackModificationDate = values?.contentModificationDate
            let fallbackDate = fallbackCreationDate ?? fallbackModificationDate

            let (takenDate, explicitSource) = await captureDate(for: url, mediaKind: mediaKind)
            let dateSource: DiskDateSource
            if let explicitSource {
                dateSource = explicitSource
            } else if fallbackCreationDate != nil {
                dateSource = .fileCreationDate
            } else if fallbackModificationDate != nil {
                dateSource = .fileModificationDate
            } else {
                dateSource = .unavailable
            }

            let item = DiskItem(
                id: normalizedID(for: url),
                url: url,
                fileName: values?.name ?? url.lastPathComponent,
                mediaKind: mediaKind,
                utTypeIdentifier: typeIdentifier,
                takenDate: takenDate,
                fallbackFileDate: fallbackDate,
                displayDateSource: dateSource,
                byteSize: Int64(values?.fileSize ?? 0)
            )
            items.append(item)
        }

        guard !items.isEmpty else {
            throw ReviewError.emptyCurrentSortFolder
        }

        return DiskScanListing(
            items: items,
            skippedHiddenCount: skippedHiddenCount,
            skippedUnsupportedCount: skippedUnsupportedCount
        )
    }

    func thumbnail(for item: DiskItem, maxPixel: CGFloat) async -> NSImage? {
        switch item.mediaKind {
        case .image:
            return await imageThumbnail(for: item.url, maxPixel: maxPixel)
        case .video:
            return await videoThumbnail(for: item.url, maxPixel: maxPixel)
        }
    }

    func featurePrintCGImage(for item: DiskItem, maxPixel: CGFloat = 320) async -> CGImage? {
        guard item.mediaKind == .image else {
            return nil
        }

        guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, Int(maxPixel))
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    func previewPlayer(for item: DiskItem) -> AVPlayer? {
        guard item.mediaKind == .video else {
            return nil
        }

        let player = AVPlayer(url: item.url)
        player.actionAtItemEnd = .pause
        return player
    }

    func itemExists(_ item: DiskItem) -> Bool {
        fileManager.fileExists(atPath: item.url.path)
    }

    private func normalizedID(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func resolvedTypeIdentifier(for url: URL, resourceValues: URLResourceValues?) -> String? {
        if let contentType = resourceValues?.contentType {
            return contentType.identifier
        }

        if let typeIdentifier = resourceValues?.typeIdentifier {
            return typeIdentifier
        }

        guard !url.pathExtension.isEmpty,
              let type = UTType(filenameExtension: url.pathExtension)
        else {
            return nil
        }

        return type.identifier
    }

    private func mediaKind(for url: URL, resourceValues: URLResourceValues?) -> DiskMediaKind? {
        let type = resourceValues?.contentType
            ?? (resourceValues?.typeIdentifier).flatMap { UTType($0) }
            ?? UTType(filenameExtension: url.pathExtension)

        guard let type else {
            return nil
        }

        if type.conforms(to: .image) {
            return .image
        }

        if type.conforms(to: .movie) || type.conforms(to: .audiovisualContent) {
            return .video
        }

        return nil
    }

    private func captureDate(for url: URL, mediaKind: DiskMediaKind) async -> (Date?, DiskDateSource?) {
        switch mediaKind {
        case .image:
            if let date = imageCaptureDate(from: url) {
                return (date, .exifTakenDate)
            }
        case .video:
            if let date = await videoCaptureDate(from: url) {
                return (date, .videoMetadataDate)
            }
        }

        return (nil, nil)
    }

    private func imageCaptureDate(from url: URL) -> Date? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return nil
        }

        if
            let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
            let value = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
            let parsed = parseEXIFDate(value)
        {
            return parsed
        }

        if
            let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
            let value = tiff[kCGImagePropertyTIFFDateTime] as? String,
            let parsed = parseEXIFDate(value)
        {
            return parsed
        }

        return nil
    }

    private func videoCaptureDate(from url: URL) async -> Date? {
        let asset = AVURLAsset(url: url)

        if let metadataDate = try? await asset.load(.creationDate) {
            if let loadedDate = try? await metadataDate.load(.dateValue) {
                return loadedDate
            }

            if
                let loadedString = try? await metadataDate.load(.stringValue),
                let parsed = parseFlexibleDate(loadedString)
            {
                return parsed
            }
        }

        return nil
    }

    private func parseEXIFDate(_ raw: String) -> Date? {
        let formatters: [DateFormatter] = [
            makeDateFormatter("yyyy:MM:dd HH:mm:ss"),
            makeDateFormatter("yyyy:MM:dd HH:mm:ssXXXXX"),
            makeDateFormatter("yyyy-MM-dd HH:mm:ss")
        ]

        for formatter in formatters {
            if let parsed = formatter.date(from: raw) {
                return parsed
            }
        }

        return parseFlexibleDate(raw)
    }

    private func parseFlexibleDate(_ raw: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = isoFormatter.date(from: raw) {
            return parsed
        }

        isoFormatter.formatOptions = [.withInternetDateTime]
        return isoFormatter.date(from: raw)
    }

    private func makeDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    private func imageThumbnail(for url: URL, maxPixel: CGFloat) async -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(128, Int(maxPixel))
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func videoThumbnail(for url: URL, maxPixel: CGFloat) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)

        let timestamp = CMTime(seconds: 0.0, preferredTimescale: 600)
        do {
            let generated = try await generator.image(at: timestamp)
            let image = generated.image
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        } catch {
            return nil
        }
    }
}
