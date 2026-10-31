import SwiftUI
import DeviceActivity

struct ContentView: View {

    @EnvironmentObject private var store: GaugeStore

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
