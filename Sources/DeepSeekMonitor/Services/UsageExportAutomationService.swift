import Foundation
import AppKit
import WebKit

extension Notification.Name {
    static let usageExportDownloadFinished = Notification.Name("usage_export_download_finished")
}

struct UsageExportDownloadEvent {
    let taskID: UUID
    let fileURL: URL
    let referenceDate: Date
}

private enum UsageExportScriptMessage {
    static let download = "usageExportDownload"
}

private enum UsageExportAutomationState {
    case idle
    case locatingRangeTrigger
    case selectingRange
    case locatingExportButton
    case waitingForDownload
}

private struct UsageExportTask {
    let id: UUID
    let referenceDate: Date
}

@MainActor
final class UsageExportAutomationService: NSObject, ObservableObject {
    static let shared = UsageExportAutomationService()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled {
                statusMessage = "自动导出已开启"
                requestExport(manual: false)
            } else {
                resetAutomationState()
                statusMessage = "自动导出已关闭"
            }
        }
    }

    @Published var autoExportIntervalSeconds: TimeInterval {
        didSet {
            let normalized = Self.normalizedInterval(autoExportIntervalSeconds)
            if normalized != autoExportIntervalSeconds {
                autoExportIntervalSeconds = normalized
                return
            }

            UserDefaults.standard.set(normalized, forKey: Self.intervalKey)
            restartTimerIfNeeded()
        }
    }

    @Published private(set) var statusMessage: String
    @Published private(set) var isLoggedIn = false
    @Published private(set) var lastDownloadFileName: String?

    private static let enabledKey = "usage_export_automation_enabled"
    private static let intervalKey = "usage_export_automation_interval_seconds"
    private static let usageURL = URL(string: "https://platform.deepseek.com/usage")!
    private static let loginURL = URL(string: "https://platform.deepseek.com/sign_in")!
    private static let defaultAutoExportInterval: TimeInterval = 300

    private var timer: Timer?
    private var window: NSWindow?
    private var webView: WKWebView?
    private var pendingExportRequest = false
    private var lastAttemptAt: Date?
    private var activeDownload: WKDownload?
    private var activeDownloadTaskID: UUID?
    private var activeDownloadDestination: URL?
    private var activeDownloadFinalDestination: URL?
    private var rangeTriggerRetryCount = 0
    private var rangeOptionRetryCount = 0
    private var exportLookupRetryCount = 0
    private var automationState: UsageExportAutomationState = .idle
    private var downloadWatchTimer: Timer?
    private var exportTriggeredAt: Date?
    private var downloadWatchAttempts = 0
    private var activeExportTask: UsageExportTask?

    private override init() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        let interval = UserDefaults.standard.double(forKey: Self.intervalKey)
        isEnabled = enabled
        autoExportIntervalSeconds = Self.normalizedInterval(interval)
        statusMessage = enabled ? "自动导出待命中" : "自动导出未开启"
        super.init()
        if interval != autoExportIntervalSeconds {
            UserDefaults.standard.set(autoExportIntervalSeconds, forKey: Self.intervalKey)
        }
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: autoExportIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTimerTick()
            }
        }
        if isEnabled {
            requestExport(manual: false)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        resetAutomationState()
    }

    func closeWindow() {
        window?.orderOut(nil)
    }

    func openLoginWindow() {
        let webView = ensureWebView()
        ensureWindow(with: webView)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if webView.url == nil {
            webView.load(URLRequest(url: Self.loginURL))
        }
    }

    func triggerManualExport() {
        requestExport(manual: true)
    }

    func reportImportSuccess(fileNames: [String]) {
        statusMessage = "已导入 \(fileNames.joined(separator: " + ")) · 官方导出时区"
    }

    func reportImportFailure(_ message: String) {
        statusMessage = "下载完成但导入失败：\(message)"
    }

    private func handleTimerTick() {
        guard isEnabled else { return }
        guard window?.isVisible != true else {
            statusMessage = "登录窗口打开中，本次后台导出已暂缓"
            return
        }
        requestExport(manual: false)
    }

    private func restartTimerIfNeeded() {
        guard timer != nil else { return }
        start()
    }

    private static func normalizedInterval(_ value: TimeInterval) -> TimeInterval {
        let allowed: [TimeInterval] = [300, 600, 1800]
        return allowed.contains(value) ? value : defaultAutoExportInterval
    }

    private func requestExport(manual: Bool) {
        guard automationState == .idle else {
            if manual {
                statusMessage = "已有本月同步任务正在进行"
            }
            return
        }
        guard manual || window?.isVisible != true else {
            statusMessage = "登录窗口打开中，本次后台导出已暂缓"
            return
        }
        if let lastAttemptAt, Date().timeIntervalSince(lastAttemptAt) < 25, manual == false {
            return
        }

        resetAutomationState()
        lastAttemptAt = Date()
        pendingExportRequest = true
        automationState = .locatingRangeTrigger
        rangeTriggerRetryCount = 0
        rangeOptionRetryCount = 0
        exportLookupRetryCount = 0
        activeExportTask = UsageExportTask(
            id: UUID(),
            referenceDate: Date()
        )

        let webView = ensureWebView()
        window?.orderOut(nil)
        statusMessage = "正在后台刷新 DeepSeek 本月用量..."
        let request = URLRequest(
            url: Self.usageURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        webView.load(request)
    }

    private func ensureWebView() -> WKWebView {
        if let webView {
            return webView
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(self, name: UsageExportScriptMessage.download)
        configuration.userContentController.addUserScript(WKUserScript(
            source: downloadBridgeScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1180, height: 860), configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.webView = webView
        return webView
    }

    private func ensureWindow(with webView: WKWebView) {
        if let window {
            window.contentView = webView
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DeepSeek 登录与导出"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = webView
        self.window = window
    }

    private func attemptExportClick() {
        guard let webView,
              automationState == .locatingRangeTrigger,
              let taskID = activeExportTask?.id else { return }

        let script = """
        (() => {
          window.__deepseekActiveExportTaskID = '\(taskID.uuidString)';
          const normalize = (value) => (value || '').replace(/\\s+/g, ' ').trim();
          const compact = (value) => normalize(value).toLowerCase().replace(/\\s+/g, '');
          const visible = (el) => {
            if (!el) return false;
            const rect = el.getBoundingClientRect();
            const style = window.getComputedStyle(el);
            return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none' && Number(style.opacity || 1) > 0;
          };
          const textOf = (el) => normalize(
            el.innerText ||
            el.textContent ||
            el.getAttribute && el.getAttribute('aria-label') ||
            el.getAttribute && el.getAttribute('title') ||
            ''
          );
          const activate = (el) => {
            if (!el) return false;
            try { el.scrollIntoView({ block: 'center', inline: 'center' }); } catch {}
            const rect = el.getBoundingClientRect();
            const eventInit = {
              clientX: rect.left + rect.width / 2,
              clientY: rect.top + rect.height / 2,
              bubbles: true,
              cancelable: true,
              composed: true,
              button: 0
            };
            if (typeof el.focus === 'function') el.focus();
            for (const type of ['pointerdown', 'mousedown', 'pointerup', 'mouseup']) {
              const EventType = type.startsWith('pointer') && typeof PointerEvent !== 'undefined' ? PointerEvent : MouseEvent;
              el.dispatchEvent(new EventType(type, eventInit));
            }
            if (typeof el.click === 'function') el.click();
            return true;
          };

          const needsLogin = !!document.querySelector('input[type="password"]') || /sign_in|login/i.test(location.href);
          if (needsLogin) return { opened: false, needsLogin: true, url: location.href };

          const labelNames = ['时间维度', '时间范围', 'time range', 'date range', 'time dimension', 'time'];
          const presetNames = new Set(['近7天', '近30天', '本月', '上月', 'last7days', 'last30days', 'thismonth', 'lastmonth']);
          const allVisible = Array.from(document.querySelectorAll('button, [role="button"], [aria-haspopup], [tabindex], label, p, span, div')).filter(visible);
          const labels = allVisible.filter((el) => {
            const text = normalize(textOf(el)).toLowerCase();
            return labelNames.some((name) => text === name || (name !== 'time' && text.includes(name)));
          });
          const seen = new Set();
          const candidates = [];

          for (const node of allVisible) {
            const cursor = window.getComputedStyle(node).cursor || '';
            const target = node.closest && node.closest('button, [role="button"], [aria-haspopup], [tabindex]');
            const candidate = target || (cursor === 'pointer' ? node : null);
            if (!candidate || seen.has(candidate) || !visible(candidate)) continue;
            seen.add(candidate);

            const text = textOf(candidate);
            const compactText = compact(text);
            const lowerText = normalize(text).toLowerCase();
            if (!text || lowerText === '导出' || lowerText === 'export') continue;

            let score = 0;
            const role = (candidate.getAttribute('role') || '').toLowerCase();
            const tag = (candidate.tagName || '').toLowerCase();
            const hasPopup = candidate.hasAttribute('aria-haspopup');
            let relevance = 0;
            if (hasPopup) score += 180;
            if (role === 'button') score += 60;
            if (tag === 'button') score += 50;
            if (presetNames.has(compactText)) {
              score += 180;
              relevance += 2;
            }
            if (/\\d{1,4}[\\/-]\\d{1,2}.*[-~至].*\\d{1,4}[\\/-]\\d{1,2}/.test(text)) {
              score += 130;
              relevance += 2;
            }
            if (text.length <= 32) score += 20;

            for (const label of labels) {
              if (candidate === label || candidate.contains(label) || label.contains(candidate)) {
                score += 140;
                relevance += 2;
              }
              const labelRect = label.getBoundingClientRect();
              const candidateRect = candidate.getBoundingClientRect();
              const verticalDistance = Math.abs(
                (labelRect.top + labelRect.height / 2) - (candidateRect.top + candidateRect.height / 2)
              );
              if (verticalDistance < 90 && candidateRect.left >= labelRect.left - 20) {
                score += Math.max(0, 120 - verticalDistance);
                relevance += 1;
              }

              let ancestor = label.parentElement;
              for (let depth = 0; ancestor && ancestor !== document.body && depth < 5; depth += 1) {
                if (ancestor.contains(candidate)) {
                  score += 90 - depth * 12;
                  relevance += 1;
                }
                ancestor = ancestor.parentElement;
              }
            }

            if (relevance > 0) candidates.push({ candidate, score, text });
          }

          candidates.sort((lhs, rhs) => {
            if (rhs.score !== lhs.score) return rhs.score - lhs.score;
            const lhsRect = lhs.candidate.getBoundingClientRect();
            const rhsRect = rhs.candidate.getBoundingClientRect();
            return lhsRect.width * lhsRect.height - rhsRect.width * rhsRect.height;
          });

          const best = candidates[0];
          if (!best) return { opened: false, needsLogin: false, url: location.href };
          activate(best.candidate);
          return { opened: true, needsLogin: false, text: best.text, score: best.score, url: location.href };
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self,
                      self.activeExportTask?.id == taskID,
                      self.automationState == .locatingRangeTrigger else { return }

                if let error {
                    self.finishAutomationFailure("时间筛选器触发失败：\(error.localizedDescription)")
                    return
                }

                let state = result as? [String: Any]
                let opened = state?["opened"] as? Bool ?? false
                let needsLogin = state?["needsLogin"] as? Bool ?? false

                if opened {
                    self.isLoggedIn = true
                    self.automationState = .selectingRange
                    self.statusMessage = "正在选择本月..."
                    self.rangeOptionRetryCount = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                        Task { @MainActor [weak self] in
                            guard self?.activeExportTask?.id == taskID else { return }
                            self?.attemptCurrentMonthSelection()
                        }
                    }
                    return
                }

                if needsLogin {
                    self.isLoggedIn = false
                    self.resetAutomationState()
                    self.statusMessage = "登录状态已失效，请在设置里手动打开登录页"
                } else {
                    if self.rangeTriggerRetryCount < 4 {
                        self.rangeTriggerRetryCount += 1
                        self.statusMessage = "页面已打开，正在等待时间筛选器..."
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                            Task { @MainActor [weak self] in
                                guard self?.activeExportTask?.id == taskID else { return }
                                self?.attemptExportClick()
                            }
                        }
                    } else {
                        self.finishAutomationFailure("已进入 usage 页面，但没有找到时间维度筛选器")
                    }
                }

            }
        }
    }

    private func attemptCurrentMonthSelection() {
        guard let webView,
              automationState == .selectingRange,
              let taskID = activeExportTask?.id else { return }

        let script = """
        (() => {
          const normalize = (value) => (value || '').replace(/\\s+/g, ' ').trim();
          const compact = (value) => normalize(value).toLowerCase().replace(/\\s+/g, '');
          const visible = (el) => {
            if (!el) return false;
            const rect = el.getBoundingClientRect();
            const style = window.getComputedStyle(el);
            return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none' && Number(style.opacity || 1) > 0;
          };
          const textOf = (el) => normalize(
            el.innerText ||
            el.textContent ||
            el.getAttribute && el.getAttribute('aria-label') ||
            el.getAttribute && el.getAttribute('title') ||
            ''
          );
          const activate = (el) => {
            if (!el) return false;
            try { el.scrollIntoView({ block: 'center', inline: 'center' }); } catch {}
            const rect = el.getBoundingClientRect();
            const eventInit = {
              clientX: rect.left + rect.width / 2,
              clientY: rect.top + rect.height / 2,
              bubbles: true,
              cancelable: true,
              composed: true,
              button: 0
            };
            if (typeof el.focus === 'function') el.focus();
            for (const type of ['pointerdown', 'mousedown', 'pointerup', 'mouseup']) {
              const EventType = type.startsWith('pointer') && typeof PointerEvent !== 'undefined' ? PointerEvent : MouseEvent;
              el.dispatchEvent(new EventType(type, eventInit));
            }
            if (typeof el.click === 'function') el.click();
            return true;
          };

          const exactNames = new Set(['本月', 'thismonth']);
          const nodes = Array.from(document.querySelectorAll('button, [role="button"], [role="option"], [role="menuitem"], li, span, div')).filter(visible);
          const seen = new Set();
          const candidates = [];

          for (const node of nodes) {
            if (!exactNames.has(compact(textOf(node)))) continue;
            const target = node.closest && node.closest('[role="option"], [role="menuitem"], li, button, [role="button"]');
            const candidate = target || node;
            if (seen.has(candidate) || !visible(candidate)) continue;
            seen.add(candidate);

            let score = 0;
            const role = (candidate.getAttribute('role') || '').toLowerCase();
            const tag = (candidate.tagName || '').toLowerCase();
            if (role === 'option' || role === 'menuitem') score += 240;
            if (tag === 'li') score += 160;
            if (tag === 'button' || role === 'button') score += 60;
            if (candidate.hasAttribute('aria-haspopup')) score -= 180;
            if (candidate === document.activeElement || candidate.contains(document.activeElement)) score -= 100;

            let ancestor = candidate.parentElement;
            for (let depth = 0; ancestor && ancestor !== document.body && depth < 5; depth += 1) {
              const context = compact(textOf(ancestor));
              if (context.includes('近30天') || context.includes('last30days')) score += 120 - depth * 15;
              if (context.includes('本月') || context.includes('thismonth')) score += 80 - depth * 10;
              ancestor = ancestor.parentElement;
            }
            candidates.push({ candidate, score });
          }

          candidates.sort((lhs, rhs) => rhs.score - lhs.score);
          const best = candidates[0];
          if (!best) return { selected: false };
          activate(best.candidate);
          return { selected: true, score: best.score };
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self,
                      self.activeExportTask?.id == taskID,
                      self.automationState == .selectingRange else { return }
                if let error {
                    self.finishAutomationFailure("选择本月失败：\(error.localizedDescription)")
                    return
                }

                let state = result as? [String: Any]
                if state?["selected"] as? Bool == true {
                    self.automationState = .locatingExportButton
                    self.statusMessage = "已选择本月，等待页面更新..."
                    self.exportLookupRetryCount = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                        Task { @MainActor [weak self] in
                            guard self?.activeExportTask?.id == taskID else { return }
                            self?.attemptFinalExportClick()
                        }
                    }
                    return
                }

                if self.rangeOptionRetryCount < 4 {
                    self.rangeOptionRetryCount += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                        Task { @MainActor [weak self] in
                            guard self?.activeExportTask?.id == taskID else { return }
                            self?.attemptCurrentMonthSelection()
                        }
                    }
                } else {
                    self.finishAutomationFailure("时间筛选器已打开，但没有找到“本月”选项")
                }
            }
        }
    }

    private func attemptFinalExportClick() {
        guard let webView,
              automationState == .locatingExportButton,
              let taskID = activeExportTask?.id else { return }

        let script = """
        (() => {
          const normalize = (value) => (value || '').replace(/\\s+/g, ' ').trim();
          const compact = (value) => normalize(value).toLowerCase().replace(/\\s+/g, '');
          const semantic = (value) => compact(value).replace(/[^a-z0-9\\u4e00-\\u9fff]/g, '');
          const visible = (el) => {
            if (!el) return false;
            const rect = el.getBoundingClientRect();
            const style = window.getComputedStyle(el);
            return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none' && Number(style.opacity || 1) > 0;
          };
          const textOf = (el) => normalize(
            el.innerText ||
            el.textContent ||
            el.getAttribute && el.getAttribute('aria-label') ||
            el.getAttribute && el.getAttribute('title') ||
            ''
          );
          const contextOf = (el) => {
            const parts = [];
            let current = el;
            for (let depth = 0; current && current !== document.body && depth < 5; depth += 1) {
              parts.push(textOf(current));
              current = current.parentElement;
            }
            return normalize(parts.join(' | '));
          };
          const activate = (el) => {
            if (!el) return false;
            try { el.scrollIntoView({ block: 'center', inline: 'center' }); } catch {}
            const rect = el.getBoundingClientRect();
            const eventInit = {
              clientX: rect.left + rect.width / 2,
              clientY: rect.top + rect.height / 2,
              bubbles: true,
              cancelable: true,
              composed: true,
              button: 0
            };
            if (typeof el.focus === 'function') el.focus();
            for (const type of ['pointerdown', 'mousedown', 'pointerup', 'mouseup']) {
              const EventType = type.startsWith('pointer') && typeof PointerEvent !== 'undefined' ? PointerEvent : MouseEvent;
              el.dispatchEvent(new EventType(type, eventInit));
            }
            if (typeof el.click === 'function') el.click();
            return true;
          };

          const rangeConfirmed = Array.from(document.querySelectorAll('button, [role="button"]'))
            .filter(visible)
            .some((node) => {
              const text = semantic(textOf(node));
              return text.includes('时间维度本月') ||
                text.includes('时间范围本月') ||
                text.includes('timerangethismonth') ||
                text.includes('timedimensionthismonth') ||
                text.includes('daterangethismonth');
            });
          if (!rangeConfirmed) return { clicked: false, rangeConfirmed: false };

          const nodes = Array.from(document.querySelectorAll('button, [role="button"], a')).filter(visible);
          const seen = new Set();
          const candidates = [];
          for (const node of nodes) {
            const text = textOf(node).toLowerCase();
            if (text !== '导出' && text !== 'export') continue;
            const candidate = node.closest && node.closest('button, [role="button"], a') || node;
            if (seen.has(candidate) || !visible(candidate)) continue;
            seen.add(candidate);

            const role = (candidate.getAttribute('role') || '').toLowerCase();
            const tag = (candidate.tagName || '').toLowerCase();
            const context = contextOf(candidate).toLowerCase();
            let score = 0;
            if (tag === 'button') score += 160;
            if (role === 'button') score += 120;
            if (context.includes('每月用量') || context.includes('monthly usage')) score += 180;
            if (context.includes('usage')) score += 40;
            candidates.push({ candidate, score, context: contextOf(candidate) });
          }

          candidates.sort((lhs, rhs) => rhs.score - lhs.score);
          const best = candidates[0];
          if (!best) return { clicked: false, rangeConfirmed: true };
          activate(best.candidate);
          return { clicked: true, rangeConfirmed: true, context: best.context };
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self,
                      self.activeExportTask?.id == taskID,
                      self.automationState == .locatingExportButton else { return }
                if let error {
                    self.finishAutomationFailure("导出按钮触发失败：\(error.localizedDescription)")
                    return
                }

                let state = result as? [String: Any]
                if state?["clicked"] as? Bool == true {
                    self.isLoggedIn = true
                    self.automationState = .waitingForDownload
                    self.statusMessage = "已选择本月，等待用量 ZIP..."
                    self.pendingExportRequest = false
                    self.exportLookupRetryCount = 0
                    self.beginDownloadWatch(for: taskID)
                    return
                }

                if state?["rangeConfirmed"] as? Bool == false,
                   self.exportLookupRetryCount < 3 {
                    self.exportLookupRetryCount += 1
                    self.automationState = .locatingRangeTrigger
                    self.rangeTriggerRetryCount = 0
                    self.statusMessage = "本月筛选尚未生效，正在重新选择..."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        Task { @MainActor [weak self] in
                            guard self?.activeExportTask?.id == taskID else { return }
                            self?.attemptExportClick()
                        }
                    }
                    return
                }

                if self.exportLookupRetryCount < 3 {
                    self.exportLookupRetryCount += 1
                    self.statusMessage = "日期已更新，正在等待导出按钮..."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                        Task { @MainActor [weak self] in
                            guard self?.activeExportTask?.id == taskID else { return }
                            self?.attemptFinalExportClick()
                        }
                    }
                } else {
                    self.finishAutomationFailure("已选择本月，但没有找到导出按钮")
                }
            }
        }
    }

    private func finishAutomationFailure(_ message: String) {
        resetAutomationState()
        statusMessage = message
    }

    private func resetAutomationState(cancelDownload: Bool = true) {
        pendingExportRequest = false
        automationState = .idle
        rangeTriggerRetryCount = 0
        rangeOptionRetryCount = 0
        exportLookupRetryCount = 0
        activeExportTask = nil
        exportTriggeredAt = nil
        downloadWatchAttempts = 0
        downloadWatchTimer?.invalidate()
        downloadWatchTimer = nil

        let download = activeDownload
        let temporaryDestination = activeDownloadDestination
        activeDownload = nil
        activeDownloadTaskID = nil
        activeDownloadDestination = nil
        activeDownloadFinalDestination = nil

        if cancelDownload, let download {
            download.delegate = nil
            download.cancel { _ in }
        }
        if let temporaryDestination {
            try? FileManager.default.removeItem(at: temporaryDestination)
        }
    }

    private func beginDownloadWatch(for taskID: UUID) {
        guard activeExportTask?.id == taskID else { return }
        exportTriggeredAt = Date()
        downloadWatchAttempts = 0
        downloadWatchTimer?.invalidate()
        downloadWatchTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.activeExportTask?.id == taskID else { return }
                self?.pollDownloadsForExport(taskID: taskID)
            }
        }
    }

    private func pollDownloadsForExport(taskID: UUID) {
        guard activeExportTask?.id == taskID else { return }
        downloadWatchAttempts += 1

        if let downloaded = newestDownloadedUsageFile() {
            lastDownloadFileName = downloaded.lastPathComponent
            statusMessage = "已发现下载文件 \(downloaded.lastPathComponent)，等待自动导入..."
            publishDownloadedFile(downloaded)
            return
        }

        if downloadWatchAttempts >= 14 {
            resetAutomationState()
            statusMessage = "后台导出超时，本次已跳过，不会打断你当前操作"
        }
    }

    private func publishDownloadedFile(_ fileURL: URL, cancelActiveDownload: Bool = true) {
        guard let task = activeExportTask else { return }
        resetAutomationState(cancelDownload: cancelActiveDownload)
        NotificationCenter.default.post(
            name: .usageExportDownloadFinished,
            object: UsageExportDownloadEvent(
                taskID: task.id,
                fileURL: fileURL,
                referenceDate: task.referenceDate
            )
        )
    }

    private func newestDownloadedUsageFile() -> URL? {
        guard let exportTriggeredAt,
              let incomingFolder = try? UsageAutoImportService.incomingFolderURL(),
              let enumerator = FileManager.default.enumerator(
                at: incomingFolder,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsSubdirectoryDescendants]
              ) else {
            return nil
        }

        var candidates: [(url: URL, modifiedAt: Date)] = []
        for case let fileURL as URL in enumerator {
            let modifiedAt = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            guard modifiedAt >= exportTriggeredAt.addingTimeInterval(-2) else { continue }
            guard detectDownloadedFileKind(at: fileURL) == .zip else { continue }
            candidates.append((fileURL, modifiedAt))
        }

        return candidates.sorted { $0.modifiedAt > $1.modifiedAt }.first?.url
    }

    private enum DetectedDownloadFileKind {
        case zip
        case csv
        case unknown
    }

    private func detectDownloadedFileKind(at url: URL) -> DetectedDownloadFileKind {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return .unknown
        }
        defer { try? handle.close() }

        let sample = (try? handle.read(upToCount: 512)) ?? Data()
        if Self.isZIPArchiveData(sample) {
            return .zip
        }

        if let text = String(data: sample, encoding: .utf8)?.lowercased(),
           text.contains("utc_date") || text.contains("user_id") || text.contains("amount") {
            return .csv
        }

        return .unknown
    }

    private var downloadBridgeScript: String {
        """
        (() => {
          if (window.__deepseekExportBridgeInstalled) return;
          window.__deepseekExportBridgeInstalled = true;

          const guessedFileName = (raw, fallback) => {
            const safe = (raw || '').trim();
            if (safe) return safe;
            return fallback || 'usage-export.zip';
          };

          const postDataUrl = (filename, dataUrl, taskID) => {
            window.webkit.messageHandlers.\(UsageExportScriptMessage.download).postMessage({
              filename: guessedFileName(filename, 'usage-export.zip'),
              dataUrl,
              taskID: taskID || ''
            });
          };

          const postBlob = async (blob, filename, taskID) => {
            if (!blob) return false;
            const capturedTaskID = taskID || window.__deepseekActiveExportTaskID || '';
            return await new Promise((resolve) => {
              try {
                const reader = new FileReader();
                reader.onloadend = () => {
                  postDataUrl(filename, reader.result, capturedTaskID);
                  resolve(true);
                };
                reader.onerror = () => resolve(false);
                reader.readAsDataURL(blob);
              } catch (error) {
                console.error('deepseek blob bridge failed', error);
                resolve(false);
              }
            });
          };

          const shouldCapture = (url, contentType, disposition) => {
            const type = (contentType || '').toLowerCase();
            const attachment = (disposition || '').toLowerCase();
            let isUsageExportEndpoint = false;
            try {
              isUsageExportEndpoint = new URL(url || '', location.href).pathname === '/api/v0/usage/export';
            } catch {}
            const isZipResponse = type.includes('application/zip') || type.includes('application/x-zip');
            const isZipAttachment = attachment.includes('attachment') && attachment.includes('.zip');
            return isUsageExportEndpoint || isZipResponse || isZipAttachment;
          };

          const blobStore = new Map();

          const postDownload = async (href, filename) => {
            if (!href) return false;
            const taskID = window.__deepseekActiveExportTaskID || '';

            try {
              if (href.startsWith('blob:')) {
                const storedBlob = blobStore.get(href);
                if (storedBlob) {
                  return await postBlob(storedBlob, filename, taskID);
                }

                const response = await fetch(href);
                const blob = await response.blob();
                return await postBlob(blob, filename, taskID);
              }

              if (href.startsWith('data:')) {
                postDataUrl(filename, href, taskID);
                return true;
              }
            } catch (error) {
              console.error('deepseek export bridge failed', error);
            }

            return false;
          };

          const interceptAnchor = async (anchor) => {
            if (!anchor) return false;
            const href = anchor.href || anchor.getAttribute('href') || '';
            const filename = anchor.download || anchor.getAttribute('download') || '';
            return await postDownload(href, filename);
          };

          document.addEventListener('click', (event) => {
            const anchor = event.target && event.target.closest ? event.target.closest('a') : null;
            if (!anchor) return;

            const href = anchor.href || anchor.getAttribute('href') || '';
            if (!(href.startsWith('blob:') || href.startsWith('data:') || anchor.hasAttribute('download'))) {
              return;
            }

            event.preventDefault();
            event.stopPropagation();
            interceptAnchor(anchor);
          }, true);

          const originalClick = HTMLAnchorElement.prototype.click;
          HTMLAnchorElement.prototype.click = function() {
            const href = this.href || this.getAttribute('href') || '';
            if (href.startsWith('blob:') || href.startsWith('data:') || this.hasAttribute('download')) {
              interceptAnchor(this);
            }
            return originalClick.apply(this, arguments);
          };

          const originalCreateObjectURL = URL.createObjectURL.bind(URL);
          URL.createObjectURL = function(object) {
            const url = originalCreateObjectURL(object);
            if (object instanceof Blob) {
              blobStore.set(url, object);
            }
            return url;
          };

          const originalRevokeObjectURL = URL.revokeObjectURL.bind(URL);
          URL.revokeObjectURL = function(url) {
            blobStore.delete(url);
            return originalRevokeObjectURL(url);
          };

          const originalWindowOpen = window.open.bind(window);
          window.open = function(url) {
            if (typeof url === 'string' && (url.startsWith('blob:') || url.startsWith('data:'))) {
              postDownload(url, 'usage-export.zip');
              return null;
            }
            return originalWindowOpen.apply(window, arguments);
          };

          const originalFetch = window.fetch.bind(window);
          window.fetch = async function() {
            const taskID = window.__deepseekActiveExportTaskID || '';
            const response = await originalFetch.apply(window, arguments);
            try {
              const requestUrl = typeof arguments[0] === 'string' ? arguments[0] : (arguments[0] && arguments[0].url) || '';
              const contentType = response.headers.get('content-type') || '';
              const disposition = response.headers.get('content-disposition') || '';
              if (shouldCapture(requestUrl || response.url, contentType, disposition)) {
                const blob = await response.clone().blob();
                const matchedName = /filename\\*=UTF-8''([^;]+)|filename="?([^"]+)"?/i.exec(disposition || '');
                const fileName = decodeURIComponent((matchedName && (matchedName[1] || matchedName[2])) || '');
                postBlob(blob, guessedFileName(fileName, requestUrl.split('/').pop() || 'usage-export.zip'), taskID);
              }
            } catch (error) {
              console.error('deepseek fetch bridge failed', error);
            }
            return response;
          };

          const originalOpen = XMLHttpRequest.prototype.open;
          const originalSend = XMLHttpRequest.prototype.send;

          XMLHttpRequest.prototype.open = function(method, url) {
            this.__deepseekUrl = typeof url === 'string' ? url : '';
            return originalOpen.apply(this, arguments);
          };

          XMLHttpRequest.prototype.send = function() {
            const taskID = window.__deepseekActiveExportTaskID || '';
            this.addEventListener('load', function() {
              try {
                const url = this.responseURL || this.__deepseekUrl || '';
                const contentType = this.getResponseHeader('content-type') || '';
                const disposition = this.getResponseHeader('content-disposition') || '';
                if (!shouldCapture(url, contentType, disposition)) return;

                if (this.response instanceof Blob) {
                  postBlob(this.response, url.split('/').pop() || 'usage-export.zip', taskID);
                  return;
                }

                if (this.response instanceof ArrayBuffer) {
                  const blob = new Blob([this.response], { type: contentType || 'application/octet-stream' });
                  postBlob(blob, url.split('/').pop() || 'usage-export.zip', taskID);
                  return;
                }

                if (typeof this.responseText === 'string') {
                  const blob = new Blob([this.responseText], { type: contentType || 'application/json' });
                  postBlob(blob, url.split('/').pop() || 'usage-export.zip', taskID);
                }
              } catch (error) {
                console.error('deepseek xhr bridge failed', error);
              }
            });

            return originalSend.apply(this, arguments);
          };
        })();
        """
    }

    private func saveBridgedDownload(filename: String, dataURL: String, taskID: String) {
        guard automationState == .waitingForDownload,
              activeExportTask?.id.uuidString == taskID else { return }
        guard let commaIndex = dataURL.firstIndex(of: ",") else {
            finishAutomationFailure("导出内容解析失败：数据格式无效")
            return
        }

        let meta = String(dataURL[..<commaIndex]).lowercased()
        let payload = String(dataURL[dataURL.index(after: commaIndex)...])

        let data: Data?
        if meta.contains(";base64") {
            data = Data(base64Encoded: payload)
        } else {
            data = payload.removingPercentEncoding?.data(using: .utf8)
        }

        guard let data else {
            finishAutomationFailure("导出内容保存失败")
            return
        }

        guard Self.isZIPArchiveData(data) else {
            let reason = exportFailureMessage(from: data) ?? "服务器返回的内容不是有效 ZIP"
            resetAutomationState()
            statusMessage = "DeepSeek 导出失败：\(reason)"
            lastDownloadFileName = nil
            return
        }

        guard let incomingFolder = try? UsageAutoImportService.incomingFolderURL() else {
            finishAutomationFailure("导出内容保存失败：无法打开专用导入目录")
            return
        }

        let finalName = normalizedDownloadFileName(from: filename)
        let destination = incomingFolder.appendingPathComponent(finalName)

        do {
            try? FileManager.default.removeItem(at: destination)
            try data.write(to: destination, options: .atomic)
            lastDownloadFileName = finalName
            statusMessage = "已保存下载文件 \(finalName)，等待自动导入..."
            publishDownloadedFile(destination)
        } catch {
            finishAutomationFailure("保存下载文件失败：\(error.localizedDescription)")
        }
    }

    private func normalizedDownloadFileName(from filename: String) -> String {
        let raw = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let noQuery = raw.split(separator: "?").first.map(String.init) ?? raw
        let lastComponent = URL(fileURLWithPath: noQuery).lastPathComponent
        let safeBase = lastComponent
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "&", with: "-")
        let fallbackBase = safeBase.isEmpty ? "usage-export" : safeBase
        if fallbackBase.lowercased().hasSuffix(".zip") {
            return fallbackBase
        }

        return "\(fallbackBase).zip"
    }

    nonisolated static func isZIPArchiveData(_ data: Data) -> Bool {
        let signatures: [[UInt8]] = [
            [0x50, 0x4B, 0x03, 0x04],
            [0x50, 0x4B, 0x05, 0x06],
            [0x50, 0x4B, 0x07, 0x08],
        ]
        return signatures.contains { data.starts(with: $0) }
    }

    private func exportFailureMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let nested = object["data"] as? [String: Any],
           let message = nested["biz_msg"] as? String,
           message.isEmpty == false {
            return message
        }
        if let message = object["msg"] as? String, message.isEmpty == false {
            return message
        }
        return nil
    }
}

extension UsageExportAutomationService: WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandler {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView.url?.absoluteString.contains("/usage") == true {
            isLoggedIn = true
            statusMessage = pendingExportRequest ? "页面已打开，正在尝试导出..." : "已连接到 usage 页面"
            if pendingExportRequest {
                attemptExportClick()
            }
            return
        }

        if webView.url?.absoluteString.contains("sign_in") == true {
            isLoggedIn = false
            resetAutomationState()
            statusMessage = "检测到需要重新登录，自动导出暂停等待手动登录"
            return
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        configure(download: download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        configure(download: download)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard activeExportTask != nil else { return }
        finishAutomationFailure("后台页面进程已终止，本次同步已停止")
    }

    private func handleNavigationFailure(_ error: Error) {
        guard activeExportTask != nil else { return }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return
        }
        finishAutomationFailure("后台页面加载失败：\(error.localizedDescription)")
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        guard download === activeDownload,
              let taskID = activeDownloadTaskID,
              activeExportTask?.id == taskID,
              automationState == .waitingForDownload else {
            completionHandler(nil)
            return
        }
        let incomingFolder = try? UsageAutoImportService.incomingFolderURL()
        let safeName = normalizedDownloadFileName(from: suggestedFilename)
        let finalDestination = incomingFolder?.appendingPathComponent(safeName)
        let temporaryDestination = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepSeekMonitor-\(UUID().uuidString).download")
        activeDownloadDestination = temporaryDestination
        activeDownloadFinalDestination = finalDestination
        if finalDestination != nil {
            try? FileManager.default.removeItem(at: temporaryDestination)
            lastDownloadFileName = safeName
            statusMessage = "正在下载 \(safeName)..."
        }
        completionHandler(finalDestination == nil ? nil : temporaryDestination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard download === activeDownload else { return }
        defer {
            activeDownload = nil
            activeDownloadTaskID = nil
            activeDownloadDestination = nil
            activeDownloadFinalDestination = nil
        }
        guard let taskID = activeDownloadTaskID,
              activeExportTask?.id == taskID else {
            if let temporaryDestination = activeDownloadDestination {
                try? FileManager.default.removeItem(at: temporaryDestination)
            }
            return
        }
        guard let temporaryDestination = activeDownloadDestination,
              let finalDestination = activeDownloadFinalDestination,
              let data = try? Data(contentsOf: temporaryDestination),
              Self.isZIPArchiveData(data) else {
            let temporaryDestination = activeDownloadDestination
            let reason: String
            if let temporaryDestination = activeDownloadDestination {
                let data = try? Data(contentsOf: temporaryDestination)
                reason = data.flatMap(exportFailureMessage(from:)) ?? "服务器返回的内容不是有效 ZIP"
            } else {
                reason = "未找到下载文件"
            }
            resetAutomationState(cancelDownload: false)
            if let temporaryDestination {
                try? FileManager.default.removeItem(at: temporaryDestination)
            }
            statusMessage = "DeepSeek 导出失败：\(reason)"
            lastDownloadFileName = nil
            return
        }

        do {
            try? FileManager.default.removeItem(at: finalDestination)
            try FileManager.default.moveItem(at: temporaryDestination, to: finalDestination)
        } catch {
            resetAutomationState(cancelDownload: false)
            statusMessage = "保存下载文件失败：\(error.localizedDescription)"
            return
        }

        statusMessage = "导出下载完成，等待自动导入..."
        publishDownloadedFile(finalDestination, cancelActiveDownload: false)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard download === activeDownload else { return }
        resetAutomationState(cancelDownload: false)
        statusMessage = "下载失败：\(error.localizedDescription)"
    }

    private func configure(download: WKDownload) {
        guard automationState == .waitingForDownload,
              let taskID = activeExportTask?.id else {
            download.cancel { _ in }
            return
        }
        if download === activeDownload {
            download.delegate = self
            return
        }
        guard activeDownload == nil else {
            download.cancel { _ in }
            return
        }
        activeDownload = download
        activeDownloadTaskID = taskID
        activeDownloadDestination = nil
        activeDownloadFinalDestination = nil
        download.delegate = self
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == UsageExportScriptMessage.download,
           let body = message.body as? [String: Any],
           let dataURL = body["dataUrl"] as? String,
           let taskID = body["taskID"] as? String {
            let filename = (body["filename"] as? String) ?? "usage-export.zip"
            saveBridgedDownload(filename: filename, dataURL: dataURL, taskID: taskID)
            return
        }

    }
}
