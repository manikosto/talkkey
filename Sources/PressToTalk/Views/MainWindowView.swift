import SwiftUI
import AVFoundation

struct MainWindowView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var history = HistoryManager.shared
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.12),
                    Color(red: 0.05, green: 0.05, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Tab bar
                HStack(spacing: 0) {
                    TabButton(title: "Home", icon: "house.fill", isSelected: selectedTab == 0) {
                        selectedTab = 0
                    }
                    TabButton(title: "History", icon: "clock.fill", isSelected: selectedTab == 1) {
                        selectedTab = 1
                    }
                    TabButton(title: "Settings", icon: "gearshape.fill", isSelected: selectedTab == 2) {
                        selectedTab = 2
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Content
                TabView(selection: $selectedTab) {
                    HomeTab(appState: appState, settings: settings)
                        .tag(0)
                    HistoryTab(history: history)
                        .tag(1)
                    SettingsTab(appState: appState, settings: settings)
                        .tag(2)
                }
                .tabViewStyle(.automatic)
            }
        }
        .frame(minWidth: 520, minHeight: 640)
        .preferredColorScheme(.dark)
        .onAppear {
            Task { await PermissionsManager.shared.checkAllPermissions() }
            settings.refreshMicrophones()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
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

            // Update usage info to refresh progress bar
            appState.updateUsageInfo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("switchToSettings"))) { _ in
            selectedTab = 2
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("showLicenseKeyInput"))) { _ in
            selectedTab = 0  // Switch to Home tab where LicenseCard is
        }
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Home Tab

