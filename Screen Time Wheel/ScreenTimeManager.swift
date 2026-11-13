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

    private func log(_ message: String, defaults: UserDefaults) {
        let line = "\(Date()): app: \(message)"
        var history = defaults.stringArray(forKey: Self.diagnosticKey) ?? []
        history.append(line)
        defaults.set(Array(history.suffix(60)), forKey: Self.diagnosticKey)
        print(line)
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

        WidgetCenter.shared
            .reloadAllTimelines()
    }
}
