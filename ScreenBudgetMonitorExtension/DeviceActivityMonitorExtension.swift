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

        resetForNewDayIfNeeded(
            defaults: defaults
        )
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

        resetForNewDayIfNeeded(
            defaults: defaults
        )

        // ------------------------------
        // 1. Reject stale callbacks
        // ------------------------------

        guard let expectedActivity =
            defaults.string(
                forKey: activeActivityKey
            )
        else {
            return
        }

        guard activity.rawValue ==
                expectedActivity
        else {

            print(
                "Ignoring stale ScreenBudget callback"
            )

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

            print(
                """
                Premature DeviceActivity callback.
                Armed only \(elapsed) seconds ago.
                Ignoring callback.
                """
            )

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

        defaults.set(
            Date(),
            forKey: usageDateKey
        )

        print(
            "Accepted usage tick: \(newTotal) minutes"
        )

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

            print(
                "Re-armed generation \(generation)"
            )

        } catch {

            defaults.removeObject(
                forKey: activeActivityKey
            )

            print(
                "Unable to re-arm ScreenBudget: \(error)"
            )
        }
    }

    // MARK: Daily reset

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
                forKey: usageDateKey
            ) as? Date {

            if calendar.isDate(
                savedDate,
                inSameDayAs: today
            ) {
                return
            }
        }

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
    }
}
