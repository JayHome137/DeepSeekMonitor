import SwiftUI

// MARK: - Desktop Widget View
//
// macOS 原生小组件风格：毛玻璃材质、SF Pro 字体、紧凑间距
// 点击模型行可打开对应的用量详情面板

private let brandBlue = Color(red: 0.302, green: 0.420, blue: 0.996)
private let flashColor = Color.blue
private let proColor = Color.purple
private let costOrange = Color.orange

struct DesktopWidgetView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.colorScheme) private var colorScheme

    let onTapModel: ((DeepSeekModel) -> Void)?

    init(viewModel: DashboardViewModel, onTapModel: ((DeepSeekModel) -> Void)? = nil) {
        self.viewModel = viewModel
        self.onTapModel = onTapModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.bottom, 12)

            balanceText
                .padding(.bottom, 10)

            costsRow
                .padding(.bottom, 12)

            tappableModelRow(
                label: "V4 Flash",
                usage: viewModel.flashUsage,
                color: flashColor,
                model: .flash
            )
            .padding(.bottom, 6)

            tappableModelRow(
                label: "V4 Pro",
                usage: viewModel.proUsage,
                color: proColor,
                model: .pro
            )

            Spacer(minLength: 0)

            if let lastUpdated = viewModel.lastUpdated {
                Text("更新 \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(16)
        .frame(width: Theme.desktopWidgetWidth, height: Theme.desktopWidgetHeight)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.desktopWidgetCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.18), radius: 18, x: 0, y: 10)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 6) {
            BrandIconView(size: 18)

            Text("DeepSeek")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 4)

            Circle()
                .fill(viewModel.isAccountAvailable ? Color.green : Color.red)
                .frame(width: 6, height: 6)
        }
    }

    // MARK: - Balance

    private var balanceText: some View {
        Text(String(format: "¥%.2f", viewModel.totalBalance))
            .font(.system(size: 26, weight: .bold, design: .rounded))
            .foregroundStyle(viewModel.isAccountAvailable ? brandBlue : .red)
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }

    // MARK: - Costs

    private var costsRow: some View {
        HStack(spacing: 12) {
            costItem(label: "今日", value: viewModel.currentDayCost)
            costItem(label: "本月", value: viewModel.currentMonthCost)
        }
    }

    private func costItem(label: String, value: Double) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
            Text(String(format: "¥%.2f", value))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(costOrange)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - Tappable Model Rows

    private func tappableModelRow(label: String, usage: ModelUsageSummary?, color: Color, model: DeepSeekModel) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)

            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(usage?.costFormatted ?? "暂无")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onNSButtonTap { onTapModel?(model) }
    }
}
