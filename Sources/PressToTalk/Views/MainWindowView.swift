import SwiftUI
import AVFoundation

struct MainWindowView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings = SettingsManager.shared
    @State private var selectedTab = 0
    @Namespace private var tabIndicator

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selectedTab: $selectedTab, namespace: tabIndicator) { switchTab(to: $0) }

            // Content: only the active tab exists, so hidden tabs never
            // observe state or re-render (unlike TabView which keeps all alive)
            ZStack {
                Theme.contentBackground.ignoresSafeArea()

                switch selectedTab {
                case 0:
                    HomeTab(appState: appState, settings: settings)
                        .transition(tabTransition)
                case 1:
                    HistoryTab(history: HistoryManager.shared)
                        .transition(tabTransition)
                case 2:
                    DictionaryTab()
                        .transition(tabTransition)
                default:
                    SettingsTab(appState: appState, settings: settings)
                        .transition(tabTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // System controls (pickers, fields, toggles) must render light here
            .environment(\.colorScheme, .light)
        }
        .frame(minWidth: 880, minHeight: 600)
        .onAppear {
            Task { await PermissionsManager.shared.checkAllPermissions() }
            settings.refreshMicrophones()
            appState.updateUsageInfo()
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            // Poll only while the window is actually on screen — the hosting
            // view stays alive when the window is hidden via the close button.
            guard MainWindowController.shared.isWindowVisible else { return }

            // Check accessibility permission
            let trusted = AXIsProcessTrusted()
            if trusted != appState.hasAccessibilityPermission {
                appState.hasAccessibilityPermission = trusted
            }

            // Check microphone permission
            let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            let hasMic = (micStatus == .authorized)
            if hasMic != appState.hasMicrophonePermission {
                appState.hasMicrophonePermission = hasMic
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("switchToSettings"))) { _ in
            switchTab(to: 3)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("switchToDictionary"))) { _ in
            switchTab(to: 2)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("switchToHistory"))) { _ in
            switchTab(to: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("showLicenseKeyInput"))) { _ in
            switchTab(to: 0)  // Switch to Home tab where LicenseCard is
        }
    }

    private var tabTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.98))
    }

    private func switchTab(to tab: Int) {
        guard tab != selectedTab else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            selectedTab = tab
        }
    }
}

// MARK: - Home Tab

struct HomeTab: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: SettingsManager
    @ObservedObject var license = LicenseManager.shared
    @ObservedObject var localService = LocalTranscriptionService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Hero section
                HeroSection(appState: appState)

                // Model setup banner
                if settings.offlineModeEnabled && !localService.hasAnyModel {
                    ModelSetupBanner()
                }

                // License / Pro status
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Plan", icon: "crown.fill")
                    LicenseCard(license: license)
                }

                // Quick setup
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Setup", icon: "checkmark.shield.fill")

                    VStack(spacing: 10) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            PermissionCard(
                                icon: "mic.fill",
                                title: "Microphone",
                                isGranted: appState.hasMicrophonePermission,
                                color: Theme.accentPink
                            ) {
                                Task { await PermissionsManager.shared.requestMicrophone() }
                            }

                            PermissionCard(
                                icon: "hand.tap.fill",
                                title: "Accessibility",
                                isGranted: appState.hasAccessibilityPermission,
                                color: Theme.accentPurple
                            ) {
                                PermissionsManager.shared.openAccessibilitySettings()
                            }
                        }
                    }
                }

                // Weekly Stats
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "This Week", icon: "chart.bar.fill")
                    WeeklyStatsCard()
                }

                // How to use
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "How to use", icon: "questionmark.circle.fill")
                    HowToUseCard(
                        primaryHotkey: settings.selectedHotkey.displayName,
                        secondaryHotkey: settings.secondaryHotkey.displayName
                    )
                }

                // Test input
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Test Input", icon: "text.cursor")
                    TestInputCard()
                }

                Spacer(minLength: 20)
            }
            .padding(32)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - History Tab

struct HistoryTab: View {
    @ObservedObject var history: HistoryManager

