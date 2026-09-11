import SwiftUI

/// Per-key setup: what each hotkey does, in which language, with which model.
///
/// Keys are independent slots rather than fixed roles, so two of them can both
/// dictate straight to the cursor and differ only in language — hold one key
/// and speak Russian, hold another and speak English.
struct HotkeySetupCard: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var localTranscription: LocalTranscriptionService
    @ObservedObject var license = LicenseManager.shared

    private var installed: [String] { localTranscription.installedModels }

    private func tint(for mode: CurrentRecordingMode) -> Color {
        switch mode {
        case .directPaste: return Theme.accentGreen
        case .review: return Theme.accentPurple
        case .translation: return Theme.accentBlue
        case .translateText: return Theme.accentCyan
        }
    }

    private func icon(for mode: CurrentRecordingMode) -> String {
        switch mode {
        case .directPaste: return "bolt.fill"
        case .review: return "wand.and.stars"
        case .translation: return "globe"
        case .translateText: return "character.cursor.ibeam"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Keys", icon: "keyboard.fill")

            SettingsCard {
                VStack(spacing: 0) {
                    columnHeader
                    Divider().background(Theme.divider)

                    ForEach(Array(HotkeyOption.allCases.enumerated()), id: \.element) { index, key in
                        if index > 0 {
                            Divider().background(Theme.divider).padding(.leading, 58)
                        }
                        row(for: key)
                    }
                }
            }

            hints
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 10) {
            Text("KEY").frame(width: 132, alignment: .leading)
            Text("DOES").frame(width: 140, alignment: .leading)
            Text("LANGUAGE").frame(width: 132, alignment: .leading)
            Text("MODEL").frame(width: 158, alignment: .leading)
            Spacer(minLength: 0)
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .tracking(1)
        .foregroundColor(Theme.textQuaternary)
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func row(for key: HotkeyOption) -> some View {
        let mode = settings.action(for: key)
        let locked = mode.requiresPro && !license.isPro

        return HStack(spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint(for: mode).opacity(0.16)).frame(width: 32, height: 32)
                    Image(systemName: icon(for: mode))
                        .font(.system(size: 14))
                        .foregroundColor(tint(for: mode))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(key.displayName)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.textPrimary)
                    if locked {
                        Text("Pro")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.accentYellow))
                    }
                }
            }
            .frame(width: 132, alignment: .leading)

            Picker("", selection: actionBinding(for: key)) {
                ForEach(CurrentRecordingMode.allCases, id: \.self) { mode in
                    Text(mode.shortName).tag(mode.storageKey)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 140)

            if mode == .translateText {
                // This key's language slot is the *target*: the source is
                // whatever was typed.
                Picker("", selection: targetLanguageBinding(for: key)) {
                    Text("Main target (\(settings.targetLanguage.displayName))").tag("")
                    ForEach(TranslationLanguage.allCases) { lang in
                        Text("\(lang.flag) \(lang.displayName)").tag(lang.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 132)

                Text("No model — works on typed text")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
                    .frame(width: 158, alignment: .leading)
            } else {
                Picker("", selection: languageBinding(for: key)) {
                    Text("Main language").tag("")
                    ForEach(WhisperLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 132)

                Picker("", selection: modelBinding(for: key)) {
                    Text("Main model").tag("")
                    ForEach(installed, id: \.self) { model in
                        Text(modelLabel(model, mode: mode)).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 158)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .opacity(locked ? 0.55 : 1)
    }

    private func modelLabel(_ model: String, mode: CurrentRecordingMode) -> String {
        let name = localTranscription.modelDisplayName[model] ?? model
        if mode == .translation && !localTranscription.supportsTranslation(model) {
            return "\(name) — can't translate"
        }
        return name
    }

    private func actionBinding(for key: HotkeyOption) -> Binding<String> {
        Binding(
            get: { settings.action(for: key).storageKey },
            set: { raw in
                if let mode = CurrentRecordingMode(storageKey: raw) {
                    settings.setAction(mode, for: key)
                }
            }
        )
    }

    private func modelBinding(for key: HotkeyOption) -> Binding<String> {
        Binding(
            get: { settings.modelOverride(for: key) ?? "" },
            set: { settings.setModelOverride($0.isEmpty ? nil : $0, for: key) }
        )
    }

    private func targetLanguageBinding(for key: HotkeyOption) -> Binding<String> {
        Binding(
            get: { settings.languagePerKey[key.rawValue].flatMap { TranslationLanguage(rawValue: $0) }?.rawValue ?? "" },
            set: { settings.setTargetLanguageOverride($0.isEmpty ? nil : TranslationLanguage(rawValue: $0), for: key) }
        )
    }

    private func languageBinding(for key: HotkeyOption) -> Binding<String> {
        Binding(
            get: { settings.languageOverride(for: key)?.rawValue ?? "" },
            set: { settings.setLanguageOverride($0.isEmpty ? nil : WhisperLanguage(rawValue: $0), for: key) }
        )
    }

    @ViewBuilder
    private var hints: some View {
        VStack(alignment: .leading, spacing: 7) {
            hint("Set two keys to Paste with different languages to dictate in either language without changing settings.")

            hint("Translate text: type in your own language, tap the key, and the text in the field is replaced with the translation before you send it. Select part of the text to translate just that.")

            hint("Hold a Translate-text key for a moment to turn on Translate on Enter for the app in front: from then on a plain Enter there translates and sends. Shift+Enter sends as typed; hold again to turn off.")

            if let translateKey = HotkeyOption.allCases.first(where: {
                settings.action(for: $0) == .translation
            }), let model = settings.modelOverride(for: translateKey),
               !localTranscription.supportsTranslation(model) {
                hint("Turbo models can't translate — that key will fall back to another installed model.", warning: true)
            }

            if !HotkeyOption.allCases.contains(where: { settings.action(for: $0) == .directPaste }) {
                hint("No key is set to Paste — nothing will type straight to the cursor.", warning: true)
            }

            hint("Naming a language is more accurate than auto-detect, and prevents the occasional wrong-language translation.")
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
