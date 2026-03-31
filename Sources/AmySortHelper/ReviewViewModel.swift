import AppKit
import AVFoundation
import Foundation

@MainActor
final class ReviewViewModel: ObservableObject {
    @Published var rootFolderPath: String {
        didSet {
            persistRootFolderPath()
        }
    }

    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var scanStatusMessage = "Ready to scan."

    @Published private(set) var scannedItemCount = 0
    @Published private(set) var skippedHiddenCount = 0
    @Published private(set) var skippedUnsupportedCount = 0

    @Published var groups: [ReviewGroup] = []
    @Published var currentGroupIndex = 0
    @Published var highlightedItemByGroup: [UUID: String] = [:]

    @Published var decisionByItemID: [String: FileDecision] = [:]
    @Published var reviewedItemIDs: Set<String> = []

    @Published var commitArmed = false
    @Published var isCommitting = false
    @Published var showLargeCommitConfirmation = false

    @Published var warningMessage: String?
    @Published var commitMessage: String?
    @Published var errorMessage: String?

    @Published private(set) var commitPlan: CommitPlan?

    private let diskService = DiskLibraryService()
    private let commitService = FileCommitService()
    private lazy var scanner = SimilarityScanner(diskService: diskService)

    private var itemLookup: [String: DiskItem] = [:]
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private var thumbnailKeysByItemID: [String: Set<String>] = [:]

    private var scanTask: Task<Void, Never>?

    private var ignoreHoverUntilMouseMoves = false
    private var mouseLocationAtKeyboardNavigation: CGPoint = .zero

    private let reviewSessionFileName = "review-session-v2.json"

    private let rootFolderDefaultsKey = "AmySortHelper.rootFolderPath.v1"

    init() {
        rootFolderPath = UserDefaults.standard.string(forKey: rootFolderDefaultsKey)
            ?? "/Users/jkfisher/Resilio Sync/Quickswap/Amy Photos/"
    }

    deinit {
        scanTask?.cancel()
    }

    func bootstrap() async {
        clearPersistedReviewSession()
        rebuildCommitPlan()
    }

    var currentGroup: ReviewGroup? {
        guard groups.indices.contains(currentGroupIndex) else {
            return nil
        }

        return groups[currentGroupIndex]
    }

    var hasPreviousGroup: Bool {
        currentGroupIndex > 0
    }

    var hasNextGroup: Bool {
        currentGroupIndex < groups.count - 1
    }

    var hasHighlightInCurrentGroup: Bool {
        guard let group = currentGroup else {
            return false
        }

        return highlightedItemID(in: group) != nil
    }

    var totalItemCount: Int {
        itemLookup.count
    }

    var reviewedItemCount: Int {
        reviewedItemIDs.intersection(Set(itemLookup.keys)).count
    }

    var commitMoveCount: Int {
        commitPlan?.totalMoveCount ?? 0
    }

    var reviewProgressLabel: String {
        "Reviewed \(reviewedItemCount) of \(totalItemCount)"
    }

    var shouldPromptBeforeQuit: Bool {
        isScanning || isCommitting || !groups.isEmpty
    }

