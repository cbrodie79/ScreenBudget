import DeviceActivity
import SwiftUI

extension DeviceActivityReport.Context {
    static let totalActivity = Self("Total Activity")
}

struct TotalActivityConfiguration {
    let totalActivity: Double
    let goalMinutes: Double
}

struct TotalActivityReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .totalActivity

    let content: (TotalActivityConfiguration) -> TotalActivityView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> TotalActivityConfiguration {

        let totalActivityDuration = await data
            .flatMap { $0.activitySegments }
            .reduce(0) { total, segment in
                total + segment.totalActivityDuration
            }

        let totalMinutes = totalActivityDuration / 60.0

        // TEMPORARY DEBUG TEST:
        // Read directly from the App Group without falling back
        // to this extension's private UserDefaults.
        let sharedDefaults = UserDefaults(
            suiteName: "group.com.example.ScreenGauge"
        )

        let savedGoal: Double

        if let sharedDefaults,
           sharedDefaults.object(forKey: "goalMinutes") != nil {
            savedGoal = sharedDefaults.double(forKey: "goalMinutes")
        } else {
            savedGoal = -1
        }

        return TotalActivityConfiguration(
            totalActivity: totalMinutes,
            goalMinutes: savedGoal
        )
    }
}
