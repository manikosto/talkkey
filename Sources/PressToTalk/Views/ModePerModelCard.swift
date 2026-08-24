import SwiftUI

/// Per-mode setup: each hotkey gets its own speech model and language.
///
/// Both are worth pinning per mode. The model trade-off differs (translation
/// *requires* a model trained on the translate task, which the turbo models
/// were not), and naming the language is more reliable than auto-detect — a
/// wrong guess makes Whisper translate into the language it guessed instead of
/// transcribing what you said.
struct ModePerModelCard: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var localTranscription: LocalTranscriptionService

    private var installed: [String] { localTranscription.installedModels }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Per-mode setup", icon: "slider.horizontal.3")

            SettingsCard {
                VStack(spacing: 0) {
                    columnHeader
                    Divider().background(Theme.divider)
                    row(.directPaste, icon: "bolt.fill", title: "Direct Paste",
                        hotkey: settings.selectedHotkey.displayName, tint: Theme.accentGreen)
                    Divider().background(Theme.divider).padding(.leading, 58)
                    row(.review, icon: "wand.and.stars", title: "Review",
                        hotkey: settings.secondaryHotkey.displayName, tint: Theme.accentPurple)
                    Divider().background(Theme.divider).padding(.leading, 58)
                    row(.translation, icon: "globe", title: "Translate",
                        hotkey: "Fn", tint: Theme.accentBlue)
                }
            }

            hints
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 10) {
            Text("MODE")
                .frame(width: 168, alignment: .leading)
            Text("MODEL")
                .frame(width: 168, alignment: .leading)
            Text("LANGUAGE")
                .frame(width: 132, alignment: .leading)
            Spacer(minLength: 0)
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .tracking(1)
        .foregroundColor(Theme.textQuaternary)
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func row(_ mode: CurrentRecordingMode, icon: String, title: String,
                     hotkey: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.16)).frame(width: 32, height: 32)
                    Image(systemName: icon).font(.system(size: 14)).foregroundColor(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                    Text(hotkey)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(tint)
                }
            }
            .frame(width: 168, alignment: .leading)

            Picker("", selection: modelBinding(for: mode)) {
                Text("Main model").tag("")
                ForEach(installed, id: \.self) { model in
                    Text(modelLabel(model, mode: mode)).tag(model)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 168)

            Picker("", selection: languageBinding(for: mode)) {
                Text("Main language").tag("")
                ForEach(WhisperLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang.rawValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 132)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func modelLabel(_ model: String, mode: CurrentRecordingMode) -> String {
        let name = localTranscription.modelDisplayName[model] ?? model
        if mode == .translation && !localTranscription.supportsTranslation(model) {
            return "\(name) — can't translate"
        }
        return name
    }

    private func modelBinding(for mode: CurrentRecordingMode) -> Binding<String> {
        Binding(
            get: { settings.modelOverride(for: mode) ?? "" },
            set: { settings.setModelOverride($0.isEmpty ? nil : $0, for: mode) }
        )
    }

    private func languageBinding(for mode: CurrentRecordingMode) -> Binding<String> {
        Binding(
            get: { settings.languageOverride(for: mode)?.rawValue ?? "" },
            set: { settings.setLanguageOverride($0.isEmpty ? nil : WhisperLanguage(rawValue: $0), for: mode) }
        )
    }

    @ViewBuilder
    private var hints: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let model = settings.modelOverride(for: .translation),
               !localTranscription.supportsTranslation(model) {
                hint("Turbo models can't translate — Translate will fall back to another installed model.",
                     warning: true)
            }
            if installed.count < 2 {
                hint("Install a second model in the library above to give a mode its own.")
            }
            hint("Pinning a language is more accurate than auto-detect, and prevents the occasional wrong-language translation.")
            hint("The two most recently used models stay in memory, so switching modes doesn't reload.")
        }
    }

    private func hint(_ text: String, warning: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: warning ? "exclamationmark.triangle.fill" : "info.circle")
                .font(.system(size: 10))
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundColor(warning ? Theme.accentOrange : Theme.textTertiary)
        .padding(.horizontal, 4)
    }
}
