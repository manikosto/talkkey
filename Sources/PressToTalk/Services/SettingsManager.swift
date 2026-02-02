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
        let langRaw = UserDefaults.standard.string(forKey: languageKey) ?? "en"
        self.selectedLanguage = WhisperLanguage(rawValue: langRaw) ?? .english

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

    func refreshMicrophones() {
        var devices: [AudioDevice] = []

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

        guard status == noErr else {
            devices.append(AudioDevice(id: "default", name: "Default Microphone", deviceID: 0))
            availableMicrophones = devices
            return
        }

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

        guard status == noErr else {
            devices.append(AudioDevice(id: "default", name: "Default Microphone", deviceID: 0))
            availableMicrophones = devices
            return
        }

        // Filter only input devices
        for deviceID in deviceIDs {
            // Check if device has input channels
            var inputPropertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var inputDataSize: UInt32 = 0
            status = AudioObjectGetPropertyDataSize(deviceID, &inputPropertyAddress, 0, nil, &inputDataSize)

            if status == noErr && inputDataSize > 0 {
                let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
                defer { bufferListPointer.deallocate() }

                status = AudioObjectGetPropertyData(deviceID, &inputPropertyAddress, 0, nil, &inputDataSize, bufferListPointer)

                if status == noErr {
                    let bufferList = bufferListPointer.pointee
                    var totalChannels: UInt32 = 0

                    // Get buffer count safely
                    let bufferCount = Int(bufferList.mNumberBuffers)
                    if bufferCount > 0 {
                        // Access first buffer
                        totalChannels = bufferList.mBuffers.mNumberChannels
                    }

                    if totalChannels > 0 {
                        // Get device name
                        var namePropertyAddress = AudioObjectPropertyAddress(
                            mSelector: kAudioDevicePropertyDeviceNameCFString,
                            mScope: kAudioObjectPropertyScopeGlobal,
                            mElement: kAudioObjectPropertyElementMain
                        )

                        var name: CFString = "" as CFString
                        var nameSize = UInt32(MemoryLayout<CFString>.size)

                        status = AudioObjectGetPropertyData(deviceID, &namePropertyAddress, 0, nil, &nameSize, &name)

                        let deviceName = status == noErr ? (name as String) : "Unknown Device"
                        devices.append(AudioDevice(id: String(deviceID), name: deviceName, deviceID: deviceID))
                    }
                }
            }
        }

        // Add default option if no devices found
        if devices.isEmpty {
            devices.append(AudioDevice(id: "default", name: "Default Microphone", deviceID: 0))
        }

        availableMicrophones = devices

        // Set default if none selected or selected device not found
        if selectedMicrophoneID == nil || !devices.contains(where: { $0.id == selectedMicrophoneID }) {
            selectedMicrophoneID = devices.first?.id
        }
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
    guard let selectedID = SettingsManager.shared.selectedMicrophoneID,
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
