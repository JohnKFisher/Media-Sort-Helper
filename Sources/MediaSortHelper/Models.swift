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
}

struct CommitExecutionResult: Sendable {
    var movedItemIDs: Set<String>
    var movedToKeepCount: Int
    var movedToDeleteCount: Int
    var movedToSendAndDeleteCount: Int
    var skippedMissingSourceCount: Int
    var renamedCount: Int
    var failureMessages: [String]

    var totalMovedCount: Int {
        movedItemIDs.count
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
