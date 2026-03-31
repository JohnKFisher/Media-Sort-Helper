import Foundation

enum DiskMediaKind: String, Codable, Sendable {
    case image
    case video
}

enum DiskDateSource: String, Codable, Sendable {
    case exifTakenDate
    case videoMetadataDate
    case fileCreationDate
    case fileModificationDate
    case unavailable

    var label: String {
        switch self {
        case .exifTakenDate:
            return "Taken"
        case .videoMetadataDate:
            return "Captured"
        case .fileCreationDate:
            return "File created"
        case .fileModificationDate:
            return "File modified"
        case .unavailable:
            return "Unknown"
        }
    }
}

struct DiskItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let url: URL
    let fileName: String
    let mediaKind: DiskMediaKind
    let utTypeIdentifier: String
    let takenDate: Date?
    let fallbackFileDate: Date?
    let displayDateSource: DiskDateSource
    let byteSize: Int64

    var preferredDate: Date? {
        takenDate ?? fallbackFileDate
    }

    var sortDate: Date {
        preferredDate ?? .distantPast
    }

    var isVideo: Bool {
        mediaKind == .video
    }
}

enum FileDecision: String, Codable, Sendable {
    case keep
    case delete
    case sendAndDelete

    var title: String {
        switch self {
        case .keep:
            return "Keep"
        case .delete:
            return "Delete"
        case .sendAndDelete:
            return "Send and Delete"
        }
    }
}

struct ReviewGroup: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var itemIDs: [String]
    let startDate: Date?
    let endDate: Date?

    init(id: UUID = UUID(), itemIDs: [String], startDate: Date?, endDate: Date?) {
        self.id = id
        self.itemIDs = itemIDs
        self.startDate = startDate
        self.endDate = endDate
    }
}

struct ScanSettings: Sendable {
    var sourceFolderURL: URL
}

struct ScanProgress: Sendable {
    var fractionCompleted: Double
    var message: String
}

struct DiskScanListing: Sendable {
    var items: [DiskItem]
    var skippedHiddenCount: Int
    var skippedUnsupportedCount: Int
}

struct ScanResult: Sendable {
    var groups: [ReviewGroup]
    var itemLookup: [String: DiskItem]
    var scannedItemCount: Int
}

enum CommitDestination: String, Sendable {
    case keep
    case delete
    case sendAndDelete

    var folderName: String {
        switch self {
        case .keep:
            return "Keep"
        case .delete:
            return "Delete"
        case .sendAndDelete:
            return "Send and Delete"
        }
    }
}

struct CommitOperation: Sendable {
    var itemID: String
    var sourceURL: URL
    var destination: CommitDestination
}

struct CommitDestinationPaths: Sendable, Hashable {
    var destinationRootURL: URL
    var keepURL: URL
    var deleteURL: URL
    var sendAndDeleteURL: URL

    func url(for destination: CommitDestination) -> URL {
        switch destination {
        case .keep:
            return keepURL
        case .delete:
            return deleteURL
        case .sendAndDelete:
            return sendAndDeleteURL
        }
    }
}

struct CommitPlan: Sendable {
    var operations: [CommitOperation]
    var reviewedCount: Int
    var keepCount: Int
    var deleteCount: Int
    var sendAndDeleteCount: Int
    var keepSamples: [String]
    var deleteSamples: [String]
    var sendAndDeleteSamples: [String]

    var totalMoveCount: Int {
        operations.count
    }

    func count(for destination: CommitDestination) -> Int {
        switch destination {
        case .keep:
            return keepCount
        case .delete:
            return deleteCount
        case .sendAndDelete:
            return sendAndDeleteCount
        }
    }

    func samples(for destination: CommitDestination) -> [String] {
        switch destination {
        case .keep:
            return keepSamples
        case .delete:
            return deleteSamples
        case .sendAndDelete:
            return sendAndDeleteSamples
        }
    }
}

struct CommitExecutionProgress: Sendable {
    var processedCount: Int
    var movedCount: Int
    var totalCount: Int
    var currentFileName: String?
    var lastProcessedFileName: String?
    var statusMessage: String

    var fractionCompleted: Double {
        guard totalCount > 0 else {
            return 0
        }

        return min(max(Double(processedCount) / Double(totalCount), 0), 1)
    }
}

struct CommitSkippedSourceDetail: Identifiable, Hashable, Sendable {
    var sourceFileName: String
    var sourcePath: String
    var destination: CommitDestination
    var destinationFolderPath: String

    var id: String {
        "\(sourcePath)|\(destination.rawValue)|missing"
    }
}

struct CommitRenamedItem: Identifiable, Hashable, Sendable {
    var sourceFileName: String
    var finalFileName: String
    var destination: CommitDestination
    var destinationPath: String

    var id: String {
        destinationPath
    }
}

struct CommitFailureDetail: Identifiable, Hashable, Sendable {
    var sourceFileName: String
    var sourcePath: String
    var destination: CommitDestination
    var destinationFolderPath: String
    var message: String

    var id: String {
        "\(sourcePath)|\(destination.rawValue)|failure|\(message)"
    }
}

struct CommitExecutionResult: Sendable {
    var destinationPaths: CommitDestinationPaths
    var totalOperationCount: Int
    var processedCount: Int
    var wasCancelled: Bool
    var movedItemIDs: Set<String>
    var movedToKeepCount: Int
    var movedToDeleteCount: Int
    var movedToSendAndDeleteCount: Int
    var skippedMissingSources: [CommitSkippedSourceDetail]
    var renamedItems: [CommitRenamedItem]
    var failures: [CommitFailureDetail]

    var totalMovedCount: Int {
        movedItemIDs.count
    }

    var skippedMissingSourceCount: Int {
        skippedMissingSources.count
    }

    var renamedCount: Int {
        renamedItems.count
    }

    var failureCount: Int {
        failures.count
    }

    var remainingCount: Int {
        max(totalOperationCount - processedCount, 0)
    }

    var hasIssues: Bool {
        skippedMissingSourceCount > 0 || failureCount > 0 || wasCancelled
    }
}

enum ReviewError: LocalizedError, Equatable {
    case missingSourceFolder
    case sourceFolderDoesNotExist
    case sourceFolderNotDirectory
    case sourceFolderConflictsWithDestination
    case unreadableSourceFolder
    case emptySourceFolder
    case noReviewedItemsToCommit

    var errorDescription: String? {
        switch self {
        case .missingSourceFolder:
            return "Choose a source folder before scanning."
        case .sourceFolderDoesNotExist:
            return "The selected source folder does not exist."
        case .sourceFolderNotDirectory:
            return "The selected source path is not a folder."
        case .sourceFolderConflictsWithDestination:
            return "Choose a source folder that is not already named Keep, Delete, or Send and Delete."
        case .unreadableSourceFolder:
            return "The selected source folder could not be read."
        case .emptySourceFolder:
            return "The selected source folder is empty. Add items to sort and scan again."
        case .noReviewedItemsToCommit:
            return "No reviewed items are ready to commit."
        }
    }
}
