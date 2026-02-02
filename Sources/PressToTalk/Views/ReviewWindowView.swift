import SwiftUI
import AppKit

struct ReviewWindowView: View {
    @ObservedObject var appState: AppState
    @StateObject private var settings = SettingsManager.shared

    @State private var originalText: String
    @State private var rewrittenText: String = ""
    @State private var selectedStyle: RewriteStyle = .original
    @State private var isRewriting = false
    @State private var errorMessage: String?

    let onInsert: (String) -> Void
    let onCancel: () -> Void

    init(text: String, appState: AppState, onInsert: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self._originalText = State(initialValue: text)
        self.appState = appState
        self.onInsert = onInsert
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.purple)
                Text("Review & Rewrite")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.3))

            // Content
            VStack(spacing: 12) {
                // Original text
                VStack(alignment: .leading, spacing: 4) {
                    Text("Original")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))

                    TextEditor(text: $originalText)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .scrollContentBackground(.hidden)
                        .frame(height: 60)
                        .padding(8)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                }

                // Style selector - compact horizontal scroll
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(RewriteStyle.allCases) { style in
                            CompactStyleButton(
                                style: style,
                                isSelected: selectedStyle == style
                            ) {
                                selectedStyle = style
                                if style != .original {
                                    Task { await rewriteText() }
                                } else {
                                    rewrittenText = ""
                                }
                            }
                        }
                    }
                }

                // Rewritten text
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Result")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))

                        if isRewriting {
                            ProgressView()
                                .scaleEffect(0.6)
                        }

                        Spacer()

                        // Model picker
                        Picker("", selection: $settings.selectedModel) {
                            ForEach(GPTModel.allCases) { model in
                                Text(model.shortName).tag(model)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                        .scaleEffect(0.85)
                        .onChange(of: settings.selectedModel) { _, _ in
                            if selectedStyle != .original {
                                Task { await rewriteText() }
                            }
                        }
                    }

                    if isRewriting {
                        HStack {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(.circular)
                            Spacer()
                        }
                        .frame(height: 80)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                    } else {
                        TextEditor(text: $rewrittenText)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 80)
                            .padding(8)
                            .background(selectedStyle == .original ? Color.white.opacity(0.05) : Color.purple.opacity(0.1))
                            .cornerRadius(8)
                            .overlay(
                                Group {
                                    if rewrittenText.isEmpty && selectedStyle == .original {
                                        Text("Select a style to rewrite...")
                                            .font(.system(size: 13))
                                            .foregroundColor(.white.opacity(0.3))
                                    }
                                }
                            )
                    }
                }

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                }
            }
            .padding(12)

            // Footer buttons
            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])

                Button(action: insertText) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.insert")
                        Text("Insert")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.purple)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(isRewriting)
            }
            .padding(12)
            .background(Color.black.opacity(0.3))
        }
        .frame(width: 420, height: 380)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .preferredColorScheme(.dark)
    }

    private func rewriteText() async {
        guard !originalText.isEmpty else { return }

        isRewriting = true
        errorMessage = nil

        do {
            rewrittenText = try await RewriteService.shared.rewrite(
                text: originalText,
                style: selectedStyle,
                model: settings.selectedModel
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isRewriting = false
    }

    private func insertText() {
        let textToInsert = rewrittenText.isEmpty ? originalText : rewrittenText
        onInsert(textToInsert)
    }
}

// MARK: - Compact Style Button

struct CompactStyleButton: View {
    let style: RewriteStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: style.icon)
                    .font(.system(size: 11))
                Text(style.displayName)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.purple : Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Window Controller

class ReviewWindowController {
    static let shared = ReviewWindowController()
    private var window: NSWindow?

    @MainActor
    func show(text: String) {
        // Close existing window if any
        window?.close()

        let contentView = ReviewWindowView(
            text: text,
            appState: AppState.shared,
            onInsert: { [weak self] text in
                self?.insertAndClose(text)
            },
            onCancel: { [weak self] in
                self?.close()
            }
        )

        let hostingView = NSHostingView(rootView: contentView)

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    func close() {
        window?.close()
        window = nil
    }

    @MainActor
    private func insertAndClose(_ text: String) {
        close()

        // Small delay to let window close, then paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            PasteboardManager.shared.pasteTextViaClipboard(text)
            HistoryManager.shared.add(text)
        }
    }
}
