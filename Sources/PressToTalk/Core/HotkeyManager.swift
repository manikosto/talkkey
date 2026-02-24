import AppKit
import AVFoundation
import Carbon
import UserNotifications

enum RecordingMode {
    case directPaste
    case review
    case translation  // Right ⌘ + configured key = translate mode
}

class HotkeyManager {
    static let shared = HotkeyManager()

    private var flagsMonitor: Any?
    private var escapeMonitor: Any?
    private var localMonitor: Any?
    private var keyDownMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var isPrimaryHotkeyPressed = false
    private var isSecondaryHotkeyPressed = false
    private var isTranslationHotkeyPressed = false
    private var wasFnHeld = false  // Track Fn state for reliable detection
    private var currentMode: RecordingMode = .directPaste
    private var recordingStartTime: Date?
    private var isCurrentlyRecording = false  // Local tracking to avoid main actor issues

    private let audioRecorder = AudioRecorder.shared
    private let transcriptionService = TranscriptionService.shared

    func setup() {
        // Monitor for hotkey (flags changed)
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Also monitor locally for when our app is active
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        // Monitor keyDown for escape
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }

        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
            return event
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        // Escape to cancel
        if event.keyCode == 53 {
            cancelRecording()
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags
        let keyCode = event.keyCode

        // Check if Right Cmd is pressed (keyCode 54)
        let rightCmdPressed = flags.contains(.command) && keyCode == 54
        let rightCmdHeld = flags.contains(.command)

        // Check if Right Option is pressed (keyCode 61)
        let rightOptPressed = flags.contains(.option) && keyCode == 61
        let rightOptHeld = flags.contains(.option)

        // Check Fn state - detect when Fn flag appears (not relying on keyCode)
        let fnHeld = flags.contains(.function)
        let fnJustPressed = fnHeld && !wasFnHeld  // Fn was just pressed
        wasFnHeld = fnHeld  // Update for next event

        // Track key states
        let wasPrimaryPressed = isPrimaryHotkeyPressed
        let wasSecondaryPressed = isSecondaryHotkeyPressed
        let wasTranslationPressed = isTranslationHotkeyPressed

        // Update states based on current flags
        if rightCmdPressed {
            isPrimaryHotkeyPressed = true
        } else if !rightCmdHeld && wasPrimaryPressed {
            isPrimaryHotkeyPressed = false
        }

        if rightOptPressed {
            isSecondaryHotkeyPressed = true
        } else if !rightOptHeld && wasSecondaryPressed {
            isSecondaryHotkeyPressed = false
        }

        if fnJustPressed {
            isTranslationHotkeyPressed = true
        } else if !fnHeld && wasTranslationPressed {
            isTranslationHotkeyPressed = false
        }

        // Start recording logic
        if !isCurrentlyRecording {
            if rightCmdPressed && !rightOptHeld && !fnHeld {
                // Only Right Cmd = direct paste
                currentMode = .directPaste
                isCurrentlyRecording = true
                startRecording()
            } else if rightOptPressed && !rightCmdHeld && !fnHeld {
                // Only Right Option = review mode (Pro only)
                if !LicenseManager.checkIsPro() {
                    showNotification(title: "Pro Feature", body: "Review mode requires Pro license")
                    return
                }
                currentMode = .review
                isCurrentlyRecording = true
                startRecording()
            } else if fnJustPressed && !rightCmdHeld && !rightOptHeld {
                // Only Fn = translation mode (Pro only)
                if !LicenseManager.checkIsPro() {
                    showNotification(title: "Pro Feature", body: "Translation requires Pro license")
                    return
                }
                currentMode = .translation
                isCurrentlyRecording = true
                startRecording()
            }
        }

        // Stop recording when all modifier keys are released
        if isCurrentlyRecording && !rightCmdHeld && !rightOptHeld && !fnHeld {
            isPrimaryHotkeyPressed = false
            isSecondaryHotkeyPressed = false
            isTranslationHotkeyPressed = false
            isCurrentlyRecording = false
            stopRecordingAndTranscribe()
        }
    }

    private func checkHotkey(hotkey: HotkeyOption, flags: NSEvent.ModifierFlags, keyCode: UInt16, wasPressed: Bool) -> (pressed: Bool, released: Bool) {
        var isModifierPressed = false
        var hotkeyPressed = false

        switch hotkey {
        case .rightCmd:
            isModifierPressed = flags.contains(.command)
            hotkeyPressed = isModifierPressed && (keyCode == 54)
        case .rightOption:
            isModifierPressed = flags.contains(.option)
            hotkeyPressed = isModifierPressed && (keyCode == 61)
        case .fn:
            hotkeyPressed = keyCode == 63 && flags.contains(.function)
            isModifierPressed = flags.contains(.function)
        }

        let hotkeyReleased = !isModifierPressed && wasPressed
        return (hotkeyPressed, hotkeyReleased)
    }

