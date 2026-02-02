import AppKit
import SwiftUI
import Combine
import Sparkle

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager?
    private var cancellables = Set<AnyCancellable>()
    private var updaterController: SPUStandardUpdaterController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize Sparkle updater
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

        // Create status bar item FIRST
        setupStatusItem()

        // Check permissions on launch
        Task {
            await PermissionsManager.shared.checkAllPermissions()
        }

        // Auto-load bundled model immediately (it's included with the app)
        Task {
            let localService = LocalTranscriptionService.shared
            // Always load bundled model if available and not loaded
            if localService.hasBundledModel && !localService.isModelLoaded {
                do {
                    try await localService.loadModel(LocalTranscriptionService.bundledModel)
                    print("Bundled model loaded successfully")
                } catch {
                    print("Failed to auto-load bundled model: \(error)")
                }
            }
        }

        // Setup hotkeys
        hotkeyManager = HotkeyManager.shared
        hotkeyManager?.setup()

        // Observe state changes to update icon
        AppState.shared.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusIcon() }
            .store(in: &cancellables)

        AppState.shared.$isTranscribing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusIcon() }
            .store(in: &cancellables)

        // Listen for check updates notification from SwiftUI
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCheckForUpdates),
            name: .init("checkForUpdates"),
            object: nil
        )

        // Show main window on first launch or if no API key
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MainWindowController.shared.show()
        }
    }

    @objc private func handleCheckForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "TalkKey")
        }

        let menu = NSMenu()

        // Status item
        let statusMenuItem = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Shortcut hint
        let hintItem = NSMenuItem(title: "Right ⌘ to record", action: nil, keyEquivalent: "")
        hintItem.isEnabled = false
        menu.addItem(hintItem)

        menu.addItem(NSMenuItem.separator())

        // Open main window
        let openItem = NSMenuItem(title: "Open TalkKey...", action: #selector(openMainWindow), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Check for Updates
        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = updaterController
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }

        let iconName: String
        let statusText: String

        if AppState.shared.isRecording {
            iconName = "mic.fill"
            statusText = "Recording..."
        } else if AppState.shared.isTranscribing {
            iconName = "ellipsis.circle"
            statusText = "Transcribing..."
        } else if !AppState.shared.hasAPIKey {
            iconName = "mic.badge.xmark"
            statusText = "API key needed"
        } else {
            iconName = "mic"
            statusText = "Ready"
        }

        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "TalkKey")

        // Update status menu item
        if let menu = statusItem.menu, let statusMenuItem = menu.item(withTag: 100) {
            statusMenuItem.title = statusText
        }
    }

    @objc private func openMainWindow() {
        MainWindowController.shared.show()
    }

    @objc private func openSettings() {
        MainWindowController.shared.show()
        // Switch to Settings tab
        NotificationCenter.default.post(name: .init("switchToSettings"), object: nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.cleanup()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Open main window when clicking Dock icon
        if !flag {
            MainWindowController.shared.show()
        }
        return true
    }
}
