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
    static let dailyActivityName = "screenBudget-approx-v1"
    static let thresholdPrefix = "dailyUsage-"
    static let armedAtKey = "widgetDiagnosticArmedAt"
    static let diagnosticLogKey = "widgetDiagnosticLog"
    static let monitorStatusKey = "widgetDiagnosticMonitorStatus"
    static let lastCheckKey = "widgetDiagnosticLastChecked"

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

        let savedName = defaults.string(forKey: Self.activeActivityKey)
        let existingName = savedName?.hasPrefix(Self.dailyActivityName) == true ? savedName! : Self.dailyActivityName
        let activity = DeviceActivityName(existingName)

        // Check the actual DeviceActivityCenter, not just a persisted flag:
        // a previous startMonitoring call may have failed or been stopped.
        if center.activities.contains(activity) {
            defaults.set(existingName, forKey: Self.activeActivityKey)
            defaults.set("Registered", forKey: Self.monitorStatusKey)
            defaults.set(Date(), forKey: Self.lastCheckKey)
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
        // once when migrating to this new threshold configuration so old values cannot survive the test.
        if savedName?.hasPrefix(Self.dailyActivityName) != true {
            defaults.set(0.0, forKey: Self.usageKey)
            defaults.set(Calendar.current.startOfDay(for: Date()),
                         forKey: Self.usageDateKey)
            defaults.set([String](), forKey: Self.diagnosticLogKey)
            defaults.removeObject(forKey: "widgetDiagnosticLastCallback")
            defaults.removeObject(forKey: "widgetDiagnosticLastEntry")
            WidgetCenter.shared.reloadTimelines(ofKind: "ScreenBudgetWidget")
        }

        // Rolling five-minute checkpoint; each accepted callback re-arms
        // a fresh generation in the monitor extension.
        let events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [
            DeviceActivityEvent.Name("dailyUsage-5"): DeviceActivityEvent(
                threshold: DateComponents(minute: 5),
                includesPastActivity: false
            )
        ]
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        let armedAt = Date()
        defaults.set(armedAt, forKey: Self.armedAtKey)
        defaults.set(0, forKey: "widgetMonitorRecoveryCount")
        defaults.removeObject(forKey: "widgetMonitorLastRecovery")
        let generation = defaults.integer(forKey: "widgetMonitorGeneration") + 1
        defaults.set(generation, forKey: "widgetMonitorGeneration")
        let replacementName = Self.dailyActivityName + "-g" + String(generation)
        defaults.set(replacementName, forKey: Self.activeActivityKey)

        do {
            try center.startMonitoring(DeviceActivityName(replacementName), during: schedule, events: events)
            NSLog("ScreenBudget estimate START activity=%@ at=%@", replacementName, armedAt.description)
            defaults.set("Monitoring (estimate)", forKey: Self.monitorStatusKey)
            defaults.set(Date(), forKey: Self.lastCheckKey)
            print("ScreenBudget rolling five-minute estimate started")
        } catch {
            defaults.removeObject(forKey: Self.activeActivityKey)
            defaults.set("Start failed: \(error)", forKey: Self.monitorStatusKey)
            defaults.set(Date(), forKey: Self.lastCheckKey)
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
