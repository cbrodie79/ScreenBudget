import DeviceActivity
import Foundation
import WidgetKit

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    private let appGroup = "group.com.example.ScreenGauge"
    private let usageKey = "widgetUsageMinutes"
    private let usageDateKey = "widgetUsageDate"
    private let activeActivityKey = "widgetMonitorActivity"

    private let dailyActivityName = "screenBudget-diagnostic-v3"
    private let thresholdPrefix = "dailyUsage-"
    private let armedAtKey = "widgetDiagnosticArmedAt"
    private let diagnosticLogKey = "widgetDiagnosticLog"
    private let lastEntryKey = "widgetDiagnosticLastEntry"
    private let lastCallbackKey = "widgetDiagnosticLastCallback"

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        // This proves the extension ran, independent of any threshold.
        guard let defaults = UserDefaults(suiteName: appGroup) else {
            NSLog("ScreenBudgetDiagnostic intervalDidStart: App Group unavailable")
            return
        }
        defaults.set("intervalDidStart at \(Date()) for \(activity.rawValue)",
                     forKey: lastEntryKey)

        guard activity.rawValue == dailyActivityName,
              defaults.string(forKey: activeActivityKey) == dailyActivityName else {
            return
        }

        resetForNewDayIfNeeded(defaults: defaults)
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)

        // Record receipt before validating the activity and event names.
        // This distinguishes an absent callback from one rejected by guards.
        guard let defaults = UserDefaults(suiteName: appGroup) else {
            NSLog("ScreenBudgetDiagnostic callback: App Group unavailable")
            return
        }
        let receipt = "at=\(Date()) activity=\(activity.rawValue) event=\(event.rawValue)"
        defaults.set(receipt, forKey: lastCallbackKey)
        defaults.set("eventDidReachThreshold at \(Date())", forKey: lastEntryKey)
        NSLog("ScreenBudgetDiagnostic RECEIVED %@", receipt)

        guard activity.rawValue == dailyActivityName,
              defaults.string(forKey: activeActivityKey) == dailyActivityName,
              event.rawValue.hasPrefix(thresholdPrefix),
              let thresholdMinutes = Int(
                event.rawValue.dropFirst(thresholdPrefix.count)
              ),
              thresholdMinutes >= 5,
              thresholdMinutes <= 30,
              thresholdMinutes % 5 == 0 else {
            return
        }

        resetForNewDayIfNeeded(defaults: defaults)

        let now = Date()
        let elapsed = (defaults.object(forKey: armedAtKey) as? Date)
            .map { now.timeIntervalSince($0) }
        let elapsedString = elapsed.map { String(format: "%.1f", $0) } ?? "unknown"
        let prior = defaults.double(forKey: usageKey)

        // Diagnostic only: record even duplicate and out-of-order callbacks.
        // Keep the most recent 40 entries so the log remains bounded.
        let message = "at=\(now) event=\(event.rawValue) threshold=\(thresholdMinutes)m elapsedSinceStart=\(elapsedString)s prior=\(Int(prior))m"
        NSLog("ScreenBudgetDiagnostic CALLBACK %@", message)
        var log = defaults.stringArray(forKey: diagnosticLogKey) ?? []
        log.append(message)
        defaults.set(Array(log.suffix(40)), forKey: diagnosticLogKey)

        // Never increment by a fixed amount: callbacks can be delayed or
        // delivered out of order. The event name is the cumulative minimum.
        let current = defaults.double(forKey: usageKey)
        let newTotal = max(current, Double(thresholdMinutes))

        guard newTotal > current else {
            return
        }

        defaults.set(newTotal, forKey: usageKey)
        defaults.set(Calendar.current.startOfDay(for: Date()),
                     forKey: usageDateKey)

        WidgetCenter.shared.reloadTimelines(ofKind: "ScreenBudgetWidget")
        print("ScreenBudget daily usage reached \(Int(newTotal)) minutes")
    }

    private func resetForNewDayIfNeeded(defaults: UserDefaults) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let savedDate = defaults.object(forKey: usageDateKey) as? Date,
           calendar.isDate(savedDate, inSameDayAs: today) {
            return
        }

        defaults.set(0.0, forKey: usageKey)
        defaults.set(today, forKey: usageDateKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "ScreenBudgetWidget")
    }
}
