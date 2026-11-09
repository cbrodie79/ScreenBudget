import DeviceActivity
import Foundation
import WidgetKit

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let appGroup = "group.com.example.ScreenGauge"
    private let usageKey = "widgetUsageMinutes"
    private let usageDateKey = "widgetUsageDate"
    private let activeActivityKey = "widgetMonitorActivity"
    private let dailyActivityName = "screenBudget-cumulative-v2"
    private let thresholdPrefix = "dailyUsage-"
    private let armedAtKey = "widgetDiagnosticArmedAt"
    private let diagnosticLogKey = "widgetDiagnosticLog"
    private let lastEntryKey = "widgetDiagnosticLastEntry"
    private let lastCallbackKey = "widgetDiagnosticLastCallback"
    private let lastAcceptedKey = "widgetDiagnosticLastAccepted"
    private let lastRejectedKey = "widgetDiagnosticLastRejected"
    private let lastLegacyKey = "widgetDiagnosticLastLegacy"
    private let acceptedCountKey = "widgetDiagnosticAcceptedCount"
    private let rejectedCountKey = "widgetDiagnosticRejectedCount"
    private let monitorStatusKey = "widgetDiagnosticMonitorStatus"

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }

        // Legacy monitor notifications must not overwrite active diagnostics.
        guard activity.rawValue == dailyActivityName,
              defaults.string(forKey: activeActivityKey) == dailyActivityName else {
            defaults.set("intervalDidStart at \(Date()) activity=\(activity.rawValue)",
                         forKey: lastLegacyKey)
            return
        }

        defaults.set("intervalDidStart at \(Date()) activity=\(activity.rawValue)",
                     forKey: lastEntryKey)
        defaults.set("Interval started (cumulative)", forKey: monitorStatusKey)
        resetForNewDayIfNeeded(defaults: defaults)
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }

        let now = Date()
        let previousCallback = defaults.object(forKey: "widgetDiagnosticCallbackAt") as? Date
        let callbackGap = previousCallback.map { now.timeIntervalSince($0) }
        let receipt = "at=\(now) activity=\(activity.rawValue) event=\(event.rawValue)"

        // Keep evidence of stale/legacy callbacks without allowing them to
        // masquerade as the newest active monitor callback.
        guard activity.rawValue == dailyActivityName,
              defaults.string(forKey: activeActivityKey) == dailyActivityName else {
            defaults.set(receipt, forKey: lastLegacyKey)
            NSLog("ScreenBudget ignored legacy callback %@", receipt)
            return
        }

        defaults.set(now, forKey: "widgetDiagnosticCallbackAt")
        defaults.set(receipt, forKey: lastCallbackKey)
        defaults.set("eventDidReachThreshold at \(now)", forKey: lastEntryKey)

        guard event.rawValue.hasPrefix(thresholdPrefix),
              let minutes = Int(event.rawValue.dropFirst(thresholdPrefix.count)),
              (5...600).contains(minutes),
              minutes % 5 == 0 else {
            record(
                "at=\(now) event=\(event.rawValue) result=REJECTED_UNKNOWN_EVENT",
                accepted: false, defaults: defaults
            )
            return
        }

        resetForNewDayIfNeeded(defaults: defaults)

        let dayStart = Calendar.current.startOfDay(for: now)
        let armedAt = defaults.object(forKey: armedAtKey) as? Date
        // The schedule repeats at midnight. Since includesPastActivity is
        // false, activity before registration on the first day is excluded.
        let countingStart = armedAt.map { max($0, dayStart) }
        let elapsed = countingStart.map { now.timeIntervalSince($0) } ?? -1
        let plausible = elapsed + 15 >= Double(minutes) * 60

        let prior = defaults.double(forKey: usageKey)
        let verdict: String
        if !plausible {
            verdict = "REJECTED_PREMATURE"
        } else if Double(minutes) <= prior {
            verdict = "IGNORED_DUPLICATE_OR_OUT_OF_ORDER"
        } else {
            verdict = "ACCEPTED"
        }

        let gapDescription = callbackGap.map { String(format: "%.1f", $0) } ?? "first"
        let message = "gap=\(gapDescription)s delta=\(minutes - Int(prior))m at=\(now) event=\(event.rawValue) threshold=\(minutes)m elapsed=\(String(format: "%.1f", elapsed))s prior=\(Int(prior))m result=\(verdict)"

        if verdict == "ACCEPTED" {
            // Cumulative checkpoints: a 20-minute callback means at least
            // 20 minutes according to iOS, NOT another 20 minutes to add.
            defaults.set(Double(minutes), forKey: usageKey)
            defaults.set(dayStart, forKey: usageDateKey)
            record(message, accepted: true, defaults: defaults)
            requestWidgetRefresh(defaults: defaults, reason: "accepted threshold \(minutes)m")
        } else if verdict == "REJECTED_PREMATURE" {
            record(message, accepted: false, defaults: defaults)
        } else {
            appendLog(message, defaults: defaults)
        }

        NSLog("ScreenBudget cumulative %@", message)
        // No stopMonitoring/startMonitoring here: do not discard accumulated
        // usage or create generations on every five-minute checkpoint.
    }

    private func requestWidgetRefresh(defaults: UserDefaults, reason: String) {
        // A request is not proof that WidgetKit has rebuilt or shown the entry.
        defaults.set([
            "at": Date(),
            "reason": reason,
            "minutes": defaults.double(forKey: usageKey)
        ], forKey: "widgetDiagnosticReloadRequest")
        WidgetCenter.shared.reloadTimelines(ofKind: "ScreenBudgetWidget")
    }

    private func record(_ message: String, accepted: Bool, defaults: UserDefaults) {
        let latestKey = accepted ? lastAcceptedKey : lastRejectedKey
        let countKey = accepted ? acceptedCountKey : rejectedCountKey
        defaults.set(message, forKey: latestKey)
        defaults.set(defaults.integer(forKey: countKey) + 1, forKey: countKey)
        appendLog(message, defaults: defaults)
    }

    private func appendLog(_ message: String, defaults: UserDefaults) {
        var entries = defaults.stringArray(forKey: diagnosticLogKey) ?? []
        entries.append(message)
        defaults.set(Array(entries.suffix(40)), forKey: diagnosticLogKey)
    }

    private func resetForNewDayIfNeeded(defaults: UserDefaults) {
        let today = Calendar.current.startOfDay(for: Date())
        if let saved = defaults.object(forKey: usageDateKey) as? Date,
           Calendar.current.isDate(saved, inSameDayAs: today) {
            return
        }
        defaults.set(0.0, forKey: usageKey)
        defaults.set(today, forKey: usageDateKey)
        defaults.set(0, forKey: acceptedCountKey)
        defaults.set(0, forKey: rejectedCountKey)
        defaults.removeObject(forKey: lastAcceptedKey)
        defaults.removeObject(forKey: lastRejectedKey)
        requestWidgetRefresh(defaults: defaults, reason: "monitor daily reset")
    }
}
