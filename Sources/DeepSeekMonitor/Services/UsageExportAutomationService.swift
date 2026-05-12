import Foundation
import AppKit
import WebKit

extension Notification.Name {
    static let usageExportDownloadFinished = Notification.Name("usage_export_download_finished")
}

private enum UsageExportScriptMessage {
    static let download = "usageExportDownload"
    static let clickTrace = "usageExportClickTrace"
}

@MainActor
final class UsageExportAutomationService: NSObject, ObservableObject {
    static let shared = UsageExportAutomationService()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled {
                statusMessage = "自动导出已开启"
                requestExport(manual: false, openWindowOnFailure: false)
            } else {
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
    @Published private(set) var lastClickTraceSummary: String?

    private static let enabledKey = "usage_export_automation_enabled"
    private static let intervalKey = "usage_export_automation_interval_seconds"
    private static let usageURL = URL(string: "https://platform.deepseek.com/usage")!
    private static let loginURL = URL(string: "https://platform.deepseek.com/sign_in")!
    private static let defaultAutoExportInterval: TimeInterval = 60

    private var timer: Timer?
    private var window: NSWindow?
    private var webView: WKWebView?
    private var pendingExportRequest = false
    private var shouldShowWindowOnFailure = false
    private var lastAttemptAt: Date?
    private var activeDownload: WKDownload?
    private var exportLookupRetryCount = 0
    private var downloadWatchTimer: Timer?
    private var exportTriggeredAt: Date?
    private var downloadWatchAttempts = 0

    private override init() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        let interval = UserDefaults.standard.double(forKey: Self.intervalKey)
        isEnabled = enabled
        autoExportIntervalSeconds = Self.normalizedInterval(interval)
        statusMessage = enabled ? "自动导出待命中" : "自动导出未开启"
        super.init()
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: autoExportIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTimerTick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        downloadWatchTimer?.invalidate()
        downloadWatchTimer = nil
    }

    func closeWindow() {
        shouldShowWindowOnFailure = false
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
        requestExport(manual: true, openWindowOnFailure: true)
    }

    func armClickTrace() {
        let webView = ensureWebView()
        ensureWindow(with: webView)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        lastClickTraceSummary = "等待你在网页里点一次目标按钮..."
        statusMessage = "点击追踪已开启，请在网页里手动点导出按钮"
        webView.evaluateJavaScript("window.__deepseekClickTraceArmed = true;", completionHandler: nil)
    }

    private func handleTimerTick() {
        guard isEnabled else { return }
        requestExport(manual: false, openWindowOnFailure: false)
    }

    private func restartTimerIfNeeded() {
        guard timer != nil else { return }
        start()
    }

    private static func normalizedInterval(_ value: TimeInterval) -> TimeInterval {
        let allowed: [TimeInterval] = [60, 300, 600, 1800]
        return allowed.contains(value) ? value : defaultAutoExportInterval
    }

