import SwiftUI

// MARK: - Balance Card

struct BalanceCardView: View {
    let totalBalance: Double
    let currentDayCost: Double
    let currentMonthCost: Double
    let isAvailable: Bool

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("账户余额", systemImage: "creditcard.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                availabilityBadge
            }

            Text(String(format: "¥%.2f", totalBalance))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isAvailable ? Theme.brand : .red)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                compactMetric(
                    title: "当日消耗",
                    systemImage: "sun.max",
                    value: String(format: "¥%.2f", currentDayCost)
                )

                compactMetric(
                    title: "本月消费",
                    systemImage: "calendar",
                    value: String(format: "¥%.2f", currentMonthCost)
                )
            }
        }
        .padding(14)
        .background(Theme.cardBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var availabilityBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isAvailable ? .green : .red)
                .frame(width: 6, height: 6)
            Text(isAvailable ? "可用" : "异常")
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(isAvailable ? .green : .red)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background((isAvailable ? Color.green : Color.red).opacity(0.1))
        .clipShape(Capsule())
    }

    private func compactMetric(title: String, systemImage: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text(title)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.orange)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
