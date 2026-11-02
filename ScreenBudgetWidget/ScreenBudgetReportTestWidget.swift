import WidgetKit
import SwiftUI
import DeviceActivity

// Diagnostic-only widget: tries to render the same protected
// DeviceActivityReport view used by ContentView inside WidgetKit.
// WidgetKit may omit the report entirely; the surrounding labels
// let us distinguish a blank report from a missing widget.
struct ScreenBudgetReportTestView: View {
    private let reportContext = DeviceActivityReport.Context("Total Activity")

    private var todayFilter: DeviceActivityFilter {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())

        return DeviceActivityFilter(
            segment: .daily(
                during: DateInterval(start: startOfDay, end: Date())
            )
        )
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("DIRECT REPORT TEST")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)

            ZStack {
                Text("Report did not render")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                DeviceActivityReport(
                    reportContext,
                    filter: todayFilter
                )
                .frame(maxWidth: .infinity, minHeight: 145)
            }
            .frame(maxWidth: .infinity, minHeight: 145)
        }
        .padding(10)
        .containerBackground(.background, for: .widget)
    }
}

struct ScreenBudgetReportTestWidget: Widget {
    let kind = "ScreenBudgetReportTestWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: ScreenBudgetProvider()
        ) { _ in
            ScreenBudgetReportTestView()
        }
        .configurationDisplayName("ScreenBudget Report Test")
        .description("Tests whether Apple's protected Screen Time report can render directly in WidgetKit.")
        .supportedFamilies([.systemMedium])
    }
}
