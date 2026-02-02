import AVFoundation
import AppKit

class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    func checkAllPermissions() async {
        await checkMicrophonePermission()
        await checkAccessibilityPermission()
        await checkAutomationPermission()
    }

    // MARK: - Microphone

    @MainActor
    func checkMicrophonePermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        AppState.shared.hasMicrophonePermission = (status == .authorized)
    }

    @MainActor
    func requestMicrophone() async {
        // Always try to request access - this will show popup if not determined,
        // or return immediately if already granted/denied
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        AppState.shared.hasMicrophonePermission = granted

        // If not granted, check why and open settings if needed
        if !granted {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            if status == .denied || status == .restricted {
                openMicrophoneSettings()
            }
        }
    }

    // MARK: - Accessibility

    @MainActor
    func checkAccessibilityPermission() async {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let trusted = AXIsProcessTrustedWithOptions(options)
        AppState.shared.hasAccessibilityPermission = trusted
    }

    func requestAccessibility() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Automation (for AppleScript)

    @MainActor
    func checkAutomationPermission() async {
        // Try running a simple AppleScript to check if we have permission
        let script = """
        tell application "System Events"
            return name of first process whose frontmost is true
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            AppState.shared.hasAutomationPermission = (error == nil)
        }
    }

    @MainActor
    func requestAutomationPermission() {
        // Running AppleScript targeting System Events will trigger the permission dialog
        let script = """
        tell application "System Events"
            keystroke ""
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)

            if error != nil {
                openAutomationSettings()
            } else {
                AppState.shared.hasAutomationPermission = true
            }
        }
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
