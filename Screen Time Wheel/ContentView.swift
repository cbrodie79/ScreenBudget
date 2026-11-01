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
                    LabeledContent("Test starts", value: diagnostics.startLabel)
                    LabeledContent("Test ends", value: diagnostics.endLabel)
                    LabeledContent("Extension entry", value: diagnostics.lastEntry)
                    LabeledContent("Last callback", value: diagnostics.lastCallback)
                    LabeledContent("Widget counter", value: "\(Int(diagnostics.widgetMinutes)) min")

                    if let message = diagnostics.latestEvent {
                        Text(message)
                            .font(.caption)
                            .textSelection(.enabled)
                    }

                    Button("Refresh diagnostics") {
                        refreshDiagnostics()
                    }

                    Text("Registration only confirms monitoring was requested. The extension entry and callback fields update only when iOS executes those methods. This one-time diagnostic test begins at the scheduled future time and lasts 45 minutes. It monitors one 5-minute threshold; the widget will not advance beyond 5 minutes. Earlier usage is excluded, and premature callbacks are logged and rejected.")
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
    let startLabel: String
    let endLabel: String
    let lastEntry: String
    let lastCallback: String
    let widgetMinutes: Double
    let latestEvent: String?

    static func read() -> MonitorDiagnostics {
        guard let defaults = UserDefaults(suiteName: AppGroup.identifier) else {
            return MonitorDiagnostics(
                monitorStatus: "App Group unavailable",
                startLabel: "Unavailable",
                endLabel: "Unavailable",
                lastEntry: "Unavailable",
                lastCallback: "Unavailable",
                widgetMinutes: 0,
                latestEvent: nil
            )
        }
        let date = defaults.object(forKey: "widgetUsageDate") as? Date
        let scheduledStart = defaults.object(forKey: "widgetDiagnosticScheduledStart") as? Date
        let scheduledEnd = defaults.object(forKey: "widgetDiagnosticScheduledEnd") as? Date
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .short
        timeFormatter.timeStyle = .short
        let monitorStatus = defaults.string(forKey: "widgetDiagnosticMonitorStatus") ?? "Not checked"
        let effectiveStatus = (scheduledEnd.map { Date() >= $0 } ?? false) && monitorStatus != "Start failed" ? "Test window ended" : monitorStatus
        let today = date.map { Calendar.current.isDateInToday($0) } ?? false
        return MonitorDiagnostics(
            monitorStatus: effectiveStatus,
            startLabel: scheduledStart.map { timeFormatter.string(from: $0) } ?? "Not scheduled",
            endLabel: scheduledEnd.map { timeFormatter.string(from: $0) } ?? "Not scheduled",
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
