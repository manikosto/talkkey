import Foundation
import AVFoundation
import CoreAudio

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let languageKey = "whisperLanguage"
    private let microphoneKey = "selectedMicrophone"
    private let hotkeyKey = "selectedHotkey"
    private let secondaryHotkeyKey = "secondaryHotkey"
    private let reviewEnabledKey = "reviewModeEnabled"
    private let selectedModelKey = "selectedGPTModel"
    private let defaultStyleKey = "defaultRewriteStyle"
    private let offlineModeKey = "offlineModeEnabled"
    private let translationEnabledKey = "translationEnabled"
    private let targetLanguageKey = "targetLanguage"
    private let translationHotkeyKey = "translationHotkey"

    @Published var selectedLanguage: WhisperLanguage {
        didSet { UserDefaults.standard.set(selectedLanguage.rawValue, forKey: languageKey) }
    }

    @Published var offlineModeEnabled: Bool {
        didSet { UserDefaults.standard.set(offlineModeEnabled, forKey: offlineModeKey) }
    }

    @Published var selectedMicrophoneID: String? {
        didSet { UserDefaults.standard.set(selectedMicrophoneID, forKey: microphoneKey) }
    }

    // Primary hotkey - direct paste
    @Published var selectedHotkey: HotkeyOption {
        didSet { UserDefaults.standard.set(selectedHotkey.rawValue, forKey: hotkeyKey) }
    }

    // Secondary hotkey - review mode
    @Published var secondaryHotkey: HotkeyOption {
        didSet { UserDefaults.standard.set(secondaryHotkey.rawValue, forKey: secondaryHotkeyKey) }
    }

    // Review mode settings
    @Published var reviewModeEnabled: Bool {
        didSet { UserDefaults.standard.set(reviewModeEnabled, forKey: reviewEnabledKey) }
    }

    @Published var selectedModel: GPTModel {
        didSet { UserDefaults.standard.set(selectedModel.rawValue, forKey: selectedModelKey) }
    }

    @Published var defaultStyle: RewriteStyle {
        didSet { UserDefaults.standard.set(defaultStyle.rawValue, forKey: defaultStyleKey) }
    }

    // Translation settings (Pro feature)
    @Published var translationEnabled: Bool {
        didSet { UserDefaults.standard.set(translationEnabled, forKey: translationEnabledKey) }
    }

    @Published var targetLanguage: TranslationLanguage {
        didSet { UserDefaults.standard.set(targetLanguage.rawValue, forKey: targetLanguageKey) }
    }

    @Published var translationHotkey: TranslationHotkey {
        didSet { UserDefaults.standard.set(translationHotkey.rawValue, forKey: translationHotkeyKey) }
    }

    @Published var availableMicrophones: [AudioDevice] = []

    init() {
        // One-time migration: switch existing users to auto-detect
        if !UserDefaults.standard.bool(forKey: "didMigrateToAutoDetect") {
            UserDefaults.standard.set("auto", forKey: languageKey)
            UserDefaults.standard.set(true, forKey: "didMigrateToAutoDetect")
        }

        let langRaw = UserDefaults.standard.string(forKey: languageKey) ?? "auto"
        self.selectedLanguage = WhisperLanguage(rawValue: langRaw) ?? .auto

        // Default to offline mode (bundled model) for new users
        if UserDefaults.standard.object(forKey: offlineModeKey) == nil {
            self.offlineModeEnabled = true
        } else {
            self.offlineModeEnabled = UserDefaults.standard.bool(forKey: offlineModeKey)
        }

        self.selectedMicrophoneID = UserDefaults.standard.string(forKey: microphoneKey)

        let hotkeyRaw = UserDefaults.standard.string(forKey: hotkeyKey) ?? "rightCmd"
        self.selectedHotkey = HotkeyOption(rawValue: hotkeyRaw) ?? .rightCmd

        let secondaryRaw = UserDefaults.standard.string(forKey: secondaryHotkeyKey) ?? "rightOption"
        self.secondaryHotkey = HotkeyOption(rawValue: secondaryRaw) ?? .rightOption

        self.reviewModeEnabled = UserDefaults.standard.bool(forKey: reviewEnabledKey)

        let modelRaw = UserDefaults.standard.string(forKey: selectedModelKey) ?? "gpt4oMini"
        self.selectedModel = GPTModel(rawValue: modelRaw) ?? .gpt4oMini

        let styleRaw = UserDefaults.standard.string(forKey: defaultStyleKey) ?? "original"
        self.defaultStyle = RewriteStyle(rawValue: styleRaw) ?? .original

        self.translationEnabled = UserDefaults.standard.bool(forKey: translationEnabledKey)

        let targetRaw = UserDefaults.standard.string(forKey: targetLanguageKey) ?? "en"
        self.targetLanguage = TranslationLanguage(rawValue: targetRaw) ?? .english

        let translationHotkeyRaw = UserDefaults.standard.string(forKey: translationHotkeyKey) ?? "slash"
        self.translationHotkey = TranslationHotkey(rawValue: translationHotkeyRaw) ?? .slash

        refreshMicrophones()
    }

    /// Sentinel meaning "don't touch the input device — use whatever macOS
    /// considers the default". This is the default behavior: TalkKey must not
    /// grab the iPhone Continuity mic (or anything else) on its own.
    static let systemDefaultMicID = "system-default"

    func refreshMicrophones() {
        var devices: [AudioDevice] = [
            AudioDevice(id: Self.systemDefaultMicID, name: "System Default", deviceID: 0)
        ]

        // Get all audio input devices using CoreAudio
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        if status == noErr {
            let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
            var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

            status = AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                0,
                nil,
                &dataSize,
                &deviceIDs
            )

            if status == noErr {
                for deviceID in deviceIDs where hasInputChannels(deviceID) {
                    // Key devices by their stable UID — the numeric AudioDeviceID
                    // changes between launches, which used to make the saved
                    // selection silently fall back to the first device found.
                    guard let uid = deviceString(deviceID, kAudioDevicePropertyDeviceUID) else { continue }
                    let name = deviceString(deviceID, kAudioDevicePropertyDeviceNameCFString) ?? "Unknown Device"
                    devices.append(AudioDevice(id: uid, name: name, deviceID: deviceID))
                }
            }
        }

        availableMicrophones = devices

        // Unknown or vanished selection → System Default, never "first device".
        if selectedMicrophoneID == nil || !devices.contains(where: { $0.id == selectedMicrophoneID }) {
            selectedMicrophoneID = Self.systemDefaultMicID
        }
    }

    private func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return false }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPointer.deallocate() }

        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferListPointer)
        guard status == noErr else { return false }

        let bufferList = UnsafeMutableAudioBufferListPointer(
            bufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
        )
        return bufferList.reduce(0) { $0 + $1.mNumberChannels } > 0
    }

    private func deviceString(_ deviceID: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var unmanaged: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &unmanaged) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value = unmanaged?.takeRetainedValue() else { return nil }
        return value as String
    }
}

