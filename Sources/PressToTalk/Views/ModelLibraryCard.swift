import SwiftUI

/// Every speech model in one list: what is installed, what it costs on disk,
/// and per-model download / activate / delete.
struct ModelLibraryCard: View {
    @ObservedObject var localTranscription: LocalTranscriptionService
    @State private var busyModel: String?
    @State private var error: String?
    @State private var pendingDeletion: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            VStack(spacing: 0) {
                ForEach(Array(localTranscription.availableModels.enumerated()), id: \.element) { index, model in
                    if index > 0 {
                        Divider().background(Theme.divider).padding(.leading, 52)
                    }
                    row(for: model)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder, lineWidth: 1))
            )

            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.accentRed)
            }
        }
        .alert("Delete this model?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
            Button("Delete", role: .destructive) {
                if let model = pendingDeletion { delete(model) }
                pendingDeletion = nil
            }
        } message: {
            if let model = pendingDeletion {
                Text("\(localTranscription.modelDisplayName[model] ?? model) will be removed from this Mac. You can download it again at any time.")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            SectionHeader(title: "Speech models", icon: "internaldrive.fill")
            Spacer()
            if localTranscription.totalDiskUsage > 0 {
                Text("\(LocalTranscriptionService.formatBytes(localTranscription.totalDiskUsage)) on disk")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }
        }
    }

    private func row(for model: String) -> some View {
        let isInstalled = localTranscription.isModelDownloaded(model)
        let isActive = localTranscription.isModelLoaded && localTranscription.selectedModel == model
        let isBusy = busyModel == model

        return HStack(spacing: 12) {
            statusIcon(isInstalled: isInstalled, isActive: isActive, isBusy: isBusy)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(localTranscription.modelDisplayName[model] ?? model)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textPrimary)

                    if isActive {
                        Text("ACTIVE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.accentGreen))
                    }
                }

                Text(subtitle(model: model, isInstalled: isInstalled, isActive: isActive, isBusy: isBusy))
                    .font(.system(size: 11))
                    .foregroundColor(isBusy ? Theme.accentOrange : Theme.textTertiary)
            }

            Spacer()

            actions(model: model, isInstalled: isInstalled, isActive: isActive, isBusy: isBusy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func statusIcon(isInstalled: Bool, isActive: Bool, isBusy: Bool) -> some View {
        let tint = isActive ? Theme.accentGreen : (isInstalled ? Theme.accentBlue : Theme.textQuaternary)
        return ZStack {
            Circle()
                .fill(tint.opacity(0.14))
                .frame(width: 30, height: 30)

            if isBusy {
                if localTranscription.isDownloading && localTranscription.downloadProgress > 0 {
                    ProgressRing(progress: localTranscription.downloadProgress, size: 16, color: Theme.accentOrange)
                } else {
                    Spinner(size: 16, color: Theme.accentOrange, lineWidth: 1.8)
                }
            } else {
                Image(systemName: isActive ? "checkmark" : (isInstalled ? "internaldrive" : "arrow.down"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(tint)
            }
        }
    }

    private func subtitle(model: String, isInstalled: Bool, isActive: Bool, isBusy: Bool) -> String {
        if isBusy {
            return isInstalled ? "Loading…" : "Downloading…"
        }
        let quality = localTranscription.modelQualityDescription[model] ?? ""
        if isInstalled {
            let size = localTranscription.diskSize(of: model).map(LocalTranscriptionService.formatBytes)
                ?? (localTranscription.modelSizeDescription[model] ?? "")
            return isActive ? "\(quality) · \(size)" : "Installed · \(size)"
        }
        return "\(quality) · \(localTranscription.modelSizeDescription[model] ?? "")"
    }

    @ViewBuilder
    private func actions(model: String, isInstalled: Bool, isActive: Bool, isBusy: Bool) -> some View {
        if isBusy {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                if !isInstalled {
                    actionButton("Download", icon: "arrow.down", tint: Theme.accentOrange) {
                        load(model)
                    }
                } else if !isActive {
                    actionButton("Use", icon: "bolt.fill", tint: Theme.accentGreen) {
                        load(model)
                    }
                }

                if isInstalled {
                    Button(action: { pendingDeletion = model }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.accentRed.opacity(0.8))
                            .frame(width: 26, height: 24)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accentRed.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("Delete from this Mac")
                }
            }
        }
    }

    private func actionButton(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(tint))
        }
        .buttonStyle(.plain)
    }

    private func load(_ model: String) {
        busyModel = model
        error = nil
        Task {
            do {
                try await localTranscription.loadModel(model)
            } catch {
                self.error = error.localizedDescription
            }
            busyModel = nil
        }
    }

    private func delete(_ model: String) {
        error = nil
        do {
            try localTranscription.deleteModel(model)
        } catch {
            self.error = "Couldn't delete: \(error.localizedDescription)"
        }
    }
}