    var body: some View {
        VStack(spacing: 0) {
            if history.items.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundColor(Theme.textQuaternary)
                    Text("No transcriptions yet")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                    Text("Your transcriptions will appear here")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("\(history.items.count) items")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textTertiary)
                    Spacer()
                    Button("Clear All") {
                        history.clear()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.accentRed.opacity(0.7))
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 32)
                .padding(.top, 44)
                .padding(.bottom, 12)
                .frame(maxWidth: 760)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(history.items) { item in
                            HistoryItemRow(item: item)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct HistoryItemRow: View {
    let item: HistoryItem
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(3)
                Text(item.formattedDate)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }

            Spacer()

            if isHovering {
                Button(action: { copyToClipboard(item.text) }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isHovering ? 0.08 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )
        )
        .onHover { isHovering = $0 }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - License Card

struct LicenseCard: View {
    @ObservedObject var license: LicenseManager
    @State private var licenseKey = ""
    @State private var showKeyInput = false
    @State private var showError = false
    @FocusState private var isKeyFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            licenseHeader

            if !license.isPro && showKeyInput {
                keyInputSection
            }

            if !license.isPro && !showKeyInput {
                limitsSection
            }
        }
        .background(cardBackground)
        .onReceive(NotificationCenter.default.publisher(for: .init("showLicenseKeyInput"))) { _ in
            showKeyInput = true
        }
    }

    private var licenseHeader: some View {
        HStack {
            HStack(spacing: 12) {
                licenseIcon
                licenseInfo
            }
            Spacer()
            licenseButton
        }
        .padding(14)
    }

    private var licenseIcon: some View {
        ZStack {
            Circle()
                .fill(license.isPro ? Theme.accentYellow.opacity(0.2) : Color.gray.opacity(0.2))
                .frame(width: 36, height: 36)
            Image(systemName: license.isPro ? "crown.fill" : "person.fill")
                .font(.system(size: 16))
                .foregroundColor(license.isPro ? Theme.accentYellow : .gray)
        }
    }

    private var licenseInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(license.isPro ? "Pro" : "Free")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                if license.isPro {
                    Text("ACTIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accentYellow)
                        .cornerRadius(4)
                }
            }
            if license.isPro {
                Text("All features unlocked")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.accentGreen)
            } else {
                Text("\(license.dailyTranscriptionsUsed)/\(LicenseManager.freeTranscriptionsPerDay) used today")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var licenseButton: some View {
        if license.isPro {
            Button(action: { license.deactivateLicense() }) {
                Text("Deactivate")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.accentRed.opacity(0.7))
            }
            .buttonStyle(.plain)
        } else {
            Button(action: { showKeyInput.toggle() }) {
                Text(showKeyInput ? "Cancel" : "Activate Pro")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.accentYellow)
            }
            .buttonStyle(.plain)
        }
    }

    private var keyInputSection: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Theme.cardBorder)

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    keyTextField
                    activateButton
                }

                if showError {
                    Text("Invalid license key")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.accentRed)
                }
            }
            .padding(14)
            .padding(.top, -4)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isKeyFieldFocused = true
                }
            }
        }
    }

    private var keyTextField: some View {
        LicenseKeyTextField(text: $licenseKey, onSubmit: activateKey)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.card)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.subtleFillStrong, lineWidth: 1)
            )
    }

    private var textFieldBorderColor: Color {
        if showError {
            return Theme.accentRed.opacity(0.5)
        } else if isKeyFieldFocused {
            return Theme.accentYellow.opacity(0.5)
        } else {
            return Theme.subtleFillStrong
        }
    }

    private var activateButton: some View {
        Button(action: activateKey) {
            Text("Activate")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.accentYellow)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(licenseKey.isEmpty)
    }

    private var limitsSection: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Theme.cardBorder)

            VStack(spacing: 10) {
                // Daily usage progress
                VStack(spacing: 6) {
                    HStack {
                        Text("Today's usage")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                        Spacer()
                        Text("\(license.dailyTranscriptionsUsed)/\(LicenseManager.freeTranscriptionsPerDay)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(license.dailyTranscriptionsUsed >= LicenseManager.freeTranscriptionsPerDay ? Theme.accentRed : Theme.textSecondary)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.subtleFillStrong)
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(dailyUsageColor)
                                .frame(width: geometry.size.width * dailyUsageProgress, height: 6)
                        }
                    }
                    .frame(height: 6)
                }

                HStack(spacing: 12) {
                    LimitBadge(icon: "timer", text: "60s max")
                    LimitBadge(icon: "globe", text: "No translate")
                }

                // Show purchase button when limit reached or close to it
                if license.dailyTranscriptionsUsed >= LicenseManager.freeTranscriptionsPerDay - 5 {
                    Button(action: {
                        NSWorkspace.shared.open(LicenseManager.purchaseURL)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "cart.fill")
                                .font(.system(size: 11))
                            Text(license.dailyTranscriptionsUsed >= LicenseManager.freeTranscriptionsPerDay ? "Upgrade to continue" : "Upgrade to Pro")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Theme.accentPurple)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }

    private var dailyUsageProgress: CGFloat {
        CGFloat(license.dailyTranscriptionsUsed) / CGFloat(LicenseManager.freeTranscriptionsPerDay)
    }

    private var dailyUsageColor: Color {
        if dailyUsageProgress >= 1.0 {
            return Theme.accentRed
        } else if dailyUsageProgress >= 0.8 {
            return Theme.accentOrange
        }
        return Theme.accentGreen
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(license.isPro ? Theme.accentYellow.opacity(0.3) : Theme.cardBorder, lineWidth: 1)
            )
    }

    private func activateKey() {
        if license.activateLicense(key: licenseKey) {
            showKeyInput = false
            licenseKey = ""
            showError = false
        } else {
            showError = true
        }
    }
}

