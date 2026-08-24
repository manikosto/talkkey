import AVFoundation
import CoreAudio
import SwiftUI
import ObjCExceptionCatcher

/// Builds the 16 kHz converter from the format audio actually arrives in, and
/// rebuilds it if that format changes mid-recording (device switched, engine
/// reconfigured). Confined to the audio thread that owns the tap.
private final class ConverterBox {
    private var cached: AVAudioConverter?
    private var cachedFormat: AVAudioFormat?

    func converter(from source: AVAudioFormat, to target: AVAudioFormat) -> AVAudioConverter? {
        if let cached, let cachedFormat, cachedFormat == source {
            return cached
        }
        guard let made = AVAudioConverter(from: source, to: target) else { return nil }
        cached = made
        cachedFormat = source
        return made
    }
}

/// Owns the recording file and releases it deterministically.
///
/// AVAudioFile finalises the WAV header — including the frame count — when it
/// deallocates. The tap block used to capture the file directly, so stopping a
/// recording left a second strong reference alive and the file could still
/// report zero frames when transcription opened it.
private final class AudioFileBox {
    private let lock = NSLock()
    private var file: AVAudioFile?

    init(_ file: AVAudioFile) { self.file = file }

    func write(_ buffer: AVAudioPCMBuffer) throws {
        lock.lock(); defer { lock.unlock() }
        try file?.write(from: buffer)
    }

    /// Drops the file so its header is written before anyone reads it.
    func close() {
        lock.lock(); file = nil; lock.unlock()
    }
}

class AudioRecorder {
    static let shared = AudioRecorder()

    /// Long-lived engine.
    ///
    /// Building one per recording cost ~1.4s before a single sample arrived,
    /// almost all of it the first `inputNode` access, which spins up the audio
    /// HAL. Measured: engine + inputNode + prepare ≈ 940 ms, and it is paid
    /// once per engine, not once per recording. Keeping the instance alive
    /// and only starting/stopping it brings press-to-first-audio to ~170 ms.
    private var audioEngine: AVAudioEngine?
    private var audioFileBox: AudioFileBox?
    private var recordingURL: URL?
    private var previousDefaultDevice: AudioDeviceID?
    private var peakLevel: Float = -160.0
    private var averageLevelSum: Float = 0
    private var levelSampleCount: Int = 0
    private var lastLevelUpdateTime: CFTimeInterval = 0
    // Counted so a failed recording can explain itself in the error shown.
    private var writeOK = 0
    private var writeFail = 0
    private var firstWriteError: String?

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
    // Below this, we assume it's silence/noise and skip transcription.
    // Kept permissive: a rejected recording is far worse than a wasted
    // transcription pass, and rejections are now surfaced via toast.
    private let minimumSpeechLevel: Float = -50.0

    var isRecording: Bool {
        audioEngine?.isRunning ?? false
    }

