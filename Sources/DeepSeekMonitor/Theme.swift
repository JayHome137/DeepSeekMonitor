import SwiftUI

// MARK: - DeepSeek Theme
//
// 品牌色: #4D6BFE (DeepSeek Blue)
// 所有 UI 组件的颜色、渐变、字体统一从这里取

enum Theme {
    static let panelWidth: CGFloat = 374
    static let panelDashboardHeight: CGFloat = 588
    static let panelEmptyHeight: CGFloat = 300
    static let panelCornerRadius: CGFloat = 22
    static let panelTopGap: CGFloat = 12
    static let detailPanelWidth: CGFloat = panelWidth
    static let detailPanelHeight: CGFloat = panelDashboardHeight
    static let detailPanelGap: CGFloat = 10

    // MARK: - Brand Colors

    /// DeepSeek 品牌蓝 #4D6BFE
    static let brand = Color(red: 0.302, green: 0.420, blue: 0.996)

    /// 浅蓝（渐变用）
    static let brandLight = Color(red: 0.420, green: 0.522, blue: 1.0)

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

    /// 图表柱体渐变
    static let chartBar = LinearGradient(
        colors: [brand.opacity(0.7), brandLight.opacity(0.3)],
        startPoint: .bottom, endPoint: .top
    )

    // MARK: - Components

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

    /// 菜单栏图标尺寸
    static let menuBarIconSize = NSSize(width: 18, height: 18)
}