// MARK: - License Key TextField (NSViewRepresentable)

struct LicenseKeyTextField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = "Enter license key"
        textField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textField.textColor = .white
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        textField.isBordered = false
        textField.focusRingType = .none
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LicenseKeyTextField

        init(_ parent: LicenseKeyTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

struct LimitBadge: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11))
        }
        .foregroundColor(Theme.textTertiary)
    }
}

// MARK: - Transcription Mode Enum

enum TranscriptionMode: String, CaseIterable {
    case offline = "offline"
    case cloud = "cloud"

    var displayName: String {
        switch self {
        case .offline: return "Offline"
        case .cloud: return "Cloud"
        }
    }

    var icon: String {
        switch self {
        case .offline: return "bolt.fill"
        case .cloud: return "cloud.fill"
        }
    }

    var description: String {
        switch self {
        case .offline: return "Local transcription, no internet needed"
        case .cloud: return "OpenAI Whisper API, requires API key"
        }
    }
}

// MARK: - Settings Tab

struct SettingsTab: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: SettingsManager
    @StateObject private var localTranscription = LocalTranscriptionService.shared

    private var transcriptionMode: TranscriptionMode {
        settings.offlineModeEnabled ? .offline : .cloud
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Transcription Mode
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Transcription Mode", icon: "waveform.circle.fill")

                    TranscriptionModeSelector(
                        settings: settings,
                        localTranscription: localTranscription,
                        appState: appState
                    )
                }

                // Language
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Transcription", icon: "text.bubble.fill")

                    SettingsCard {
                        VStack(spacing: 0) {
                            SettingRow(icon: "globe", title: "Language", color: Theme.accentBlue) {
                                Picker("", selection: $settings.selectedLanguage) {
                                    ForEach(WhisperLanguage.allCases) { lang in
                                        Text(lang.displayName).tag(lang)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 140)
                            }
                        }
                    }
                }

                // Audio
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Audio", icon: "waveform")

                    SettingsCard {
                        VStack(spacing: 0) {
                            SettingRow(icon: "mic.fill", title: "Microphone", color: Theme.accentPink) {
                                Picker("", selection: $settings.selectedMicrophoneID) {
                                    ForEach(settings.availableMicrophones) { device in
                                        Text(device.name).tag(Optional(device.id))
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 180)
                            }

                            Divider()
                                .background(Theme.cardBorder)
                                .padding(.leading, 58)

                            MicrophoneTestRow()

                            Divider()
                                .background(Theme.cardBorder)
                                .padding(.leading, 58)

                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Theme.accentGreen.opacity(0.16))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "doc.on.clipboard")
                                        .font(.system(size: 14))
                                        .foregroundColor(Theme.accentGreen)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Always copy to clipboard")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(Theme.textPrimary)
                                    Text("Off: your clipboard is left alone, and TalkKey copies only when there is no text field to type into")
                                        .font(.system(size: 11))
                                        .foregroundColor(Theme.textTertiary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer()

                                Toggle("", isOn: $settings.alwaysCopyToClipboard)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                            }
                            .padding(14)
                        }
                    }
                }

                // Hotkeys
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Hotkeys", icon: "keyboard.fill")

                    SettingsCard {
                        VStack(spacing: 0) {
                            SettingRow(icon: "bolt.fill", title: "Direct Paste", color: Theme.accentGreen) {
                                Picker("", selection: $settings.selectedHotkey) {
                                    ForEach(HotkeyOption.allCases) { option in
                                        Text(option.displayName).tag(option)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 120)
                            }

                            Divider()
                                .background(Theme.cardBorder)
                                .padding(.leading, 58)

                            // Review Mode (Pro only)
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Theme.accentPurple.opacity(0.2))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "wand.and.stars")
                                        .font(.system(size: 14))
                                        .foregroundColor(Theme.accentPurple)
                                }

                                Text("Review Mode")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Theme.textPrimary)

                                if !LicenseManager.shared.isPro {
                                    Text("PRO")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Theme.accentYellow)
                                        .cornerRadius(3)
                                }

                                Spacer()

                                Picker("", selection: $settings.secondaryHotkey) {
                                    ForEach(HotkeyOption.allCases) { option in
                                        Text(option.displayName).tag(option)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 120)
                                .disabled(!LicenseManager.shared.isPro)
                                .opacity(LicenseManager.shared.isPro ? 1 : 0.5)
                            }
                            .padding(14)

                            Divider()
                                .background(Theme.cardBorder)
                                .padding(.leading, 58)

                            // Translation row (Pro only)
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Theme.accentBlue.opacity(0.2))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "globe")
                                        .font(.system(size: 14))
                                        .foregroundColor(Theme.accentBlue)
                                }

                                Text("Translate")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Theme.textPrimary)

                                Text("Fn")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Theme.accentBlue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Theme.accentBlue.opacity(0.2))
                                    .cornerRadius(4)

                                if !LicenseManager.shared.isPro {
                                    Text("PRO")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Theme.accentYellow)
                                        .cornerRadius(3)
                                }

                                Spacer()

                                Picker("", selection: $settings.targetLanguage) {
                                    ForEach(TranslationLanguage.allCases) { lang in
                                        Text("\(lang.flag) \(lang.displayName)")
                                            .tag(lang)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 150)
                                .disabled(!LicenseManager.shared.isPro)
                                .opacity(LicenseManager.shared.isPro ? 1 : 0.5)
                            }
                            .padding(14)
                        }
                    }

                    // Hotkey descriptions
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Theme.accentGreen)
                                .frame(width: 6, height: 6)
                            Text("Direct Paste: Transcribes and pastes immediately")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textSecondary)
                        }
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Theme.accentPurple)
                                .frame(width: 6, height: 6)
                            Text("Review Mode: Opens window to edit and restyle text")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textSecondary)
                        }
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Theme.accentBlue)
                                .frame(width: 6, height: 6)
                            Text("Translate: Transcribes and translates to selected language")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 4)
                }

                // Upgrade to Pro (only for free users)
                if !LicenseManager.shared.isPro {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Upgrade", icon: "crown.fill")

                        SettingsCard {
                            VStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Theme.accentYellow.opacity(0.2))
                                            .frame(width: 36, height: 36)
                                        Image(systemName: "crown.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(Theme.accentYellow)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Unlock Pro Features")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(Theme.textPrimary)
                                        Text("Cloud mode, translation, review & more")
                                            .font(.system(size: 11))
                                            .foregroundColor(Theme.textSecondary)
                                    }

                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.top, 14)

                                Button(action: {
                                    NSWorkspace.shared.open(LicenseManager.purchaseURL)
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "cart.fill")
                                            .font(.system(size: 13))
                                        Text("Buy License — $15")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        LinearGradient(
                                            colors: [Theme.accentPurple, Theme.accentPurple.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 14)
                            }
                        }
                    }
                }

                // About
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "About", icon: "info.circle.fill")

                    SettingsCard {
                        VStack(spacing: 0) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("TalkKey")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Theme.textPrimary)
                                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                                        .font(.system(size: 12))
                                        .foregroundColor(Theme.textSecondary)
                                }
                                Spacer()
                                Link(destination: URL(string: "https://github.com/manikosto/talkkey")!) {
                                    Image(systemName: "arrow.up.right.square")
                                        .foregroundColor(Theme.textTertiary)
                                }
                            }
                            .padding(14)

                            Divider()
                                .background(Theme.subtleFillStrong)

                            Button(action: {
                                NotificationCenter.default.post(name: .init("checkForUpdates"), object: nil)
                            }) {
                                HStack {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .foregroundColor(Theme.accentCyan)
                                    Text("Check for Updates")
                                        .font(.system(size: 13))
                                        .foregroundColor(Theme.textPrimary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(14)
                        }
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(32)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }
}

