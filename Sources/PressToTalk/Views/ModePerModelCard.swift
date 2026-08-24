import SwiftUI

/// Pins a speech model to each mode.
///
/// The trade-off genuinely differs per mode: direct paste goes straight into
/// your document so it wants the best accuracy you'll tolerate waiting for,
/// review is read before it lands, and translation *requires* a model trained
/// on the translate task — which the turbo models were not.
struct ModePerModelCard: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var localTranscription: LocalTranscriptionService

    private var installed: [String] {
        localTranscription.installedModels
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Model per mode", icon: "slider.horizontal.3")

            SettingsCard {
                VStack(spacing: 0) {
                    row(.directPaste, icon: "bolt.fill", title: "Direct Paste", tint: Theme.accentGreen)
                    divider
                    row(.review, icon: "wand.and.stars", title: "Review", tint: Theme.accentPurple)
                    divider
                    row(.translation, icon: "globe", title: "Translate", tint: Theme.accentBlue)
                }
            }

            if installed.count < 2 {
                hint("Install a second model in the library above to give a mode its own.")
            } else if translationUsesTurbo {
                hint("Turbo models can't translate — Translate will fall back to another installed model.",
                     warning: true)
            } else {
                hint("Only the two most recently used models stay in memory; switching to a third reloads it.")
            }
        }
    }

    private var divider: some View {
        Divider().background(Theme.divider).padding(.leading, 58)
    }

    private var translationUsesTurbo: Bool {
        guard let model = settings.modelOverride(for: .translation) else { return false }
        return !localTranscription.supportsTranslation(model)
    }

    private func row(_ mode: CurrentRecordingMode, icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.16)).frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Text(subtitle(for: mode))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }

            Spacer()

            Picker("", selection: binding(for: mode)) {
                Text("Same as main").tag("")
                ForEach(installed, id: \.self) { model in
                    Text(label(for: model, mode: mode)).tag(model)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 190)
        }
        .padding(14)
    }

    private func label(for model: String, mode: CurrentRecordingMode) -> String {
        let name = localTranscription.modelDisplayName[model] ?? model
        if mode == .translation && !localTranscription.supportsTranslation(model) {
            return "\(name) — no translate"
        }
        return name
    }

    private func subtitle(for mode: CurrentRecordingMode) -> String {
        if let model = settings.modelOverride(for: mode) {
            let name = localTranscription.modelDisplayName[model] ?? model
            return localTranscription.isModelDownloaded(model)
                ? "Using \(name)"
                : "\(name) not installed — falls back to main"
        }
        let main = localTranscription.modelDisplayName[localTranscription.selectedModel]
            ?? localTranscription.selectedModel
        return "Using main model (\(main))"
    }

    private func binding(for mode: CurrentRecordingMode) -> Binding<String> {
        Binding(
            get: { settings.modelOverride(for: mode) ?? "" },
            set: { settings.setModelOverride($0.isEmpty ? nil : $0, for: mode) }
        )
    }

    private func hint(_ text: String, warning: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: warning ? "exclamationmark.triangle.fill" : "info.circle")
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11))
            Spacer()
        }
        .foregroundColor(warning ? Theme.accentOrange : Theme.textTertiary)
        .padding(.horizontal, 4)
    }
}
