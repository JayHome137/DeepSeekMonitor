import SwiftUI

// MARK: - Usage Chart

struct UsageChartView: View {
    let dataPoints: [DashboardViewModel.ChartDataPoint]
    let totalTokens: Int
    let isUnavailable: Bool

    @Environment(\.colorScheme) var colorScheme

    private var maxTokens: Int {
        dataPoints.map(\.tokens).max() ?? 1
    }

    private var hasData: Bool {
        dataPoints.contains { $0.tokens > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 标题
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.brand)
                Text("消耗趋势")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()

                if totalTokens > 0 {
                    Text("合计 \(formattedTotal)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }

            if hasData {
                chartContent
            } else {
                emptyChart
            }
        }
        .padding(14)
        .background(Theme.cardBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Chart

    private var chartContent: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(dataPoints) { point in
                VStack(spacing: 4) {
                    // 数值
                    Text(point.formattedTokens)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    // 柱体
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.chartBar)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 4,
                            maxHeight: barHeight(for: point.tokens)
                        )
                        .animation(.easeOut(duration: 0.3), value: point.tokens)

                    // 日期
                    Text(point.dayLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .frame(height: 120)
        .padding(.top, 4)
    }

    // MARK: - Empty

    private var emptyChart: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title3)
                    .foregroundStyle(.quaternary)
                Text(isUnavailable ? "官方暂未开放实时趋势接口" : "暂无趋势数据")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(height: 80)
    }

    // MARK: - Helpers

    private func barHeight(for tokens: Int) -> CGFloat {
        guard maxTokens > 0 else { return 4 }
        return max(4, CGFloat(tokens) / CGFloat(maxTokens) * 90)
    }

    private var formattedTotal: String {
        if totalTokens >= 1_000_000 {
            String(format: "%.2fM", Double(totalTokens) / 1_000_000)
        } else if totalTokens >= 1_000 {
            String(format: "%.1fK", Double(totalTokens) / 1_000)
        } else {
            "\(totalTokens)"
        }
    }
}
