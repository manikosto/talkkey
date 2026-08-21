import SwiftUI
import AppKit

enum ToastKind {
    case success
    case info
    case warning
    case error

    var color: Color {
        switch self {
        case .success: return .green
        case .info: return Color(red: 0.35, green: 0.65, blue: 1.0)
        case .warning: return .orange
        case .error: return Color(red: 1.0, green: 0.35, blue: 0.3)
        }
    }

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return "doc.on.clipboard.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

/// Floating result card shown after a recording when something needs the
/// user's attention — the transcript that could not be pasted (with a Copy
/// button), a too-quiet recording, or an error. Nothing fails silently.
struct ResultToastView: View {
    let kind: ToastKind
    let title: String
    let detail: String?
    let copyText: String?
    let onClose: () -> Void
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: kind.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(kind.color)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let copyText {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(copyText, forType: .string)
                        withAnimation(.easeOut(duration: 0.15)) { copied = true }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: .semibold))
                            Text(copied ? "Copied" : "Copy")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(copied ? .green : .white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(copied ? 0.06 : 0.12)))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 3)
                }
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 380, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.25))
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.25), Color.white.opacity(0.06), kind.color.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.35), radius: 14, y: 5)
        // Margin so the shadows fade before the window edge (no square halo)
        .padding(28)
    }
}

// MARK: - Window controller

@MainActor
final class ResultToastController {
    static let shared = ResultToastController()

    private var panel: NSPanel?
    private var generation = 0
    private var hideWork: DispatchWorkItem?

    func show(kind: ToastKind, title: String, detail: String? = nil, copyText: String? = nil, duration: TimeInterval = 7) {
        generation &+= 1
        let gen = generation
        hideWork?.cancel()

        if let old = panel {
            old.orderOut(nil)
            old.contentView = nil
            panel = nil
        }

        let view = ResultToastView(
            kind: kind,
            title: title,
            detail: detail,
            copyText: copyText,
            onClose: { [weak self] in self?.hide() }
        )
        let hostingView = NSHostingView(rootView: view)
        let size = hostingView.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 96)
            panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y - 12))
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrameOrigin(origin)
            }
        }

        self.panel = panel

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == gen else { return }
            self.hide()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func hide() {
        generation &+= 1
        let gen = generation
        hideWork?.cancel()
        hideWork = nil
        guard let panel = panel else { return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                guard self.generation == gen, let panel = self.panel else { return }
                panel.orderOut(nil)
                panel.contentView = nil
                self.panel = nil
            }
        })
    }
}
