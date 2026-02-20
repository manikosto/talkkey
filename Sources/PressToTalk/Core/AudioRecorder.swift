import AVFoundation
import CoreAudio

class AudioRecorder {
    static let shared = AudioRecorder()

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var previousDefaultDevice: AudioDeviceID?
    private var peakLevel: Float = -160.0
    private var averageLevelSum: Float = 0
    private var levelSampleCount: Int = 0

    // Live PCM buffer for streaming transcription (16kHz mono Float32)
    private let samplesLock = NSLock()
    private var _currentAudioSamples: [Float] = []

    var currentAudioSamples: [Float] {
        samplesLock.lock()
        let copy = _currentAudioSamples
        samplesLock.unlock()
        return copy
    }

    // Minimum average level (in dB) to consider as actual speech
    // Below this, we assume it's silence/noise and skip transcription
    private let minimumSpeechLevel: Float = -45.0

    var isRecording: Bool {
        audioEngine?.isRunning ?? false
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

        // Reset audio samples buffer
        samplesLock.lock()
        _currentAudioSamples = []
        samplesLock.unlock()

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
        recordingURL = tempDir.appendingPathComponent("recording_\(Date().timeIntervalSince1970).wav")

        guard let recordingURL = recordingURL else {
            throw RecordingError.setupFailed
        }

        // Setup AVAudioEngine
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target format: 16kHz mono Float32 (WhisperKit's native format)
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            throw RecordingError.setupFailed
        }

        // Create converter from input format to 16kHz mono
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecordingError.setupFailed
        }

        // Create audio file for final transcription (16kHz mono WAV)
        let audioFile = try AVAudioFile(forWriting: recordingURL, settings: targetFormat.settings)
        self.audioFile = audioFile

        // Install tap on input node
        let bufferSize: AVAudioFrameCount = 4096
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Convert to 16kHz mono
            let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * 16000.0 / inputFormat.sampleRate)
            guard frameCapacity > 0, let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
                return
            }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

            if error != nil {
                return
            }

            guard convertedBuffer.frameLength > 0 else { return }

            // Write to file
            do {
                try audioFile.write(from: convertedBuffer)
            } catch {
                print("Error writing audio file: \(error)")
            }

            // Extract Float32 samples
            guard let channelData = convertedBuffer.floatChannelData else { return }
            let frameCount = Int(convertedBuffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))

            // Accumulate samples for streaming
            self.samplesLock.lock()
            self._currentAudioSamples.append(contentsOf: samples)
            self.samplesLock.unlock()

            // Calculate audio level from PCM samples
            var sumSquares: Float = 0
            var peak: Float = 0
            for sample in samples {
                let abs = Swift.abs(sample)
                sumSquares += sample * sample
                if abs > peak { peak = abs }
            }
            let rms = sqrt(sumSquares / Float(frameCount))

            // Convert to dB
            let rmsDB = rms > 0 ? 20 * log10(rms) : -160
            let peakDB = peak > 0 ? 20 * log10(peak) : -160

            // Track levels for silence detection
            self.averageLevelSum += rmsDB
            self.levelSampleCount += 1
            if peakDB > self.peakLevel {
                self.peakLevel = peakDB
            }

            // Convert dB to 0-1 range for UI
            let normalizedLevel = max(0, (rmsDB + 50) / 50)
            let cgLevel = CGFloat(min(1.0, max(0.05, normalizedLevel)))

            Task { @MainActor in
                AppState.shared.updateAudioLevel(cgLevel)
            }
        }

        engine.prepare()
        try engine.start()
        self.audioEngine = engine
    }

    func stopRecording() -> URL? {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil

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
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil

        // Restore previous default input device
        if let previousDevice = previousDefaultDevice {
            _ = setAudioInputDevice(previousDevice)
            previousDefaultDevice = nil
        }

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil

        // Clear samples buffer
        samplesLock.lock()
        _currentAudioSamples = []
        samplesLock.unlock()

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
