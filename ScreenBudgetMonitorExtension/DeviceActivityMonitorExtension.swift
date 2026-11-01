import DeviceActivity
import Foundation
import WidgetKit

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    private let appGroup = "group.com.example.ScreenGauge"
    private let usageKey = "widgetUsageMinutes"
    private let usageDateKey = "widgetUsageDate"
    private let activeActivityKey = "widgetMonitorActivity"

    private let dailyActivityName = "screenBudget-daily-v2"
    private let thresholdPrefix = "dailyUsage-"

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        guard activity.rawValue == dailyActivityName,
              let defaults = UserDefaults(suiteName: appGroup),
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

        guard activity.rawValue == dailyActivityName,
              let defaults = UserDefaults(suiteName: appGroup),
              defaults.string(forKey: activeActivityKey) == dailyActivityName,
              event.rawValue.hasPrefix(thresholdPrefix),
              let thresholdMinutes = Int(
                event.rawValue.dropFirst(thresholdPrefix.count)
              ),
              thresholdMinutes >= 5,
              thresholdMinutes <= 600,
              thresholdMinutes % 5 == 0 else {
            return
        }

        resetForNewDayIfNeeded(defaults: defaults)

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
