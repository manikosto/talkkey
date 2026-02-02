import Foundation

class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    private let historyKey = "transcriptionHistory"
    private let maxItems = 50

    @Published var items: [HistoryItem] = []

    init() {
        loadHistory()
    }

    func add(_ text: String) {
        let item = HistoryItem(text: text, date: Date())
        items.insert(item, at: 0)

        // Limit history size
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }

        saveHistory()
    }

    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        saveHistory()
    }

    func clear() {
        items.removeAll()
        saveHistory()
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) else {
            return
        }
        items = decoded
    }

    private func saveHistory() {
        guard let encoded = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(encoded, forKey: historyKey)
    }
}

struct HistoryItem: Identifiable, Codable {
    let id: UUID
    let text: String
    let date: Date

    init(text: String, date: Date) {
        self.id = UUID()
        self.text = text
        self.date = date
    }

    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
