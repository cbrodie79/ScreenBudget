import SwiftUI

struct TotalActivityView: View {

    let configuration: TotalActivityConfiguration

    private var progress: Double {
        guard configuration.goalMinutes > 0 else {
            return 0
        }

        return configuration.totalActivity /
            configuration.goalMinutes
    }

    private var normalProgress: Double {
        min(progress, 1.0)
    }

    private var overageProgress: Double {
        min(max(progress - 1.0, 0.0), 1.0)
    }

    var body: some View {
        ZStack {

            // Background ring
            Circle()
                .stroke(
                    .secondary.opacity(0.18),
                    lineWidth: 16
                )

            // Normal usage
            Circle()
                .trim(
                    from: 0,
                    to: normalProgress
                )
                .stroke(
                    .primary,
                    style: StrokeStyle(
                        lineWidth: 16,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))

            // Usage beyond the daily goal
            if progress > 1.0 {
                Circle()
                    .trim(
                        from: 0,
                        to: overageProgress
                    )
                    .stroke(
                        .red,
                        style: StrokeStyle(
                            lineWidth: 15,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 2) {
                Text(
                    formatDuration(
                        configuration.totalActivity
                    )
                )
                .font(
                    .system(
                        size: 26,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()

                Text(
                    progress > 1.0
                        ? "Over goal"
                        : "Today"
                )
                .font(.caption)
                .foregroundStyle(
                    progress > 1.0
                        ? .red
                        : .secondary
                )
            }
        }
        .padding(8)
        .background(
            Color(
                uiColor:
                    .secondarySystemGroupedBackground
            )
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

#Preview {
    TotalActivityView(
        configuration: TotalActivityConfiguration(
            totalActivity: 83,
            goalMinutes: 120
        )
    )
    .frame(width: 220, height: 220)
}
