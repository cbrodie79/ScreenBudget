import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct ScreenBudgetEntry: TimelineEntry {
    let date: Date
    let usageMinutes: Double
    let goalMinutes: Double
    let lastUpdatedAt: Date?
}

// MARK: - Timeline Provider

struct ScreenBudgetProvider: TimelineProvider {

    private let appGroup =
        "group.com.example.ScreenGauge"

    private let usageKey =
        "widgetUsageMinutes"

    private let goalKey =
        "goalMinutes"

    private let usageDateKey = "widgetUsageDate"
    private let lastUpdateKey = "widgetUsageLastUpdatedAt"

    func placeholder(
        in context: Context
    ) -> ScreenBudgetEntry {

        ScreenBudgetEntry(
            date: Date(),
            usageMinutes: 95,
            goalMinutes: 180,
            lastUpdatedAt: Date()
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (
            ScreenBudgetEntry
        ) -> Void
    ) {

        completion(
            loadEntry()
        )
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (
            Timeline<ScreenBudgetEntry>
        ) -> Void
    ) {

        let entry =
            loadEntry()

        /*
         The monitor extension will call:
         WidgetCenter.shared.reloadAllTimelines()

         whenever a 5-minute usage threshold is crossed.

         This fallback refresh means WidgetKit can also
         periodically ask for a fresh entry on its own.
        */

        let nextRefresh =
            Calendar.current.date(
                byAdding: .minute,
                value: 30,
                to: Date()
            ) ?? Date()
                .addingTimeInterval(1800)

        let timeline =
            Timeline(
                entries: [entry],
                policy: .after(
                    nextRefresh
                )
            )

        completion(timeline)
    }

    private func loadEntry()
        -> ScreenBudgetEntry {

        let defaults =
            UserDefaults(
                suiteName: appGroup
            )

        let usageDate = defaults?.object(forKey: usageDateKey) as? Date
        let isToday = usageDate.map { Calendar.current.isDateInToday($0) } ?? false
        let usageMinutes = isToday ? (defaults?.double(forKey: usageKey) ?? 0) : 0
        let lastUpdated = isToday ? (defaults?.object(forKey: lastUpdateKey) as? Date) : nil

        let savedGoal =
            defaults?.double(
                forKey: goalKey
            ) ?? 0

        let goalMinutes =
            savedGoal > 0
                ? savedGoal
                : 120

        return ScreenBudgetEntry(
            date: Date(),
            usageMinutes: usageMinutes,
            goalMinutes: goalMinutes,
            lastUpdatedAt: lastUpdated
        )
    }
}


// MARK: - Widget View

struct ScreenBudgetWidgetView: View {

    let entry: ScreenBudgetEntry

    private var progress: Double {
        guard entry.goalMinutes > 0 else {
            return 0
        }

        return entry.usageMinutes /
            entry.goalMinutes
    }

    private var normalProgress: Double {
        min(
            progress,
            1.0
        )
    }

    private var overageProgress: Double {
        min(
            max(
                progress - 1.0,
                0
            ),
            1.0
        )
    }

    var body: some View {
        ZStack {

            // Background ring

            Circle()
                .stroke(
                    .secondary.opacity(0.20),
                    lineWidth: 14
                )

            // Usage up to goal

            Circle()
                .trim(
                    from: 0,
                    to: normalProgress
                )
                .stroke(
                    .primary,
                    style: StrokeStyle(
                        lineWidth: 14,
                        lineCap: .round
                    )
                )
                .rotationEffect(
                    .degrees(-90)
                )

            // Usage beyond goal

            if progress > 1 {

                Circle()
                    .trim(
                        from: 0,
                        to: overageProgress
                    )
                    .stroke(
                        .red,
                        style: StrokeStyle(
                            lineWidth: 14,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(
                        .degrees(-90)
                    )
            }

            VStack(
                spacing: 2
            ) {

                Text(
                    formatDuration(
                        entry.usageMinutes
                    )
                )
                .font(
                    .system(
                        size: 24,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .minimumScaleFactor(0.7)
                .monospacedDigit()

                Text(
                    progress > 1
                        ? "Over goal"
                        : "Today"
                )
                .font(.caption2)
                .foregroundStyle(
                    progress > 1
                        ? .red
                        : .secondary
                )

                if let lastUpdatedAt = entry.lastUpdatedAt {
                    Text("Updated \(lastUpdatedAt, style: .time)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Awaiting update")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .containerBackground(
            .background,
            for: .widget
        )
    }
}


// MARK: - Widget

struct ScreenBudgetWidget: Widget {

    let kind =
        "ScreenBudgetWidget"

    var body: some WidgetConfiguration {

        StaticConfiguration(
            kind: kind,
            provider:
                ScreenBudgetProvider()
        ) { entry in

            ScreenBudgetWidgetView(
                entry: entry
            )
        }
        .configurationDisplayName(
            "ScreenBudget"
        )
        .description(
            "See today's Screen Time against your daily goal."
        )
        .supportedFamilies([
            .systemSmall
        ])
    }
}


// MARK: - Formatting

private func formatDuration(
    _ minutes: Double
) -> String {

    let totalMinutes =
        max(
            0,
            Int(minutes)
        )

    let hours =
        totalMinutes / 60

    let mins =
        totalMinutes % 60

    if hours == 0 {
        return "\(mins)m"
    }

    if mins == 0 {
        return "\(hours)h"
    }

    return "\(hours)h \(mins)m"
}


// MARK: - Preview

#Preview(
    as: .systemSmall
) {

    ScreenBudgetWidget()

} timeline: {

    ScreenBudgetEntry(
        date: Date(),
        usageMinutes: 95,
        goalMinutes: 180,
        lastUpdatedAt: Date()
    )

    ScreenBudgetEntry(
        date: Date(),
        usageMinutes: 215,
        goalMinutes: 180,
        lastUpdatedAt: Date()
    )
}
