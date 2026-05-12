import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: DashboardViewModel

    let onOpenSettings: () -> Void
    let onOpenModelDetail: (DeepSeekModel) -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.panelCornerRadius, style: .continuous)
                .fill(Theme.windowBackground(for: colorScheme))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.panelCornerRadius, style: .continuous)
                        .strokeBorder(Theme.panelBorder(for: colorScheme), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 12) {
                header

                if viewModel.hasAPIKey {
                    dashboard
                } else {
                    emptyState
                }
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelCornerRadius, style: .continuous))
        .shadow(color: Theme.panelShadow(for: colorScheme), radius: 20, x: 0, y: 12)
        .frame(width: Theme.panelWidth, height: Theme.panelHeight)
        .background(Color.clear)
    }

    private var header: some View {
        HStack(spacing: 10) {
            BrandIconView(size: 22)

            VStack(alignment: .leading, spacing: 0) {
                Text("DeepSeek Monitor")
                    .font(.title2.weight(.semibold))
            }

            Spacer()

            Button(action: {
                Task { await viewModel.refresh() }
            }) {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("刷新")
            .disabled(viewModel.isLoading || !viewModel.hasAPIKey)

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("设置")

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("关闭")
        }
    }

    private var dashboard: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                if let errorMessage = viewModel.errorMessage {
                    statusMessage(errorMessage, systemImage: "xmark.octagon.fill", color: .red)
                }

                BalanceCardView(
                    totalBalance: viewModel.totalBalance,
                    currentDayCost: viewModel.currentDayCost,
                    currentMonthCost: viewModel.currentMonthCost,
                    isAvailable: viewModel.isAccountAvailable
                )

                UsageCardsView(
                    flashUsage: viewModel.flashUsage,
                    proUsage: viewModel.proUsage,
                    isUnavailable: viewModel.isUsageUnavailable,
                    onOpenModelDetail: onOpenModelDetail
                )

                UsageChartView(
                    dataPoints: viewModel.chartData,
                    totalTokens: viewModel.totalTokens,
                    isUnavailable: viewModel.isUsageUnavailable
                )
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Theme.brand)

            VStack(spacing: 6) {
                Text("需要配置 API Key")
                    .font(.headline)
                Text("配置后即可查看余额和最近用量。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("打开设置", action: onOpenSettings)
                .buttonStyle(.borderedProminent)
                .tint(Theme.brand)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func statusMessage(_ text: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer()
        }
        .padding(10)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
