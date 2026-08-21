import SwiftUI

struct DictionaryTab: View {
    @ObservedObject var dictionary = DictionaryManager.shared
    @State private var newTerm = ""
    @State private var newVariants = ""
    @State private var editing: DictionaryEntry?
    @FocusState private var termFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                addCard

                if dictionary.entries.isEmpty {
                    emptyState
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Your terms (\(dictionary.entries.count))", icon: "text.book.closed.fill")
                        VStack(spacing: 8) {
                            ForEach(dictionary.entries) { entry in
                                DictionaryRow(
                                    entry: entry,
                                    onToggle: { toggled in dictionary.update(toggled) },
                                    onDelete: { dictionary.remove(entry) },
                                    onEdit: { editing = entry }
                                )
                            }
                        }
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(32)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $editing) { entry in
            DictionaryEditSheet(entry: entry) { updated in
                dictionary.update(updated)
                editing = nil
            } onCancel: {
                editing = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Dictionary", icon: "character.book.closed.fill")

            SettingsCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Theme.accentPurple.opacity(0.2))
                                .frame(width: 32, height: 32)
                            Image(systemName: "wand.and.sparkles")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.accentPurple)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Custom vocabulary")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.textPrimary)
                            Text("Names, brands and jargon TalkKey should always spell correctly")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textSecondary)
                        }

                        Spacer()

                        Toggle("", isOn: $dictionary.isEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    .padding(14)

                    Divider()
                        .background(Theme.cardBorder)
                        .padding(.leading, 58)

                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Theme.accentCyan.opacity(0.2))
                                .frame(width: 32, height: 32)
                            Image(systemName: "text.magnifyingglass")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.accentCyan)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fix near-misses")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.textPrimary)
                            Text("Also repair words that came out almost right")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textSecondary)
                        }

                        Spacer()

                        Toggle("", isOn: $dictionary.fuzzyEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(!dictionary.isEnabled)
                    }
                    .padding(14)
                    .opacity(dictionary.isEnabled ? 1 : 0.45)
                }
            }
        }
    }

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Add a term", icon: "plus.circle.fill")

            SettingsCard {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        field(placeholder: "Term — e.g. Playwright", text: $newTerm)
                            .focused($termFocused)
                            .onSubmit(addTerm)

                        Button(action: addTerm) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Add")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(Theme.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(newTerm.isEmpty ? Theme.subtleFillStrong : Theme.accentPurple)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    field(placeholder: "Misheard as (optional) — плейрайт, play right", text: $newVariants)
                        .onSubmit(addTerm)

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                        Text("Leave the second field empty and TalkKey will still catch close misspellings on its own.")
                            .font(.system(size: 11))
                        Spacer()
                    }
                    .foregroundColor(Theme.textTertiary)
                }
                .padding(14)
            }
        }
    }

    private func field(placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundColor(Theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Theme.subtleFill)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.cardBorder, lineWidth: 1)
            )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 40))
                .foregroundColor(Theme.subtleFillStrong)
            Text("No terms yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.textTertiary)
            Text("Add the words TalkKey keeps getting wrong — product names,\npeople, technical terms.")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func addTerm() {
        let trimmed = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        dictionary.add(term: trimmed, variants: newVariants)
        newTerm = ""
        newVariants = ""
        termFocused = true
    }
}

// MARK: - Row

private struct DictionaryRow: View {
    let entry: DictionaryEntry
    let onToggle: (DictionaryEntry) -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                var copy = entry
                copy.isEnabled.toggle()
                onToggle(copy)
            }) {
                Image(systemName: entry.isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundColor(entry.isEnabled ? Theme.accentGreen : Theme.textQuaternary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.term)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(entry.isEnabled ? .white : Theme.textTertiary)

                if !entry.variants.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 9))
                        Text(entry.variantsText)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .foregroundColor(Theme.textTertiary)
                }
            }

            Spacer()

            if isHovering {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.accentRed.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(isHovering ? 0.08 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )
        )
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

// MARK: - Edit sheet

private struct DictionaryEditSheet: View {
    @State var entry: DictionaryEntry
    let onSave: (DictionaryEntry) -> Void
    let onCancel: () -> Void
    @State private var variantsText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit term")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Term")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                TextField("", text: $entry.term)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
                    .padding(9)
                    .background(Theme.cardBorder)
                    .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Misheard as (comma separated)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                TextField("", text: $variantsText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)
                    .padding(9)
                    .background(Theme.cardBorder)
                    .cornerRadius(8)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                Button(action: {
                    var updated = entry
                    updated.variantsText = variantsText
                    onSave(updated)
                }) {
                    Text("Save")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Theme.accentPurple)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Theme.contentBackground)
        .onAppear { variantsText = entry.variantsText }
    }
}