struct SettingsCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Theme.cardBorder, lineWidth: 1)
                    )
            )
    }
}

struct SettingRow<Content: View>: View {
    let icon: String
    let title: String
    let color: Color
    let content: Content

    init(icon: String, title: String, color: Color, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.color = color
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
            }

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textPrimary)

            Spacer()

            content
        }
        .padding(14)
    }
}

// MARK: - Hero Section

struct HeroSection: View {
    @ObservedObject var appState: AppState
    @ObservedObject var license = LicenseManager.shared
    @ObservedObject var localService = LocalTranscriptionService.shared

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                // Breathing glow: frame-driven only while recording, static otherwise
                if appState.isRecording {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        let pulse = 0.5 + 0.5 * sin(t * (2 * .pi / 1.8))
                        glowCircle
                            .scaleEffect(1.0 + 0.12 * pulse)
                            .opacity(0.75 + 0.25 * pulse)
                    }
                } else {
                    glowCircle
                }

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white, statusColor.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .overlay(Circle().stroke(statusColor.opacity(0.45), lineWidth: 2))
                    .shadow(color: statusColor.opacity(0.22), radius: 18, y: 6)
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)

                if isModelLoading {
                    Spinner(size: 34, color: statusColor, lineWidth: 3)
                } else {
                    Image(systemName: statusIcon)
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(colors: [statusColor, statusColor.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                        )
                        .scaleEffect(appState.isRecording ? 1.08 : 1.0)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appState.isRecording)
            .animation(.easeInOut(duration: 0.35), value: statusText)

            VStack(spacing: 6) {
                Text(statusText)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                Text(statusSubtext)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
            }
            .animation(.easeInOut(duration: 0.25), value: statusText)
        }
        .padding(.vertical, 16)
    }

    private var glowCircle: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [statusColor.opacity(0.4), statusColor.opacity(0)],
                    center: .center,
                    startRadius: 30,
                    endRadius: 80
                )
            )
            .frame(width: 160, height: 160)
            .blur(radius: 20)
    }

    private var isModelLoading: Bool {
        SettingsManager.shared.offlineModeEnabled && (localService.isModelLoading || localService.isDownloading) && !localService.isModelLoaded
    }

    private var statusIcon: String {
        if needsModel { return "arrow.down.circle" }
        if appState.isRecording { return "waveform" }
        if appState.isTranscribing { return "text.bubble.fill" }
        if !appState.hasMicrophonePermission { return "mic.slash.fill" }
        return "mic.fill"
    }

    private var needsModel: Bool {
        SettingsManager.shared.offlineModeEnabled && !localService.hasAnyModel
    }

    private var statusText: String {
        if needsModel { return "Model Required" }
        if isModelLoading { return "Preparing AI..." }
        if appState.isRecording { return "Recording..." }
        if appState.isTranscribing { return "Transcribing..." }
        if !appState.hasMicrophonePermission { return "Microphone Required" }
        return "Ready"
    }

    private var statusSubtext: String {
        if needsModel { return "Download a speech model in Settings" }
        if isModelLoading { return "Loading speech recognition model" }
        if appState.isRecording { return "Release to transcribe" }
        if appState.isTranscribing { return "Processing audio..." }
        if !appState.hasMicrophonePermission { return "Grant microphone access to continue" }
        return "Hold the hotkey to start"
    }

    private var statusColor: Color {
        if needsModel { return Theme.accentOrange }
        if isModelLoading { return Theme.accentCyan }
        if appState.isRecording { return Theme.accentRed }
        if appState.isTranscribing { return Theme.accentBlue }
        if !appState.hasMicrophonePermission { return Theme.accentOrange }
        return Theme.accentGreen
    }
}

