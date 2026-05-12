import SwiftUI

// MARK: - Usage Cards

struct UsageCardsView: View {
    let flashUsage: ModelUsageSummary?
    let proUsage: ModelUsageSummary?
    let isUnavailable: Bool
    let onOpenModelDetail: (DeepSeekModel) -> Void

    @Environment(\.colorScheme) var colorScheme

    private var maxTokens: Int {
        max(flashUsage?.totalTokens ?? 0, proUsage?.totalTokens ?? 0, 1)
    }

    var body: some View {
        VStack(spacing: 8) {
            UsageCardRow(
                model: .flash,
                usage: flashUsage,
                maxTokens: maxTokens,
                gradient: Theme.flashGradient,
                tint: Theme.flash,
                isUnavailable: isUnavailable,
                onOpenDetail: onOpenModelDetail
            )
            UsageCardRow(
                model: .pro,
                usage: proUsage,
                maxTokens: maxTokens,
                gradient: Theme.proGradient,
                tint: Theme.pro,
                isUnavailable: isUnavailable,
                onOpenDetail: onOpenModelDetail
            )
        }
    }
}

// MARK: - Row

private struct UsageCardRow: View {
    let model: DeepSeekModel
    let usage: ModelUsageSummary?
    let maxTokens: Int
    let gradient: LinearGradient
    let tint: Color
    let isUnavailable: Bool
    let onOpenDetail: (DeepSeekModel) -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: { onOpenDetail(model) }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(gradient.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: model.systemImageName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)

                    if let usage {
                        HStack(spacing: 6) {
                            Text("\(usage.totalTokensFormatted) Tokens")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color(.separatorColor).opacity(0.2))
                                        .frame(height: 4)

                                    Capsule()
                                        .fill(gradient)
                                        .frame(
                                            width: geo.size.width * CGFloat(usage.totalTokens) / CGFloat(maxTokens),
                                            height: 4
                                        )
                                        .animation(.easeOut(duration: 0.3), value: usage.totalTokens)
                                }
                            }
                            .frame(height: 4)
                        }
                    } else {
                        Text(isUnavailable ? "官方暂未开放实时用量接口" : "暂无数据")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                if let usage {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(usage.costFormatted)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .contentTransition(.numericText())
                            .foregroundStyle(.primary)

                        Text(costPerToken(usage))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(12)
            .background(Theme.cardBackground(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(usage == nil)
    }

    private func costPerToken(_ usage: ModelUsageSummary) -> String {
        let cost = Double(usage.costInCents) / 100.0
        guard cost > 0 else { return "" }
        let tpy = Double(usage.totalTokens) / cost
        if tpy > 1_000_000 {
            return String(format: "%.1fM T/¥", tpy / 1_000_000)
        } else if tpy > 1_000 {
            return String(format: "%.1fK T/¥", tpy / 1_000)
        }
        return ""
    }
}