    private func startRecording() {
        // Save the current app BEFORE showing overlay
        PasteboardManager.shared.saveCurrentApp()

        Task { @MainActor in
            // Check and request microphone permission
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            if status == .notDetermined {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                AppState.shared.hasMicrophonePermission = granted
                if !granted {
                    showNotification(title: "Permission Required", body: "Please grant microphone access")
                    return
                }
            } else if status != .authorized {
                AppState.shared.hasMicrophonePermission = false
                showNotification(title: "Permission Required", body: "Please grant microphone access in System Settings")
                return
            } else {
                AppState.shared.hasMicrophonePermission = true
            }

            // Check if we have what we need: either offline mode with model, or API key
            let offlineReady = SettingsManager.shared.offlineModeEnabled
            if !offlineReady && !AppState.shared.hasAPIKey {
                showNotification(title: "Setup Required", body: "Enable offline mode or add API key")
                return
            }

            // Check transcription limit for free users
            if !LicenseManager.shared.canTranscribe {
                showDailyLimitAlert()
                return
            }

            // Prevent starting if already recording
            guard !AppState.shared.isRecording else { return }

            do {
                try audioRecorder.startRecording()
                recordingStartTime = Date()
                UsageTracker.shared.startRecording()

                // Set the recording mode in AppState for overlay display
                switch currentMode {
                case .directPaste:
                    AppState.shared.currentRecordingMode = .directPaste
                case .review:
                    AppState.shared.currentRecordingMode = .review
                case .translation:
                    AppState.shared.currentRecordingMode = .translation
                }

                AppState.shared.isRecording = true
                RecordingOverlayWindowController.shared.show()
            } catch {
                print("Recording error: \(error)")
                showNotification(title: "Recording Error", body: error.localizedDescription)
            }
        }
    }

    private func stopRecordingAndTranscribe() {
        Task { @MainActor in
            guard AppState.shared.isRecording else { return }

            let recordingDuration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
            recordingStartTime = nil

            // Check if there's sufficient audio before stopping
            let hasSufficientAudio = audioRecorder.hasSufficientAudio

            AppState.shared.isRecording = false
            RecordingOverlayWindowController.shared.hide()

            // Track usage time
            UsageTracker.shared.stopRecording()

            guard let audioURL = audioRecorder.stopRecording() else {
                return
            }

            // Skip transcription if audio level was too low (silence/noise)
            guard hasSufficientAudio else {
                try? FileManager.default.removeItem(at: audioURL)
                showNotification(title: "No Speech Detected", body: "Recording was too quiet. Please speak louder or check your microphone.")
                return
            }

            AppState.shared.isTranscribing = true

            do {
                // For translation mode, pass translateToLanguage
                let translateToLanguage = currentMode == .translation ? SettingsManager.shared.targetLanguage : nil
                let text = try await transcriptionService.transcribe(audioURL: audioURL, translateTo: translateToLanguage)

                if !text.isEmpty {
                    // Track stats
                    UsageTracker.shared.recordTranscription(text: text, recordingDuration: recordingDuration)
                    LicenseManager.shared.recordTranscription()

                    switch currentMode {
                    case .directPaste:
                        // Direct paste like before
                        PasteboardManager.shared.pasteText(text)
                        HistoryManager.shared.add(text)
                    case .review:
                        // Show review window
                        ReviewWindowController.shared.show(text: text)
                    case .translation:
                        // Direct paste translated text
                        PasteboardManager.shared.pasteText(text)
                        HistoryManager.shared.add(text)
                    }
                }
            } catch {
                AppState.shared.showErrorMessage(error.localizedDescription)
                showNotification(title: "Error", body: error.localizedDescription)
            }

            AppState.shared.isTranscribing = false
        }
    }

    private func cancelRecording() {
        isCurrentlyRecording = false
        Task { @MainActor in
            guard AppState.shared.isRecording else { return }

            AppState.shared.isRecording = false
            isPrimaryHotkeyPressed = false
            isSecondaryHotkeyPressed = false
            UsageTracker.shared.cancelRecording()
            audioRecorder.cancelRecording()
            RecordingOverlayWindowController.shared.hide()
        }
    }

    func cleanup() {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
        }
        flagsMonitor = nil
        escapeMonitor = nil
        localMonitor = nil
        keyDownMonitor = nil
        localKeyDownMonitor = nil
    }

    private func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func showDailyLimitAlert() {
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = "Daily Limit Reached"
            alert.informativeText = "You've used all \(LicenseManager.freeTranscriptionsPerDay) free transcriptions for today.\n\nUpgrade to Pro for unlimited transcriptions, longer recordings, and translation features."
            alert.alertStyle = .informational
            alert.icon = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil)

            alert.addButton(withTitle: "Buy License — $15")
            alert.addButton(withTitle: "Enter Key")
            alert.addButton(withTitle: "Later")

            // Bring app to front
            NSApp.activate(ignoringOtherApps: true)

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Open purchase page
                NSWorkspace.shared.open(LicenseManager.purchaseURL)
            } else if response == .alertSecondButtonReturn {
                // Open main window and show license key input
                MainWindowController.shared.show()
                // Small delay to let window appear, then show key input
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(name: .init("showLicenseKeyInput"), object: nil)
                }
            }
        }
    }
}
