import SwiftUI

// MARK: - DeepSeek Theme
//
// 品牌色: #4D6BFE (DeepSeek Blue)
// 所有 UI 组件的颜色、渐变、字体统一从这里取

enum Theme {
    static let panelWidth: CGFloat = 356
    static let panelHeight: CGFloat = 500
    static let panelDashboardHeight: CGFloat = 560
    static let panelEmptyHeight: CGFloat = 300
    static let panelCornerRadius: CGFloat = 22
    static let panelTopGap: CGFloat = 12
    static let detailPanelWidth: CGFloat = 420
    static let detailPanelGap: CGFloat = 10
    static let desktopWidgetWidth: CGFloat = 260
    static let desktopWidgetHeight: CGFloat = 250
    static let desktopWidgetGap: CGFloat = 10
    static let desktopWidgetCornerRadius: CGFloat = panelCornerRadius

    // MARK: - Brand Colors

    /// DeepSeek 品牌蓝 #4D6BFE
    static let brand = Color(red: 0.302, green: 0.420, blue: 0.996)

    /// 浅蓝（渐变用）
    static let brandLight = Color(red: 0.420, green: 0.522, blue: 1.0)

    /// 深蓝（按压/强调）
    static let brandDark = Color(red: 0.227, green: 0.322, blue: 0.839)

    /// 品牌色半透明（弱化背景）
    static let brandFaint = Color(red: 0.302, green: 0.420, blue: 0.996, opacity: 0.08)

    // MARK: - Model Colors

    /// V4 Flash — 蓝色系
    static let flash = Color.blue
    static let flashGradient = LinearGradient(
        colors: [.blue, .cyan.opacity(0.7)],
        startPoint: .leading, endPoint: .trailing
    )

    /// V4 Pro — 紫色系（推理模型）
    static let pro = Color.purple
    static let proGradient = LinearGradient(
        colors: [.purple, .indigo.opacity(0.7)],
        startPoint: .leading, endPoint: .trailing
    )

    // MARK: - Gradients

    /// 品牌渐变（水平）
    static let brandGradient = LinearGradient(
        colors: [brand, brandLight],
        startPoint: .leading, endPoint: .trailing
    )

    /// 品牌渐变（垂直）
    static let brandGradientVertical = LinearGradient(
        colors: [brand, brandLight],
        startPoint: .top, endPoint: .bottom
    )

    /// 图表柱体渐变
    static let chartBar = LinearGradient(
        colors: [brand.opacity(0.7), brandLight.opacity(0.3)],
        startPoint: .bottom, endPoint: .top
    )

    // MARK: - Components

    /// 卡片背景
    static func cardBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(white: 0.12).opacity(0.94)
            : Color(white: 0.97).opacity(0.92)
    }

    /// 窗口背景
    static func windowBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.13, green: 0.15, blue: 0.18).opacity(0.88)
            : Color(red: 0.96, green: 0.98, blue: 1.0).opacity(0.90)
    }

    static func panelBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.black.opacity(0.08)
    }

    static func panelShadow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.black.opacity(0.28)
            : Color.black.opacity(0.18)
    }

    /// 余额金额字体（大号等宽）
    static let balanceFont = Font.system(size: 28, weight: .bold, design: .rounded)

    /// 菜单栏图标尺寸
    static let menuBarIconSize = NSSize(width: 18, height: 18)

    // MARK: - Modifier Helpers

    /// 卡片样式
    struct CardStyle: ViewModifier {
        @Environment(\.colorScheme) var colorScheme

        func body(content: Content) -> some View {
            content
                .padding(14)
                .background(cardBackground(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// 图标容器
    struct IconCircle: View {
        let color: Color

        var body: some View {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(color)
        }
    }
}

// MARK: - View Extension

extension View {
    /// 统一卡片样式
    func themeCard() -> some View {
        modifier(Theme.CardStyle())
    }

    /// DeepSeek 品牌色 tint
    func themeTint() -> some View {
        self.tint(Theme.brand)
    }
}
