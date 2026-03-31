import AppKit
import AVKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var viewModel: ReviewViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HSplitView {
            controlsPane
                .frame(minWidth: 290, idealWidth: 320, maxWidth: 380)

            reviewPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appBackgroundColor)
        .task {
            await viewModel.bootstrap()
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Confirm Large Commit", isPresented: $viewModel.showLargeCommitConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Commit Move") {
                viewModel.confirmLargeCommitAndCommit()
            }
        } message: {
            Text("This commit will move more than 200 files. Continue?")
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showCommitPreview },
            set: { viewModel.showCommitPreview = $0 }
        )) {
            CommitPreviewSheet()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showCommitResults },
            set: { newValue in
                if !newValue {
                    viewModel.dismissCommitResults()
                } else {
                    viewModel.showCommitResults = true
                }
            }
        )) {
            CommitResultsSheet()
                .environmentObject(viewModel)
        }
    }

    private var controlsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(AppMetadata.displayName)
                    .font(.title2.bold())

                Text(AppMetadata.releaseLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(sidebarSecondaryTextColor)

                Text("Review files from the selected folder and move reviewed items to Keep, Delete, or Send and Delete when you commit.")
                    .font(.subheadline)
                    .foregroundStyle(sidebarSecondaryTextColor)

                Divider()

                folderSection

                Divider()

                scanSection

                Divider()

                statusSection
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 20)
        }
        .background(sidebarBackgroundColor)
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Folder")
                .font(.headline)

            Text("Source folder")
                .font(.caption.weight(.semibold))
                .foregroundStyle(sidebarSecondaryTextColor)

            if viewModel.hasSelectedSourceFolder {
                Text(viewModel.sourceFolderDisplayText)
                    .font(.caption.monospaced())
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .textSelection(.enabled)
            } else {
                Text(viewModel.sourceFolderDisplayText)
                    .font(.caption.monospaced())
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .textSelection(.disabled)
            }

            Text(viewModel.sourceFolderDescription)
                .font(.caption)
                .foregroundStyle(sidebarSecondaryTextColor)

            Text(viewModel.destinationFolderDescription)
                .font(.caption)
                .foregroundStyle(sidebarSecondaryTextColor)

            Text("Destination root")
                .font(.caption.weight(.semibold))
                .foregroundStyle(sidebarSecondaryTextColor)

            Text(viewModel.destinationRootDisplayText)
                .font(.caption.monospaced())
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.06))
                )
                .textSelection(.enabled)

            destinationPathRow(title: "Keep", destination: .keep)
            destinationPathRow(title: "Delete", destination: .delete)
            destinationPathRow(title: "Send/Delete", destination: .sendAndDelete)

            Button(viewModel.hasSelectedSourceFolder ? "Change Folder..." : "Choose Folder...") {
                viewModel.changeSourceFolder()
            }
            .buttonStyle(.bordered)
        }
    }

    private func destinationPathRow(title: String, destination: CommitDestination) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(sidebarSecondaryTextColor)

            Text(viewModel.destinationPath(for: destination))
                .font(.caption.monospaced())
                .foregroundStyle(sidebarSecondaryTextColor)
                .textSelection(.enabled)
        }
    }

    private var scanSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scan")
                .font(.headline)

            Button {
                viewModel.scan()
            } label: {
                Label(viewModel.isScanning ? "Scanning..." : "Scan Folder", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isScanning || viewModel.isCommitting || !viewModel.hasSelectedSourceFolder)

            if viewModel.isScanning {
                Button(role: .destructive) {
                    viewModel.stopScan()
                } label: {
                    Label("Stop Scan", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if viewModel.isScanning {
                ProgressView(value: viewModel.scanProgress)
            }

            Text(viewModel.scanStatusMessage)
                .font(.caption)
                .foregroundStyle(sidebarSecondaryTextColor)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.headline)

            Text("Scanned files: \(viewModel.scannedItemCount)")
                .font(.footnote)
            Text("Review items: \(viewModel.groups.count)")
                .font(.footnote)
            Text(viewModel.reviewProgressLabel)
                .font(.footnote)

            if viewModel.skippedHiddenCount > 0 || viewModel.skippedUnsupportedCount > 0 {
                Text("Skipped hidden: \(viewModel.skippedHiddenCount)  •  Skipped unsupported: \(viewModel.skippedUnsupportedCount)")
                    .font(.caption)
                    .foregroundStyle(sidebarSecondaryTextColor)
            }

            if let warning = viewModel.warningMessage {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let message = viewModel.latestCommitSummary {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private var reviewPane: some View {
        Group {
            if let group = viewModel.currentGroup {
                ReviewGroupView(group: group)
            } else {
                ContentUnavailableView(
                    "No Files Loaded",
                    systemImage: "folder",
                    description: Text("Choose any source folder, then scan to load its top-level files.")
                )
            }
        }
        .safeAreaPadding(.top, 8)
    }

    private var appBackgroundColor: Color {
        if colorScheme == .dark {
            return Color(nsColor: NSColor(calibratedWhite: 0.11, alpha: 1.0))
        }

        return Color(red: 0.96, green: 0.98, blue: 1.0).opacity(0.45)
    }

    private var sidebarBackgroundColor: Color {
        if colorScheme == .dark {
            return Color(nsColor: NSColor(calibratedWhite: 0.16, alpha: 1.0))
        }

        return Color(red: 0.97, green: 0.985, blue: 1.0).opacity(0.5)
    }

    private var sidebarSecondaryTextColor: Color {
        if colorScheme == .dark {
            return Color(nsColor: .secondaryLabelColor).opacity(0.98)
        }

        return .secondary
    }
}

private struct ReviewGroupView: View {
    @EnvironmentObject private var viewModel: ReviewViewModel

    let group: ReviewGroup

    @State private var previewImage: NSImage?
    @State private var previewPlayer: AVPlayer?
    @State private var loadingVideo = false
    @State private var decisionPulse = false

    private let singleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    private let intervalFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    private var highlightedItemID: String? {
        viewModel.highlightedItemID(in: group)
    }

    private var highlightedIsVideo: Bool {
        guard let highlightedItemID else {
            return false
        }

        return viewModel.isVideo(itemID: highlightedItemID)
    }

    private var highlightedDecision: FileDecision? {
        guard let highlightedItemID else {
            return nil
        }
        return viewModel.decision(for: highlightedItemID)
    }

    private var keepColor: Color {
        Color(red: 0.19, green: 0.74, blue: 0.43)
    }

    private var deleteColor: Color {
        Color(red: 0.94, green: 0.28, blue: 0.30)
    }

    private var sendAndDeleteColor: Color {
        Color(red: 0.93, green: 0.75, blue: 0.22)
    }

    private var neutralDecisionColor: Color {
        Color(red: 0.35, green: 0.40, blue: 0.46)
    }

    private var decisionAccentColor: Color {
        guard let highlightedDecision else {
            return neutralDecisionColor.opacity(0.7)
        }

        switch highlightedDecision {
        case .keep:
            return keepColor
        case .delete:
            return deleteColor
        case .sendAndDelete:
            return sendAndDeleteColor
        }
    }

    private var decisionBannerLabel: String {
        switch highlightedDecision {
        case .keep:
            return "KEEPING SELECTED ITEM"
        case .delete:
            return "MARKED TO DELETE"
        case .sendAndDelete:
            return "SEND AND DELETE"
        case .none:
            return "NO ITEM SELECTED"
        }
    }

    private var decisionPillLabel: String {
        switch highlightedDecision {
        case .keep:
            return "KEEP"
        case .delete:
            return "DELETE"
        case .sendAndDelete:
            return "SEND+DELETE"
        case .none:
            return "NONE"
        }
    }

    private var decisionBannerSymbolName: String {
        switch highlightedDecision {
        case .keep:
            return "checkmark.circle.fill"
        case .delete:
            return "xmark.circle.fill"
        case .sendAndDelete:
            return "arrowshape.turn.up.forward.circle.fill"
        case .none:
            return "minus.circle.fill"
        }
    }

    private var reviewFraction: Double {
        guard viewModel.totalItemCount > 0 else {
            return 0
        }
        let fraction = Double(viewModel.reviewedItemCount) / Double(viewModel.totalItemCount)
        return min(max(fraction, 0), 1)
    }

    private var reviewRingColor: Color {
        if viewModel.totalItemCount > 0, viewModel.reviewedItemCount >= viewModel.totalItemCount {
            return keepColor
        }
        return Color(red: 0.20, green: 0.58, blue: 0.94)
    }

    private var groupDateLabel: String {
        switch (group.startDate, group.endDate) {
        case let (.some(start), .some(end)):
            if abs(start.timeIntervalSince(end)) < 0.5 {
                return singleDateFormatter.string(from: start)
            }
            return intervalFormatter.string(from: start, to: end)
        case let (.some(start), .none):
            return singleDateFormatter.string(from: start)
        case let (.none, .some(end)):
            return singleDateFormatter.string(from: end)
        case (.none, .none):
            return "Capture date unavailable"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            previewColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            commitSection
        }
        .padding(24)
        .onAppear {
            viewModel.ensureHighlightedItem(in: group)
            viewModel.markTerminalItemVisibleIfNeeded(in: group)
        }
        .task(id: highlightedItemID) {
            await loadPreview(for: highlightedItemID)
        }
        .onChange(of: group.id) { _, _ in
            previewPlayer?.pause()
            previewPlayer = nil
            loadingVideo = false
            viewModel.ensureHighlightedItem(in: group)
            viewModel.markTerminalItemVisibleIfNeeded(in: group)
        }
        .onChange(of: highlightedItemID) { _, _ in
            viewModel.markTerminalItemVisibleIfNeeded(in: group)
        }
        .onChange(of: highlightedDecision?.rawValue) { _, _ in
            triggerDecisionPulse()
        }
        .onDisappear {
            previewPlayer?.pause()
            previewPlayer = nil
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Item \(viewModel.currentGroupIndex + 1) of \(viewModel.groups.count)")
                    .font(.title3.bold())

                Text(groupDateLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Tip: ` toggles Keep/Delete, S marks Send and Delete, left/right moves items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                CompactProgressRing(
                    progress: reviewFraction,
                    accentColor: reviewRingColor,
                    label: "\(viewModel.reviewedItemCount)/\(viewModel.totalItemCount)"
                )

                VStack(alignment: .trailing, spacing: 5) {
                    Text("Reviewed")
                        .font(.caption.weight(.semibold))

                    if let plan = viewModel.commitPlan {
                        Text("Ready to move: \(plan.totalMoveCount)")
                            .font(.caption)
                        Text("Keep: \(plan.keepCount)  •  Delete: \(plan.deleteCount)  •  Send/Delete: \(plan.sendAndDeleteCount)")
                            .font(.caption)
                    } else {
                        Text("Ready to move: 0")
                            .font(.caption)
                    }
                }
                .multilineTextAlignment(.trailing)
            }
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let highlightedItemID {
                Text(viewModel.itemFileName(highlightedItemID))
                    .font(.headline)
                    .lineLimit(1)

                Text(viewModel.itemDateLabel(highlightedItemID))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Size: \(viewModel.itemByteSizeLabel(highlightedItemID))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: decisionBannerSymbolName)
                    .font(.caption.weight(.bold))
                Text(decisionBannerLabel)
                    .font(.subheadline.bold())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(decisionAccentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(decisionPulse ? 1.006 : 1.0)
            .animation(.easeInOut(duration: 0.18), value: decisionPulse)

            ZStack {
                previewTextureBackground

                if loadingVideo {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Loading video preview...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else if highlightedIsVideo, let previewPlayer {
                    AVPlayerPreviewView(player: previewPlayer)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(8)
                } else if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(8)
                } else {
                    Text("No preview available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .overlay(alignment: .topTrailing) {
                Text(decisionPillLabel)
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(decisionAccentColor, in: Capsule())
                    .foregroundStyle(.white)
                    .padding(12)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(decisionAccentColor, lineWidth: 2.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.32), lineWidth: 1)
            )
            .shadow(
                color: decisionAccentColor.opacity(decisionPulse ? 0.38 : 0.22),
                radius: decisionPulse ? 20 : 14,
                x: 0,
                y: 4
            )
            .animation(.easeInOut(duration: 0.2), value: highlightedDecision?.rawValue)
            .animation(.easeInOut(duration: 0.18), value: decisionPulse)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(decisionAccentColor, lineWidth: 3)
        )
        .shadow(color: Color.black.opacity(0.07), radius: 12, x: 0, y: 7)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var commitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.isCommitting, let commitProgress = viewModel.commitProgress {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: commitProgress.fractionCompleted)

                    Text(commitProgress.statusMessage)
                        .font(.subheadline.weight(.semibold))

                    Text(viewModel.commitProgressSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let currentFileName = commitProgress.currentFileName {
                        Text("Current file: \(currentFileName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let lastProcessedFileName = commitProgress.lastProcessedFileName {
                        Text("Last processed: \(lastProcessedFileName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Spacer()
                        Button("Cancel Commit", role: .destructive) {
                            viewModel.cancelCommit()
                        }
                    }
                }
            } else {
                HStack {
                    Spacer()
                    Button {
                        viewModel.requestCommit()
                    } label: {
                        Text("Review Commit Scope")
                    }
                    .disabled(viewModel.commitMoveCount == 0 || !viewModel.commitArmed)
                }
            }

            Toggle(
                "I understand this moves reviewed files from the selected folder into sibling Keep/Delete/Send and Delete folders.",
                isOn: $viewModel.commitArmed
            )
            .toggleStyle(.checkbox)
            .font(.footnote)
            .disabled(viewModel.isCommitting)
        }
    }

    private var previewTextureBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.93, green: 0.94, blue: 0.95),
                            Color(red: 0.90, green: 0.91, blue: 0.93)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Subtle dotted grain to avoid a flat block behind media.
            Canvas { context, size in
                let dotColor = Color.white.opacity(0.09)
                for x in stride(from: 2.0, to: size.width, by: 12.0) {
                    for y in stride(from: 2.0, to: size.height, by: 12.0) {
                        let rect = CGRect(x: x, y: y, width: 1.2, height: 1.2)
                        context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))

            RoundedRectangle(cornerRadius: 16)
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.20),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 20,
                        endRadius: 560
                    )
                )
                .blendMode(.screen)
        }
    }

    private func triggerDecisionPulse() {
        withAnimation(.easeOut(duration: 0.1)) {
            decisionPulse = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 170_000_000)
            withAnimation(.easeIn(duration: 0.16)) {
                decisionPulse = false
            }
        }
    }

    private func loadPreview(for itemID: String?) async {
        guard let itemID else {
            previewImage = nil
            previewPlayer?.pause()
            previewPlayer = nil
            loadingVideo = false
            return
        }

        previewPlayer?.pause()
        previewPlayer = nil
        loadingVideo = false

        if viewModel.isVideo(itemID: itemID) {
            previewImage = nil
            loadingVideo = true

            if let thumb = await viewModel.thumbnail(for: itemID, maxPixel: 1800), highlightedItemID == itemID {
                previewImage = thumb
            }

            if highlightedItemID == itemID {
                if let player = viewModel.previewPlayer(for: itemID) {
                    _ = await player.seek(to: .zero)
                    player.play()
                    previewPlayer = player
                } else {
                    previewPlayer = nil
                }
                loadingVideo = false
            }

            return
        }

        if let image = await viewModel.thumbnail(for: itemID, maxPixel: 3000), highlightedItemID == itemID {
            previewImage = image
        }
    }
}

private struct CommitPreviewSheet: View {
    @EnvironmentObject private var viewModel: ReviewViewModel
    @Environment(\.dismiss) private var dismiss

    private let previewDestinations: [CommitDestination] = [.keep, .delete, .sendAndDelete]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Review Commit Scope")
                            .font(.title2.bold())
                        Text("Confirm the exact source, destination paths, and sample files before any move begins.")
                            .foregroundStyle(.secondary)
                    }

                    CommitPathCard(title: "Source Folder", path: viewModel.sourceFolderDisplayText)
                    CommitPathCard(title: "Destination Root", path: viewModel.destinationRootDisplayText)

                    ForEach(previewDestinations, id: \.rawValue) { destination in
                        CommitPreviewDestinationCard(
                            title: destination.folderName,
                            path: viewModel.destinationPath(for: destination),
                            count: viewModel.commitCount(for: destination),
                            samples: viewModel.commitSamples(for: destination),
                            remainingCount: viewModel.remainingSampleCount(for: destination)
                        )
                    }

                    Text("Reviewed files only will move. Existing name conflicts are auto-renamed instead of overwritten.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .frame(minWidth: 640, minHeight: 560)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm Commit") {
                        dismiss()
                        viewModel.confirmCommitPreview()
                    }
                    .disabled(viewModel.commitMoveCount == 0)
                }
            }
        }
    }
}

private struct CommitResultsSheet: View {
    @EnvironmentObject private var viewModel: ReviewViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let result = viewModel.lastCommitResult {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(viewModel.commitResultsTitle)
                                .font(.title2.bold())
                            Text(resultsSummaryText(for: result))
                                .foregroundStyle(.secondary)
                        }

                        CommitPathCard(title: "Destination Root", path: result.destinationPaths.destinationRootURL.path)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Outcome")
                                .font(.headline)
                            Text("Requested: \(result.totalOperationCount)")
                            Text("Processed: \(result.processedCount)")
                            Text("Moved: \(result.totalMovedCount)")
                            Text("Keep: \(result.movedToKeepCount)  •  Delete: \(result.movedToDeleteCount)  •  Send and Delete: \(result.movedToSendAndDeleteCount)")
                            Text("Renamed: \(result.renamedCount)  •  Missing: \(result.skippedMissingSourceCount)  •  Failures: \(result.failureCount)")
                            if result.wasCancelled {
                                Text("Remaining unprocessed: \(result.remainingCount)")
                            }
                        }
                        .font(.body)

                        if !result.renamedItems.isEmpty {
                            CommitResultSection(title: "Renamed On Conflict") {
                                ForEach(result.renamedItems) { renamedItem in
                                    CommitResultRow(
                                        title: "\(renamedItem.sourceFileName) → \(renamedItem.finalFileName)",
                                        subtitle: renamedItem.destinationPath
                                    )
                                }
                            }
                        }

                        if !result.skippedMissingSources.isEmpty {
                            CommitResultSection(title: "Skipped Missing Sources") {
                                ForEach(result.skippedMissingSources) { missingItem in
                                    CommitResultRow(
                                        title: missingItem.sourceFileName,
                                        subtitle: "Missing at commit time. Intended destination: \(missingItem.destinationFolderPath)"
                                    )
                                }
                            }
                        }

                        if !result.failures.isEmpty {
                            CommitResultSection(title: "Failures") {
                                ForEach(result.failures) { failure in
                                    CommitResultRow(
                                        title: failure.sourceFileName,
                                        subtitle: "\(failure.message)\nDestination: \(failure.destinationFolderPath)"
                                    )
                                }
                            }
                        }
                    } else {
                        Text("No commit results available.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }
            .frame(minWidth: 680, minHeight: 560)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func resultsSummaryText(for result: CommitExecutionResult) -> String {
        if result.wasCancelled {
            return "The commit stopped before all files were processed. Already moved files were left in their destination folders."
        }

        if result.hasIssues {
            return "Some files moved successfully, but the run also included skips or failures. Review the details below before continuing."
        }

        return "All requested reviewed files were moved successfully."
    }
}

private struct CommitPathCard: View {
    let title: String
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(path)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.06))
                )
        }
    }
}

private struct CommitPreviewDestinationCard: View {
    let title: String
    let path: String
    let count: Int
    let samples: [String]
    let remainingCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(count) file(s)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(path)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(.secondary)

            if samples.isEmpty {
                Text("No files queued for this destination.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(samples, id: \.self) { sample in
                        Text("- \(sample)")
                            .font(.caption)
                    }

                    if remainingCount > 0 {
                        Text("- \(remainingCount) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

private struct CommitResultSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
    }
}

private struct CommitResultRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

private struct AVPlayerPreviewView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .floating
        playerView.videoGravity = .resizeAspect
        playerView.player = player
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
        if player.timeControlStatus != .playing {
            player.play()
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
    }
}

private struct CompactProgressRing: View {
    let progress: Double
    let accentColor: Color
    let label: String

    var body: some View {
        let clamped = min(max(progress, 0), 1)

        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.15), lineWidth: 4.5)

            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    accentColor,
                    style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text(label)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 46, height: 46)
    }
}