    func changeRootFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Amy Photos Root Folder"
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: rootFolderPath, isDirectory: true)

        let response = panel.runModal()
        guard response == .OK, let selectedURL = panel.url else {
            return
        }

        rootFolderPath = selectedURL.standardizedFileURL.path

        clearCurrentSessionState()
        clearPersistedReviewSession()
        warningMessage = nil
        commitMessage = nil
        errorMessage = nil
        scanStatusMessage = "Folder changed. Run scan to load items from Current Sort."
    }

    func scan() {
        guard !isScanning else {
            return
        }

        let rootFolderURL: URL
        do {
            rootFolderURL = try diskService.validateRootFolder(path: rootFolderPath)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        errorMessage = nil
        warningMessage = nil
        commitMessage = nil
        commitArmed = false
        showLargeCommitConfirmation = false

        clearCurrentSessionState()
        clearPersistedReviewSession()

        isScanning = true
        scanProgress = 0
        scanStatusMessage = "Loading files from Current Sort..."

        scanTask?.cancel()
        scanTask = Task { [weak self] in
            guard let self else {
                return
            }

            defer {
                self.isScanning = false
                self.scanTask = nil
            }

            do {
                let listing = try await self.diskService.loadCurrentSortItems(rootFolderURL: rootFolderURL)
                self.skippedHiddenCount = listing.skippedHiddenCount
                self.skippedUnsupportedCount = listing.skippedUnsupportedCount

                let settings = ScanSettings(
                    rootFolderURL: rootFolderURL
                )

                let scanResult = try await self.scanner.scan(items: listing.items, settings: settings) { [weak self] progress in
                    self?.scanProgress = progress.fractionCompleted
                    self?.scanStatusMessage = progress.message
                }

                self.applyScanResult(scanResult)

                var warnings: [String] = []
                if self.skippedHiddenCount > 0 {
                    warnings.append("Skipped hidden: \(self.skippedHiddenCount)")
                }
                if self.skippedUnsupportedCount > 0 {
                    warnings.append("Skipped unsupported: \(self.skippedUnsupportedCount)")
                }
                self.warningMessage = warnings.isEmpty ? nil : warnings.joined(separator: "  •  ")
            } catch is CancellationError {
                self.scanStatusMessage = "Scan cancelled."
            } catch let reviewError as ReviewError {
                if reviewError == .emptyCurrentSortFolder {
                    self.warningMessage = reviewError.localizedDescription
                    self.scanStatusMessage = "Current Sort is empty."
                } else {
                    self.errorMessage = reviewError.localizedDescription
                    self.scanStatusMessage = "Scan failed."
                }
            } catch {
                self.errorMessage = error.localizedDescription
                self.scanStatusMessage = "Scan failed."
            }
        }
    }

    func stopScan() {
        guard isScanning else {
            return
        }

        scanStatusMessage = "Stopping scan..."
        scanTask?.cancel()
    }

    func previousGroup() {
        guard currentGroupIndex > 0, let group = currentGroup else {
            return
        }

        markHighlightedItemReviewed(in: group)
        currentGroupIndex -= 1

        if let newGroup = currentGroup {
            ensureHighlightedItem(in: newGroup)
            markTerminalItemVisibleIfNeeded(in: newGroup)
        }

        rebuildCommitPlan()
    }

    func nextGroup() {
        guard currentGroupIndex < groups.count - 1, let group = currentGroup else {
            return
        }

        markHighlightedItemReviewed(in: group)
        currentGroupIndex += 1

        if let newGroup = currentGroup {
            ensureHighlightedItem(in: newGroup)
            markTerminalItemVisibleIfNeeded(in: newGroup)
        }

        rebuildCommitPlan()
    }

    func highlightedItemID(in group: ReviewGroup) -> String? {
        guard !group.itemIDs.isEmpty else {
            return nil
        }

        if let highlighted = highlightedItemByGroup[group.id], group.itemIDs.contains(highlighted) {
            return highlighted
        }

        return group.itemIDs.first
    }

    func isHighlighted(itemID: String, in group: ReviewGroup) -> Bool {
        highlightedItemID(in: group) == itemID
    }

    func ensureHighlightedItem(in group: ReviewGroup) {
        guard let highlighted = highlightedItemID(in: group) else {
            highlightedItemByGroup.removeValue(forKey: group.id)
            return
        }

        if highlightedItemByGroup[group.id] != highlighted {
            highlightedItemByGroup[group.id] = highlighted
        }
    }

    func setHighlighted(itemID: String, in group: ReviewGroup) {
        guard group.itemIDs.contains(itemID) else {
            return
        }

        if let previous = highlightedItemByGroup[group.id], previous != itemID {
            reviewedItemIDs.insert(previous)
        }

        if highlightedItemByGroup[group.id] != itemID {
            highlightedItemByGroup[group.id] = itemID
            markTerminalItemVisibleIfNeeded(in: group)
            rebuildCommitPlan()
        }
    }

    func highlightPreviousItemInCurrentGroup() {
        guard let group = currentGroup else {
            return
        }

        beginKeyboardNavigationSession()
        moveHighlight(in: group, delta: -1)
    }

    func highlightNextItemInCurrentGroup() {
        guard let group = currentGroup else {
            return
        }

        beginKeyboardNavigationSession()
        moveHighlight(in: group, delta: 1)
    }

    func shouldAcceptHoverHighlight() -> Bool {
        guard ignoreHoverUntilMouseMoves else {
            return true
        }

        let currentMouseLocation = NSEvent.mouseLocation
        let dx = currentMouseLocation.x - mouseLocationAtKeyboardNavigation.x
        let dy = currentMouseLocation.y - mouseLocationAtKeyboardNavigation.y
        let distanceSquared = (dx * dx) + (dy * dy)

        guard distanceSquared > 4.0 else {
            return false
        }

        ignoreHoverUntilMouseMoves = false
        mouseLocationAtKeyboardNavigation = currentMouseLocation
        return true
    }

    func decision(for itemID: String) -> FileDecision {
        decisionByItemID[itemID] ?? .delete
    }

    func isKept(itemID: String) -> Bool {
        decision(for: itemID) == .keep
    }

    func isReviewed(itemID: String) -> Bool {
        reviewedItemIDs.contains(itemID)
    }

    func setDecision(_ decision: FileDecision, for itemID: String, markReviewed: Bool = true) {
        guard itemLookup[itemID] != nil else {
            return
        }

        decisionByItemID[itemID] = decision
        if markReviewed {
            reviewedItemIDs.insert(itemID)
        }

        commitMessage = nil
        rebuildCommitPlan()
    }

    func toggleDecision(for itemID: String) {
        let newDecision: FileDecision
        switch decision(for: itemID) {
        case .keep:
            newDecision = .delete
        case .delete, .sendAndDelete:
            newDecision = .keep
        }
        setDecision(newDecision, for: itemID)
    }

    func toggleHighlightedItemDecisionInCurrentGroup() {
        guard let group = currentGroup else {
            return
        }

        ensureHighlightedItem(in: group)
        guard let highlighted = highlightedItemID(in: group) else {
            return
        }

        toggleDecision(for: highlighted)
    }

    func markHighlightedItemSendAndDeleteInCurrentGroup() {
        guard let group = currentGroup else {
            return
        }

        ensureHighlightedItem(in: group)
        guard let highlighted = highlightedItemID(in: group) else {
            return
        }

        setDecision(.sendAndDelete, for: highlighted)
    }

    func keepOnly(itemID: String, in group: ReviewGroup) {
        for id in group.itemIDs {
            let decision: FileDecision = (id == itemID) ? .keep : .delete
            decisionByItemID[id] = decision
            reviewedItemIDs.insert(id)
        }

        commitMessage = nil
        rebuildCommitPlan()
    }

    func keepAll(in group: ReviewGroup) {
        for id in group.itemIDs {
            decisionByItemID[id] = .keep
            reviewedItemIDs.insert(id)
        }

        commitMessage = nil
        rebuildCommitPlan()
    }

    func deleteAll(in group: ReviewGroup) {
        for id in group.itemIDs {
            decisionByItemID[id] = .delete
            reviewedItemIDs.insert(id)
        }

        commitMessage = nil
        rebuildCommitPlan()
    }

    func keepCount(in group: ReviewGroup) -> Int {
        group.itemIDs.filter { decision(for: $0) == .keep }.count
    }

    func deleteCount(in group: ReviewGroup) -> Int {
        group.itemIDs.filter { decision(for: $0) == .delete }.count
    }

    func reviewedCount(in group: ReviewGroup) -> Int {
        group.itemIDs.filter { reviewedItemIDs.contains($0) }.count
    }

    func itemFileName(_ itemID: String) -> String {
        itemLookup[itemID]?.fileName ?? itemID
    }

    func itemByteSizeLabel(_ itemID: String) -> String {
        let bytes = itemLookup[itemID]?.byteSize ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func itemDateLabel(_ itemID: String) -> String {
        guard let item = itemLookup[itemID] else {
            return "Date unavailable"
        }

        guard let date = item.preferredDate else {
            return "Date unavailable"
        }

        return "\(dateFormatter.string(from: date)) (\(item.displayDateSource.label))"
    }

    func itemPreferredDate(_ itemID: String) -> Date? {
        itemLookup[itemID]?.preferredDate
    }

    func isVideo(itemID: String) -> Bool {
        itemLookup[itemID]?.isVideo == true
    }

    func mediaBadges(for itemID: String) -> [String] {
        guard let item = itemLookup[itemID] else {
            return []
        }

        var badges: [String] = []
        if item.mediaKind == .video {
            badges.append("VIDEO")
        } else {
            badges.append("IMAGE")
        }

        let ext = item.url.pathExtension.uppercased()
        if !ext.isEmpty {
            badges.append(ext)
        }

        return badges
    }

    func thumbnail(for itemID: String, maxPixel: CGFloat = 480) async -> NSImage? {
        guard let item = itemLookup[itemID] else {
            return nil
        }

        let key = NSString(string: "\(itemID)-\(Int(maxPixel))")
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }

        guard let image = await diskService.thumbnail(for: item, maxPixel: maxPixel) else {
            return nil
        }

        thumbnailCache.setObject(image, forKey: key)
        thumbnailKeysByItemID[itemID, default: []].insert(key as String)
        return image
    }

    func previewPlayer(for itemID: String) -> AVPlayer? {
        guard let item = itemLookup[itemID] else {
            return nil
        }

        return diskService.previewPlayer(for: item)
    }

    func markTerminalItemVisibleIfNeeded(in group: ReviewGroup) {
        guard
            currentGroupIndex == groups.count - 1,
            let highlighted = highlightedItemID(in: group),
            let lastItem = group.itemIDs.last,
            highlighted == lastItem
        else {
            return
        }

        reviewedItemIDs.insert(highlighted)
        rebuildCommitPlan()
    }

    func requestCommit() {
        guard commitArmed else {
            return
        }

        guard let plan = commitPlan, plan.totalMoveCount > 0 else {
            warningMessage = ReviewError.noReviewedItemsToCommit.localizedDescription
            return
        }

        if plan.totalMoveCount > 200 {
            showLargeCommitConfirmation = true
            return
        }

        commitReviewedItems()
    }

    func confirmLargeCommitAndCommit() {
        showLargeCommitConfirmation = false
        commitReviewedItems()
    }

    private func commitReviewedItems() {
        guard !isCommitting else {
            return
        }

        guard let plan = commitPlan, plan.totalMoveCount > 0 else {
            warningMessage = ReviewError.noReviewedItemsToCommit.localizedDescription
            return
        }

        let rootFolderURL: URL
        do {
            rootFolderURL = try diskService.validateRootFolder(path: rootFolderPath)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        isCommitting = true
        commitMessage = nil
        errorMessage = nil
        warningMessage = nil

        let commitService = self.commitService
        Task { [weak self] in
            guard let self else {
                return
            }

            defer {
                self.isCommitting = false
            }

            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try commitService.execute(plan: plan, rootFolderURL: rootFolderURL)
                }.value

                self.applyCommitResult(result)
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func applyCommitResult(_ result: CommitExecutionResult) {
        guard !result.movedItemIDs.isEmpty else {
            warningMessage = "No files were moved."
            commitArmed = false
            rebuildCommitPlan()
            return
        }

        let movedSummary = "Moved \(result.totalMovedCount) file(s): Keep \(result.movedToKeepCount), Delete \(result.movedToDeleteCount), Send and Delete \(result.movedToSendAndDeleteCount)."
        var details: [String] = [movedSummary]
        if result.renamedCount > 0 {
            details.append("Auto-renamed on conflicts: \(result.renamedCount)")
        }
        if result.skippedMissingSourceCount > 0 {
            details.append("Missing at commit time: \(result.skippedMissingSourceCount)")
        }
        if !result.failureMessages.isEmpty {
            details.append("Failures: \(result.failureMessages.count)")
            warningMessage = result.failureMessages.prefix(3).joined(separator: "  •  ")
        }

        commitMessage = details.joined(separator: "  •  ")
        commitArmed = false
        showLargeCommitConfirmation = false

        // Reload from disk after commit so the review view always reflects the actual folder state.
        scan()
    }

    private func applyScanResult(_ result: ScanResult) {
        groups = result.groups
        itemLookup = result.itemLookup
        scannedItemCount = result.scannedItemCount

        currentGroupIndex = 0
        highlightedItemByGroup = [:]
        decisionByItemID = [:]
        reviewedItemIDs = []

        for group in groups {
            if let first = group.itemIDs.first {
                highlightedItemByGroup[group.id] = first
            }
            for itemID in group.itemIDs {
                decisionByItemID[itemID] = .delete
            }
        }

        if let currentGroup {
            ensureHighlightedItem(in: currentGroup)
            markTerminalItemVisibleIfNeeded(in: currentGroup)
        }

        scanProgress = 1.0
        scanStatusMessage = "Loaded \(result.scannedItemCount) item(s)."

        rebuildCommitPlan()
    }

    private func clearCurrentSessionState() {
        groups = []
        currentGroupIndex = 0
        highlightedItemByGroup = [:]
        decisionByItemID = [:]
        reviewedItemIDs = []
        itemLookup = [:]
        scannedItemCount = 0
        skippedHiddenCount = 0
        skippedUnsupportedCount = 0
        commitPlan = nil
        commitArmed = false

        thumbnailCache.removeAllObjects()
        thumbnailKeysByItemID = [:]
    }

    private func rebuildCommitPlan() {
        commitPlan = commitService.buildCommitPlan(
            itemLookup: itemLookup,
            decisions: decisionByItemID,
            reviewedItemIDs: reviewedItemIDs
        )
    }

    private func moveHighlight(in group: ReviewGroup, delta: Int) {
        ensureHighlightedItem(in: group)
        guard
            let currentHighlighted = highlightedItemID(in: group),
            let currentIndex = group.itemIDs.firstIndex(of: currentHighlighted)
        else {
            return
        }

        let targetIndex = max(0, min(group.itemIDs.count - 1, currentIndex + delta))
        let targetID = group.itemIDs[targetIndex]

        if currentHighlighted != targetID {
            reviewedItemIDs.insert(currentHighlighted)
            highlightedItemByGroup[group.id] = targetID
            markTerminalItemVisibleIfNeeded(in: group)
            rebuildCommitPlan()
        }
    }

    private func markHighlightedItemReviewed(in group: ReviewGroup) {
        guard let highlighted = highlightedItemID(in: group) else {
            return
        }

        reviewedItemIDs.insert(highlighted)
    }

    private func beginKeyboardNavigationSession() {
        ignoreHoverUntilMouseMoves = true
        mouseLocationAtKeyboardNavigation = NSEvent.mouseLocation
    }

    private func persistRootFolderPath() {
        UserDefaults.standard.set(rootFolderPath, forKey: rootFolderDefaultsKey)
    }

    private var persistedReviewSessionURL: URL {
        let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        let bundleID = Bundle.main.bundleIdentifier ?? "com.jkfisher.amysorthelper"
        return appSupportURL
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent(reviewSessionFileName, isDirectory: false)
    }

    private func clearPersistedReviewSession() {
        let url = persistedReviewSessionURL
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
