import SwiftUI
import DeviceActivity

struct ContentView: View {

    @EnvironmentObject private var store: GaugeStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var diagnostics = MonitorDiagnostics.read()

    private let reportContext =
        DeviceActivityReport.Context("Total Activity")

    private var todayFilter: DeviceActivityFilter {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())

        return DeviceActivityFilter(
            segment: .daily(
                during: DateInterval(
                    start: startOfDay,
                    end: Date()
                )
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {

                // MARK: - Screen Time Gauge

                Section("Today's usage") {
                    ZStack {

                        // Fallback shown while Screen Time data is unavailable
                        ZStack {
                            Circle()
                                .stroke(
                                    .secondary.opacity(0.18),
                                    lineWidth: 16
                                )

                            Text("Waiting for\nrefreshed data")
                                .font(
                                    .system(
                                        size: 16,
                                        weight: .semibold,
                                        design: .rounded
                                    )
                                )
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 190, height: 190)

                        // Actual Screen Time report
                        DeviceActivityReport(
                            reportContext,
                            filter: todayFilter
                        )
                        .id(store.goalMinutes)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 220
                        )
                    }
                }

                // MARK: - Daily Goal

                Section("Daily limit") {
                    HStack {
                        Slider(
                            value: $store.goalMinutes,
                            in: 15...600,
                            step: 15
                        )

                        Text(formatDuration(store.goalMinutes))
                            .monospacedDigit()
                            .frame(
                                width: 65,
                                alignment: .trailing
                            )
                    }

                }

                Section("Monitor diagnostics") {
                    LabeledContent("Monitor", value: diagnostics.monitorStatus)
                    LabeledContent("Extension entry", value: diagnostics.lastEntry)
                    LabeledContent("Last callback", value: diagnostics.lastCallback)
                    LabeledContent("Estimated widget usage", value: "\(Int(diagnostics.widgetMinutes)) min")

                    if let message = diagnostics.latestEvent {
                        Text(message)
                            .font(.caption)
                            .textSelection(.enabled)
                    }

                    Button("Refresh diagnostics") {
                        refreshDiagnostics()
                    }

                    Text("The widget estimates screen time in five-minute checkpoints. Premature callbacks are rejected and retried once. iOS may delay or miss callbacks; this can undercount actual usage. The accurate total remains in the report above.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // MARK: - Screen Time Permission

                Section("Screen Time") {
                    Button("Request Screen Time Access") {
                        Task {
                            await store.requestScreenTimeAccess()
                        }
                    }

                    Text(
                        "Screen Budget uses Apple's Screen Time framework to calculate today's device activity."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .onAppear {
                store.refreshDay()

                ScreenTimeManager.shared
                    .startMonitoringIfNeeded()
                refreshDiagnostics()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    refreshDiagnostics()
                }
            }
        }
    }

    private func refreshDiagnostics() {
        diagnostics = MonitorDiagnostics.read()
    }
}

private struct MonitorDiagnostics {
    let monitorStatus: String
    let lastEntry: String
    let lastCallback: String
    let widgetMinutes: Double
    let latestEvent: String?

    static func read() -> MonitorDiagnostics {
        guard let defaults = UserDefaults(suiteName: AppGroup.identifier) else {
            return MonitorDiagnostics(
                monitorStatus: "App Group unavailable",
                lastEntry: "Unavailable",
                lastCallback: "Unavailable",
                widgetMinutes: 0,
                latestEvent: nil
            )
        }
        let date = defaults.object(forKey: "widgetUsageDate") as? Date
        let monitorStatus = defaults.string(forKey: "widgetDiagnosticMonitorStatus") ?? "Not checked"
        let today = date.map { Calendar.current.isDateInToday($0) } ?? false
        return MonitorDiagnostics(
            monitorStatus: monitorStatus,
            lastEntry: defaults.string(forKey: "widgetDiagnosticLastEntry") ?? "None observed",
            lastCallback: defaults.string(forKey: "widgetDiagnosticLastCallback") ?? "None observed",
            widgetMinutes: today ? defaults.double(forKey: "widgetUsageMinutes") : 0,
            latestEvent: defaults.stringArray(forKey: "widgetDiagnosticLog")?.last
        )
    }
}

private func formatDuration(_ minutes: Double) -> String {
    let totalMinutes = max(0, Int(minutes))
    let hours = totalMinutes / 60
    let mins = totalMinutes % 60

    if hours == 0 {
        return "\(mins)m"
    }

    if mins == 0 {
        return "\(hours)h"
    }

    return "\(hours)h \(mins)m"
}
