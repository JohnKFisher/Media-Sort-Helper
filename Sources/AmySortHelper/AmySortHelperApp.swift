import AppKit
import SwiftUI

@main
struct AmySortHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = ReviewViewModel()

    var body: some Scene {
        WindowGroup(AppMetadata.displayName) {
            RootView()
                .environmentObject(viewModel)
                .frame(minWidth: 1140, minHeight: 780)
                .onAppear {
                    appDelegate.shouldPromptBeforeQuit = { [viewModel] in
                        viewModel.shouldPromptBeforeQuit
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(AppMetadata.displayName)") {
                    NSApp.orderFrontStandardAboutPanel(options: aboutPanelOptions)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }

            CommandMenu("Review Navigation") {
                Button("Previous Group") {
                    viewModel.previousGroup()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(!viewModel.hasPreviousGroup)

                Button("Next Group") {
                    viewModel.nextGroup()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(!viewModel.hasNextGroup)

                Divider()

                Button("Highlight Previous Item") {
                    viewModel.highlightPreviousItemInCurrentGroup()
                }
                .keyboardShortcut(.upArrow, modifiers: [])
                .disabled(!viewModel.hasHighlightInCurrentGroup)

                Button("Highlight Next Item") {
                    viewModel.highlightNextItemInCurrentGroup()
                }
                .keyboardShortcut(.downArrow, modifiers: [])
                .disabled(!viewModel.hasHighlightInCurrentGroup)

                Button("Toggle Highlighted Keep/Delete") {
                    viewModel.toggleHighlightedItemDecisionInCurrentGroup()
                }
                .keyboardShortcut("`", modifiers: [])
                .disabled(!viewModel.hasHighlightInCurrentGroup)

                Button("Mark Highlighted Send and Delete") {
                    viewModel.markHighlightedItemSendAndDeleteInCurrentGroup()
                }
                .keyboardShortcut("s", modifiers: [])
                .disabled(!viewModel.hasHighlightInCurrentGroup)
            }
        }
    }

    private var aboutPanelOptions: [NSApplication.AboutPanelOptionKey: Any] {
        [
            .applicationName: AppMetadata.displayName,
            .applicationVersion: AppMetadata.version,
            .version: "Build \(AppMetadata.build)",
            .credits: NSAttributedString(
                string: "Amy Sort Helper \(AppMetadata.version)\nReview files from Current Sort and safely move reviewed items to Keep/Delete/Send and Delete on commit."
            )
        ]
    }
}
