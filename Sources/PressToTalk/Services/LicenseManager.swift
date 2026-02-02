import Foundation

@MainActor
class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    private let licenseKeyKey = "licenseKey"
    private let dailyCountKey = "dailyTranscriptionCount"
    private let lastResetDateKey = "lastDailyResetDate"

    // Hardcoded license key for now (will be replaced with proper validation later)
    private static let validLicenseKeys = ["MANIKOSTO"]

    // Purchase URL
    static let purchaseURL = URL(string: "https://talkkey.io/#pricing")!

    // Free tier limits
    static let freeTranscriptionsPerDay = 25
    static let freeMaxRecordingSeconds = 60

    @Published var isPro: Bool = false
    @Published var dailyTranscriptionsUsed: Int = 0

    // Thread-safe check (reads directly from UserDefaults)
    nonisolated static func checkIsPro() -> Bool {
        if let savedKey = UserDefaults.standard.string(forKey: "licenseKey") {
            return validLicenseKeys.contains(savedKey.uppercased())
        }
        return false
    }

    private init() {
        // Check if user has a valid license
        if let savedKey = UserDefaults.standard.string(forKey: licenseKeyKey) {
            isPro = Self.validLicenseKeys.contains(savedKey.uppercased())
        }

        // Load daily count and reset if new day
        resetDailyCountIfNeeded()
        dailyTranscriptionsUsed = UserDefaults.standard.integer(forKey: dailyCountKey)
    }

    // MARK: - License Activation

    func activateLicense(key: String) -> Bool {
        let normalizedKey = key.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if Self.validLicenseKeys.contains(normalizedKey) {
            UserDefaults.standard.set(normalizedKey, forKey: licenseKeyKey)
            isPro = true
            return true
        }
        return false
    }

    func deactivateLicense() {
        UserDefaults.standard.removeObject(forKey: licenseKeyKey)
        isPro = false
    }

    var currentLicenseKey: String? {
        UserDefaults.standard.string(forKey: licenseKeyKey)
    }

    // MARK: - Usage Limits

    var canTranscribe: Bool {
        if isPro { return true }
        return dailyTranscriptionsUsed < Self.freeTranscriptionsPerDay
    }

    var remainingTranscriptions: Int {
        if isPro { return Int.max }
        return max(0, Self.freeTranscriptionsPerDay - dailyTranscriptionsUsed)
    }

    var maxRecordingSeconds: Int {
        if isPro { return 300 } // 5 minutes for Pro
        return Self.freeMaxRecordingSeconds
    }

    func recordTranscription() {
        guard !isPro else { return }

        resetDailyCountIfNeeded()
        dailyTranscriptionsUsed += 1
        UserDefaults.standard.set(dailyTranscriptionsUsed, forKey: dailyCountKey)
    }

    private func resetDailyCountIfNeeded() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let lastReset = UserDefaults.standard.object(forKey: lastResetDateKey) as? Date {
            let lastResetDay = calendar.startOfDay(for: lastReset)
            if today > lastResetDay {
                // New day - reset count
                dailyTranscriptionsUsed = 0
                UserDefaults.standard.set(0, forKey: dailyCountKey)
                UserDefaults.standard.set(today, forKey: lastResetDateKey)
            }
        } else {
            // First run
            UserDefaults.standard.set(today, forKey: lastResetDateKey)
        }
    }

    // MARK: - Feature Access

    var canUseTranslation: Bool {
        isPro
    }

    var canUseReviewMode: Bool {
        isPro
    }

    var canUseCloudMode: Bool {
        isPro
    }

    var canDownloadModels: Bool {
        isPro
    }
}