// MARK: - Supporting Views

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
                .textCase(.uppercase)
                .tracking(1)
        }
    }
}


struct WeeklyStatsCard: View {
    @ObservedObject private var tracker = UsageTracker.shared

    var body: some View {
        HStack(spacing: 0) {
            StatItem(
                value: "\(tracker.averageWPM)",
                label: "WPM",
                sublabel: "Average speed"
            )

            Divider()
                .frame(height: 40)
                .background(Theme.subtleFillStrong)

            StatItem(
                value: "\(tracker.weeklyWords)",
                label: "Words",
                sublabel: "This week"
            )

            Divider()
                .frame(height: 40)
                .background(Theme.subtleFillStrong)

            StatItem(
                value: "\(tracker.totalTranscriptions)",
                label: "Total",
                sublabel: "Transcriptions"
            )

            Divider()
                .frame(height: 40)
                .background(Theme.subtleFillStrong)

            StatItem(
                value: "\(tracker.weeklyMinutesSaved)",
                label: "min",
                sublabel: "Saved this week"
            )
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))
        )
    }
}

struct StatItem: View {
    let value: String
    let label: String
    let sublabel: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
            }
            Text(sublabel)
                .font(.system(size: 10))
                .foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PermissionCard: View {
    let icon: String
    let title: String
    let isGranted: Bool
    let color: Color
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: { if !isGranted { action() } }) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isGranted ? Theme.accentGreen.opacity(0.2) : color.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: isGranted ? "checkmark" : icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isGranted ? Theme.accentGreen : color)
                }

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 8)

                if !isGranted {
                    Text("Grant")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.subtleFillStrong)
                        .cornerRadius(5)
                        .fixedSize()
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(isHovering && !isGranted ? 0.08 : 0.05))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .disabled(isGranted)
    }
}

