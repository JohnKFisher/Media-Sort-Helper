import XCTest
@testable import MediaSortHelper

final class FileCommitServiceTests: XCTestCase {
    func testExecuteMovesFilesIntoSiblingDestinationFolders() async throws {
        let service = FileCommitService()

        try await withTemporaryWorkspace { workspaceURL in
            let sourceFolderURL = workspaceURL.appendingPathComponent("Batch 07", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceFolderURL, withIntermediateDirectories: true)

            let sourceFileURL = sourceFolderURL.appendingPathComponent("photo-a.jpg")
            try Data("a".utf8).write(to: sourceFileURL)

            let item = makeDiskItem(for: sourceFileURL)
            let plan = service.buildCommitPlan(
                itemLookup: [item.id: item],
                decisions: [item.id: .keep],
                reviewedItemIDs: [item.id]
            )

            let result = try await service.execute(plan: plan, sourceFolderURL: sourceFolderURL)

            XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceURL.appendingPathComponent("Keep/photo-a.jpg").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: sourceFileURL.path))
            XCTAssertEqual(result.destinationPaths.destinationRootURL, workspaceURL)
            XCTAssertEqual(result.movedToKeepCount, 1)
            XCTAssertEqual(result.failureCount, 0)
        }
    }

    func testExecuteAutoRenamesOnConflictsAndReportsRenamedItem() async throws {
        let service = FileCommitService()

        try await withTemporaryWorkspace { workspaceURL in
            let sourceFolderURL = workspaceURL.appendingPathComponent("Batch 08", isDirectory: true)
            let keepFolderURL = workspaceURL.appendingPathComponent("Keep", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceFolderURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: keepFolderURL, withIntermediateDirectories: true)

            let existingURL = keepFolderURL.appendingPathComponent("photo-b.jpg")
            let sourceFileURL = sourceFolderURL.appendingPathComponent("photo-b.jpg")
            try Data("existing".utf8).write(to: existingURL)
            try Data("incoming".utf8).write(to: sourceFileURL)

            let item = makeDiskItem(for: sourceFileURL)
            let plan = service.buildCommitPlan(
                itemLookup: [item.id: item],
                decisions: [item.id: .keep],
                reviewedItemIDs: [item.id]
            )

            let result = try await service.execute(plan: plan, sourceFolderURL: sourceFolderURL)

            XCTAssertEqual(result.renamedCount, 1)
            XCTAssertEqual(result.renamedItems.first?.finalFileName, "photo-b (2).jpg")
            XCTAssertTrue(FileManager.default.fileExists(atPath: keepFolderURL.appendingPathComponent("photo-b (2).jpg").path))
        }
    }

    func testExecuteReportsMissingSourcesWithoutFailingWholeCommit() async throws {
        let service = FileCommitService()

        try await withTemporaryWorkspace { workspaceURL in
            let sourceFolderURL = workspaceURL.appendingPathComponent("Batch 09", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceFolderURL, withIntermediateDirectories: true)

            let existingURL = sourceFolderURL.appendingPathComponent("photo-c.jpg")
            try Data("c".utf8).write(to: existingURL)
            let missingURL = sourceFolderURL.appendingPathComponent("missing.jpg")

            let existingItem = makeDiskItem(for: existingURL)
            let missingItem = makeDiskItem(for: missingURL)
            let itemLookup = [
                existingItem.id: existingItem,
                missingItem.id: missingItem,
            ]
            let decisions: [String: FileDecision] = [
                existingItem.id: .delete,
                missingItem.id: .keep,
            ]

            let plan = service.buildCommitPlan(
                itemLookup: itemLookup,
                decisions: decisions,
                reviewedItemIDs: [existingItem.id, missingItem.id]
            )

            let result = try await service.execute(plan: plan, sourceFolderURL: sourceFolderURL)

            XCTAssertEqual(result.totalMovedCount, 1)
            XCTAssertEqual(result.skippedMissingSourceCount, 1)
            XCTAssertEqual(result.failureCount, 0)
            XCTAssertEqual(result.processedCount, 2)
            XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceURL.appendingPathComponent("Delete/photo-c.jpg").path))
        }
    }

    func testExecuteTracksPerFileFailuresWithoutDiscardingSuccessfulMoves() async throws {
        let service = FileCommitService()

        try await withTemporaryWorkspace { workspaceURL in
            let sourceFolderURL = workspaceURL.appendingPathComponent("Batch 10", isDirectory: true)
            let keepFolderURL = workspaceURL.appendingPathComponent("Keep", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceFolderURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: keepFolderURL, withIntermediateDirectories: true)

            let readOnlyURL = sourceFolderURL.appendingPathComponent("locked.jpg")
            let deleteURL = sourceFolderURL.appendingPathComponent("delete-me.jpg")
            try Data("locked".utf8).write(to: readOnlyURL)
            try Data("delete".utf8).write(to: deleteURL)

            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: keepFolderURL.path)
            defer {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: keepFolderURL.path)
            }

            let lockedItem = makeDiskItem(for: readOnlyURL)
            let deleteItem = makeDiskItem(for: deleteURL)
            let itemLookup = [
                lockedItem.id: lockedItem,
                deleteItem.id: deleteItem,
            ]
            let decisions: [String: FileDecision] = [
                lockedItem.id: .keep,
                deleteItem.id: .delete,
            ]

            let plan = service.buildCommitPlan(
                itemLookup: itemLookup,
                decisions: decisions,
                reviewedItemIDs: [lockedItem.id, deleteItem.id]
            )

            let result = try await service.execute(plan: plan, sourceFolderURL: sourceFolderURL)

            XCTAssertEqual(result.totalMovedCount, 1)
            XCTAssertEqual(result.failureCount, 1)
            XCTAssertEqual(result.failures.first?.sourceFileName, "locked.jpg")
            XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceURL.appendingPathComponent("Delete/delete-me.jpg").path))
        }
    }
}

private func withTemporaryWorkspace(
    perform: (URL) async throws -> Void
) async throws {
    let workspaceURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: workspaceURL)
    }

    try await perform(workspaceURL)
}

private func makeDiskItem(for url: URL) -> DiskItem {
    DiskItem(
        id: url.standardizedFileURL.path,
        url: url,
        fileName: url.lastPathComponent,
        mediaKind: .image,
        utTypeIdentifier: "public.jpeg",
        takenDate: nil,
        fallbackFileDate: nil,
        displayDateSource: .unavailable,
        byteSize: 1
    )
}
