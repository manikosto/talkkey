import Foundation
import Combine

@MainActor
class UsageTracker: ObservableObject {
    static let shared = UsageTracker()

    private let firstLaunchKey = "firstLaunchDate"
    private let trialDays: Int = 3

    // Stats keys
    private let weeklyWordsKey = "weeklyWordsTranscribed"
    private let weeklySecondsRecordedKey = "weeklySecondsRecorded"
    private let weekStartKey = "statsWeekStart"
    private let totalTranscriptionsKey = "totalTranscriptions"

    // Average typing speed: ~40 WPM, speaking: ~150 WPM
    // So speaking saves roughly 2.75x the time
    private let typingWPM: Double = 40
    private let speakingWPM: Double = 150

    // Published stats for real-time updates
    @Published private(set) var currentWeeklyWords: Int = 0
    @Published private(set) var currentWeeklySecondsRecorded: Double = 0
    @Published private(set) var currentTotalTranscriptions: Int = 0

    var firstLaunchDate: Date? {
        get {
            guard let timestamp = UserDefaults.standard.object(forKey: firstLaunchKey) as? TimeInterval else {
                return nil
            }
            return Date(timeIntervalSince1970: timestamp)
        }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: firstLaunchKey)
            }
        }
    }

    init() {
        // Set first launch date if not set
        if firstLaunchDate == nil {
            firstLaunchDate = Date()
        }
        // Load initial stats
        refreshStats()
    }

    func refreshStats() {
        resetWeeklyStatsIfNeeded()
        currentWeeklyWords = UserDefaults.standard.integer(forKey: weeklyWordsKey)
        currentWeeklySecondsRecorded = UserDefaults.standard.double(forKey: weeklySecondsRecordedKey)
        currentTotalTranscriptions = UserDefaults.standard.integer(forKey: totalTranscriptionsKey)
    }

    var trialEndDate: Date {
        guard let firstLaunch = firstLaunchDate else {
            return Date().addingTimeInterval(TimeInterval(trialDays * 24 * 60 * 60))
        }
        return firstLaunch.addingTimeInterval(TimeInterval(trialDays * 24 * 60 * 60))
    }

    var remainingDays: Int {
        let remaining = Calendar.current.dateComponents([.day], from: Date(), to: trialEndDate).day ?? 0
        return max(0, remaining)
    }

    var remainingHours: Int {
        let remaining = Calendar.current.dateComponents([.hour], from: Date(), to: trialEndDate).hour ?? 0
        return max(0, remaining)
    }

    var isTrialExpired: Bool {
        Date() >= trialEndDate
    }

    /// Progress from 0.0 (just started) to 1.0 (expired)
    var trialProgress: Double {
        if isTrialExpired { return 1.0 }
        guard let firstLaunch = firstLaunchDate else { return 0 }
        let totalDuration = TimeInterval(trialDays * 24 * 60 * 60)
        let elapsed = Date().timeIntervalSince(firstLaunch)
        return min(1.0, max(0.0, elapsed / totalDuration))
    }

    /// Remaining progress (1.0 = full, 0.0 = expired)
    var remainingProgress: Double {
        1.0 - trialProgress
    }

    var isLimitReached: Bool {
        isTrialExpired
    }

    var formattedRemaining: String {
        if isTrialExpired {
            return "Expired"
        }

        let days = remainingDays
        if days > 0 {
            return "\(days) day\(days == 1 ? "" : "s") left"
        }

        let hours = remainingHours
        if hours > 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s") left"
        }

        return "< 1 hour left"
    }

    // MARK: - Weekly Stats

    private var weekStart: Date {
        get {
            if let timestamp = UserDefaults.standard.object(forKey: weekStartKey) as? TimeInterval {
                return Date(timeIntervalSince1970: timestamp)
            }
            let start = Calendar.current.startOfWeek(for: Date())
            UserDefaults.standard.set(start.timeIntervalSince1970, forKey: weekStartKey)
            return start
        }
        set {
            UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: weekStartKey)
        }
    }

    private func resetWeeklyStatsIfNeeded() {
        let currentWeekStart = Calendar.current.startOfWeek(for: Date())
        if weekStart < currentWeekStart {
            weekStart = currentWeekStart
            UserDefaults.standard.set(0, forKey: weeklyWordsKey)
            UserDefaults.standard.set(0.0, forKey: weeklySecondsRecordedKey)
        }
    }

    var weeklyWords: Int {
        currentWeeklyWords
    }

    var weeklySecondsRecorded: Double {
        currentWeeklySecondsRecorded
    }

    var totalTranscriptions: Int {
        currentTotalTranscriptions
    }

    /// Estimated minutes saved vs typing
    var weeklyMinutesSaved: Int {
        let words = Double(currentWeeklyWords)
        let typingTime = words / typingWPM  // minutes to type
        let speakingTime = words / speakingWPM  // minutes to speak
        let saved = typingTime - speakingTime
        return max(0, Int(saved))
    }

    /// Average words per minute of recording
    var averageWPM: Int {
        guard currentWeeklySecondsRecorded > 0 else { return 0 }
        let minutes = currentWeeklySecondsRecorded / 60.0
        return Int(Double(currentWeeklyWords) / minutes)
    }

    func recordTranscription(text: String, recordingDuration: TimeInterval) {
        resetWeeklyStatsIfNeeded()

        let wordCount = text.split(separator: " ").count

        let newWords = currentWeeklyWords + wordCount
        UserDefaults.standard.set(newWords, forKey: weeklyWordsKey)
        currentWeeklyWords = newWords

        let newSeconds = currentWeeklySecondsRecorded + recordingDuration
        UserDefaults.standard.set(newSeconds, forKey: weeklySecondsRecordedKey)
        currentWeeklySecondsRecorded = newSeconds

        let newTotal = currentTotalTranscriptions + 1
        UserDefaults.standard.set(newTotal, forKey: totalTranscriptionsKey)
        currentTotalTranscriptions = newTotal

        AppState.shared.updateUsageInfo()
    }

    // Legacy methods for compatibility
    func startRecording() {}
    func stopRecording() {
        Task { @MainActor in
            AppState.shared.updateUsageInfo()
        }
    }
    func cancelRecording() {}

    func resetTrial() {
        firstLaunchDate = Date()
        Task { @MainActor in
            AppState.shared.updateUsageInfo()
        }
    }
}

// MARK: - Calendar Extension

extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let components = self.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? date
    }
}
