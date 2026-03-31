import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var shouldPromptBeforeQuit: (() -> Bool)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Bring the first app window to the front on launch.
        NSApp.setActivationPolicy(.regular)
        if let appIcon = Self.loadAppIcon() {
            NSApp.applicationIconImage = appIcon
        }
        NSApp.activate(ignoringOtherApps: true)

        installWindowObservers()

        Task { @MainActor in
            await self.configureWindowsWhenReady()
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard shouldPromptBeforeQuit?() == true else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Quit Without Committing?"
        alert.informativeText = "Quitting now will discard your current review progress. Commit reviewed files first if you want those decisions applied."
        alert.addButton(withTitle: "Quit Without Committing")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        return response == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    private func installWindowObservers() {
        let notificationCenter = NotificationCenter.default

        let names: [Notification.Name] = [
            NSWindow.didBecomeMainNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification
        ]

        for name in names {
            notificationCenter.addObserver(
                self,
                selector: #selector(handleWindowNotification(_:)),
                name: name,
                object: nil
            )
        }
    }

    private func configureWindowsWhenReady() async {
        // SwiftUI sometimes creates windows after didFinishLaunching; poll briefly.
        for _ in 0..<24 {
            configureAllWindows()
            if !NSApp.windows.isEmpty {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        configureAllWindows()
    }

    @objc
    private func handleWindowNotification(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            configureWindow(window)
        } else {
            configureAllWindows()
        }
    }

    private func configureAllWindows() {
        for window in NSApp.windows {
            configureWindow(window)
        }
    }

    private func configureWindow(_ window: NSWindow) {
        Self.applyWindowStyle(to: window)
    }

    static func applyWindowStyle(to window: NSWindow) {
        // Keep content below the title bar so controls are never hidden in/after full screen.
        if window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.remove(.fullSizeContentView)
        }
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .expanded
        window.toolbar?.showsBaselineSeparator = true
        window.isMovableByWindowBackground = false
    }

    private static func loadAppIcon() -> NSImage? {
        if let namedIcon = NSImage(named: "AppIcon") {
            return namedIcon
        }

        guard let fallbackURL = Bundle.module.url(
            forResource: "icon_512x512@2x",
            withExtension: "png",
            subdirectory: "Assets.xcassets/AppIcon.appiconset"
        ) else {
            return nil
        }

        return NSImage(contentsOf: fallbackURL)
    }
}
