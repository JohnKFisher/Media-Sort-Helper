import Foundation

final class FileCommitService: @unchecked Sendable {
    private let fileManager = FileManager.default

    func destinationPaths(for sourceFolderURL: URL) -> CommitDestinationPaths {
        let destinationRootURL = sourceFolderURL.deletingLastPathComponent()
        return CommitDestinationPaths(
            destinationRootURL: destinationRootURL,
            keepURL: destinationRootURL.appendingPathComponent(CommitDestination.keep.folderName, isDirectory: true),
            deleteURL: destinationRootURL.appendingPathComponent(CommitDestination.delete.folderName, isDirectory: true),
            sendAndDeleteURL: destinationRootURL.appendingPathComponent(CommitDestination.sendAndDelete.folderName, isDirectory: true)
        )
    }

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

    func execute(
        plan: CommitPlan,
        sourceFolderURL: URL,
        progress: @escaping @Sendable (CommitExecutionProgress) async -> Void = { _ in }
    ) async throws -> CommitExecutionResult {
        if plan.operations.isEmpty {
            throw ReviewError.noReviewedItemsToCommit
        }

        let destinationPaths = destinationPaths(for: sourceFolderURL)

        try fileManager.createDirectory(at: destinationPaths.keepURL, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: destinationPaths.deleteURL, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: destinationPaths.sendAndDeleteURL, withIntermediateDirectories: true, attributes: nil)

        var movedItemIDs: Set<String> = []
        var movedToKeepCount = 0
        var movedToDeleteCount = 0
        var movedToSendAndDeleteCount = 0
        var skippedMissingSources: [CommitSkippedSourceDetail] = []
        var renamedItems: [CommitRenamedItem] = []
        var failures: [CommitFailureDetail] = []
        var processedCount = 0
        var wasCancelled = false
        var lastProcessedFileName: String?

        await progress(
            CommitExecutionProgress(
                processedCount: processedCount,
                movedCount: movedItemIDs.count,
                totalCount: plan.totalMoveCount,
                currentFileName: nil,
                lastProcessedFileName: nil,
                statusMessage: "Prepared destination folders."
            )
        )

        for operation in plan.operations {
            if Task.isCancelled {
                wasCancelled = true
                break
            }

            let currentFileName = operation.sourceURL.lastPathComponent
            await progress(
                CommitExecutionProgress(
                    processedCount: processedCount,
                    movedCount: movedItemIDs.count,
                    totalCount: plan.totalMoveCount,
                    currentFileName: currentFileName,
                    lastProcessedFileName: lastProcessedFileName,
                    statusMessage: "Moving \(currentFileName)..."
                )
            )

            guard fileManager.fileExists(atPath: operation.sourceURL.path) else {
                skippedMissingSources.append(
                    CommitSkippedSourceDetail(
                        sourceFileName: currentFileName,
                        sourcePath: operation.sourceURL.path,
                        destination: operation.destination,
                        destinationFolderPath: destinationPaths.url(for: operation.destination).path
                    )
                )
                processedCount += 1
                lastProcessedFileName = currentFileName

                await progress(
                    CommitExecutionProgress(
                        processedCount: processedCount,
                        movedCount: movedItemIDs.count,
                        totalCount: plan.totalMoveCount,
                        currentFileName: nil,
                        lastProcessedFileName: lastProcessedFileName,
                        statusMessage: "Skipped missing source: \(currentFileName)"
                    )
                )
                continue
            }

            let destinationFolder = destinationPaths.url(for: operation.destination)

            do {
                let resolvedDestinationURL = uniqueDestinationURL(
                    in: destinationFolder,
                    preferredFileName: currentFileName
                )

                if resolvedDestinationURL.lastPathComponent != currentFileName {
                    renamedItems.append(
                        CommitRenamedItem(
                            sourceFileName: currentFileName,
                            finalFileName: resolvedDestinationURL.lastPathComponent,
                            destination: operation.destination,
                            destinationPath: resolvedDestinationURL.path
                        )
                    )
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
                failures.append(
                    CommitFailureDetail(
                        sourceFileName: currentFileName,
                        sourcePath: operation.sourceURL.path,
                        destination: operation.destination,
                        destinationFolderPath: destinationFolder.path,
                        message: error.localizedDescription
                    )
                )
            }

            processedCount += 1
            lastProcessedFileName = currentFileName

            await progress(
                CommitExecutionProgress(
                    processedCount: processedCount,
                    movedCount: movedItemIDs.count,
                    totalCount: plan.totalMoveCount,
                    currentFileName: nil,
                    lastProcessedFileName: lastProcessedFileName,
                    statusMessage: "Processed \(processedCount) of \(plan.totalMoveCount) files."
                )
            )

            await Task.yield()
        }

        if wasCancelled {
            await progress(
                CommitExecutionProgress(
                    processedCount: processedCount,
                    movedCount: movedItemIDs.count,
                    totalCount: plan.totalMoveCount,
                    currentFileName: nil,
                    lastProcessedFileName: lastProcessedFileName,
                    statusMessage: "Commit cancelled. Already moved files remain moved."
                )
            )
        } else {
            await progress(
                CommitExecutionProgress(
                    processedCount: processedCount,
                    movedCount: movedItemIDs.count,
                    totalCount: plan.totalMoveCount,
                    currentFileName: nil,
                    lastProcessedFileName: lastProcessedFileName,
                    statusMessage: "Commit finished."
                )
            )
        }

        return CommitExecutionResult(
            destinationPaths: destinationPaths,
            totalOperationCount: plan.totalMoveCount,
            processedCount: processedCount,
            wasCancelled: wasCancelled,
            movedItemIDs: movedItemIDs,
            movedToKeepCount: movedToKeepCount,
            movedToDeleteCount: movedToDeleteCount,
            movedToSendAndDeleteCount: movedToSendAndDeleteCount,
            skippedMissingSources: skippedMissingSources,
            renamedItems: renamedItems,
            failures: failures
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
