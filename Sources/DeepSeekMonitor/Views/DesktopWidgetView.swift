import SwiftUI

struct DesktopWidgetView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                BrandIconView(size: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text("DeepSeek")
                        .font(.headline.weight(.semibold))
                    Text(viewModel.isAccountAvailable ? "账户可用" : "等待数据")
                        .font(.caption2)
                        .foregroundStyle(viewModel.isAccountAvailable ? .green : .secondary)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("账户余额")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "¥%.2f", viewModel.totalBalance))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(viewModel.isAccountAvailable ? Theme.brand : .red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            HStack(spacing: 10) {
                widgetMetric(title: "今日", value: viewModel.currentDayCost)
                widgetMetric(title: "本月", value: viewModel.currentMonthCost)
            }

            miniUsageRow(title: "V4 Flash", usage: viewModel.flashUsage, color: Theme.flash)
            miniUsageRow(title: "V4 Pro", usage: viewModel.proUsage, color: Theme.pro)

            if let lastUpdated = viewModel.lastUpdated {
                Text("更新 \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(16)
        .frame(width: Theme.desktopWidgetWidth, height: Theme.desktopWidgetHeight)
        .background(Theme.windowBackground(for: colorScheme))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.desktopWidgetCornerRadius, style: .continuous)
                .strokeBorder(Theme.panelBorder(for: colorScheme), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.desktopWidgetCornerRadius, style: .continuous))
        .shadow(color: Theme.panelShadow(for: colorScheme), radius: 18, x: 0, y: 10)
    }

    private func widgetMetric(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "¥%.2f", value))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func miniUsageRow(title: String, usage: ModelUsageSummary?, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(usage?.costFormatted ?? "暂无")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }
}
