import SwiftUI

// MARK: - Usage Cards

struct UsageCardsView: View {
    let flashUsage: ModelUsageSummary?
    let v4FlashUsage: ModelUsageSummary?
    let isUnavailable: Bool
    let onOpenModelDetail: (DeepSeekModel) -> Void

    @Environment(\.colorScheme) var colorScheme

    private var maxTokens: Int {
        max(flashUsage?.totalTokens ?? 0, v4FlashUsage?.totalTokens ?? 0, 1)
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
                model: .v4Flash,
                usage: v4FlashUsage,
                maxTokens: maxTokens,
                gradient: Theme.v4FlashGradient,
                tint: Theme.v4Flash,
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
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(model.statusLabel)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(tint.opacity(0.12), in: Capsule())
                            .fixedSize()
                    }

                    if let usage {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("近 7 日 · \(usage.totalTokensFormatted)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)

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
            .frame(height: 72)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.borderless)
        .disabled(usage == nil)
        .help("\(model.rawValue)\n\(model.statusDescription)")
    }

    private func costPerToken(_ usage: ModelUsageSummary) -> String {
        let cost = NSDecimalNumber(decimal: usage.costAmount).doubleValue
        guard cost > 0 else { return "" }
        let tpy = Double(usage.totalTokens) / cost
        let symbol = currencySymbol(for: usage.currencyCode)
        if tpy > 1_000_000 {
            return String(format: "%.1fM T/%@", tpy / 1_000_000, symbol)
        } else if tpy > 1_000 {
            return String(format: "%.1fK T/%@", tpy / 1_000, symbol)
        }
        return ""
    }
}