struct HowToUseCard: View {
    let primaryHotkey: String
    let secondaryHotkey: String

    var body: some View {
        VStack(spacing: 0) {
            // Direct paste mode
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Theme.accentGreen.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.accentGreen)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Direct Paste")
                            .foregroundColor(Theme.textPrimary)
                            .font(.system(size: 13, weight: .medium))
                        Text(primaryHotkey)
                            .foregroundColor(Theme.accentGreen)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Theme.accentGreen.opacity(0.2))
                            .cornerRadius(4)
                    }
                    Text("Hold to record, release to paste text instantly")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }

                Spacer()
            }
            .padding(14)

            Divider()
                .background(Theme.cardBorder)
                .padding(.leading, 56)

            // Review mode
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Theme.accentPurple.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.accentPurple)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Review Mode")
                            .foregroundColor(Theme.textPrimary)
                            .font(.system(size: 13, weight: .medium))
                        Text(secondaryHotkey)
                            .foregroundColor(Theme.accentPurple)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Theme.accentPurple.opacity(0.2))
                            .cornerRadius(4)
                    }
                    Text("Hold to record, release to edit and restyle text")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }

                Spacer()
            }
            .padding(14)

            Divider()
                .background(Theme.cardBorder)
                .padding(.leading, 56)

            // Translation mode
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Theme.accentBlue.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: "globe")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.accentBlue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Translate")
                            .foregroundColor(Theme.textPrimary)
                            .font(.system(size: 13, weight: .medium))
                        Text("Fn")
                            .foregroundColor(Theme.accentBlue)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Theme.accentBlue.opacity(0.2))
                            .cornerRadius(4)
                    }
                    Text("Hold Fn to record and translate")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }

                Spacer()
            }
            .padding(14)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))
        )
    }
}

// MARK: - Transcription Mode Selector

