import Foundation
import Combine

/// One vocabulary entry.
///
/// `term` is the canonical spelling that should end up in the transcript.
/// `variants` are explicit mishearings ("plywright", "плейрайт") that are
/// replaced verbatim; when empty, fuzzy matching alone has to catch it.
struct DictionaryEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var term: String
    var variants: [String] = []
    var isEnabled: Bool = true

    var variantsText: String {
        get { variants.joined(separator: ", ") }
        set {
            variants = newValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }
}

/// Custom vocabulary applied to every transcription.
///
/// Two independent mechanisms, because neither is sufficient alone:
///
/// 1. **Priming** — the terms are handed to the model before decoding
///    (WhisperKit `promptTokens`, OpenAI `prompt`). This biases recognition
///    itself, so the word often comes out right in the first place.
/// 2. **Post-processing** — whatever still came out wrong is repaired in the
///    text: exact variant replacement first, then conservative fuzzy matching.
@MainActor
final class DictionaryManager: ObservableObject {
    static let shared = DictionaryManager()

    private let entriesKey = "customDictionaryEntries"
    private let enabledKey = "customDictionaryEnabled"
    private let fuzzyKey = "customDictionaryFuzzyEnabled"

    @Published var entries: [DictionaryEntry] = [] {
        didSet { persistEntries() }
    }

