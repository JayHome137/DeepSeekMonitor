# 自动导出内存优化说明

本文档说明本 fork 相对上游的改动，以及这些改动背后的实测依据。

对应 issue 的问题描述：自动导出长时间运行后，`com.apple.WebKit.WebContent` 进程 RSS 涨到约 1 GB 且只增不减。

## 症状

- 开启「网页自动导出」（默认 300 秒）并连续运行约 10 天，WebContent 涨到约 1 GB
- 同期主进程仅约 81 MB
- 退出 App 后内存立刻回落，说明泄漏发生在渲染进程而非宿主进程

重启 App 后 55 分钟的实测：

```text
WebKit.WebContent   225 MB
DeepSeekMonitor      81 MB
```

## 根因

### 1. WKWebView 从不销毁（主因）

`UsageExportAutomationService` 把 WebView 当常驻单例使用：

- `ensureWebView()` 只在 `webView == nil` 时创建，之后永不复用判断
- `closeWindow()` 只有 `window?.orderOut(nil)`
- `ensureWindow()` 中 `window.isReleasedWhenClosed = false`，且 `window.contentView = webView`，视图层级持续持有 WebView
- 全文没有 `webView = nil`，也没有 `deinit`

WebContent 进程从 App 启动起就没有退出过，JS 堆碎片与 DOM / 图层缓存全部累积在同一个进程里。

### 2. 每轮定时任务都重新下载整包前端

`requestExport()` 使用 `cachePolicy: .reloadIgnoringLocalCacheData` 加载 `/usage`，配合 300 秒间隔，等于每 5 分钟把 SPA 的 JS/CSS 全量重新下载并解析一遍。

### 3. `blobStore` 是真实泄漏

`downloadBridgeScript` 中：

```js
const blobStore = new Map();
URL.createObjectURL = function(object) {
  if (object instanceof Blob && object.size <= maximumDownloadBytes) {
    blobStore.set(url, object);
```

只有页面主动 `revokeObjectURL` 才会 `delete`。而导出流程是「生成 blob → `a.click()` → 丢弃」，从不 revoke，因此每份 ZIP（上限 64 MiB）会一直驻留在 JS 堆中。此项与 WKWebView 本身无关，导出越频繁涨得越快。

## 改动

### `fix(export)`: 释放空闲 WKWebView 并清理导出 blob 缓存

- 新增 `destroyWebView()`：停载、解除 delegate、移除 script message handler、断开 `window.contentView` 强引用、置空 `webView`
- 新增 `scheduleIdleTeardown(delay:)`：`resetAutomationState()` 收尾时挂延迟任务，90 秒后仅在「窗口不可见 + 无进行中任务 + 无待处理请求」同时成立时才拆
- `closeWindow()` 走同一路径（延迟 5 秒）
- `window` 增加 `delegate`，处理点红叉关闭窗口
- `webViewWebContentProcessDidTerminate` 中清空失效实例
- `postBlob` 过桥成功后批量 `revokeObjectURL` 并清空 `blobStore`

**登录态不受影响**：`websiteDataStore = .default()` 是磁盘持久化存储，cookie / localStorage 落盘，重建 WebView 不会掉登录；销毁丢掉的只是内存中的 SPA 会话。

### `chore(export)`: 下调默认间隔并复用 HTTP 缓存

- 默认导出间隔 300s → 1800s（设置中的可选值列表不变）
- 导出导航 `cachePolicy` 改为 `.useProtocolCachePolicy`

> `AGENTS.md` 记录了「Existing defaults remain 60 seconds and 5 minutes」这一约定。若需保持原默认值，可只保留前一提交。

## 不要这样改（已验证的反面结论）

**不要把 `.default()` 换成 `.nonPersistent()`。**

- 官方语义是 private browsing：「no data will be written to the file system」，进程退出即丢，会导致每次启动都要重新登录
- 更关键的是它对 WebContent 的 RSS **没有任何帮助**：存储是否落盘与渲染进程内存占用无关，数据本来就在该进程内。决定性变量是 WebView 存活时长，而非数据存放位置

同理，用 `removeData(ofTypes: allWebsiteDataTypes)` 「清理内存」会连 cookie 一并删除（`WKWebsiteDataTypeCookies` 属于该集合），下一个导出周期就会跳转 `/sign_in`。

## 验证

```text
swift test                                     → 59 tests, 2 skipped, 0 failures
xcodebuild ... CODE_SIGNING_ALLOWED=NO build    → BUILD SUCCEEDED
                                                  DeepSeekMonitor.app
                                                  WidgetSupport.appex
```

真机实测（macOS 27.0.1，arm64，开启自动导出）：

| | 结果 |
|---|---|
| 改前 | 55 分钟 225 MB；连续 10 天约 1 GB |
| 改后 | 导出结束后 WebContent 约 1 分 48 秒退出；主进程稳定 138 MB |

## 关于验收标准

WebKit 的 `WebProcessCache` 会保活渲染进程一小段时间，因此「进程立刻消失」不是合理预期。真正的判据是 **RSS 有上界、不随运行天数线性增长**。

## 本地构建补充说明（不进入上游）

在开发签名（无 provisioning profile）环境下，`UserDefaults(suiteName:)` 读写 App Group 域会被 cfprefsd 拒绝：

```text
Using kCFPreferencesAnyUser with a container is only allowed for System Containers,
detaching from cfprefsd
```

写入会静默丢失，导致 WidgetKit 小组件拿不到快照。若自行构建时遇到小组件空白，可改用 App Group 容器内的文件传递快照：

```swift
FileManager.default
    .containerURL(forSecurityApplicationGroupIdentifier: "<TeamID>.group.com.deepseek.monitor")?
    .appendingPathComponent("widget-snapshot.json")
```

App 侧写入、Widget 侧用 `Data(contentsOf:)` 读取即可绕开 cfprefsd。此项与上游代码无关，仅为本地构建经验记录。
