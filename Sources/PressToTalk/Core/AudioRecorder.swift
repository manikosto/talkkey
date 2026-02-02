import AVFoundation
import CoreAudio

class AudioRecorder {
    static let shared = AudioRecorder()

    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var recordingURL: URL?
    private var previousDefaultDevice: AudioDeviceID?
    private var peakLevel: Float = -160.0
    private var averageLevelSum: Float = 0
    private var levelSampleCount: Int = 0

    // Minimum average level (in dB) to consider as actual speech
    // Below this, we assume it's silence/noise and skip transcription
    private let minimumSpeechLevel: Float = -45.0

    var isRecording: Bool {
        audioRecorder?.isRecording ?? false
    }

    var hasSufficientAudio: Bool {
        guard levelSampleCount > 0 else { return false }
        let avgLevel = averageLevelSum / Float(levelSampleCount)
        return avgLevel > minimumSpeechLevel || peakLevel > -35.0
    }

    func startRecording() throws {
        // Check microphone permission first
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else {
            throw RecordingError.noMicrophonePermission
        }

        // Reset level tracking
        peakLevel = -160.0
        averageLevelSum = 0
        levelSampleCount = 0

        // Set selected microphone as default input device
        if let selectedDeviceID = getSelectedAudioDeviceID() {
            // Save current default device to restore later
            previousDefaultDevice = getCurrentDefaultInputDevice()
            let success = setAudioInputDevice(selectedDeviceID)
            if !success {
                print("Warning: Failed to set audio input device \(selectedDeviceID)")
            }
            // Small delay to let the system switch devices
            Thread.sleep(forTimeInterval: 0.1)
        }

        let tempDir = FileManager.default.temporaryDirectory
        recordingURL = tempDir.appendingPathComponent("recording_\(Date().timeIntervalSince1970).m4a")

        guard let recordingURL = recordingURL else {
            throw RecordingError.setupFailed
        }

        // Settings for good quality recording that Whisper API accepts
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.record()

        // Start level monitoring on main thread
        DispatchQueue.main.async {
            self.levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.updateAudioLevel()
            }
        }
    }

    private func updateAudioLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }

        recorder.updateMeters()
        let level = recorder.averagePower(forChannel: 0)
        let peak = recorder.peakPower(forChannel: 0)

        // Track levels for silence detection
        averageLevelSum += level
        levelSampleCount += 1
        if peak > peakLevel {
            peakLevel = peak
        }

        // Convert dB to 0-1 range
        // Average power is typically -160 to 0 dB
        let normalizedLevel = max(0, (level + 50) / 50)
        let cgLevel = CGFloat(min(1.0, max(0.05, normalizedLevel)))

        Task { @MainActor in
            AppState.shared.updateAudioLevel(cgLevel)
        }
    }

    func stopRecording() -> URL? {
        levelTimer?.invalidate()
        levelTimer = nil

        audioRecorder?.stop()
        audioRecorder = nil

        // Restore previous default input device
        if let previousDevice = previousDefaultDevice {
            _ = setAudioInputDevice(previousDevice)
            previousDefaultDevice = nil
        }

        Task { @MainActor in
            AppState.shared.resetAudioLevels()
        }

        return recordingURL
    }

    func cancelRecording() {
        levelTimer?.invalidate()
        levelTimer = nil

        audioRecorder?.stop()
        audioRecorder = nil

        // Restore previous default input device
        if let previousDevice = previousDefaultDevice {
            _ = setAudioInputDevice(previousDevice)
            previousDefaultDevice = nil
        }

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil

        Task { @MainActor in
            AppState.shared.resetAudioLevels()
        }
    }

    private func getCurrentDefaultInputDevice() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        return status == noErr ? deviceID : nil
    }
}

// MARK: - Microphone Test

@MainActor
class MicrophoneTestService: ObservableObject {
    static let shared = MicrophoneTestService()

    @Published var isTesting = false
    @Published var audioLevel: CGFloat = 0.05

    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var testURL: URL?

    func toggleTest() {
        if isTesting {
            stopTest()
        } else {
            startTest()
        }
    }

    private func startTest() {
        // Set selected microphone
        if let selectedDeviceID = getSelectedAudioDeviceID() {
            _ = setAudioInputDevice(selectedDeviceID)
            Thread.sleep(forTimeInterval: 0.1)
        }

        let tempDir = FileManager.default.temporaryDirectory
        testURL = tempDir.appendingPathComponent("mic_test.m4a")

        guard let url = testURL else { return }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            isTesting = true

            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.updateLevel()
                }
            }
        } catch {
            print("Mic test error: \(error)")
        }
    }

    func stopTest() {
        levelTimer?.invalidate()
        levelTimer = nil
        audioRecorder?.stop()
        audioRecorder = nil
        isTesting = false
        audioLevel = 0.05

        if let url = testURL {
            try? FileManager.default.removeItem(at: url)
        }
        testURL = nil
    }

    private func updateLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let level = recorder.averagePower(forChannel: 0)
        let normalized = max(0, (level + 50) / 50)
        audioLevel = CGFloat(min(1.0, max(0.05, normalized)))
    }
}

enum RecordingError: Error, LocalizedError {
    case setupFailed
    case noMicrophonePermission

    var errorDescription: String? {
        switch self {
        case .setupFailed:
            return "Failed to setup audio recording"
        case .noMicrophonePermission:
            return "Microphone permission not granted"
        }
    }
}
