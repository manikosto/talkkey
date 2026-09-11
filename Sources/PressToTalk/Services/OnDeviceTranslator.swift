import AppKit
import SwiftUI
import Translation

/// Apple's on-device translation (macOS 15+), driven without any visible UI.
///
/// The framework hands out a `TranslationSession` only through the SwiftUI
/// `translationTask` modifier, so a tiny invisible panel hosts one view whose
/// task performs the pending request. The panel is only ever shown when a
/// language pack has to be downloaded: the system presents its download sheet
/// on the hosting window, and a hidden window can't show one.
@available(macOS 15.0, *)
@MainActor
final class OnDeviceTranslator {
    static let shared = OnDeviceTranslator()

    enum Availability {
        /// The pack is on this Mac; translation runs immediately and offline.
        case installed
        /// Supported, but macOS has to download the pack first.
        case needsDownload
        /// This pair can't be translated on device.
        case unsupported
    }

    enum Failure: LocalizedError {
        case notReady
        case timedOut

        var errorDescription: String? {
            switch self {
            case .notReady: return "On-device translation didn't start"
            case .timedOut: return "On-device translation timed out"
            }
        }
    }

    private let host = TranslationHostModel()
    private var panel: NSWindow?
    /// Requests run one at a time. A configuration change cancels the task
    /// serving the previous request, and a session cancelled mid-translate
    /// was seen to never come back — so overlapping requests must not happen.
    private var queue: Task<Void, Never>?

    private init() {}

    /// Debug: TALKKEY_TRANSLATE_PREPARE=1 calls prepareTranslation() even for
    /// installed languages, to see whether macOS wants to (re)download.
    private let forcePrepare = ProcessInfo.processInfo.environment["TALKKEY_TRANSLATE_PREPARE"] != nil

    /// `source` is the language the text was found to be in; without it the
    /// framework has to identify the language itself, which it cannot do for
    /// a language whose pack isn't installed yet (unableToIdentifyLanguage).
    func availability(for text: String, from source: Locale.Language?, to target: TranslationLanguage) async -> Availability {
        let language = Locale.Language(identifier: target.localeIdentifier)
        let availability = LanguageAvailability()
        let status: LanguageAvailability.Status?
        if let source {
            status = await availability.status(from: source, to: language)
        } else {
            status = try? await availability.status(for: text, to: language)
        }
        guard let status else { return .unsupported }
        switch status {
        case .installed: return .installed
        case .supported: return .needsDownload
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }

    /// Translates `text`, letting the framework detect the source language.
    /// When the pack is missing and `allowDownload` is set, the system asks
    /// the user to download it first.
    func translate(_ text: String, from source: Locale.Language?, to target: TranslationLanguage, allowDownload: Bool) async throws -> String {
        let previous = queue
        let task = Task<String, Error> { @MainActor in
            await previous?.value
            return try await self.perform(text, from: source, to: target, allowDownload: allowDownload)
        }
        queue = Task { _ = try? await task.value }
        return try await task.value
    }

    private func perform(_ text: String, from source: Locale.Language?, to target: TranslationLanguage, allowDownload: Bool) async throws -> String {
        ensurePanel()

        let job = TranslationJob(text: text, prepare: allowDownload || forcePrepare)
        host.pending = job
        let targetLanguage = Locale.Language(identifier: target.localeIdentifier)
        if host.configuration?.source == source, host.configuration?.target == targetLanguage {
            // Same pair as last time: a fresh Configuration would compare
            // equal (versions start at 0) and the task would never re-run.
            // Invalidating the stored one bumps its version instead.
            host.configuration?.invalidate()
        } else {
            host.configuration = TranslationSession.Configuration(source: source, target: targetLanguage)
        }

        if allowDownload { showPanel() }
        defer { if allowDownload { hidePanel() } }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                job.continuation = continuation
                // Guard against the task never starting (window not attached)
                // or a download prompt the user never answers.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(allowDownload ? 300 : 60))
                    job.fail(with: Failure.timedOut)
                }
            }
        } onCancel: {
            Task { @MainActor in job.fail(with: CancellationError()) }
        }
    }

    /// Loads the model for `target` ahead of the first real request, so the
    /// first tap of the day isn't the one that pays the ~1s model start-up.
    func warmUp(target: TranslationLanguage) {
        Task { @MainActor in
            let probe = target == .english ? "Привет" : "Hello"
            let source = Locale.Language(identifier: target == .english ? "ru" : "en")
            guard await availability(for: probe, from: source, to: target) == .installed else { return }
            _ = try? await translate(probe, from: source, to: target, allowDownload: false)
        }
    }

    // MARK: - Hosting panel

    private func ensurePanel() {
        guard panel == nil else { return }

        // A plain window rather than a non-activating panel: the system's
        // language-download sheet is attached to this window and needs it to
        // be key, which a non-activating panel can never be.
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 96),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "TalkKey Translation"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: TranslationHostView(model: host))
        // Ordered in so SwiftUI runs the task, but invisible and untouchable.
        // orderFrontRegardless does not activate TalkKey or take focus.
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func showPanel() {
        guard let panel else { return }
        panel.center()
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func hidePanel() {
        guard let panel else { return }
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
    }
}

/// One request handed from `translate` to the hosted task.
@available(macOS 15.0, *)
@MainActor
final class TranslationJob {
    let text: String
    let prepare: Bool
    var continuation: CheckedContinuation<String, Error>?

    init(text: String, prepare: Bool) {
        self.text = text
        self.prepare = prepare
    }

    func succeed(with result: String) {
        continuation?.resume(returning: result)
        continuation = nil
    }

    func fail(with error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

@available(macOS 15.0, *)
@MainActor
final class TranslationHostModel: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?
    var pending: TranslationJob?

    func run(_ session: TranslationSession) async {
        guard let job = pending else { return }
        pending = nil
        do {
            if job.prepare {
                DebugLog.append("OnDeviceTranslator: prepareTranslation (download prompt)…")
                try await session.prepareTranslation()
                DebugLog.append("OnDeviceTranslator: prepared")
            }
            let started = Date()
            DebugLog.append("OnDeviceTranslator: translating \(session.sourceLanguage?.minimalIdentifier ?? "?")→\(session.targetLanguage?.minimalIdentifier ?? "?")")
            let response = try await session.translate(job.text)
            DebugLog.append("OnDeviceTranslator: done in \(String(format: "%.2f", Date().timeIntervalSince(started)))s")
            job.succeed(with: response.targetText)
        } catch {
            DebugLog.append("OnDeviceTranslator: error \(error)")
            job.fail(with: error)
        }
    }
}

@available(macOS 15.0, *)
struct TranslationHostView: View {
    @ObservedObject var model: TranslationHostModel

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 20))
                .foregroundColor(.secondary)
            Text("Preparing on-device translation…")
                .font(.system(size: 12, weight: .medium))
            Text("macOS downloads the language once, then it works offline.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(width: 340, height: 96)
        .translationTask(model.configuration) { session in
            await model.run(session)
        }
    }
}