struct TranscriptionModeSelector: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var localTranscription: LocalTranscriptionService
    @ObservedObject var appState: AppState
    @ObservedObject var license = LicenseManager.shared
    @State private var apiKey: String = ""
    @State private var isSavingKey = false
    @State private var showKeyField = false
    @State private var showProRequired = false
    @State private var showAPIKeyRequired = false

    private var transcriptionMode: TranscriptionMode {
        settings.offlineModeEnabled ? .offline : .cloud
    }

    var body: some View {
        VStack(spacing: 12) {
            // Mode selector
            SettingsCard {
                VStack(spacing: 0) {
                    // Mode picker
                    HStack(spacing: 0) {
                        ForEach(TranscriptionMode.allCases, id: \.self) { mode in
                            Button(action: {
                                // Cloud mode requires Pro
                                if mode == .cloud && !license.canUseCloudMode {
                                    showProRequired = true
                                    return
                                }
                                // Cloud mode requires API key
                                if mode == .cloud && !appState.hasAPIKey {
                                    showAPIKeyRequired = true
                                    showKeyField = true
                                }
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    settings.offlineModeEnabled = (mode == .offline)
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: mode.icon)
                                        .font(.system(size: 14))
                                    Text(mode.displayName)
                                        .font(.system(size: 13, weight: .medium))
                                    // Show PRO badge for Cloud if not Pro user
                                    if mode == .cloud && !license.isPro {
                                        Text("PRO")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Theme.accentYellow)
                                            .cornerRadius(3)
                                    }
                                }
                                .foregroundColor(transcriptionMode == mode ? .white : Theme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(transcriptionMode == mode ? Theme.subtleFillStrong : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.card)
                    )
                    .padding(10)

                    Divider()
                        .background(Theme.cardBorder)

                    // Mode description
                    HStack {
                        Image(systemName: transcriptionMode.icon)
                            .font(.system(size: 12))
                            .foregroundColor(transcriptionMode == .offline ? Theme.accentOrange : Theme.accentBlue)
                        Text(transcriptionMode.description)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                        Spacer()
                    }
                    .padding(12)
                }
            }

            // Mode-specific content
            if transcriptionMode == .offline {
                ModelLibraryCard(localTranscription: localTranscription)
                ModePerModelCard(settings: settings, localTranscription: localTranscription)
            } else {
                // Cloud mode: API Key
                SettingsCard {
                    VStack(spacing: 0) {
                        HStack {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Theme.accentBlue.opacity(0.2))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: appState.hasAPIKey ? "checkmark" : "key.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(Theme.accentBlue)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("OpenAI API Key")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(Theme.textPrimary)
                                    if appState.hasAPIKey {
                                        Text("Key saved securely")
                                            .font(.system(size: 11))
                                            .foregroundColor(Theme.accentGreen)
                                    } else {
                                        Text("Required for cloud transcription")
                                            .font(.system(size: 11))
                                            .foregroundColor(Theme.textSecondary)
                                    }
                                }
                            }

                            Spacer()

                            if appState.hasAPIKey {
                                Button(action: { showKeyField.toggle() }) {
                                    Text(showKeyField ? "Hide" : "Change")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Theme.accentBlue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(14)

                        if !appState.hasAPIKey || showKeyField {
                            Divider()
                                .background(Theme.cardBorder)

                            VStack(spacing: 12) {
                                SecureField("sk-...", text: $apiKey)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(Theme.textPrimary)
                                    .padding(10)
                                    .background(Theme.card)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Theme.subtleFillStrong, lineWidth: 1)
                                    )

                                HStack {
                                    Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.up.right.square")
                                            Text("Get API Key")
                                        }
                                        .font(.system(size: 11))
                                        .foregroundColor(Theme.accentBlue.opacity(0.8))
                                    }

                                    Spacer()

                                    Button(action: saveAPIKey) {
                                        HStack(spacing: 6) {
                                            if isSavingKey {
                                                Spinner(size: 15, color: .white)
                                            } else {
                                                Image(systemName: "checkmark.circle.fill")
                                            }
                                            Text("Save Key")
                                        }
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Theme.accentBlue)
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(apiKey.isEmpty || isSavingKey)
                                    .opacity(apiKey.isEmpty ? 0.5 : 1)
                                }
                            }
                            .padding(14)
                        }
                    }
                }

                // Info about cloud mode
                if appState.hasAPIKey {
                    HStack {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.accentBlue.opacity(0.6))
                        Text("Uses OpenAI Whisper API for transcription")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .alert("API Key Required", isPresented: $showAPIKeyRequired) {
            Button("OK") { }
        } message: {
            Text("Please add your OpenAI API key to use Cloud mode. Enter your key in the field below.")
        }
    }

    private func saveAPIKey() {
        guard !apiKey.isEmpty else { return }
        isSavingKey = true

        Task {
            _ = KeychainService.shared.saveAPIKey(apiKey)
            await MainActor.run {
                appState.hasAPIKey = true
                appState.hasCustomKey = true
                apiKey = ""
                showKeyField = false
                isSavingKey = false
            }
        }
    }
}

// MARK: - Model Setup Banner