struct AudioDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let deviceID: AudioDeviceID

    init(id: String, name: String, deviceID: AudioDeviceID = 0) {
        self.id = id
        self.name = name
        self.deviceID = deviceID
    }
}

// MARK: - Audio Device Helper

func getSelectedAudioDeviceID() -> AudioDeviceID? {
    // nil → recording uses whatever input macOS currently considers default;
    // TalkKey switches devices only for an explicit user selection.
    guard let selectedID = SettingsManager.shared.selectedMicrophoneID,
          selectedID != SettingsManager.systemDefaultMicID,
          let device = SettingsManager.shared.availableMicrophones.first(where: { $0.id == selectedID }) else {
        return nil
    }
    return device.deviceID > 0 ? device.deviceID : nil
}

func setAudioInputDevice(_ deviceID: AudioDeviceID) -> Bool {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var mutableDeviceID = deviceID
    let status = AudioObjectSetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0,
        nil,
        UInt32(MemoryLayout<AudioDeviceID>.size),
        &mutableDeviceID
    )

    return status == noErr
}

enum WhisperLanguage: String, CaseIterable, Identifiable {
    case auto = "auto"
    case english = "en"
    case russian = "ru"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case chinese = "zh"
    case japanese = "ja"
    case korean = "ko"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto-detect"
        case .english: return "English"
        case .russian: return "Russian"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        case .chinese: return "Chinese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        }
    }
}

enum HotkeyOption: String, CaseIterable, Identifiable {
    case rightCmd = "rightCmd"
    case rightOption = "rightOption"
    case fn = "fn"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rightCmd: return "Right ⌘"
        case .rightOption: return "Right ⌥"
        case .fn: return "Fn"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .rightCmd: return 54
        case .rightOption: return 61
        case .fn: return 63
        }
    }
}

