import DeviceActivity
import Foundation
import WidgetKit

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    private let appGroup = "group.com.example.ScreenGauge"
    private let usageKey = "widgetUsageMinutes"
    private let usageDateKey = "widgetUsageDate"
    private let activeActivityKey = "widgetMonitorActivity"

    private let dailyActivityName = "screenBudget-approx-v1"
    private let thresholdPrefix = "dailyUsage-"
    private let armedAtKey = "widgetDiagnosticArmedAt"
    private let diagnosticLogKey = "widgetDiagnosticLog"
    private let lastEntryKey = "widgetDiagnosticLastEntry"
    private let lastCallbackKey = "widgetDiagnosticLastCallback"
    private let generationKey = "widgetMonitorGeneration"
    private let retryCountKey = "widgetMonitorRecoveryCount"
    private let lastRetryKey = "widgetMonitorLastRecovery"
    private let monitorStatusKey = "widgetDiagnosticMonitorStatus"

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        // This proves the extension ran, independent of any threshold.
        guard let defaults = UserDefaults(suiteName: appGroup) else {
            NSLog("ScreenBudgetDiagnostic intervalDidStart: App Group unavailable")
            return
        }
        defaults.set("intervalDidStart at \(Date()) for \(activity.rawValue)",
                     forKey: lastEntryKey)

        guard activity.rawValue.hasPrefix(dailyActivityName + "-g"),
              defaults.string(forKey: activeActivityKey) == activity.rawValue else {
            return
        }

        defaults.set("Monitoring (estimate)", forKey: monitorStatusKey)
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

        guard activity.rawValue.hasPrefix(dailyActivityName + "-g"),
              defaults.string(forKey: activeActivityKey) == activity.rawValue,
              event.rawValue.hasPrefix(thresholdPrefix),
              let thresholdMinutes = Int(
                event.rawValue.dropFirst(thresholdPrefix.count)
              ),
              thresholdMinutes == 5 else {
            return
        }

        resetForNewDayIfNeeded(defaults: defaults)

        let now = Date()
        let elapsed = (defaults.object(forKey: armedAtKey) as? Date)
            .map { now.timeIntervalSince($0) }
        let elapsedString = elapsed.map { String(format: "%.1f", $0) } ?? "unknown"
        let prior = defaults.double(forKey: usageKey)

        // With includesPastActivity=false, 5 minutes of device usage
        // cannot occur in fewer than 5 minutes of wall-clock time.
        // Never invent minutes to fill a delay or a rejected callback.
        let dayStart = Calendar.current.startOfDay(for: now)
        let anchor = (defaults.object(forKey: armedAtKey) as? Date)
            .map { max($0, dayStart) }
        let plausible = anchor.map {
            now.timeIntervalSince($0) >= 5 * 60 - 15
        } ?? false

        // Diagnostic only: record even rejected, duplicate, or out-of-order
        // callbacks. Keep a bounded history so we can inspect false positives.
        // Keep the most recent 40 entries so the log remains bounded.
        let verdict = plausible ? "ACCEPTED" : "REJECTED_PREMATURE"
        let message = "at=\(now) event=\(event.rawValue) threshold=\(thresholdMinutes)m elapsedSinceStart=\(elapsedString)s prior=\(Int(prior))m result=\(verdict)"
        NSLog("ScreenBudgetDiagnostic CALLBACK %@", message)
        var log = defaults.stringArray(forKey: diagnosticLogKey) ?? []
        log.append(message)
        defaults.set(Array(log.suffix(40)), forKey: diagnosticLogKey)

        if plausible {
            // At most five verified minutes per monitoring generation.
            // This is a conservative usage estimate, not exact Screen Time.
            defaults.set(prior + 5, forKey: usageKey)
            defaults.set(dayStart, forKey: usageDateKey)
            defaults.set(0, forKey: retryCountKey)
            WidgetCenter.shared.reloadTimelines(ofKind: "ScreenBudgetWidget")
            rearm(activity: activity, defaults: defaults, now: now, isRecovery: false)
        } else {
            // One immediate retry is allowed; don't endlessly restart
            // the monitor if iOS keeps delivering false callbacks.
            let retries = defaults.integer(forKey: retryCountKey)
            let lastRetry = defaults.object(forKey: lastRetryKey) as? Date
            if retries < 1 && (lastRetry == nil ||
                 now.timeIntervalSince(lastRetry!) > 600) {
                defaults.set(retries + 1, forKey: retryCountKey)
                defaults.set(now, forKey: lastRetryKey)
                rearm(activity: activity, defaults: defaults, now: now, isRecovery: true)
            } else {
                defaults.set("Premature callback; awaiting repair", forKey: monitorStatusKey)
                // A subsequent foreground app launch can re-arm it.
                DeviceActivityCenter().stopMonitoring([activity])
            }
        }
    }

    private func rearm(
        activity: DeviceActivityName,
        defaults: UserDefaults,
        now: Date,
        isRecovery: Bool
    ) {
        let center = DeviceActivityCenter()
        let generation = defaults.integer(forKey: generationKey) + 1
        let nextName = dailyActivityName + "-g" + String(generation)
        let next = DeviceActivityName(nextName)
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        let event = DeviceActivityEvent(
            threshold: DateComponents(minute: 5),
            includesPastActivity: false
        )

        // Persist the new identity before registering so immediate/stale
        // callbacks from the previous activity can't double count.
        defaults.set(generation, forKey: generationKey)
        defaults.set(nextName, forKey: activeActivityKey)
        defaults.set(now, forKey: armedAtKey)
        center.stopMonitoring([activity])
        do {
            try center.startMonitoring(
                next,
                during: schedule,
                events: [DeviceActivityEvent.Name("dailyUsage-5"): event]
            )
            defaults.set(
                isRecovery ? "Retrying after early callback" : "Monitoring (estimate)",
                forKey: monitorStatusKey
            )
            NSLog("ScreenBudget estimate rearmed %@ recovery=%@", nextName,
                  String(isRecovery))
        } catch {
            defaults.removeObject(forKey: activeActivityKey)
            defaults.set("Rearm failed: \(error)", forKey: monitorStatusKey)
            NSLog("ScreenBudget estimate rearm failed: %@", String(describing: error))
        }
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