struct ModelSetupBanner: View {
    @ObservedObject var localService = LocalTranscriptionService.shared
    @State private var selectedModel = "small"
    @State private var isDownloading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.accentOrange.opacity(0.2))
                        .frame(width: 40, height: 40)
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Theme.accentOrange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Speech Model Required")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Text("Choose and download a model to start transcribing")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
            }

            // Model picker
            VStack(spacing: 10) {
                ForEach(localService.availableModels, id: \.self) { model in
                    Button(action: { selectedModel = model }) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(selectedModel == model ? Theme.accentOrange : Theme.subtleFillStrong)
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle()
                                        .fill(Theme.card)
                                        .frame(width: 8, height: 8)
                                        .opacity(selectedModel == model ? 1 : 0)
                                )

                            VStack(alignment: .leading, spacing: 1) {
                                Text(localService.modelDisplayName[model] ?? model)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Theme.textPrimary)
                                Text(localService.modelQualityDescription[model] ?? "")
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.textTertiary)
                            }

                            Spacer()

                            Text(localService.modelSizeDescription[model] ?? "")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Theme.textTertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedModel == model ? Theme.accentOrange.opacity(0.1) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if let error = error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.accentRed)
            }

            Button(action: downloadModel) {
                HStack(spacing: 8) {
                    if isDownloading {
                        Spinner(size: 16, color: .white)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 14))
                    }
                    Text(isDownloading ? "Downloading..." : "Download \(localService.modelDisplayName[selectedModel] ?? selectedModel)")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isDownloading ? Color.gray : Theme.accentOrange)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(isDownloading)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.accentOrange.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.accentOrange.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func downloadModel() {
        isDownloading = true
        error = nil
        Task {
            do {
                try await localService.loadModel(selectedModel)
                AppState.shared.needsModelSetup = false
            } catch {
                self.error = error.localizedDescription
            }
            isDownloading = false
        }
    }
}

// MARK: - Test Input Card

struct TestInputCard: View {
    @State private var testText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                TextEditor(text: $testText)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(height: 80)
                    .padding(10)
                    .background(Theme.card)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isFocused ? Theme.accentPurple.opacity(0.5) : Theme.subtleFillStrong, lineWidth: 1)
                    )
            }

            HStack(spacing: 10) {
                Text("Click here, then hold the hotkey to transcribe")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)

                Spacer()

                Button(action: { testText = "" }) {
                    Text("Clear")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.subtleFillStrong)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(testText.isEmpty)
                .opacity(testText.isEmpty ? 0.5 : 1)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))
        )
    }
}

// MARK: - Microphone Test Row

struct MicrophoneTestRow: View {
    @StateObject private var testService = MicrophoneTestService.shared

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(testService.isTesting ? Theme.accentGreen.opacity(0.2) : Theme.accentCyan.opacity(0.2))
                    .frame(width: 32, height: 32)
                Image(systemName: testService.isTesting ? "waveform" : "mic.badge.plus")
                    .font(.system(size: 14))
                    .foregroundColor(testService.isTesting ? Theme.accentGreen : Theme.accentCyan)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Test Microphone")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textPrimary)

                Text(testService.isTesting ? "Listening... Speak to see levels" : "Check if microphone is working")
                    .font(.system(size: 11))
                    .foregroundColor(testService.isTesting ? Theme.accentGreen : Theme.textSecondary)
            }

            Spacer()

            if testService.isTesting {
                // Level meter
                HStack(spacing: 2) {
                    ForEach(0..<10, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(CGFloat(i) / 10.0 < testService.audioLevel ? (i < 7 ? Theme.accentGreen : Theme.accentOrange) : Theme.subtleFillStrong)
                            .frame(width: 4, height: 18)
                    }
                }
                .padding(.trailing, 8)
            }

            Button(action: { testService.toggleTest() }) {
                Text(testService.isTesting ? "Stop" : "Test")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(testService.isTesting ? Theme.accentRed : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(testService.isTesting ? Theme.accentRed.opacity(0.2) : Theme.accentCyan)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .onDisappear {
            testService.stopTest()
        }
    }
}

// MARK: - Window Controller

class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()
    private var window: NSWindow?

    var isWindowVisible: Bool {
        window?.isVisible ?? false
    }

    @MainActor
    func show() {
        if let window = window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = MainWindowView(appState: AppState.shared)
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.title = "TalkKey"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)
        window.delegate = self
        window.setFrameAutosaveName("TalkKeyMainWindow")
        if window.frame.width < 900 {
            window.setContentSize(NSSize(width: 1060, height: 700))
        }
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide window instead of closing when clicking red X
        sender.orderOut(nil)
        return false
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    @MainActor
    func hide() {
        window?.orderOut(nil)
    }
}
