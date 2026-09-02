import Combine
import Sparkle

@MainActor
protocol SparkleUpdateChecking: AnyObject {
    var canCheckForUpdates: Bool { get }
    var sessionInProgress: Bool { get }

    func checkForUpdateInformation()
    func checkForUpdates()
}

extension SPUUpdater: SparkleUpdateChecking {}

@MainActor
final class SparkleUpdateMonitor: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case updateAvailable(version: String)
    }

    @Published private(set) var status: Status = .idle

    var menuTitle: String {
        switch status {
        case .idle:
            String(localized: "检查更新…", bundle: .main, comment: "检查应用更新的菜单项。")
        case .checking:
            String(localized: "正在检查更新…", bundle: .main, comment: "正在检查应用更新的菜单状态。")
        case let .updateAvailable(version):
            String(
                format: String(
                    localized: "新版本 %@ 可用…",
                    bundle: .main,
                    comment: "发现可用更新时显示版本号的菜单标题。",
                ),
                locale: Locale.current,
                version,
            )
        }
    }

    var isMenuActionEnabled: Bool {
        status != .checking
    }

    private var availableVersionBeforeCheck: String?
    private var pendingVersion: String?

    func startSilentCheck(using updater: SparkleUpdateChecking) {
        guard status != .checking, !updater.sessionInProgress else { return }
        beginCheck()
        updater.checkForUpdateInformation()
    }

    func showUpdate(using updater: SparkleUpdateChecking) {
        guard status != .checking, updater.canCheckForUpdates else { return }

        updater.checkForUpdates()
    }

    private var availableVersion: String? {
        guard case let .updateAvailable(version) = status else { return nil }
        return version
    }

    private func beginCheck() {
        guard status != .checking else { return }

        availableVersionBeforeCheck = availableVersion
        pendingVersion = nil
        status = .checking
    }

    private func recordAvailableUpdate(_ update: SUAppcastItem) {
        let version = update.displayVersionString
        if status == .checking {
            pendingVersion = version
        } else {
            status = .updateAvailable(version: version)
        }
    }

    func handleScheduledUpdate(_ update: SUAppcastItem) {
        availableVersionBeforeCheck = nil
        pendingVersion = nil
        status = .updateAvailable(version: update.displayVersionString)
    }

    private func finishCheck(error: (any Error)?) {
        guard status == .checking else { return }

        if isNoUpdateError(error) {
            status = .idle
        } else if error != nil {
            if let availableVersionBeforeCheck {
                status = .updateAvailable(version: availableVersionBeforeCheck)
            } else {
                status = .idle
            }
        } else if let pendingVersion {
            status = .updateAvailable(version: pendingVersion)
        } else {
            status = .idle
        }

        availableVersionBeforeCheck = nil
        pendingVersion = nil
    }

    private func isNoUpdateError(_ error: (any Error)?) -> Bool {
        guard let error = error as NSError? else { return false }
        return error.domain == SUSparkleErrorDomain
            && error.code == Int(SUError.noUpdateError.rawValue)
    }
}

extension SparkleUpdateMonitor: SPUUpdaterDelegate {
    func updater(_: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if updateCheck == .updatesInBackground {
            beginCheck()
        }
    }

    func updater(_: SPUUpdater, didFindValidUpdate update: SUAppcastItem) {
        recordAvailableUpdate(update)
    }

    func updater(
        _: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?,
    ) {
        guard updateCheck == .updateInformation || updateCheck == .updatesInBackground else {
            return
        }
        finishCheck(error: error)
    }
}

extension SparkleUpdateMonitor: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _: SUAppcastItem,
        andInImmediateFocus _: Bool,
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state _: SPUUserUpdateState,
    ) {
        guard !handleShowingUpdate else { return }
        handleScheduledUpdate(update)
    }
}
