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
    static let dailyActivityName = "screenBudget-cumulative-v2"
    static let thresholdPrefix = "dailyUsage-"
    static let armedAtKey = "widgetDiagnosticArmedAt"
    static let diagnosticLogKey = "widgetDiagnosticLog"
    static let monitorStatusKey = "widgetDiagnosticMonitorStatus"
    static let lastCheckKey = "widgetDiagnosticLastChecked"
    static let lastAcceptedKey = "widgetDiagnosticLastAccepted"
    static let lastRejectedKey = "widgetDiagnosticLastRejected"
    static let lastLegacyKey = "widgetDiagnosticLastLegacy"
    static let acceptedCountKey = "widgetDiagnosticAcceptedCount"
    static let rejectedCountKey = "widgetDiagnosticRejectedCount"

    private let center = DeviceActivityCenter()
    private init() {}

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            startMonitoringIfNeeded()
        } catch {
            NSLog("ScreenBudget authorization failed: %@", String(describing: error))
        }
    }

    func startMonitoringIfNeeded() {
        guard let defaults = UserDefaults(suiteName: Self.appGroup) else { return }
        resetForNewDayIfNeeded(defaults: defaults)

        let activity = DeviceActivityName(Self.dailyActivityName)
        // Only retire our old ScreenBudget monitors. Do not interfere
        // with other activity-monitoring features.
        let previousActivities = center.activities.filter {
            ($0.rawValue.hasPrefix("screenBudget-") || $0.rawValue == "dailyWidgetTracking") && $0 != activity
        }
        if !previousActivities.isEmpty {
            center.stopMonitoring(previousActivities)
            defaults.set(previousActivities.map { $0.rawValue }.sorted().joined(separator: ", "), forKey: "widgetDiagnosticRetiredMonitors")
        }


        defaults.set(center.activities.map { $0.rawValue }.sorted().joined(separator: ", "), forKey: "widgetDiagnosticRegisteredMonitors")
        defaults.set("All apps/categories/websites; monitor has no device filter. Daily 00:00–23:59; five-minute thresholds through 600m; includesPastActivity=false. Zone: \(TimeZone.current.identifier); OS: \(ProcessInfo.processInfo.operatingSystemVersionString)", forKey: "widgetDiagnosticConfiguration")
        if center.activities.contains(activity) {
            defaults.set(Self.dailyActivityName, forKey: Self.activeActivityKey)
            defaults.set("Registered (cumulative)", forKey: Self.monitorStatusKey)
            defaults.set(Date(), forKey: Self.lastCheckKey)
            return
        }

        let migrating = defaults.string(forKey: Self.activeActivityKey) != Self.dailyActivityName
        if migrating {
            // The rolling-v1 count isn't comparable to cumulative thresholds.
            defaults.set(0.0, forKey: Self.usageKey)
            defaults.set(Calendar.current.startOfDay(for: Date()),
                         forKey: Self.usageDateKey)
            defaults.set([String](), forKey: Self.diagnosticLogKey)
            defaults.set(0, forKey: Self.acceptedCountKey)
            defaults.set(0, forKey: Self.rejectedCountKey)
            for key in [Self.lastAcceptedKey, Self.lastRejectedKey,
                        Self.lastLegacyKey, "widgetDiagnosticLastCallback",
                        "widgetDiagnosticLastEntry"] {
                defaults.removeObject(forKey: key)
            }
            WidgetCenter.shared.reloadTimelines(ofKind: "ScreenBudgetWidget")
        }

        // One monitor for the entire day. Each event is a cumulative
        // total, not an increment. Do not stop/restart after callbacks.
        // Supports estimates up to 10 hours per day in five-minute steps.
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for minutes in stride(from: 5, through: 600, by: 5) {
            let eventName = DeviceActivityEvent.Name(
                "\(Self.thresholdPrefix)\(minutes)"
            )
            events[eventName] = DeviceActivityEvent(
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

        // Set the identity and anchor before calling startMonitoring:
        // the system can deliver callbacks during registration.
        let armedAt = Date()
        defaults.set(Self.dailyActivityName, forKey: Self.activeActivityKey)
        defaults.set(armedAt, forKey: Self.armedAtKey)

        do {
            try center.startMonitoring(activity, during: schedule, events: events)
            defaults.set(center.activities.map { $0.rawValue }.sorted().joined(separator: ", "), forKey: "widgetDiagnosticRegisteredMonitors")
            defaults.set("Registered (cumulative)", forKey: Self.monitorStatusKey)
            defaults.set(Date(), forKey: Self.lastCheckKey)
            NSLog("ScreenBudget cumulative monitor registered at %@; %d events",
                  armedAt.description, events.count)
        } catch {
            defaults.removeObject(forKey: Self.activeActivityKey)
            defaults.set("Start failed: \(error)", forKey: Self.monitorStatusKey)
            defaults.set(Date(), forKey: Self.lastCheckKey)
            NSLog("ScreenBudget cumulative monitor failed: %@", String(describing: error))
        }
    }

    private func resetForNewDayIfNeeded(defaults: UserDefaults) {
        let today = Calendar.current.startOfDay(for: Date())
        if let saved = defaults.object(forKey: Self.usageDateKey) as? Date,
           Calendar.current.isDate(saved, inSameDayAs: today) {
            return
        }
        defaults.set(0.0, forKey: Self.usageKey)
        defaults.set(today, forKey: Self.usageDateKey)
        defaults.set(0, forKey: Self.acceptedCountKey)
        defaults.set(0, forKey: Self.rejectedCountKey)
        defaults.removeObject(forKey: Self.lastAcceptedKey)
        defaults.removeObject(forKey: Self.lastRejectedKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "ScreenBudgetWidget")
    }
}
