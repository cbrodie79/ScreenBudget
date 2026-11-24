import SwiftUI
import DeviceActivity
import UIKit

struct ContentView: View {

    @EnvironmentObject private var store: GaugeStore
    @State private var diagnosticExportURL: URL?
    @State private var showingExportSheet = false
    @State private var exportFailed = false

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

                Section("Widget diagnostics") {
                    Button("Capture snapshot") {
                        ScreenTimeManager.shared.captureSnapshot("manual_snapshot")
                    }
                    Button("Mark discrepancy") {
                        ScreenTimeManager.shared.captureSnapshot("discrepancy_marked")
                    }
                    Button("Export diagnostic logs") {
                        diagnosticExportURL = ScreenTimeManager.shared.exportDiagnostics()
                        showingExportSheet = diagnosticExportURL != nil
                        exportFailed = diagnosticExportURL == nil
                    }
                    Text("Logs are saved locally for up to seven days. Mark a discrepancy before opening or refreshing the widget when possible. The export includes timestamps and widget estimates, not your app usage history.")
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
                // Capture the extension's last saved estimate BEFORE any app-side reset or monitoring recovery.
                ScreenTimeManager.shared.captureSnapshot("app_open_before_sync")
                store.refreshDay()
                ScreenTimeManager.shared.startMonitoringIfNeeded()
                ScreenTimeManager.shared.captureSnapshot("app_open_after_sync")
            }
            .sheet(isPresented: $showingExportSheet) {
                if let diagnosticExportURL {
                    DiagnosticShareSheet(items: [diagnosticExportURL])
                }
            }
            .alert("Unable to export diagnostics", isPresented: $exportFailed) {
                Button("OK", role: .cancel) {}
            }

        }
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

private struct DiagnosticShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
