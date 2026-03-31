import Foundation

final class SimilarityScanner: @unchecked Sendable {
    init(diskService _: DiskLibraryService) {}

    func scan(
        items: [DiskItem],
        settings _: ScanSettings,
        progress: @escaping @MainActor (ScanProgress) -> Void
    ) async throws -> ScanResult {
        let sortedItems = items.sorted(by: itemSortPredicate)
        let itemLookup = Dictionary(uniqueKeysWithValues: sortedItems.map { ($0.id, $0) })

        await progress(.init(fractionCompleted: 0.4, message: "Preparing singleton review list..."))

        let groups = sortedItems.map { item in
            ReviewGroup(itemIDs: [item.id], startDate: item.preferredDate, endDate: item.preferredDate)
        }

        await progress(.init(fractionCompleted: 1.0, message: "Scan complete. Loaded \(groups.count) file(s)."))

        return ScanResult(
            groups: groups,
            itemLookup: itemLookup,
            scannedItemCount: sortedItems.count
        )
    }

    private func itemSortPredicate(_ lhs: DiskItem, _ rhs: DiskItem) -> Bool {
        let lhsDate = lhs.sortDate
        let rhsDate = rhs.sortDate
        if lhsDate == rhsDate {
            return lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName) == .orderedAscending
        }
        return lhsDate < rhsDate
    }
}