    /// Master switch — off means transcription behaves exactly as before.
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: enabledKey) }
    }

    /// Fuzzy repair can be disabled separately: priming plus exact variants is
    /// the risk-free subset, fuzzy is the part that can, rarely, overreach.
    @Published var fuzzyEnabled: Bool {
        didSet { UserDefaults.standard.set(fuzzyEnabled, forKey: fuzzyKey) }
    }

    /// Words shorter than this are never fuzzy-matched — at three characters
    /// almost everything is "similar" to everything else.
    private let minFuzzyLength = 4

    /// How many character edits may separate a word from a term before they
    /// stop counting as the same word.
    ///
    /// A budget beats a similarity ratio here: a ratio strict enough to
    /// protect five-letter words ("alure") rejects plausible long mishearings
    /// ("playwrite" → "playwright", three edits), and a ratio loose enough for
    /// the long ones starts rewriting short unrelated words.
    private func editBudget(forLength length: Int) -> Int {
        switch length {
        case ..<6: return 1
        case ..<10: return 2
        default: return 3
        }
    }

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
        fuzzyEnabled = UserDefaults.standard.object(forKey: fuzzyKey) as? Bool ?? true

        if let data = UserDefaults.standard.data(forKey: entriesKey),
           let decoded = try? JSONDecoder().decode([DictionaryEntry].self, from: data) {
            entries = decoded
        }
    }

    private func persistEntries() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: entriesKey)
    }

    // MARK: - Editing

    func add(term: String, variants: String = "") {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var entry = DictionaryEntry(term: trimmed)
        entry.variantsText = variants
        entries.insert(entry, at: 0)
    }

    func remove(_ entry: DictionaryEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    func update(_ entry: DictionaryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
    }

    private var activeEntries: [DictionaryEntry] {
        guard isEnabled else { return [] }
        return entries.filter { $0.isEnabled && !$0.term.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: - Priming

    /// Comma-separated terms fed to the model before decoding. Capped because
    /// the prompt competes with the audio for the model's context.
    func primingPrompt() -> String? {
        let terms = activeEntries.map(\.term)
        guard !terms.isEmpty else { return nil }

        var out: [String] = []
        var length = 0
        for term in terms {
            if length + term.count + 2 > 480 { break }
            out.append(term)
            length += term.count + 2
        }
        return out.isEmpty ? nil : out.joined(separator: ", ")
    }

    // MARK: - Post-processing

    /// Repairs a transcript: exact variant replacement, then optional fuzzy
    /// matching. Punctuation and spacing around each word are preserved.
    func apply(to text: String) -> String {
        let entries = activeEntries
        guard !entries.isEmpty, !text.isEmpty else { return text }

        var result = text

        // Pass 1 — explicit variants, longest first so multi-word variants win
        // over any single word they contain.
        let variantPairs = entries
            .flatMap { entry in entry.variants.map { (variant: $0, term: entry.term) } }
            .filter { $0.variant.count >= 2 }
            .sorted { $0.variant.count > $1.variant.count }

        for pair in variantPairs {
            result = replaceWholeWords(in: result, of: pair.variant, with: pair.term)
        }

        guard fuzzyEnabled else { return result }

        // Pass 2 — fuzzy repair, single words only. Multi-word terms are left
        // to the variant pass: sliding a fuzzy window over phrases is where
        // this kind of correction starts damaging correct text.
        let singleWordTerms = entries
            .map(\.term)
            .filter { !$0.contains(" ") && $0.count >= minFuzzyLength }
        guard !singleWordTerms.isEmpty else { return result }

        return rewriteWords(in: result) { word in
            let bare = word.trimmingCharacters(in: .punctuationCharacters)
            guard bare.count >= minFuzzyLength else { return nil }
            let lowerBare = bare.lowercased()

            // Same word, different casing — normalize it. Brand spelling
            // ("github" → "GitHub") is a main reason to keep a dictionary.
            if let canonical = singleWordTerms.first(where: { $0.lowercased() == lowerBare }) {
                return canonical == bare ? nil : word.replacingOccurrences(of: bare, with: canonical)
            }

            var best: (term: String, distance: Int)?
            for term in singleWordTerms {
                // Comparing across scripts is meaningless and produces
                // false matches between Cyrillic and Latin lookalikes.
                guard isSameScript(term, bare) else { continue }
                let lowerTerm = term.lowercased()

                // An inflection or plural of the term — "pytests", "Аллюра".
                // These are correct words the user did not ask us to touch;
                // rewriting them to the base form corrupts the sentence, and
                // in Russian that means mangling nearly every case ending.
                if lowerBare.count > lowerTerm.count, lowerBare.hasPrefix(lowerTerm) { continue }

                let budget = editBudget(forLength: max(lowerBare.count, lowerTerm.count))
                guard abs(lowerBare.count - lowerTerm.count) <= budget else { continue }

                let distance = levenshtein(Array(lowerBare), Array(lowerTerm))
                if distance <= budget, distance < (best?.distance ?? Int.max) {
                    best = (term, distance)
                }
            }

            guard let match = best else { return nil }
            return word.replacingOccurrences(of: bare, with: match.term)
        }
    }

    // MARK: - Text helpers

    /// Replaces whole-word occurrences, case-insensitively, without regex —
    /// terms are user input and would otherwise need escaping.
    private func replaceWholeWords(in text: String, of needle: String, with replacement: String) -> String {
        guard let pattern = try? NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: needle) + "(?![\\p{L}\\p{N}])",
            options: [.caseInsensitive]
        ) else { return text }

        let range = NSRange(text.startIndex..., in: text)
        return pattern.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }

    /// Applies `transform` to every whitespace-separated token, keeping the
    /// original separators intact.
    private func rewriteWords(in text: String, transform: (String) -> String?) -> String {
        var out = ""
        var current = ""

        func flush() {
            guard !current.isEmpty else { return }
            out += transform(current) ?? current
            current = ""
        }

        for char in text {
            if char.isWhitespace {
                flush()
                out.append(char)
            } else {
                current.append(char)
            }
        }
        flush()
        return out
    }

    private func isSameScript(_ a: String, _ b: String) -> Bool {
        func isCyrillic(_ s: String) -> Bool {
            s.unicodeScalars.contains { $0.value >= 0x0400 && $0.value <= 0x04FF }
        }
        return isCyrillic(a) == isCyrillic(b)
    }

    private func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,        // deletion
                    current[j - 1] + 1,     // insertion
                    previous[j - 1] + cost  // substitution
                )
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
