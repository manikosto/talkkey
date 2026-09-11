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
    private var panel: NSPanel?

    private init() {}

    func availability(for text: String, to target: TranslationLanguage) async -> Availability {
        let language = Locale.Language(identifier: target.localeIdentifier)
        guard let status = try? await LanguageAvailability().status(for: text, to: language) else {
            return .unsupported
        }
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
    func translate(_ text: String, to target: TranslationLanguage, allowDownload: Bool) async throws -> String {
        ensurePanel()

        let job = TranslationJob(text: text, prepare: allowDownload)
        host.pending = job
        host.configuration = TranslationSession.Configuration(
            source: nil,
            target: Locale.Language(identifier: target.localeIdentifier)
        )
        // Same target twice in a row would compare equal and never re-run the
        // task; invalidating bumps the version so it always does.
        host.configuration?.invalidate()

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

    // MARK: - Hosting panel

    private func ensurePanel() {
        guard panel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 96),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
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
        panel.orderFrontRegardless()
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
                try await session.prepareTranslation()
            }
            let response = try await session.translate(job.text)
            job.succeed(with: response.targetText)
        } catch {
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
