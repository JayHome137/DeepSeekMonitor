import Combine
import Foundation
@preconcurrency import Sparkle

@MainActor
final class SoftwareUpdateController: NSObject, ObservableObject {
    enum State: Equatable {
        case unavailable(String)
        case idle
        case checking
        case upToDate
        case updateAvailable(version: String)
        case downloading(version: String)
        case installing(version: String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var canCheckForUpdates = false

    private var updaterController: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?

    var currentVersionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "--"
    }

    var isChecking: Bool {
        state == .checking
    }

    override init() {
        super.init()

        guard Self.hasValidReleaseConfiguration(in: .main) else {
            state = .unavailable("更新签名尚未配置")
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        updaterController = controller
        canCheckObservation = controller.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            let isAvailable = updater.canCheckForUpdates
            Task { @MainActor [weak self] in
                self?.canCheckForUpdates = isAvailable
            }
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates, let updater = updaterController?.updater else { return }
        state = .checking
        updater.checkForUpdates()
    }

    private static func hasValidReleaseConfiguration(in bundle: Bundle) -> Bool {
        guard
            let feedValue = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            let feedURL = URL(string: feedValue),
            feedURL.scheme?.lowercased() == "https",
            feedURL.host != nil,
            let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            let decodedKey = Data(base64Encoded: publicKey),
            decodedKey.count == 32,
            boolValue(for: "SURequireSignedFeed", in: bundle),
            boolValue(for: "SUVerifyUpdateBeforeExtraction", in: bundle),
            boolValue(for: "SUEnableInstallerLauncherService", in: bundle),
            let allowedSchemes = bundle.object(forInfoDictionaryKey: "SUAllowedURLSchemes") as? [String],
            Set(allowedSchemes.map { $0.lowercased() }) == ["https"]
        else {
            return false
        }
        return true
    }

    private static func boolValue(for key: String, in bundle: Bundle) -> Bool {
        (bundle.object(forInfoDictionaryKey: key) as? NSNumber)?.boolValue == true
    }
}

extension SoftwareUpdateController: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        state = .updateAvailable(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        let nsError = error as NSError
        let reasonValue = (nsError.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.intValue
        guard let reason = reasonValue.map({
            SPUNoUpdateFoundReason(rawValue: OSStatus($0))
        }) else {
            state = .failed("未找到可安装的更新")
            return
        }

        if reason == .onLatestVersion || reason == .onNewerThanLatestVersion {
            state = .upToDate
        } else {
            state = .failed("发现的版本与当前 Mac 不兼容")
        }
    }

    func updater(
        _ updater: SPUUpdater,
        willDownloadUpdate item: SUAppcastItem,
        with request: NSMutableURLRequest
    ) {
        state = .downloading(version: item.displayVersionString)
    }

    func updater(
        _ updater: SPUUpdater,
        failedToDownloadUpdate item: SUAppcastItem,
        error: Error
    ) {
        state = .failed("更新下载失败，请稍后重试")
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        state = .idle
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate item: SUAppcastItem,
        state updateState: SPUUserUpdateState
    ) {
        switch choice {
        case .install:
            break
        case .dismiss, .skip:
            state = .idle
        @unknown default:
            state = .idle
        }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        state = .installing(version: item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        if (error as NSError).code == Int(SUError.installationCanceledError.rawValue) {
            state = .idle
            return
        }

        switch state {
        case .upToDate, .failed:
            break
        default:
            state = .failed("检查更新失败，请稍后重试")
        }
    }
}