struct HomeTab: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: SettingsManager
    @ObservedObject var license = LicenseManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Hero section
                HeroSection(appState: appState)

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
                                color: .pink
                            ) {
                                Task { await PermissionsManager.shared.requestMicrophone() }
                            }

                            PermissionCard(
                                icon: "hand.tap.fill",
                                title: "Accessibility",
                                isGranted: appState.hasAccessibilityPermission,
                                color: .purple
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
            .padding(24)
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
                        .foregroundColor(.white.opacity(0.2))
                    Text("No transcriptions yet")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                    Text("Your transcriptions will appear here")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("\(history.items.count) items")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                    Button("Clear All") {
                        history.clear()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red.opacity(0.7))
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(history.items) { item in
                            HistoryItemRow(item: item)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
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
                    .foregroundColor(.white)
                    .lineLimit(3)
                Text(item.formattedDate)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer()

            if isHovering {
                Button(action: { copyToClipboard(item.text) }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
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
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
                .fill(license.isPro ? Color.yellow.opacity(0.2) : Color.gray.opacity(0.2))
                .frame(width: 36, height: 36)
            Image(systemName: license.isPro ? "crown.fill" : "person.fill")
                .font(.system(size: 16))
                .foregroundColor(license.isPro ? .yellow : .gray)
        }
    }

    private var licenseInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(license.isPro ? "Pro" : "Free")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                if license.isPro {
                    Text("ACTIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow)
                        .cornerRadius(4)
                }
            }
            if license.isPro {
                Text("All features unlocked")
                    .font(.system(size: 11))
                    .foregroundColor(.green)
            } else {
                Text("\(license.dailyTranscriptionsUsed)/\(LicenseManager.freeTranscriptionsPerDay) used today")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private var licenseButton: some View {
        if license.isPro {
            Button(action: { license.deactivateLicense() }) {
                Text("Deactivate")
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        } else {
            Button(action: { showKeyInput.toggle() }) {
                Text(showKeyInput ? "Cancel" : "Activate Pro")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.yellow)
            }
            .buttonStyle(.plain)
        }
    }

    private var keyInputSection: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.08))

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    keyTextField
                    activateButton
                }

                if showError {
                    Text("Invalid license key")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
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
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }

    private var textFieldBorderColor: Color {
        if showError {
            return Color.red.opacity(0.5)
        } else if isKeyFieldFocused {
            return Color.yellow.opacity(0.5)
        } else {
            return Color.white.opacity(0.1)
        }
    }

    private var activateButton: some View {
        Button(action: activateKey) {
            Text("Activate")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.yellow)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(licenseKey.isEmpty)
    }

    private var limitsSection: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.08))

            VStack(spacing: 10) {
                // Daily usage progress
                VStack(spacing: 6) {
                    HStack {
                        Text("Today's usage")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text("\(license.dailyTranscriptionsUsed)/\(LicenseManager.freeTranscriptionsPerDay)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(license.dailyTranscriptionsUsed >= LicenseManager.freeTranscriptionsPerDay ? .red : .white.opacity(0.7))
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.1))
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
                        .background(Color.purple)
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
            return .red
        } else if dailyUsageProgress >= 0.8 {
            return .orange
        }
        return .green
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(license.isPro ? Color.yellow.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1)
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
        .foregroundColor(.white.opacity(0.4))
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
                            SettingRow(icon: "globe", title: "Language", color: .blue) {
                                Picker("", selection: $settings.selectedLanguage) {
                                    // Auto-detect only for Cloud mode (small model doesn't detect well)
                                    ForEach(WhisperLanguage.allCases.filter { lang in
                                        settings.offlineModeEnabled ? lang != .auto : true
                                    }) { lang in
                                        Text(lang.displayName).tag(lang)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 140)
                                .onChange(of: settings.offlineModeEnabled) { _, isOffline in
                                    // Switch from auto to English when going offline
                                    if isOffline && settings.selectedLanguage == .auto {
                                        settings.selectedLanguage = .english
                                    }
                                }
                            }

                            if settings.offlineModeEnabled {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 10))
                                    Text("Auto-detect available in Cloud mode")
                                        .font(.system(size: 11))
                                }
                                .foregroundColor(.white.opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 10)
                                .padding(.top, -4)
                            }

                        }
                    }
                }

                // Audio
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Audio", icon: "waveform")

                    SettingsCard {
                        VStack(spacing: 0) {
                            SettingRow(icon: "mic.fill", title: "Microphone", color: .pink) {
                                Picker("", selection: $settings.selectedMicrophoneID) {
                                    ForEach(settings.availableMicrophones) { device in
                                        Text(device.name).tag(Optional(device.id))
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 180)
                            }

                            Divider()
                                .background(Color.white.opacity(0.08))
                                .padding(.leading, 58)

                            MicrophoneTestRow()
                        }
                    }
                }

                // Hotkeys
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Hotkeys", icon: "keyboard.fill")

                    SettingsCard {
                        VStack(spacing: 0) {
                            SettingRow(icon: "bolt.fill", title: "Direct Paste", color: .green) {
                                Picker("", selection: $settings.selectedHotkey) {
                                    ForEach(HotkeyOption.allCases) { option in
                                        Text(option.displayName).tag(option)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 120)
                            }

                            Divider()
                                .background(Color.white.opacity(0.08))
                                .padding(.leading, 58)

                            // Review Mode (Pro only)
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.purple.opacity(0.2))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "wand.and.stars")
                                        .font(.system(size: 14))
                                        .foregroundColor(.purple)
                                }

                                Text("Review Mode")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)

                                if !LicenseManager.shared.isPro {
                                    Text("PRO")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.yellow)
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
                                .background(Color.white.opacity(0.08))
                                .padding(.leading, 58)

                            // Translation row (Pro only)
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue.opacity(0.2))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "globe")
                                        .font(.system(size: 14))
                                        .foregroundColor(.blue)
                                }

                                Text("Translate")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)

                                Text("Fn")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(4)

                                if !LicenseManager.shared.isPro {
                                    Text("PRO")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.yellow)
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
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text("Direct Paste: Transcribes and pastes immediately")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 6, height: 6)
                            Text("Review Mode: Opens window to edit and restyle text")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 6, height: 6)
                            Text("Translate: Transcribes and translates to selected language")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
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
                                            .fill(Color.yellow.opacity(0.2))
                                            .frame(width: 36, height: 36)
                                        Image(systemName: "crown.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(.yellow)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Unlock Pro Features")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.white)
                                        Text("Cloud mode, translation, review & more")
                                            .font(.system(size: 11))
                                            .foregroundColor(.white.opacity(0.5))
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
                                            colors: [Color.purple, Color.purple.opacity(0.8)],
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
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("TalkKey")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            Spacer()
                            Link(destination: URL(string: "https://github.com/manikosto/talkkey")!) {
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                        .padding(14)
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(24)
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
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
                .foregroundColor(.white)

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

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.15, green: 0.15, blue: 0.2), Color(red: 0.1, green: 0.1, blue: 0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .overlay(Circle().stroke(statusColor.opacity(0.5), lineWidth: 2))
                    .shadow(color: statusColor.opacity(0.3), radius: 20)

                if isModelLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: statusColor))
                        .scaleEffect(1.5)
                } else {
                    Image(systemName: statusIcon)
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(colors: [statusColor, statusColor.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                        )
                }
            }

            VStack(spacing: 6) {
                Text(statusText)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(statusSubtext)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.vertical, 16)
    }

    private var isModelLoading: Bool {
        SettingsManager.shared.offlineModeEnabled && localService.isModelLoading && !localService.isModelLoaded
    }

    private var statusIcon: String {
        if appState.isRecording { return "waveform" }
        if appState.isTranscribing { return "text.bubble.fill" }
        if !appState.hasMicrophonePermission { return "mic.slash.fill" }
        return "mic.fill"
    }

    private var statusText: String {
        if isModelLoading { return "Preparing AI..." }
        if appState.isRecording { return "Recording..." }
        if appState.isTranscribing { return "Transcribing..." }
        if !appState.hasMicrophonePermission { return "Microphone Required" }
        return "Ready"
    }

    private var statusSubtext: String {
        if isModelLoading { return "Loading speech recognition model" }
        if appState.isRecording { return "Release to transcribe" }
        if appState.isTranscribing { return "Processing audio..." }
        if !appState.hasMicrophonePermission { return "Grant microphone access to continue" }
        return "Hold the hotkey to start"
    }

    private var statusColor: Color {
        if isModelLoading { return .cyan }
        if appState.isRecording { return .red }
        if appState.isTranscribing { return .blue }
        if !appState.hasMicrophonePermission { return .orange }
        return .green
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
                .foregroundColor(.white.opacity(0.5))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
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
                .background(Color.white.opacity(0.1))

            StatItem(
                value: "\(tracker.weeklyWords)",
                label: "Words",
                sublabel: "This week"
            )

            Divider()
                .frame(height: 40)
                .background(Color.white.opacity(0.1))

            StatItem(
                value: "\(tracker.totalTranscriptions)",
                label: "Total",
                sublabel: "Transcriptions"
            )

            Divider()
                .frame(height: 40)
                .background(Color.white.opacity(0.1))

            StatItem(
                value: "\(tracker.weeklyMinutesSaved)",
                label: "min",
                sublabel: "Saved this week"
            )
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
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
                    .foregroundColor(.white)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            Text(sublabel)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
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
                        .fill(isGranted ? Color.green.opacity(0.2) : color.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: isGranted ? "checkmark" : icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isGranted ? .green : color)
                }

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 8)

                if !isGranted {
                    Text("Grant")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(5)
                        .fixedSize()
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(isHovering && !isGranted ? 0.08 : 0.05))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
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
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Direct Paste")
                            .foregroundColor(.white)
                            .font(.system(size: 13, weight: .medium))
                        Text(primaryHotkey)
                            .foregroundColor(.green)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(4)
                    }
                    Text("Hold to record, release to paste text instantly")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()
            }
            .padding(14)

            Divider()
                .background(Color.white.opacity(0.06))
                .padding(.leading, 56)

            // Review mode
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 14))
                        .foregroundColor(.purple)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Review Mode")
                            .foregroundColor(.white)
                            .font(.system(size: 13, weight: .medium))
                        Text(secondaryHotkey)
                            .foregroundColor(.purple)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .cornerRadius(4)
                    }
                    Text("Hold to record, release to edit and restyle text")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()
            }
            .padding(14)

            Divider()
                .background(Color.white.opacity(0.06))
                .padding(.leading, 56)

            // Translation mode
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: "globe")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Translate")
                            .foregroundColor(.white)
                            .font(.system(size: 13, weight: .medium))
                        Text("Fn")
                            .foregroundColor(.blue)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                    Text("Hold Fn to record and translate")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()
            }
            .padding(14)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
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
                                            .foregroundColor(.black)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.yellow)
                                            .cornerRadius(3)
                                    }
                                }
                                .foregroundColor(transcriptionMode == mode ? .white : .white.opacity(0.5))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(transcriptionMode == mode ? Color.white.opacity(0.15) : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.05))
                    )
                    .padding(10)

                    Divider()
                        .background(Color.white.opacity(0.08))

                    // Mode description
                    HStack {
                        Image(systemName: transcriptionMode.icon)
                            .font(.system(size: 12))
                            .foregroundColor(transcriptionMode == .offline ? .orange : .blue)
                        Text(transcriptionMode.description)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                    }
                    .padding(12)
                }
            }

            // Mode-specific content
            if transcriptionMode == .offline {
                // Offline mode: Model status and download
                SettingsCard {
                    VStack(spacing: 0) {
                        HStack {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.orange.opacity(0.2))
                                        .frame(width: 32, height: 32)
                                    if localTranscription.isModelLoading {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                                    } else {
                                        Image(systemName: localTranscription.isModelLoaded ? "checkmark" : (localTranscription.hasBundledModel ? "checkmark.circle" : "arrow.down.circle"))
                                            .font(.system(size: 14))
                                            .foregroundColor(localTranscription.isModelLoaded ? .green : .orange)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Whisper Model")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white)
                                    if localTranscription.isModelLoading {
                                        Text("Preparing model...")
                                            .font(.system(size: 11))
                                            .foregroundColor(.orange)
                                    } else if localTranscription.isModelLoaded {
                                        Text(localTranscription.modelDisplayName[localTranscription.selectedModel] ?? localTranscription.selectedModel)
                                            .font(.system(size: 11))
                                            .foregroundColor(.green)
                                    } else if localTranscription.hasBundledModel {
                                        Text("Bundled - tap to activate")
                                            .font(.system(size: 11))
                                            .foregroundColor(.orange)
                                    } else {
                                        Text("Not downloaded")
                                            .font(.system(size: 11))
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                }
                            }

                            Spacer()

                            if localTranscription.isModelLoading {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                                    Text("Loading...")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.orange)
                                }
                            } else if localTranscription.isModelLoaded {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                    Text("Ready")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .padding(14)
                    }
                }

                // Model selection (always visible)
                ModelSelectionCard(localTranscription: localTranscription)
            } else {
                // Cloud mode: API Key
                SettingsCard {
                    VStack(spacing: 0) {
                        HStack {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue.opacity(0.2))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: appState.hasAPIKey ? "checkmark" : "key.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.blue)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("OpenAI API Key")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white)
                                    if appState.hasAPIKey {
                                        Text("Key saved securely")
                                            .font(.system(size: 11))
                                            .foregroundColor(.green)
                                    } else {
                                        Text("Required for cloud transcription")
                                            .font(.system(size: 11))
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                }
                            }

                            Spacer()

                            if appState.hasAPIKey {
                                Button(action: { showKeyField.toggle() }) {
                                    Text(showKeyField ? "Hide" : "Change")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(14)

                        if !appState.hasAPIKey || showKeyField {
                            Divider()
                                .background(Color.white.opacity(0.08))

                            VStack(spacing: 12) {
                                SecureField("sk-...", text: $apiKey)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )

                                HStack {
                                    Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.up.right.square")
                                            Text("Get API Key")
                                        }
                                        .font(.system(size: 11))
                                        .foregroundColor(.blue.opacity(0.8))
                                    }

                                    Spacer()

                                    Button(action: saveAPIKey) {
                                        HStack(spacing: 6) {
                                            if isSavingKey {
                                                ProgressView()
                                                    .scaleEffect(0.7)
                                            } else {
                                                Image(systemName: "checkmark.circle.fill")
                                            }
                                            Text("Save Key")
                                        }
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Color.blue)
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
                            .foregroundColor(.blue.opacity(0.6))
                        Text("Uses OpenAI Whisper API for transcription")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
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

// MARK: - Model Selection Card

struct ModelSelectionCard: View {
    @ObservedObject var localTranscription: LocalTranscriptionService
    @State private var selectedModel: String
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showModelPicker = false

    init(localTranscription: LocalTranscriptionService) {
        self.localTranscription = localTranscription
        self._selectedModel = State(initialValue: localTranscription.selectedModel)
    }

    private var isBundledModel: Bool {
        selectedModel == LocalTranscriptionService.bundledModel
    }

    private var isCurrentModelLoaded: Bool {
        localTranscription.isModelLoaded && localTranscription.selectedModel == selectedModel
    }

    private var needsDownload: Bool {
        !isBundledModel && !localTranscription.isModelDownloaded(selectedModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with model picker
            HStack {
                Text("AI Model")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                Picker("", selection: $selectedModel) {
                    ForEach(localTranscription.availableModels, id: \.self) { model in
                        HStack {
                            Text(localTranscription.modelDisplayName[model] ?? model)
                            if let size = localTranscription.modelSizeDescription[model] {
                                Text("• \(size)")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tag(model)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()
                .background(Color.white.opacity(0.08))

            // Model info
            HStack(spacing: 8) {
                // Status icon
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.2))
                        .frame(width: 28, height: 28)

                    if isLoading || localTranscription.isModelLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                            .progressViewStyle(CircularProgressViewStyle(tint: statusColor))
                    } else {
                        Image(systemName: statusIcon)
                            .font(.system(size: 12))
                            .foregroundColor(statusColor)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(localTranscription.modelDisplayName[selectedModel] ?? selectedModel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundColor(statusColor.opacity(0.8))
                }

                Spacer()

                // Action button
                if !isCurrentModelLoaded && !localTranscription.isModelLoading && !isLoading {
                    Button(action: loadSelectedModel) {
                        HStack(spacing: 4) {
                            Image(systemName: needsDownload ? "arrow.down.circle.fill" : "bolt.fill")
                                .font(.system(size: 11))
                            Text(needsDownload ? "Download" : "Load")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(needsDownload ? Color.orange : Color.green)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)

            if let error = loadError {
                Divider()
                    .background(Color.white.opacity(0.08))
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .padding(10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(statusColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private var statusIcon: String {
        if isCurrentModelLoaded {
            return "checkmark.circle.fill"
        } else if isBundledModel || localTranscription.isModelDownloaded(selectedModel) {
            return "circle"
        } else {
            return "arrow.down.circle"
        }
    }

    private var statusColor: Color {
        if isCurrentModelLoaded {
            return .green
        } else if isBundledModel || localTranscription.isModelDownloaded(selectedModel) {
            return .blue
        } else {
            return .orange
        }
    }

    private var statusText: String {
        if isLoading || localTranscription.isModelLoading {
            return needsDownload ? "Downloading..." : "Loading..."
        } else if isCurrentModelLoaded {
            return "Active"
        } else if isBundledModel {
            return "Included • Tap Load to activate"
        } else if localTranscription.isModelDownloaded(selectedModel) {
            return "Downloaded • Tap Load to activate"
        } else {
            return localTranscription.modelQualityDescription[selectedModel] ?? "Requires download"
        }
    }

    private func loadSelectedModel() {
        Task {
            isLoading = true
            loadError = nil
            do {
                try await localTranscription.loadModel(selectedModel)
            } catch {
                loadError = error.localizedDescription
            }
            isLoading = false
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
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(height: 80)
                    .padding(10)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isFocused ? Color.purple.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            }

            HStack(spacing: 10) {
                Text("Click here, then hold the hotkey to transcribe")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))

                Spacer()

                Button(action: { testText = "" }) {
                    Text("Clear")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.1))
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
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
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
                    .fill(testService.isTesting ? Color.green.opacity(0.2) : Color.cyan.opacity(0.2))
                    .frame(width: 32, height: 32)
                Image(systemName: testService.isTesting ? "waveform" : "mic.badge.plus")
                    .font(.system(size: 14))
                    .foregroundColor(testService.isTesting ? .green : .cyan)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Test Microphone")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)

                Text(testService.isTesting ? "Listening... Speak to see levels" : "Check if microphone is working")
                    .font(.system(size: 11))
                    .foregroundColor(testService.isTesting ? .green : .white.opacity(0.5))
            }

            Spacer()

            if testService.isTesting {
                // Level meter
                HStack(spacing: 2) {
                    ForEach(0..<10, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(CGFloat(i) / 10.0 < testService.audioLevel ? (i < 7 ? Color.green : Color.orange) : Color.white.opacity(0.15))
                            .frame(width: 4, height: 18)
                    }
                }
                .padding(.trailing, 8)
            }

            Button(action: { testService.toggleTest() }) {
                Text(testService.isTesting ? "Stop" : "Test")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(testService.isTesting ? .red : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(testService.isTesting ? Color.red.opacity(0.2) : Color.cyan)
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
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.title = "TalkKey"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)
        window.delegate = self
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
