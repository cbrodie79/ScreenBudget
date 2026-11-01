import Foundation
import FamilyControls
import DeviceActivity
import WidgetKit

final class ScreenTimeManager {

    static let shared = ScreenTimeManager()

    static let appGroup = "group.com.example.ScreenGauge"
    static let usageKey = "widgetUsageMinutes"
    static let usageDateKey = "widgetUsageDate"
    static let activeActivityKey = "widgetMonitorActivity"

    // New name separates the cumulative monitor from the old, restarting
    // five-minute monitors. One repeating schedule covers the whole day.
    static let dailyActivityName = "screenBudget-diagnostic-v3"
    static let thresholdPrefix = "dailyUsage-"
    static let armedAtKey = "widgetDiagnosticArmedAt"
    static let diagnosticLogKey = "widgetDiagnosticLog"

    private let center = DeviceActivityCenter()

    private init() {}

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared
                .requestAuthorization(for: .individual)
            startMonitoringIfNeeded()
        } catch {
            print("Screen Time authorization failed: \(error)")
        }
    }

    func startMonitoringIfNeeded() {
        guard let defaults = UserDefaults(suiteName: Self.appGroup) else {
            return
        }

        resetForNewDayIfNeeded(defaults: defaults)

        let activity = DeviceActivityName(Self.dailyActivityName)

        // Check the actual DeviceActivityCenter, not just a persisted flag:
        // a previous startMonitoring call may have failed or been stopped.
        if center.activities.contains(activity) {
            defaults.set(Self.dailyActivityName, forKey: Self.activeActivityKey)
            return
        }

        // Migrate away from any previously registered per-bucket monitors.
        // Do not stop unrelated monitors belonging to other features.
        let legacyActivities = center.activities.filter {
            $0.rawValue.hasPrefix("screenBudget-") && $0 != activity
        }
        if !legacyActivities.isEmpty {
            center.stopMonitoring(legacyActivities)
        }

        // This is a new diagnostic monitor. Clear the old inflated counter
        // once when migrating from v2 so old values cannot survive the test.
        if defaults.string(forKey: Self.activeActivityKey) != Self.dailyActivityName {
            defaults.set(0.0, forKey: Self.usageKey)
            defaults.set(Calendar.current.startOfDay(for: Date()),
                         forKey: Self.usageDateKey)
            defaults.set([String](), forKey: Self.diagnosticLogKey)
            WidgetCenter.shared.reloadTimelines(ofKind: "ScreenBudgetWidget")
        }

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]

        // Each event fires when total daily activity passes its threshold.
        // An event includes usage before ScreenBudget was opened today.
        for minutes in stride(from: 5, through: 30, by: 5) {
            let name = DeviceActivityEvent.Name(
                "\(Self.thresholdPrefix)\(minutes)"
            )
            events[name] = DeviceActivityEvent(
                threshold: DateComponents(
                    hour: minutes / 60,
                    minute: minutes % 60
                ),
                includesPastActivity: false
            )
        }

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        // Keep a wall-clock anchor for diagnosing unexpectedly early events.
        // IncludesPastActivity is false for this experiment: it intentionally
        // excludes usage before monitoring starts.
        let armedAt = Date()
        defaults.set(armedAt, forKey: Self.armedAtKey)
        // A threshold callback may arrive during startMonitoring.
        defaults.set(Self.dailyActivityName, forKey: Self.activeActivityKey)

        do {
            try center.startMonitoring(activity, during: schedule, events: events)
            NSLog("ScreenBudgetDiagnostic START activity=%@ at=%@ events=5,10,15,20,25,30 includesPastActivity=false", Self.dailyActivityName, armedAt.description)
            print("ScreenBudget diagnostic monitor started with 6 thresholds")
        } catch {
            defaults.removeObject(forKey: Self.activeActivityKey)
            NSLog("ScreenBudgetDiagnostic START_FAILED: %@", String(describing: error))
            print("Unable to start ScreenBudget daily monitor: \(error)")
        }
    }

    private func resetForNewDayIfNeeded(defaults: UserDefaults) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let savedDate = defaults.object(forKey: Self.usageDateKey) as? Date,
           calendar.isDate(savedDate, inSameDayAs: today) {
            return
        }

        defaults.set(0.0, forKey: Self.usageKey)
        defaults.set(today, forKey: Self.usageDateKey)
        // Keep the repeating monitor registered across midnight.
        WidgetCenter.shared.reloadTimelines(ofKind: "ScreenBudgetWidget")
    }
}
