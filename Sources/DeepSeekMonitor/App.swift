import SwiftUI
import AppKit

// MARK: - App Entry Point

@main
struct DeepSeekMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 菜单栏应用不需要窗口，使用 Settings 作为偏好设置入口
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 初始化菜单栏管理器
        menuBarManager = MenuBarManager()

        // 如果后续需要监听系统事件（休眠/唤醒等），在这里注册
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarManager?.cleanup()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - System Events

    @objc private func systemWillSleep() {
        // 系统休眠前：暂停定时刷新
        menuBarManager?.stopAutoRefresh()
    }

    @objc private func systemDidWake() {
        // 系统唤醒后：恢复定时刷新 + 立即刷新一次
        menuBarManager?.startAutoRefresh()
        Task { [weak self] in
            await self?.menuBarManager?.viewModel.refresh()
        }
    }
}