    private func requestExport(manual: Bool, openWindowOnFailure: Bool) {
        if let lastAttemptAt, Date().timeIntervalSince(lastAttemptAt) < 25, manual == false {
            return
        }

        lastAttemptAt = Date()
        pendingExportRequest = true
        exportLookupRetryCount = 0
        shouldShowWindowOnFailure = openWindowOnFailure

        let webView = ensureWebView()
        let currentURL = webView.url?.absoluteString ?? ""
        if currentURL.contains("/usage") {
            attemptExportClick()
        } else {
            statusMessage = "正在打开 DeepSeek 用量页面..."
            webView.load(URLRequest(url: Self.usageURL))
            if openWindowOnFailure {
                ensureWindow(with: webView)
                window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private func ensureWebView() -> WKWebView {
        if let webView {
            return webView
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(self, name: UsageExportScriptMessage.download)
        configuration.userContentController.add(self, name: UsageExportScriptMessage.clickTrace)
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
        guard let webView else { return }

        let script = """
        (() => {
          const normalized = (value) => (value || '').replace(/\\s+/g, ' ').trim();

          const visible = (el) => {
            if (!el) return false;
            const rect = el.getBoundingClientRect();
            const style = window.getComputedStyle(el);
            return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none';
          };

          const textOf = (el) => normalized([
            el.innerText,
            el.textContent,
            el.getAttribute && el.getAttribute('aria-label'),
            el.getAttribute && el.getAttribute('title')
          ].filter(Boolean).join(' '));

          const contextOf = (el) => {
            const parts = [];
            let current = el;
            for (let i = 0; current && i < 5; i += 1) {
              const text = textOf(current);
              if (text) {
                parts.push(text);
              }
              current = current.parentElement;
            }
            return normalized(parts.join(' | '));
          };

          const uniqueElements = (elements) => {
            const seen = new Set();
            return elements.filter((el) => {
              if (!el || seen.has(el)) return false;
              seen.add(el);
              return true;
            });
          };

          const activate = (el) => {
            if (!el) return false;
            try { el.scrollIntoView({ block: 'center', inline: 'center' }); } catch {}

            const rect = el.getBoundingClientRect();
            const point = {
              clientX: Math.max(1, Math.min(window.innerWidth - 1, rect.left + rect.width / 2)),
              clientY: Math.max(1, Math.min(window.innerHeight - 1, rect.top + rect.height / 2)),
              bubbles: true,
              cancelable: true,
              composed: true,
              button: 0,
              buttons: 1
            };

            const hit = document.elementFromPoint(point.clientX, point.clientY);
            const chain = [];
            let current = hit;
            while (current && current !== document.body && chain.length < 6) {
              chain.push(current);
              current = current.parentElement;
            }

            const targets = uniqueElements([
              el,
              hit,
              ...chain,
              el.closest && el.closest('[role="button"]'),
              el.parentElement
            ]);

            const eventTypes = ['pointerover', 'mouseover', 'pointerenter', 'mouseenter', 'pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'];
            for (const target of targets) {
              if (typeof target.focus === 'function') {
                target.focus();
              }
              for (const type of eventTypes) {
                const EventCtor = type.startsWith('pointer') && typeof PointerEvent !== 'undefined' ? PointerEvent : MouseEvent;
                target.dispatchEvent(new EventCtor(type, point));
              }
              if (typeof target.click === 'function') {
                target.click();
              }
            }

            return {
              hitTag: hit && hit.tagName ? hit.tagName.toLowerCase() : '',
              hitText: hit ? textOf(hit) : ''
            };
          };

          const scoreOf = (el) => {
            const text = textOf(el);
            if (!text) return -1;

            const lowerText = text.toLowerCase();
            const role = (el.getAttribute && el.getAttribute('role') || '').toLowerCase();
            const tag = (el.tagName || '').toLowerCase();
            const context = contextOf(el);
            const lowerContext = context.toLowerCase();
            const cursor = window.getComputedStyle(el).cursor || '';

            let score = 0;
            if (role === 'button') score += 80;
            if (tag === 'button') score += 60;
            if (tag === 'div') score += 20;
            if (cursor === 'pointer') score += 20;
            if (text === '导出') score += 200;
            if (text.includes('导出')) score += 80;
            if (lowerText.includes('export')) score += 40;
            if (context.includes('每月用量')) score += 160;
            if (lowerContext.includes('usage')) score += 20;
            if (lowerContext.includes('chart')) score -= 30;
            if (lowerContext.includes('设置')) score -= 40;
            return score;
          };

          const passwordField = document.querySelector('input[type="password"]');
          const candidates = Array.from(document.querySelectorAll('button, a, [role="button"], span, div')).filter(visible);
          const ranked = candidates
            .map((el) => ({ el, score: scoreOf(el) }))
            .filter((item) => item.score > 0)
            .sort((lhs, rhs) => rhs.score - lhs.score);
          const best = ranked[0];
          const exportElement = best && best.el;

          if (exportElement) {
            const activation = activate(exportElement);
            return {
              clicked: true,
              needsLogin: false,
              url: location.href,
              score: best.score,
              text: textOf(exportElement),
              context: contextOf(exportElement),
              role: exportElement.getAttribute && exportElement.getAttribute('role') || '',
              tag: exportElement.tagName.toLowerCase(),
              hitTag: activation.hitTag,
              hitText: activation.hitText
            };
          }

          return {
            clicked: false,
            needsLogin: !!passwordField || /sign_in|login/i.test(location.href),
            url: location.href
          };
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let error {
                    self.statusMessage = "导出按钮触发失败：\(error.localizedDescription)"
                    if self.shouldShowWindowOnFailure {
                        self.openLoginWindow()
                    }
                    self.pendingExportRequest = false
                    return
                }

                let state = result as? [String: Any]
                let clicked = state?["clicked"] as? Bool ?? false
                let needsLogin = state?["needsLogin"] as? Bool ?? false

                if clicked {
                    self.isLoggedIn = true
                    let text = state?["text"] as? String ?? "导出"
                    let context = state?["context"] as? String ?? ""
                    self.statusMessage = context.contains("每月用量")
                        ? "已点按每月用量的\(text)，等待下载..."
                        : "已触发\(text)，等待下载..."
                    self.beginDownloadWatch()
                    self.scheduleFollowUpExportClick(after: 1.0)
                    self.pendingExportRequest = false
                    self.exportLookupRetryCount = 0
                    self.shouldShowWindowOnFailure = false
                    return
                }

                if needsLogin {
                    self.isLoggedIn = false
                    self.statusMessage = self.shouldShowWindowOnFailure
                        ? "需要先登录 DeepSeek 平台"
                        : "登录状态已失效，请在设置里手动打开登录页"
                    self.exportLookupRetryCount = 0
                    if self.shouldShowWindowOnFailure {
                        self.openLoginWindow()
                    }
                } else {
                    if self.exportLookupRetryCount < 3 {
                        self.exportLookupRetryCount += 1
                        self.statusMessage = "页面已打开，正在等待导出按钮..."
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                            Task { @MainActor [weak self] in
                                self?.attemptExportClick()
                            }
                        }
                    } else {
                        self.statusMessage = "已进入 usage 页面，但暂时没找到导出按钮"
                        self.exportLookupRetryCount = 0
                        if self.shouldShowWindowOnFailure {
                            self.openLoginWindow()
                        }
                    }
                }

                self.pendingExportRequest = false
            }
        }
    }

    private func beginDownloadWatch() {
        exportTriggeredAt = Date()
        downloadWatchAttempts = 0
        downloadWatchTimer?.invalidate()
        downloadWatchTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollDownloadsForExport()
            }
        }
    }

    private func scheduleFollowUpExportClick(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            Task { @MainActor [weak self] in
                self?.attemptFollowUpExportClick()
            }
        }
    }

    private func attemptFollowUpExportClick() {
        guard let webView else { return }

        let script = """
        (() => {
          const normalized = (value) => (value || '').replace(/\\s+/g, ' ').trim();

          const visible = (el) => {
            const rect = el.getBoundingClientRect();
            const style = window.getComputedStyle(el);
            return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none';
          };
          const textOf = (el) => normalized([
            el.innerText,
            el.textContent,
            el.getAttribute && el.getAttribute('aria-label'),
            el.getAttribute && el.getAttribute('title')
          ].filter(Boolean).join(' '));
          const contextOf = (el) => {
            const parts = [];
            let current = el;
            for (let i = 0; current && i < 5; i += 1) {
              const text = textOf(current);
              if (text) {
                parts.push(text);
              }
              current = current.parentElement;
            }
            return normalized(parts.join(' | '));
          };

          const activate = (el) => {
            if (!el) return false;
            try { el.scrollIntoView({ block: 'center', inline: 'center' }); } catch {}
            const rect = el.getBoundingClientRect();
            const point = {
              clientX: Math.max(1, Math.min(window.innerWidth - 1, rect.left + rect.width / 2)),
              clientY: Math.max(1, Math.min(window.innerHeight - 1, rect.top + rect.height / 2)),
              bubbles: true,
              cancelable: true,
              composed: true,
              button: 0,
              buttons: 1
            };

            if (typeof el.focus === 'function') {
              el.focus();
            }

            const eventTypes = ['pointerover', 'mouseover', 'pointerenter', 'mouseenter', 'pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'];
            for (const type of eventTypes) {
              const EventCtor = type.startsWith('pointer') && typeof PointerEvent !== 'undefined' ? PointerEvent : MouseEvent;
              el.dispatchEvent(new EventCtor(type, point));
            }

            if (typeof el.click === 'function') {
              el.click();
            }

            return true;
          };

          const nodes = Array.from(document.querySelectorAll('button, a, [role="button"], li, span, div')).filter(visible);
          const exactExport = nodes.find((el) => {
            const text = textOf(el);
            const role = (el.getAttribute && el.getAttribute('role') || '').toLowerCase();
            const context = contextOf(el);
            return role === 'button' && text === '导出' && context.includes('每月用量');
          });

          if (exactExport) {
            activate(exactExport);
            return { clicked: true, keyword: '导出' };
          }

          const priorities = ['下载', '确认', 'zip', 'csv', 'amount', '导出'];

          for (const keyword of priorities) {
            const target = nodes.find((el) => textOf(el).toLowerCase().includes(keyword.toLowerCase()));
            if (target) {
              activate(target);
              return { clicked: true, keyword };
            }
          }

          return { clicked: false };
        })();
        """

        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func pollDownloadsForExport() {
        downloadWatchAttempts += 1

        if let downloaded = newestDownloadedUsageFile() {
            lastDownloadFileName = downloaded.lastPathComponent
            statusMessage = "已发现下载文件 \(downloaded.lastPathComponent)，等待自动导入..."
            downloadWatchTimer?.invalidate()
            downloadWatchTimer = nil
            NotificationCenter.default.post(name: .usageExportDownloadFinished, object: nil)
            return
        }

        if downloadWatchAttempts == 2 || downloadWatchAttempts == 5 {
            scheduleFollowUpExportClick(after: 0.2)
        }

        if downloadWatchAttempts >= 14 {
            downloadWatchTimer?.invalidate()
            downloadWatchTimer = nil
            statusMessage = shouldShowWindowOnFailure
                ? "等待下载超时，可能还需要网页里的二次确认"
                : "后台导出超时，本次已跳过，不会打断你当前操作"
            if shouldShowWindowOnFailure {
                openLoginWindow()
            }
        }
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
            guard detectDownloadedFileKind(at: fileURL) != .unknown else { continue }
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
        let ext = url.pathExtension.lowercased()
        if ext == "zip" { return .zip }
        if ext == "csv" { return .csv }

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return .unknown
        }
        defer { try? handle.close() }

        let sample = (try? handle.read(upToCount: 256)) ?? Data()
        if sample.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
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

          const describeElement = (el) => {
            if (!el) return null;
            const text = (el.innerText || el.textContent || '').trim().replace(/\\s+/g, ' ').slice(0, 160);
            const href = el.href || el.getAttribute && el.getAttribute('href') || '';
            const cls = el.className && typeof el.className === 'string' ? el.className.slice(0, 160) : '';
            const role = el.getAttribute && el.getAttribute('role') || '';
            const aria = el.getAttribute && el.getAttribute('aria-label') || '';
            const id = el.id || '';
            const cursor = window.getComputedStyle(el).cursor || '';
            return {
              tag: (el.tagName || '').toLowerCase(),
              text,
              href,
              role,
              ariaLabel: aria,
              className: cls,
              id,
              cursor
            };
          };

          const scoreElement = (el) => {
            if (!el || !el.tagName) return -1;
            const tag = (el.tagName || '').toLowerCase();
            const text = (el.innerText || el.textContent || '').trim().toLowerCase();
            const href = el.href || el.getAttribute && el.getAttribute('href') || '';
            const role = el.getAttribute && el.getAttribute('role') || '';
            const aria = el.getAttribute && el.getAttribute('aria-label') || '';
            const cursor = window.getComputedStyle(el).cursor || '';

            let score = 0;
            if (tag === 'button') score += 8;
            if (tag === 'a') score += 6;
            if (role.toLowerCase() === 'button') score += 6;
            if (href) score += 4;
            if (el.hasAttribute && el.hasAttribute('download')) score += 8;
            if (cursor === 'pointer') score += 3;

            const haystack = [text, href, aria].join(' ').toLowerCase();
            if (haystack.includes('导出')) score += 10;
            if (haystack.includes('export')) score += 10;
            if (haystack.includes('下载')) score += 8;
            if (haystack.includes('zip')) score += 6;
            if (haystack.includes('csv')) score += 5;
            if (haystack.includes('month=')) score += 4;
            if (haystack.includes('year=')) score += 4;

            return score;
          };

          const firstElementsFromPath = (event) => {
            const rawPath = event.composedPath ? event.composedPath() : [];
            return rawPath.filter((node) => node && node.tagName).slice(0, 8);
          };

          const bestCandidateFromPath = (path) => {
            if (!Array.isArray(path) || path.length === 0) return null;
            let best = null;
            let bestScore = -1;
            for (const el of path) {
              const score = scoreElement(el);
              if (score > bestScore) {
                best = el;
                bestScore = score;
              }
            }
            return best;
          };

          const postDataUrl = (filename, dataUrl) => {
            window.webkit.messageHandlers.\(UsageExportScriptMessage.download).postMessage({
              filename: guessedFileName(filename, 'usage-export.zip'),
              dataUrl
            });
          };

          const postBlob = async (blob, filename) => {
            if (!blob) return false;
            return await new Promise((resolve) => {
              try {
                const reader = new FileReader();
                reader.onloadend = () => {
                  postDataUrl(filename, reader.result);
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
            const haystack = [url, contentType, disposition].filter(Boolean).join(' ').toLowerCase();
            return haystack.includes('zip') ||
              haystack.includes('csv') ||
              haystack.includes('octet-stream') ||
              haystack.includes('download') ||
              haystack.includes('export') ||
              haystack.includes('usage');
          };

          const blobStore = new Map();

          const postDownload = async (href, filename) => {
            if (!href) return false;

            try {
              if (href.startsWith('blob:')) {
                const storedBlob = blobStore.get(href);
                if (storedBlob) {
                  return await postBlob(storedBlob, filename);
                }

                const response = await fetch(href);
                const blob = await response.blob();
                return await postBlob(blob, filename);
              }

              if (href.startsWith('data:')) {
                postDataUrl(filename, href);
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

          document.addEventListener('mousedown', (event) => {
            if (window.__deepseekClickTraceArmed) {
              window.__deepseekClickTraceArmed = false;
              const hit = document.elementFromPoint(event.clientX, event.clientY);
              const path = firstElementsFromPath(event);
              const target = bestCandidateFromPath([
                hit,
                ...(path || []),
                event.target
              ].filter(Boolean));
              window.webkit.messageHandlers.\(UsageExportScriptMessage.clickTrace).postMessage({
                pointX: event.clientX,
                pointY: event.clientY,
                target: describeElement(target),
                raw: describeElement(event.target),
                hit: describeElement(hit),
                path: path.map(describeElement),
                url: location.href
              });
            }
          }, true);

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
            const response = await originalFetch.apply(window, arguments);
            try {
              const requestUrl = typeof arguments[0] === 'string' ? arguments[0] : (arguments[0] && arguments[0].url) || '';
              const contentType = response.headers.get('content-type') || '';
              const disposition = response.headers.get('content-disposition') || '';
              if (shouldCapture(requestUrl || response.url, contentType, disposition)) {
                const blob = await response.clone().blob();
                const matchedName = /filename\\*=UTF-8''([^;]+)|filename="?([^"]+)"?/i.exec(disposition || '');
                const fileName = decodeURIComponent((matchedName && (matchedName[1] || matchedName[2])) || '');
                postBlob(blob, guessedFileName(fileName, requestUrl.split('/').pop() || 'usage-export.zip'));
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
            this.addEventListener('load', function() {
              try {
                const url = this.responseURL || this.__deepseekUrl || '';
                const contentType = this.getResponseHeader('content-type') || '';
                const disposition = this.getResponseHeader('content-disposition') || '';
                if (!shouldCapture(url, contentType, disposition)) return;

                if (this.response instanceof Blob) {
                  postBlob(this.response, url.split('/').pop() || 'usage-export.zip');
                  return;
                }

                if (this.response instanceof ArrayBuffer) {
                  const blob = new Blob([this.response], { type: contentType || 'application/octet-stream' });
                  postBlob(blob, url.split('/').pop() || 'usage-export.zip');
                  return;
                }

                if (typeof this.responseText === 'string' && (contentType.includes('csv') || url.toLowerCase().includes('csv'))) {
                  const dataUrl = 'data:text/csv;charset=utf-8,' + encodeURIComponent(this.responseText);
                  postDataUrl(url.split('/').pop() || 'usage-export.csv', dataUrl);
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

    private func saveBridgedDownload(filename: String, dataURL: String) {
        guard let commaIndex = dataURL.firstIndex(of: ",") else {
            statusMessage = "导出内容解析失败：数据格式无效"
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

        guard let data,
              let incomingFolder = try? UsageAutoImportService.incomingFolderURL() else {
            statusMessage = "导出内容保存失败"
            return
        }

        let finalName = normalizedDownloadFileName(from: filename, data: data, meta: meta)
        let destination = incomingFolder.appendingPathComponent(finalName)

        do {
            try? FileManager.default.removeItem(at: destination)
            try data.write(to: destination, options: .atomic)
            lastDownloadFileName = finalName
            statusMessage = "已保存下载文件 \(finalName)，等待自动导入..."
            downloadWatchTimer?.invalidate()
            downloadWatchTimer = nil
            NotificationCenter.default.post(name: .usageExportDownloadFinished, object: nil)
        } catch {
            statusMessage = "保存下载文件失败：\(error.localizedDescription)"
        }
    }

    private func normalizedDownloadFileName(from filename: String, data: Data, meta: String) -> String {
        let raw = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let noQuery = raw.split(separator: "?").first.map(String.init) ?? raw
        let safeBase = noQuery
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "&", with: "-")

        let inferredExtension: String
        if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) || meta.contains("application/zip") || meta.contains("octet-stream") {
            inferredExtension = "zip"
        } else if meta.contains("text/csv") {
            inferredExtension = "csv"
        } else {
            inferredExtension = ""
        }

        let fallbackBase = safeBase.isEmpty ? "usage-export" : safeBase
        if inferredExtension.isEmpty {
            return fallbackBase
        }

        if fallbackBase.lowercased().hasSuffix(".\(inferredExtension)") {
            return fallbackBase
        }

        return "\(fallbackBase).\(inferredExtension)"
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
            statusMessage = shouldShowWindowOnFailure
                ? "请在打开的窗口中完成登录"
                : "检测到需要重新登录，自动导出暂停等待手动登录"
            return
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        configure(download: download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        configure(download: download)
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let incomingFolder = try? UsageAutoImportService.incomingFolderURL()
        let destination = incomingFolder?.appendingPathComponent(suggestedFilename)
        if let destination {
            try? FileManager.default.removeItem(at: destination)
            lastDownloadFileName = suggestedFilename
            statusMessage = "正在下载 \(suggestedFilename)..."
        }
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        statusMessage = "导出下载完成，等待自动导入..."
        downloadWatchTimer?.invalidate()
        downloadWatchTimer = nil
        NotificationCenter.default.post(name: .usageExportDownloadFinished, object: nil)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        statusMessage = "下载失败：\(error.localizedDescription)"
    }

    private func configure(download: WKDownload) {
        activeDownload = download
        download.delegate = self
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == UsageExportScriptMessage.download,
           let body = message.body as? [String: Any],
           let dataURL = body["dataUrl"] as? String {
            let filename = (body["filename"] as? String) ?? "usage-export.zip"
            saveBridgedDownload(filename: filename, dataURL: dataURL)
            return
        }

        if message.name == UsageExportScriptMessage.clickTrace,
           let body = message.body as? [String: Any] {
            let target = body["target"] as? [String: Any]
            let hit = body["hit"] as? [String: Any]
            let path = body["path"] as? [[String: Any]] ?? []
            let url = body["url"] as? String ?? ""
            let text = (target?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let href = (target?["href"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let tag = (target?["tag"] as? String) ?? "unknown"
            let role = (target?["role"] as? String) ?? ""
            let aria = (target?["ariaLabel"] as? String) ?? ""
            let hitTag = (hit?["tag"] as? String) ?? "unknown"
            let hitText = ((hit?["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let pathSummary = path.prefix(4).map { item in
                let itemTag = (item["tag"] as? String) ?? "unknown"
                let itemText = ((item["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let itemRole = (item["role"] as? String) ?? ""
                return "\(itemTag){\(itemText.isEmpty ? "-" : itemText)}[\(itemRole.isEmpty ? "-" : itemRole)]"
            }.joined(separator: " -> ")

            lastClickTraceSummary = "best=\(tag){\(text.isEmpty ? "-" : text)} href=\(href.isEmpty ? "-" : href) role=\(role.isEmpty ? "-" : role) aria=\(aria.isEmpty ? "-" : aria) | hit=\(hitTag){\(hitText.isEmpty ? "-" : hitText)}"
            statusMessage = "已捕获网页点击，继续把这条信息发给我就行"
            if url.isEmpty == false {
                lastClickTraceSummary = "\(lastClickTraceSummary ?? "") | path=\(pathSummary.isEmpty ? "-" : pathSummary) | page=\(url)"
            }
        }
    }
}
