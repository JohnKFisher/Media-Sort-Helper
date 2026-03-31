import XCTest
@testable import MediaSortHelper

final class DiskLibraryServiceTests: XCTestCase {
    func testValidateSourceFolderRejectsReservedDestinationFolderNames() throws {
        let service = DiskLibraryService()

        try withTemporaryDirectory(named: "Keep") { keepURL in
            XCTAssertThrowsError(try service.validateSourceFolder(path: keepURL.path)) { error in
                XCTAssertEqual(error as? ReviewError, .sourceFolderConflictsWithDestination)
            }
        }

        try withTemporaryDirectory(named: "Delete") { deleteURL in
            XCTAssertThrowsError(try service.validateSourceFolder(path: deleteURL.path)) { error in
                XCTAssertEqual(error as? ReviewError, .sourceFolderConflictsWithDestination)
            }
        }

        try withTemporaryDirectory(named: "Send and Delete") { sendAndDeleteURL in
            XCTAssertThrowsError(try service.validateSourceFolder(path: sendAndDeleteURL.path)) { error in
                XCTAssertEqual(error as? ReviewError, .sourceFolderConflictsWithDestination)
            }
        }
    }

    func testValidateSourceFolderAcceptsRegularFolder() throws {
        let service = DiskLibraryService()

        try withTemporaryDirectory(named: "Batch 01") { sourceURL in
            let validatedURL = try service.validateSourceFolder(path: sourceURL.path)
            XCTAssertEqual(validatedURL, sourceURL.standardizedFileURL)
        }
    }
}

private func withTemporaryDirectory(
    named name: String,
    perform: (URL) throws -> Void
) throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let directoryURL = rootURL.appendingPathComponent(name, isDirectory: true)

    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: rootURL)
    }

    try perform(directoryURL)
}