enum GPTModel: String, CaseIterable, Identifiable {
    case gpt4oMini = "gpt4oMini"
    case gpt4o = "gpt4o"
    case gpt4Turbo = "gpt4Turbo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gpt4oMini: return "GPT-4o Mini (Fast)"
        case .gpt4o: return "GPT-4o (Best)"
        case .gpt4Turbo: return "GPT-4 Turbo"
        }
    }

    var apiName: String {
        switch self {
        case .gpt4oMini: return "gpt-4o-mini"
        case .gpt4o: return "gpt-4o"
        case .gpt4Turbo: return "gpt-4-turbo"
        }
    }

    var shortName: String {
        switch self {
        case .gpt4oMini: return "Mini"
        case .gpt4o: return "4o"
        case .gpt4Turbo: return "Turbo"
        }
    }
}

enum RewriteStyle: String, CaseIterable, Identifiable {
    case original = "original"
    case formal = "formal"
    case casual = "casual"
    case concise = "concise"
    case detailed = "detailed"
    case bullets = "bullets"
    case email = "email"
    case technical = "technical"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: return "Original"
        case .formal: return "Formal"
        case .casual: return "Casual"
        case .concise: return "Concise"
        case .detailed: return "Detailed"
        case .bullets: return "Bullet Points"
        case .email: return "Email"
        case .technical: return "Technical"
        }
    }

    var icon: String {
        switch self {
        case .original: return "doc.text"
        case .formal: return "building.columns"
        case .casual: return "face.smiling"
        case .concise: return "arrow.down.right.and.arrow.up.left"
        case .detailed: return "text.magnifyingglass"
        case .bullets: return "list.bullet"
        case .email: return "envelope"
        case .technical: return "wrench.and.screwdriver"
        }
    }

    var prompt: String {
        switch self {
        case .original:
            return "Return the text exactly as provided, only fixing obvious typos and punctuation."
        case .formal:
            return "Rewrite this text in a formal, professional tone suitable for business communication. Maintain the original meaning."
        case .casual:
            return "Rewrite this text in a casual, friendly tone. Make it conversational while keeping the core message."
        case .concise:
            return "Make this text more concise. Remove unnecessary words while preserving the key information."
        case .detailed:
            return "Expand this text with more details and explanations. Make it more comprehensive."
        case .bullets:
            return "Convert this text into clear, organized bullet points. Each bullet should be a complete thought."
        case .email:
            return "Format this as a professional email with appropriate greeting and closing. Keep it clear and courteous."
        case .technical:
            return "Rewrite this in a technical, precise style. Use appropriate terminology and be specific."
        }
    }
}

enum TranslationLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case russian = "ru"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case chinese = "zh"
    case japanese = "ja"
    case korean = "ko"
    case arabic = "ar"
    case hindi = "hi"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .russian: return "Русский"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .portuguese: return "Português"
        case .chinese: return "中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .arabic: return "العربية"
        case .hindi: return "हिन्दी"
        }
    }

    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .russian: return "🇷🇺"
        case .spanish: return "🇪🇸"
        case .french: return "🇫🇷"
        case .german: return "🇩🇪"
        case .italian: return "🇮🇹"
        case .portuguese: return "🇧🇷"
        case .chinese: return "🇨🇳"
        case .japanese: return "🇯🇵"
        case .korean: return "🇰🇷"
        case .arabic: return "🇸🇦"
        case .hindi: return "🇮🇳"
        }
    }

    var fullName: String {
        switch self {
        case .english: return "English"
        case .russian: return "Russian"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        case .chinese: return "Chinese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .arabic: return "Arabic"
        case .hindi: return "Hindi"
        }
    }
}

enum TranslationHotkey: String, CaseIterable, Identifiable {
    case slash = "slash"         // /
    case backslash = "backslash" // \
    case t = "t"                 // T
    case g = "g"                 // G
    case space = "space"         // Space

    var id: String { rawValue }

    var keyCode: UInt16 {
        switch self {
        case .slash: return 44
        case .backslash: return 42
        case .t: return 17
        case .g: return 5
        case .space: return 49
        }
    }

    var displayName: String {
        switch self {
        case .slash: return "/"
        case .backslash: return "\\"
        case .t: return "T"
        case .g: return "G"
        case .space: return "Space"
        }
    }

    var shortcutDisplay: String {
        switch self {
        case .slash: return "⌘ /"
        case .backslash: return "⌘ \\"
        case .t: return "⌘ T"
        case .g: return "⌘ G"
        case .space: return "⌘ Space"
        }
    }
}
