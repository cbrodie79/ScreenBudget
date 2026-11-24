import Foundation
import FamilyControls
import DeviceActivity
import WidgetKit

final class ScreenTimeManager {

    static let shared = ScreenTimeManager()

    static let appGroup =
        "group.com.example.ScreenGauge"

    static let usageKey =
        "widgetUsageMinutes"

    static let usageDateKey =
        "widgetUsageDate"

    static let generationKey =
        "widgetMonitorGeneration"

    static let armedAtKey =
        "widgetMonitorArmedAt"

    static let activeActivityKey =
        "widgetMonitorActivity"

    static let minutesPerTick = 5.0
    static let lastUpdateKey = "widgetUsageLastUpdatedAt"
    static let diagnosticKey = "widgetMonitorDiagnostics"

    private func record(_ event: String, details: [String: Any] = [:], defaults: UserDefaults) {
        var entry: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "source": "app",
            "event": event,
            "usageMinutes": defaults.double(forKey: Self.usageKey),
            "generation": defaults.integer(forKey: Self.generationKey),
            "activity": defaults.string(forKey: Self.activeActivityKey) ?? ""
        ]
        details.forEach { entry[$0.key] = $0.value }
        guard let payload = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              let line = String(data: payload, encoding: .utf8) else { return }
        let key = "screenBudgetDiagnostics.app"
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600).timeIntervalSince1970
        var history = defaults.stringArray(forKey: key) ?? []
        history.append(line)
        history = history.filter {
            guard let data = $0.data(using: .utf8),
                  let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let timestamp = value["timestamp"] as? Double else { return false }
            return timestamp >= cutoff
        }
        defaults.set(Array(history.suffix(3000)), forKey: key)
    }

    func captureSnapshot(_ event: String, details: [String: Any] = [:]) {
        guard let defaults = UserDefaults(suiteName: Self.appGroup) else { return }
        var snapshot = details
        snapshot["monitorArmedAt"] = (defaults.object(forKey: Self.armedAtKey) as? Date)?.timeIntervalSince1970 ?? 0
        snapshot["usageDate"] = (defaults.object(forKey: Self.usageDateKey) as? Date)?.timeIntervalSince1970 ?? 0
        snapshot["lastUsageUpdate"] = (defaults.object(forKey: Self.lastUpdateKey) as? Date)?.timeIntervalSince1970 ?? 0
        snapshot["registeredMonitorCount"] = center.activities.count
        record(event, details: snapshot, defaults: defaults)
    }

    func exportDiagnostics() -> URL? {
        captureSnapshot("export_requested")
        guard let defaults = UserDefaults(suiteName: Self.appGroup) else { return nil }
        let keys = ["screenBudgetDiagnostics.app", "screenBudgetDiagnostics.monitor", "screenBudgetDiagnostics.widget"]
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600).timeIntervalSince1970
        let events: [[String: Any]] = keys.flatMap { defaults.stringArray(forKey: $0) ?? [] }
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }
            .filter { ($0["timestamp"] as? Double ?? 0) >= cutoff }
            .sorted { ($0["timestamp"] as? Double ?? 0) < ($1["timestamp"] as? Double ?? 0) }
        let report: [String: Any] = [
            "formatVersion": 1,
            "exportedAt": Date().timeIntervalSince1970,
            "retentionDays": 7,
            "events": events
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("screenbudget-diagnostics-\(Int(Date().timeIntervalSince1970)).json")
        do { try data.write(to: url, options: .atomic); return url }
        catch { return nil }
    }

    private func log(_ message: String, defaults: UserDefaults) {
        record(message, defaults: defaults)
        print("ScreenBudget app: \(message)")
    }

    private let center =
        DeviceActivityCenter()

    private init() {}

    // MARK: Authorization

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared
                .requestAuthorization(for: .individual)

            startMonitoringIfNeeded()

        } catch {
            print(
                "Screen Time authorization failed: \(error)"
            )
        }
    }

    // MARK: Start / restore monitoring

    func startMonitoringIfNeeded() {

        guard let defaults =
            UserDefaults(
                suiteName: Self.appGroup
            )
        else {
            return
        }

        captureSnapshot("before_monitor_recovery")
        resetForNewDayIfNeeded(
            defaults: defaults
        )

        /*
         If we already have an active monitor
         registered today, don't restart it every
         time ContentView appears.

         Restarting would throw away part of the
         current 5-minute bucket.
        */

        let activeNames = center.activities
        let expected = defaults.string(forKey: Self.activeActivityKey)
        if let expected, activeNames.contains(where: { $0.rawValue == expected }) {
            log("Monitor confirmed active: \(expected)", defaults: defaults)
            return
        }
        log("Recovering missing monitor (saved=\(expected ?? "none"), registered=\(activeNames.count))", defaults: defaults)
        let stale = activeNames.filter { $0.rawValue.hasPrefix("screenBudget-") }
        if !stale.isEmpty { center.stopMonitoring(stale) }
        defaults.removeObject(forKey: Self.activeActivityKey)
        armFreshFiveMinuteEvent(defaults: defaults)
    }

    // MARK: Fresh monitor

    private func armFreshFiveMinuteEvent(
        defaults: UserDefaults
    ) {

        let oldGeneration =
            defaults.integer(
                forKey: Self.generationKey
            )

        let generation =
            oldGeneration + 1

        let activityName =
            DeviceActivityName(
                "screenBudget-\(generation)"
            )

        let eventName =
            DeviceActivityEvent.Name(
                "fiveMinutes-\(generation)"
            )

        let event =
            DeviceActivityEvent(
                threshold: DateComponents(
                    minute: 5
                ),
                includesPastActivity: false
            )

        let schedule =
            DeviceActivitySchedule(
                intervalStart: DateComponents(
                    hour: 0,
                    minute: 0
                ),
                intervalEnd: DateComponents(
                    hour: 23,
                    minute: 59
                ),
                repeats: true
            )

        /*
         Persist generation information before
         registering it.

         That gives the extension a way to reject
         callbacks belonging to stale generations.
        */

        defaults.set(
            generation,
            forKey: Self.generationKey
        )

        defaults.set(
            activityName.rawValue,
            forKey: Self.activeActivityKey
        )

        defaults.set(
            Date(),
            forKey: Self.armedAtKey
        )

        do {
            try center.startMonitoring(
                activityName,
                during: schedule,
                events: [
                    eventName: event
                ]
            )

            log("Armed generation \(generation)", defaults: defaults)

        } catch {

            defaults.removeObject(
                forKey: Self.activeActivityKey
            )

            log("Unable to start monitor: \(error)", defaults: defaults)
        }
    }

    // MARK: Day handling

    private func resetForNewDayIfNeeded(
        defaults: UserDefaults
    ) {

        let calendar =
            Calendar.current

        let today =
            calendar.startOfDay(
                for: Date()
            )

        if let savedDate =
            defaults.object(
                forKey: Self.usageDateKey
            ) as? Date {

            if calendar.isDate(
                savedDate,
                inSameDayAs: today
            ) {
                return
            }
        }

        let stale = center.activities.filter { $0.rawValue.hasPrefix("screenBudget-") }
        if !stale.isEmpty { center.stopMonitoring(stale) }
        log("New-day reset; stopped \(stale.count) old monitors", defaults: defaults)
        let previousUsage = defaults.double(forKey: Self.usageKey)
        defaults.set(
            0.0,
            forKey: Self.usageKey
        )
        defaults.removeObject(forKey: Self.lastUpdateKey)

        defaults.set(
            today,
            forKey: Self.usageDateKey
        )

        defaults.removeObject(
            forKey: Self.activeActivityKey
        )

        record("daily_reset", details: ["previousUsageMinutes": previousUsage], defaults: defaults)
        WidgetCenter.shared
            .reloadAllTimelines()
    }
}
