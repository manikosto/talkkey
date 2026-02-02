import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var license = LicenseManager.shared
    @State private var apiKey: String = ""
    @State private var showingKey: Bool = false
    @State private var saveSuccess: Bool = false
    @State private var licenseKey: String = ""

    var body: some View {
        Form {
            // License Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("License")
                            .font(.headline)
                        Spacer()
                        if license.isPro {
                            HStack(spacing: 4) {
                                Image(systemName: "crown.fill")
                                    .foregroundColor(.yellow)
                                Text("PRO")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.yellow.opacity(0.2))
                            .cornerRadius(6)
                        }
                    }

                    if license.isPro {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Text("All features unlocked")
                                .font(.system(size: 13))
                                .foregroundColor(.green)
                        }

                        Button("Deactivate License") {
                            license.deactivateLicense()
                        }
                        .foregroundColor(.red)
                        .font(.caption)
                    } else {
                        Text("Free: \(license.dailyTranscriptionsUsed)/\(LicenseManager.freeTranscriptionsPerDay) transcriptions today")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)

                        HStack {
                            TextField("Enter license key", text: $licenseKey)
                                .textFieldStyle(.roundedBorder)

                            Button("Activate") {
                                _ = license.activateLicense(key: licenseKey)
                            }
                            .buttonStyle(.bordered)
                            .disabled(licenseKey.isEmpty)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Upgrade to Pro")
                                .font(.system(size: 13, weight: .semibold))

                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.green)
                                    .font(.system(size: 11))
                                Text("Unlimited transcriptions")
                                    .font(.system(size: 12))
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.green)
                                    .font(.system(size: 11))
                                Text("Cloud mode (OpenAI Whisper API)")
                                    .font(.system(size: 12))
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.green)
                                    .font(.system(size: 11))
                                Text("AI text formatting")
                                    .font(.system(size: 12))
                            }

                            Button(action: {
                                NSWorkspace.shared.open(LicenseManager.purchaseURL)
                            }) {
                                HStack {
                                    Image(systemName: "cart.fill")
                                    Text("Buy License — $15")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                        }
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("OpenAI API Key")
                        .font(.headline)

                    HStack {
                        if showingKey {
                            TextField("sk-...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("sk-...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(showingKey ? "Hide" : "Show") {
                            showingKey.toggle()
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack(spacing: 12) {
                        Button("Save") {
                            if KeychainService.shared.saveAPIKey(apiKey) {
                                appState.hasAPIKey = true
                                saveSuccess = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    saveSuccess = false
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKey.isEmpty)

                        if appState.hasAPIKey {
                            Button("Delete", role: .destructive) {
                                KeychainService.shared.deleteAPIKey()
                                appState.hasAPIKey = false
                                apiKey = ""
                            }
                            .buttonStyle(.bordered)
                        }

                        if saveSuccess {
                            Text("Saved!")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                    }

                    Link("Get API Key from OpenAI",
                         destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.caption)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Permissions")
                        .font(.headline)

                    PermissionRow(
                        title: "Microphone",
                        description: "Required for voice recording",
                        isGranted: appState.hasMicrophonePermission
                    ) {
                        Task {
                            await PermissionsManager.shared.requestMicrophone()
                        }
                    }

                    PermissionRow(
                        title: "Accessibility",
                        description: "Required for auto-paste (Cmd+V)",
                        isGranted: appState.hasAccessibilityPermission
                    ) {
                        PermissionsManager.shared.openAccessibilitySettings()
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to Use")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 4) {
                        ShortcutRow(keys: "Right \u{2318}", description: "Hold to record, release to transcribe")
                        ShortcutRow(keys: "Esc", description: "Cancel recording")
                    }
                    .font(.system(size: 13))
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TalkKey v1.0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("A simple voice-to-text tool powered by OpenAI Whisper")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 480)
        .preferredColorScheme(.dark)
        .onAppear {
            if let existingKey = KeychainService.shared.getAPIKey() {
                apiKey = existingKey
            }
            Task {
                await PermissionsManager.shared.checkAllPermissions()
            }
        }
    }
}

struct PermissionRow: View {
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("Grant") {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ShortcutRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack {
            Text(keys)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)

            Text(description)
                .foregroundColor(.secondary)
        }
    }
}
