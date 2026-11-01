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
    static let dailyActivityName = "screenBudget-diagnostic-v7"
    static let thresholdPrefix = "dailyUsage-"
    static let armedAtKey = "widgetDiagnosticArmedAt"
    static let diagnosticLogKey = "widgetDiagnosticLog"
    static let monitorStatusKey = "widgetDiagnosticMonitorStatus"
    static let lastCheckKey = "widgetDiagnosticLastChecked"
    static let scheduledStartKey = "widgetDiagnosticScheduledStart"
    static let scheduledEndKey = "widgetDiagnosticScheduledEnd"

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
        if defaults.string(forKey: Self.activeActivityKey) != Self.dailyActivityName {
            defaults.set(0.0, forKey: Self.usageKey)
            defaults.set(Calendar.current.startOfDay(for: Date()),
                         forKey: Self.usageDateKey)
            defaults.set([String](), forKey: Self.diagnosticLogKey)
            defaults.removeObject(forKey: "widgetDiagnosticLastCallback")
            defaults.removeObject(forKey: "widgetDiagnosticLastEntry")
            WidgetCenter.shared.reloadTimelines(ofKind: "ScreenBudgetWidget")
        }

        // Isolate the monitor: register ONE five-minute threshold only.
        // Do not include usage from before monitoring was registered.
        let eventName = DeviceActivityEvent.Name("\(Self.thresholdPrefix)5")
        let events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [
            eventName: DeviceActivityEvent(
                threshold: DateComponents(minute: 5),
                includesPastActivity: false
            )
        ]

        // One-shot future window: the first minute boundary at least two
        // minutes from now, followed by 45 minutes of monitoring.
        // Explicit calendar components prevent matching an earlier interval
        // with the same hour/minute (including around midnight).
        let calendar = Calendar.current
        let now = Date()
        let minuteStart = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        let scheduledStart = calendar.date(byAdding: .minute, value: 3,
                                           to: minuteStart) ?? now.addingTimeInterval(180)
        let scheduledEnd = calendar.date(byAdding: .minute, value: 45,
                                         to: scheduledStart) ?? scheduledStart.addingTimeInterval(2700)
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(components, from: scheduledStart),
            intervalEnd: calendar.dateComponents(components, from: scheduledEnd),
            repeats: false
        )

        // Save before registering so callbacks can validate against the
        // actual future interval, not simply the registration timestamp.
        let armedAt = now
        defaults.set(armedAt, forKey: Self.armedAtKey)
        defaults.set(scheduledStart, forKey: Self.scheduledStartKey)
        defaults.set(scheduledEnd, forKey: Self.scheduledEndKey)
        // A threshold callback may arrive during startMonitoring.
        defaults.set(Self.dailyActivityName, forKey: Self.activeActivityKey)

        do {
            try center.startMonitoring(activity, during: schedule, events: events)
            NSLog("ScreenBudgetDiagnostic START activity=%@ registered=%@ windowStart=%@ windowEnd=%@ events=5 only includesPastActivity=false", Self.dailyActivityName, armedAt.description, scheduledStart.description, scheduledEnd.description)
            defaults.set("Scheduled", forKey: Self.monitorStatusKey)
            defaults.set(Date(), forKey: Self.lastCheckKey)
            print("ScreenBudget future diagnostic window scheduled")
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
