import Foundation
import Combine
import WidgetKit

@MainActor
final class GaugeStore: ObservableObject {
    @Published var goalMinutes: Double {
        didSet {
            save()
            WidgetCenter.shared.reloadTimelines(ofKind: "ScreenBudgetWidget")
        }
    }
    @Published var usedMinutes: Double { didSet { save() } }
    @Published var demoMode: Bool { didSet { save() } }

    private let defaults: UserDefaults
    private let goalKey = "goalMinutes"
    private let usedKey = "usedMinutes"
    private let demoKey = "demoMode"
    private let dateKey = "usageDate"

    init() {
        defaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
        let today = Self.dateString(Date())

        if defaults.string(forKey: dateKey) != today {
            defaults.set(today, forKey: dateKey)
            defaults.set(0.0, forKey: usedKey)
        }

        goalMinutes = defaults.object(forKey: goalKey) as? Double ?? 120
        usedMinutes = defaults.object(forKey: usedKey) as? Double ?? 0
        demoMode = defaults.object(forKey: demoKey) as? Bool ?? true
    }

    var progress: Double {
        goalMinutes > 0 ? usedMinutes / goalMinutes : 0
    }

    var isOverLimit: Bool {
        progress > 1
    }

    func requestScreenTimeAccess() async {
        await ScreenTimeManager.shared.requestAuthorization()
    }

    func refreshDay() {
        let today = Self.dateString(Date())
        if defaults.string(forKey: dateKey) != today {
            defaults.set(today, forKey: dateKey)
            usedMinutes = 0
            WidgetCenter.shared.reloadTimelines(ofKind: "ScreenBudgetWidget")
        }
    }

    func refreshWidget() {
        save()
        WidgetCenter.shared.reloadTimelines(ofKind: "ScreenBudgetWidget")
    }

    private func save() {
        defaults.set(goalMinutes, forKey: goalKey)
        defaults.set(usedMinutes, forKey: usedKey)
        defaults.set(demoMode, forKey: demoKey)
        defaults.set(Self.dateString(Date()), forKey: dateKey)
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
