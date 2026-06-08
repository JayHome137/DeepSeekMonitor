import WidgetKit
import SwiftUI

// MARK: - Widget Colors

private let brandBlue = Color(red: 0.302, green: 0.420, blue: 0.996)
private let brandBlueLight = Color(red: 0.420, green: 0.522, blue: 1.0)
private let costOrange = Color.orange
private let glassBase = Color(red: 0.035, green: 0.055, blue: 0.060)
private let textStrong = Color(red: 0.98, green: 0.99, blue: 1.0)
private let textMain = Color(red: 0.86, green: 0.90, blue: 0.91)
private let textMuted = Color(red: 0.70, green: 0.76, blue: 0.78)
private let textFaint = Color(red: 0.56, green: 0.62, blue: 0.64)

// MARK: - Widget Configuration

struct DeepSeekWidget: Widget {
    let kind: String = "com.deepseek.monitor.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            DeepSeekWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("DeepSeek Monitor")
        .description("查看余额和模型用量")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Entry View

struct DeepSeekWidgetEntryView: View {
    var entry: WidgetEntry
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if entry.isWidgetEnabled {
                MediumWidgetView(entry: entry)
            } else {
                DisabledWidgetView()
            }
        }
        .containerBackground(for: .widget) {
            WidgetPanelBackground(colorScheme: colorScheme)
        }
        .unredacted()
    }
}

private struct WidgetPanelBackground: View {
    let colorScheme: ColorScheme

    var body: some View {
        ZStack {
            Color.clear
                .background(.ultraThinMaterial)

            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.18 : 0.28),
                    Color.white.opacity(colorScheme == .dark ? 0.055 : 0.12),
                    Color.white.opacity(0.015),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            glassBase
                .opacity(colorScheme == .dark ? 0.08 : 0.018)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.07),
                    lineWidth: 0.8
                )
        }
    }
}

// MARK: - Shared Pieces

private struct WidgetHeader: View {
    let title: String
    let isAvailable: Bool

    var body: some View {
        HStack(spacing: 7) {
            BrandGlyph()

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(textStrong)
                .widgetAccentable(false)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 4)

            Circle()
                .fill(isAvailable ? Color.green : Color.red)
                .frame(width: 6, height: 6)
        }
    }
}

private struct BrandGlyph: View {
    var body: some View {
        ZStack {
            Image("widget-icon")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .widgetAccentable(false)
        }
        .frame(width: 30, height: 30)
    }
}

private enum ModelBadgeKind {
    case flash
    case pro

    var background: Color {
        switch self {
        case .flash:
            Color(red: 0.10, green: 0.22, blue: 0.24)
        case .pro:
            Color(red: 0.22, green: 0.16, blue: 0.30)
        }
    }

    var foreground: Color {
        switch self {
        case .flash:
            Color(red: 0.25, green: 0.56, blue: 1.0)
        case .pro:
            Color(red: 0.94, green: 0.18, blue: 1.0)
        }
    }

    var symbolName: String {
        switch self {
        case .flash:
            "bolt.fill"
        case .pro:
            "brain.head.profile"
        }
    }
}

private struct ModelBadge: View {
    let kind: ModelBadgeKind
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .fill(kind.background)

            Image(systemName: kind.symbolName)
                .font(.system(size: size * 0.52, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(kind.foreground)
                .widgetAccentable(false)
        }
        .frame(width: size, height: size)
        .widgetAccentable(false)
    }
}

private struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.24), lineWidth: 0.7)
            )
    }
}

private struct BalanceAmount: View {
    let entry: WidgetEntry
    let size: CGFloat

    var body: some View {
        Text(entry.hasData ? currency(entry.balance) : "¥--")
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(entry.hasData ? (entry.isAvailable ? brandBlueLight : Color.red.opacity(0.95)) : textMuted)
            .widgetAccentable(false)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
    }
}

private struct CostPill: View {
    let label: String
    let value: Double?

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(textMuted)
                .widgetAccentable(false)

            Text(value.map(currency) ?? "¥--")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(costOrange.opacity(0.98))
                .widgetAccentable(false)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct ModelCostRow: View {
    let entry: WidgetEntry
    let kind: ModelBadgeKind
    let costCents: Int
    let url: String
    let showsChevron: Bool
    var height: CGFloat = 36

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 8) {
                ModelBadge(kind: kind, size: 25)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(entry.hasData ? costFormatted(costCents) : "--")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(entry.hasData ? textStrong : textFaint)
                    .widgetAccentable(false)
                    .lineLimit(1)
                    .frame(width: 58, alignment: .trailing)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(textFaint)
                        .frame(width: 8)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(modelRowBackground)
        }
    }

    private var modelRowBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.115),
                        Color.white.opacity(0.040),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.24),
                                Color.white.opacity(0.020),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.6
                    )
            }
            .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Disabled Widget

private struct DisabledWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: "DeepSeek", isAvailable: false)

            Spacer(minLength: 0)

            GlassCard {
                VStack(alignment: .leading, spacing: 5) {
                    Text("小组件已关闭")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(textMain)
                        .widgetAccentable(false)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text("在设置中重新启用")
                        .font(.caption2)
                        .foregroundStyle(textMuted)
                        .widgetAccentable(false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
        }
        .padding(16)
        .widgetURL(URL(string: "deepseekmonitor://settings"))
    }
}

// MARK: - Medium Widget

private struct MediumWidgetView: View {
    var entry: WidgetEntry

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            leftColumn
                .frame(maxWidth: .infinity, alignment: .leading)
            rightColumn
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: "DeepSeek Monitor", isAvailable: entry.isAvailable)
                .padding(.bottom, 10)

            BalanceAmount(entry: entry, size: 28)
                .padding(.bottom, 10)

            HStack(spacing: 10) {
                CostPill(label: "今日", value: entry.hasData ? entry.dayCost : nil)
                CostPill(label: "本月", value: entry.hasData ? entry.monthCost : nil)
            }

            Spacer(minLength: 0)

            if entry.hasData {
                Text("更新 \(entry.lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(textFaint)
                    .widgetAccentable(false)
            }
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("模型用量")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(textMain)
                .widgetAccentable(false)

            ModelCostRow(
                entry: entry,
                kind: .flash,
                costCents: entry.flashCostCents,
                url: "deepseekmonitor://flash",
                showsChevron: true,
                height: 38
            )

            ModelCostRow(
                entry: entry,
                kind: .pro,
                costCents: entry.proCostCents,
                url: "deepseekmonitor://pro",
                showsChevron: true,
                height: 38
            )

            Spacer(minLength: 0)
        }
    }
}

private func currency(_ value: Double) -> String {
    String(format: "¥%.2f", value)
}

private func costFormatted(_ cents: Int) -> String {
    currency(Double(cents) / 100.0)
}

// MARK: - Preview

#Preview(as: .systemMedium) {
    DeepSeekWidget()
} timeline: {
    WidgetEntry.placeholder
    WidgetEntry(
        date: Date(),
        isWidgetEnabled: true,
        balance: 1234.56,
        isAvailable: true,
        dayCost: 12.34,
        monthCost: 98.76,
        flashTokens: 150000,
        flashCostCents: 560,
        proTokens: 85000,
        proCostCents: 1230,
        lastUpdated: Date(),
        hasData: true
    )
}
