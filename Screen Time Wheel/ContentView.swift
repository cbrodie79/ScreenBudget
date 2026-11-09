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
            ),
            users: .all,
            devices: .all
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
                    Text(diagnosticDetails).font(.caption).textSelection(.enabled)
                    Button("Mark test baseline") {
                        let defaults = UserDefaults(suiteName: AppGroup.identifier)
                        defaults?.set(Date(), forKey: "widgetDiagnosticTestStarted")
                        defaults?.set(MonitorDiagnostics.read().widgetMinutes, forKey: "widgetDiagnosticTestBaseline")
                        refreshDiagnostics()
                    }
                    Text(testProgress).font(.caption)
                    Text("Report: all available users/devices; all apps/categories/websites; local midnight to now. Compare the same device scope in Settings → Screen Time. Note the report total, mark a baseline, use one app for 10 minutes, then return and refresh. Compare increases, since monitoring may begin partway through a day.")
                        .font(.footnote)
                    LabeledContent("Active activity", value: diagnostics.activeActivity)
                    LabeledContent("Extension entry", value: diagnostics.lastEntry)
                    LabeledContent("Last active callback", value: diagnostics.lastCallback)
                    LabeledContent("Accepted events", value: "\(diagnostics.acceptedCount)")
                    LabeledContent("Rejected events", value: "\(diagnostics.rejectedCount)")
                    LabeledContent("Last accepted", value: diagnostics.lastAccepted)
                    LabeledContent("Last rejected", value: diagnostics.lastRejected)
                    LabeledContent("Last legacy callback", value: diagnostics.lastLegacy)
                    LabeledContent("Estimated widget usage", value: "\(Int(diagnostics.widgetMinutes)) min")

                    if let message = diagnostics.latestEvent {
                        Text(message)
                            .font(.caption)
                            .textSelection(.enabled)
                    }

                    ForEach(Array(diagnostics.eventLog.enumerated()), id: \.offset) { _, entry in
                        Text(entry).font(.caption).textSelection(.enabled)
                    }

                    Button("Refresh diagnostics") {
                        refreshDiagnostics()
                    }

                    Text("Threshold notifications may overcount or undercount. The clock-time check rejects impossible totals but cannot verify actual screen use. Legacy callbacks are ignored.")
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
                    ScreenTimeManager.shared.startMonitoringIfNeeded()
                    refreshDiagnostics()
                }
            }
        }
    }

    private var diagnosticDetails: String {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        let registered = defaults?.string(forKey: "widgetDiagnosticRegisteredMonitors") ?? "Unknown"
        let retired = defaults?.string(forKey: "widgetDiagnosticRetiredMonitors") ?? "None"
        let config = defaults?.string(forKey: "widgetDiagnosticConfiguration") ?? "Unknown"
        let armed = (defaults?.object(forKey: "widgetDiagnosticArmedAt") as? Date)?.formatted(date: .abbreviated, time: .standard) ?? "Unknown"
        return "Registered: \(registered)\nRetired: \(retired)\nArmed: \(armed)\n\(config)"
    }

    private var testProgress: String {
        guard let defaults = UserDefaults(suiteName: AppGroup.identifier),
              let start = defaults.object(forKey: "widgetDiagnosticTestStarted") as? Date else {
            return "No test baseline marked"
        }
        guard Calendar.current.isDateInToday(start) else { return "Baseline expired; mark a new one" }
        let delta = diagnostics.widgetMinutes - defaults.double(forKey: "widgetDiagnosticTestBaseline")
        guard delta >= 0 else { return "Monitor reset; mark a new baseline" }
        return "\(Int(Date().timeIntervalSince(start) / 60)) min elapsed; widget increase: \(Int(delta)) min"
    }

    private func refreshDiagnostics() {
        diagnostics = MonitorDiagnostics.read()
    }
}

private struct MonitorDiagnostics {
    let monitorStatus: String
    let activeActivity: String
    let lastEntry: String
    let lastCallback: String
    let lastAccepted: String
    let lastRejected: String
    let lastLegacy: String
    let acceptedCount: Int
    let rejectedCount: Int
    let widgetMinutes: Double
    let latestEvent: String?
    let eventLog: [String]

    static func read() -> MonitorDiagnostics {
        guard let defaults = UserDefaults(suiteName: AppGroup.identifier) else {
            return MonitorDiagnostics(
                monitorStatus: "App Group unavailable",
                activeActivity: "Unavailable",
                lastEntry: "Unavailable",
                lastCallback: "Unavailable",
                lastAccepted: "Unavailable",
                lastRejected: "Unavailable",
                lastLegacy: "Unavailable",
                acceptedCount: 0,
                rejectedCount: 0,
                widgetMinutes: 0,
                latestEvent: nil,
                eventLog: []
            )
        }
        let date = defaults.object(forKey: "widgetUsageDate") as? Date
        let monitorStatus = defaults.string(forKey: "widgetDiagnosticMonitorStatus") ?? "Not checked"
        let today = date.map { Calendar.current.isDateInToday($0) } ?? false
        return MonitorDiagnostics(
            monitorStatus: monitorStatus,
            activeActivity: defaults.string(forKey: "widgetMonitorActivity") ?? "None",
            lastEntry: defaults.string(forKey: "widgetDiagnosticLastEntry") ?? "None observed",
            lastCallback: defaults.string(forKey: "widgetDiagnosticLastCallback") ?? "None observed",
            lastAccepted: defaults.string(forKey: "widgetDiagnosticLastAccepted") ?? "None observed",
            lastRejected: defaults.string(forKey: "widgetDiagnosticLastRejected") ?? "None observed",
            lastLegacy: defaults.string(forKey: "widgetDiagnosticLastLegacy") ?? "None observed",
            acceptedCount: today ? defaults.integer(forKey: "widgetDiagnosticAcceptedCount") : 0,
            rejectedCount: today ? defaults.integer(forKey: "widgetDiagnosticRejectedCount") : 0,
            widgetMinutes: today ? defaults.double(forKey: "widgetUsageMinutes") : 0,
            latestEvent: defaults.stringArray(forKey: "widgetDiagnosticLog")?.last,
            eventLog: Array((defaults.stringArray(forKey: "widgetDiagnosticLog") ?? []).suffix(12))
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