    /// Pays the one-off HAL initialisation at launch instead of on the first
    /// hotkey press. Preparing does not open the input stream, so no recording
    /// indicator appears until `start()`.
    func prewarm() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        _ = warmEngine()
    }

    /// Returns the shared engine, creating and preparing it on first use.
    private func warmEngine() -> AVAudioEngine {
        if let engine = audioEngine { return engine }

        let engine = AVAudioEngine()
        _ = engine.inputNode        // the expensive part — once per process
        engine.prepare()

        // The input device can change under us (headset plugged in, mic
        // switched). AVAudioEngine tears its graph down when that happens, so
        // re-prepare while idle rather than discovering it mid-recording.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self, !(self.audioEngine?.isRunning ?? false) else { return }
            self.audioEngine?.prepare()
        }

        audioEngine = engine
        return engine
    }

    private func resetSamplesBuffer() {
        samplesLock.lock()
        _currentAudioSamples = []
        samplesLock.unlock()
    }

    var hasSufficientAudio: Bool {
        guard levelSampleCount > 0 else { return false }
        let avgLevel = averageLevelSum / Float(levelSampleCount)
        return avgLevel > minimumSpeechLevel || peakLevel > -40.0
    }

    func startRecording() async throws {
        // Check microphone permission first
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else {
            throw RecordingError.noMicrophonePermission
        }

        writeOK = 0; writeFail = 0; firstWriteError = nil
        // Reset level tracking
        peakLevel = -160.0
        averageLevelSum = 0
        levelSampleCount = 0

        // Reset audio samples buffer
        resetSamplesBuffer()
        AudioLevelStore.shared.reset()

        // Set selected microphone as default input device
        if let selectedDeviceID = getSelectedAudioDeviceID() {
            // Save current default device to restore later
            previousDefaultDevice = getCurrentDefaultInputDevice()
            let success = setAudioInputDevice(selectedDeviceID)
            if !success {
                print("Warning: Failed to set audio input device \(selectedDeviceID)")
            }
            // Give the system time to switch devices without blocking the main thread
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        let tempDir = FileManager.default.temporaryDirectory
        recordingURL = tempDir.appendingPathComponent("recording_\(Date().timeIntervalSince1970).wav")

        guard let recordingURL = recordingURL else {
            throw RecordingError.setupFailed
        }

        // Reuse the warm engine — see `warmEngine()` for why this matters.
        let engine = warmEngine()
        let inputNode = engine.inputNode

        // Target format: 16kHz mono Float32 (WhisperKit's native format)
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            throw RecordingError.setupFailed
        }

        // Create audio file for final transcription (16kHz mono WAV)
        let audioFileBox = AudioFileBox(try AVAudioFile(forWriting: recordingURL, settings: targetFormat.settings))
        self.audioFileBox = audioFileBox

        // Install tap on input node. Remove any stale tap first — the node is
        // shared across recordings now, and installing twice traps.
        inputNode.removeTap(onBus: 0)
        let bufferSize: AVAudioFrameCount = 1024

        // The converter is built from the first buffer's own format rather than
        // from a format read in advance. Reading it up front and handing it to
        // installTap is what crashed the app: if the input device changed in
        // between — headphones, the iPhone mic, the system rebuilding the audio
        // graph — AVAudioEngine fails an internal assertion and raises an
        // Objective-C exception, which Swift cannot catch, so the process
        // aborted with no error at all. Deriving it per buffer also lets a
        // recording survive a device change midway through.
        let converterBox = ConverterBox()
        let tapBlock: AVAudioNodeTapBlock = { [weak self] buffer, _ in
            guard let self = self else { return }

            let sourceFormat = buffer.format
            guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0 else { return }

            guard let converter = converterBox.converter(from: sourceFormat, to: targetFormat) else { return }

            // Convert to 16kHz mono
            let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * 16000.0 / sourceFormat.sampleRate)
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
                try audioFileBox.write(convertedBuffer)
                self.writeOK += 1
            } catch {
                self.writeFail += 1
                if self.firstWriteError == nil { self.firstWriteError = "\(error)" }
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

            // Convert dB to 0-1 range for the overlay waveform. Written straight
            // to the lock-protected store — no main-thread hop, no SwiftUI publish.
            let now = CACurrentMediaTime()
            if now - self.lastLevelUpdateTime >= AudioLevelStore.pushInterval {
                self.lastLevelUpdateTime = now
                let normalizedLevel = max(0, (rmsDB + 50) / 50)
                AudioLevelStore.shared.push(min(1.0, max(0.04, normalizedLevel)))
            }
        }

        // format: nil tells the engine to use the node's own current format,
        // which removes the mismatch that made this call raise. The guard
        // catches anything AVFAudio still throws so it surfaces as an error
        // instead of aborting the process.
        var installFailed = ObjCExceptionCatcher.try {
            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: nil, block: tapBlock)
        }

        if installFailed == nil, !engine.isRunning {
            do {
                try engine.start()
            } catch {
                installFailed = error as NSError
            }
        }

        guard installFailed == nil else {
            // A stale graph (device yanked, HAL hiccup, format churn) can leave
            // the engine unusable. Rebuild once — this costs the ~940 ms
            // warm-up, but only in the rare failure case.
            print("Audio setup failed, rebuilding engine: \(installFailed!.localizedDescription)")
            audioEngine?.stop()
            audioEngine = nil
            let fresh = warmEngine()
            let node = fresh.inputNode

            if let retryError = ObjCExceptionCatcher.try({
                node.removeTap(onBus: 0)
                node.installTap(onBus: 0, bufferSize: bufferSize, format: nil, block: tapBlock)
            }) {
                print("Audio setup failed again: \(retryError.localizedDescription)")
                throw RecordingError.setupFailed
            }
            try fresh.start()
            return
        }
    }

    func stopRecording() -> URL? {
        // Stop the stream but keep the engine — see `warmEngine()`. Stopping
        // releases the microphone, so the recording indicator still clears.
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioFileBox?.close()
        audioFileBox = nil

        // Clear samples buffer
        samplesLock.lock()
        _currentAudioSamples = []
        samplesLock.unlock()

        // Restore previous default input device
        if let previousDevice = previousDefaultDevice {
            _ = setAudioInputDevice(previousDevice)
            previousDefaultDevice = nil
        }

        AudioLevelStore.shared.reset()

        // Hand back this session's file and forget it, so a recording started
        // immediately afterwards can't have its fresh, still-empty file
        // returned to the take that just ended.
        let url = recordingURL
        recordingURL = nil

        // Only return a file that actually has audio in it. WhisperKit asserts
        // on an empty one ("buffer.frameCapacity != 0"), which surfaced to
        // users as a raw CoreAudio error; a nil here becomes a plain message.
        guard let url, let frames = try? AVAudioFile(forReading: url).length, frames > 0 else {
            lastFailureDetail = "writes: \(writeOK) ok / \(writeFail) failed"
                + (firstWriteError.map { "; first error: \($0)" } ?? "")
            if let url { try? FileManager.default.removeItem(at: url) }
            return nil
        }

        lastFailureDetail = nil
        return url
    }

    /// Why the last recording produced nothing usable, for the error shown to
    /// the user and for diagnosing reports.
    private(set) var lastFailureDetail: String?

    func cancelRecording() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioFileBox?.close()
        audioFileBox = nil

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

        AudioLevelStore.shared.reset()
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
