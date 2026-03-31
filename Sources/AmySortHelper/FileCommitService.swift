import Foundation

final class FileCommitService: @unchecked Sendable {
    private let fileManager = FileManager.default

    func buildCommitPlan(
        itemLookup: [String: DiskItem],
        decisions: [String: FileDecision],
        reviewedItemIDs: Set<String>
    ) -> CommitPlan {
        var operations: [CommitOperation] = []
        var keepSamples: [String] = []
        var deleteSamples: [String] = []
        var sendAndDeleteSamples: [String] = []
        var keepCount = 0
        var deleteCount = 0
        var sendAndDeleteCount = 0

        for itemID in reviewedItemIDs.sorted() {
            guard let item = itemLookup[itemID] else {
                continue
            }

            let decision = decisions[itemID] ?? .delete
            let destination: CommitDestination
            switch decision {
            case .keep:
                destination = .keep
            case .delete:
                destination = .delete
            case .sendAndDelete:
                destination = .sendAndDelete
            }

            operations.append(
                CommitOperation(
                    itemID: itemID,
                    sourceURL: item.url,
                    destination: destination
                )
            )

            switch destination {
            case .keep:
                keepCount += 1
                if keepSamples.count < 5 {
                    keepSamples.append(item.fileName)
                }
            case .delete:
                deleteCount += 1
                if deleteSamples.count < 5 {
                    deleteSamples.append(item.fileName)
                }
            case .sendAndDelete:
                sendAndDeleteCount += 1
                if sendAndDeleteSamples.count < 5 {
                    sendAndDeleteSamples.append(item.fileName)
                }
            }
        }

        return CommitPlan(
            operations: operations,
            reviewedCount: reviewedItemIDs.count,
            keepCount: keepCount,
            deleteCount: deleteCount,
            sendAndDeleteCount: sendAndDeleteCount,
            keepSamples: keepSamples,
            deleteSamples: deleteSamples,
            sendAndDeleteSamples: sendAndDeleteSamples
        )
    }

    func execute(plan: CommitPlan, rootFolderURL: URL) throws -> CommitExecutionResult {
        if plan.operations.isEmpty {
            throw ReviewError.noReviewedItemsToCommit
        }

        let keepFolderURL = rootFolderURL.appendingPathComponent(CommitDestination.keep.folderName, isDirectory: true)
        let deleteFolderURL = rootFolderURL.appendingPathComponent(CommitDestination.delete.folderName, isDirectory: true)
        let sendAndDeleteFolderURL = rootFolderURL.appendingPathComponent(CommitDestination.sendAndDelete.folderName, isDirectory: true)

        try fileManager.createDirectory(at: keepFolderURL, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: deleteFolderURL, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: sendAndDeleteFolderURL, withIntermediateDirectories: true, attributes: nil)

        var movedItemIDs: Set<String> = []
        var movedToKeepCount = 0
        var movedToDeleteCount = 0
        var movedToSendAndDeleteCount = 0
        var skippedMissingSourceCount = 0
        var renamedCount = 0
        var failureMessages: [String] = []

        for operation in plan.operations {
            guard fileManager.fileExists(atPath: operation.sourceURL.path) else {
                skippedMissingSourceCount += 1
                continue
            }

            let destinationFolder: URL = {
                switch operation.destination {
                case .keep:
                    return keepFolderURL
                case .delete:
                    return deleteFolderURL
                case .sendAndDelete:
                    return sendAndDeleteFolderURL
                }
            }()

            do {
                let resolvedDestinationURL = uniqueDestinationURL(
                    in: destinationFolder,
                    preferredFileName: operation.sourceURL.lastPathComponent
                )

                if resolvedDestinationURL.lastPathComponent != operation.sourceURL.lastPathComponent {
                    renamedCount += 1
                }

                try fileManager.moveItem(at: operation.sourceURL, to: resolvedDestinationURL)
                movedItemIDs.insert(operation.itemID)

                switch operation.destination {
                case .keep:
                    movedToKeepCount += 1
                case .delete:
                    movedToDeleteCount += 1
                case .sendAndDelete:
                    movedToSendAndDeleteCount += 1
                }
            } catch {
                failureMessages.append("\(operation.sourceURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return CommitExecutionResult(
            movedItemIDs: movedItemIDs,
            movedToKeepCount: movedToKeepCount,
            movedToDeleteCount: movedToDeleteCount,
            movedToSendAndDeleteCount: movedToSendAndDeleteCount,
            skippedMissingSourceCount: skippedMissingSourceCount,
            renamedCount: renamedCount,
            failureMessages: failureMessages
        )
    }

    private func uniqueDestinationURL(in destinationFolder: URL, preferredFileName: String) -> URL {
        let baseName = (preferredFileName as NSString).deletingPathExtension
        let fileExtension = (preferredFileName as NSString).pathExtension

        var candidate = destinationFolder.appendingPathComponent(preferredFileName)
        guard fileManager.fileExists(atPath: candidate.path) else {
            return candidate
        }

        var suffix = 2
        while true {
            let candidateName: String
            if fileExtension.isEmpty {
                candidateName = "\(baseName) (\(suffix))"
            } else {
                candidateName = "\(baseName) (\(suffix)).\(fileExtension)"
            }

            candidate = destinationFolder.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }

            suffix += 1
        }
    }
}
