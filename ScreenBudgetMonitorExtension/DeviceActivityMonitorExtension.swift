import DeviceActivity
import Foundation
import WidgetKit

final class DeviceActivityMonitorExtension:
    DeviceActivityMonitor {

    private let appGroup =
        "group.com.example.ScreenGauge"

    private let usageKey =
        "widgetUsageMinutes"

    private let usageDateKey =
        "widgetUsageDate"

    private let generationKey =
        "widgetMonitorGeneration"

    private let armedAtKey =
        "widgetMonitorArmedAt"

    private let activeActivityKey =
        "widgetMonitorActivity"

    private let minutesPerTick =
        5.0

    private let lastUpdateKey = "widgetUsageLastUpdatedAt"
    private let diagnosticKey = "widgetMonitorDiagnostics"

    private func log(_ message: String, defaults: UserDefaults) {
        let line = "\(Date()): monitor: \(message)"
        var history = defaults.stringArray(forKey: diagnosticKey) ?? []
        history.append(line)
        defaults.set(Array(history.suffix(60)), forKey: diagnosticKey)
        print(line)
    }

    /*
     A legitimate 5-minute usage event physically
     cannot happen only a few seconds after we
     armed a fresh 5-minute threshold.

     Give the callback a little tolerance.
    */

    private let minimumAcceptedWallTime:
        TimeInterval = 4 * 60

    private let center =
        DeviceActivityCenter()

    // MARK: Interval started

    override func intervalDidStart(
        for activity: DeviceActivityName
    ) {

        super.intervalDidStart(
            for: activity
        )

        guard let defaults =
            UserDefaults(
                suiteName: appGroup
            )
        else {
            return
        }

        let didReset = resetForNewDayIfNeeded(defaults: defaults)
        log("Interval started \(activity.rawValue), reset=\(didReset)", defaults: defaults)
        if didReset {
            rearmFreshEvent(replacing: activity, defaults: defaults)
        }
    }

    // MARK: Five-minute threshold

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {

        super.eventDidReachThreshold(
            event,
            activity: activity
        )

        guard let defaults =
            UserDefaults(
                suiteName: appGroup
            )
        else {
            return
        }

        if resetForNewDayIfNeeded(defaults: defaults) {
            log("Threshold after day reset; rearming without count", defaults: defaults)
            rearmFreshEvent(replacing: activity, defaults: defaults)
            return
        }

        // ------------------------------
        // 1. Reject stale callbacks
        // ------------------------------

        guard let expectedActivity =
            defaults.string(
                forKey: activeActivityKey
            )
        else {
            log("Ignored callback without expected activity: \(activity.rawValue)", defaults: defaults)
            return
        }

        guard activity.rawValue ==
                expectedActivity
        else {

            log("Ignored stale callback \(activity.rawValue), expected \(expectedActivity)", defaults: defaults)

            return
        }

        // ------------------------------
        // 2. Check how recently it was armed
        // ------------------------------

        guard let armedAt =
            defaults.object(
                forKey: armedAtKey
            ) as? Date
        else {
            log("Arming timestamp missing; rearming", defaults: defaults)
            rearmFreshEvent(
                replacing: activity,
                defaults: defaults
            )

            return
        }

        let elapsed =
            Date().timeIntervalSince(
                armedAt
            )

        // ------------------------------
        // 3. Detect bogus early callback
        // ------------------------------

        if elapsed < minimumAcceptedWallTime {

            log("Premature callback ignored at \(Int(elapsed))s for \(activity.rawValue)", defaults: defaults)
            // Keep monitor armed: a legitimate threshold may still arrive.

            return
        }

        // ------------------------------
        // 4. Accept one 5-minute unit
        // ------------------------------

        let current =
            defaults.double(
                forKey: usageKey
            )

        let newTotal =
            current + minutesPerTick

        defaults.set(
            newTotal,
            forKey: usageKey
        )

        let now = Date()
        defaults.set(now, forKey: usageDateKey)
        defaults.set(now, forKey: lastUpdateKey)
        log("Accepted tick \(current) -> \(newTotal)m at \(Int(elapsed))s", defaults: defaults)

        WidgetCenter.shared
            .reloadAllTimelines()

        // ------------------------------
        // 5. Arm the next 5-minute unit
        // ------------------------------

        rearmFreshEvent(
            replacing: activity,
            defaults: defaults
        )
    }

    // MARK: Re-arm

    private func rearmFreshEvent(
        replacing oldActivity:
            DeviceActivityName,
        defaults: UserDefaults
    ) {

        center.stopMonitoring(
            [oldActivity]
        )

        let oldGeneration =
            defaults.integer(
                forKey: generationKey
            )

        let generation =
            oldGeneration + 1

        let activity =
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
         Persist the new identity before starting
         it so late callbacks from the old generation
         won't count.
        */

        defaults.set(
            generation,
            forKey: generationKey
        )

        defaults.set(
            activity.rawValue,
            forKey: activeActivityKey
        )

        defaults.set(
            Date(),
            forKey: armedAtKey
        )

        do {
            try center.startMonitoring(
                activity,
                during: schedule,
                events: [
                    eventName: event
                ]
            )

            log("Re-armed generation \(generation)", defaults: defaults)

        } catch {

            defaults.removeObject(
                forKey: activeActivityKey
            )

            log("Failed re-arm generation \(generation): \(error)", defaults: defaults)
        }
    }

    // MARK: Daily reset

    @discardableResult
    private func resetForNewDayIfNeeded(
        defaults: UserDefaults
    ) -> Bool {

        let calendar =
            Calendar.current

        let today =
            calendar.startOfDay(
                for: Date()
            )

        if let savedDate =
            defaults.object(
                forKey: usageDateKey
            ) as? Date {

            if calendar.isDate(
                savedDate,
                inSameDayAs: today
            ) {
                return false
            }
        }

        log("New day reset", defaults: defaults)
        defaults.removeObject(forKey: lastUpdateKey)
        defaults.set(
            0.0,
            forKey: usageKey
        )

        defaults.set(
            today,
            forKey: usageDateKey
        )

        WidgetCenter.shared
            .reloadAllTimelines()
        return true
    }
}
