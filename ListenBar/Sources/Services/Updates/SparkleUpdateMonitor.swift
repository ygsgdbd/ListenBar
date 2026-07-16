import Combine
import Sparkle

@MainActor
protocol SparkleUpdateChecking: AnyObject {
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
        case updateAvailable
    }

    @Published private(set) var status: Status = .idle

    private var foundUpdateDuringSilentCheck = false

    var menuTitle: String {
        status == .updateAvailable ? "发现新版本…" : "检查更新…"
    }

    var isMenuActionEnabled: Bool {
        status != .checking
    }

    func startSilentCheck(using updater: SparkleUpdateChecking) {
        guard status != .checking, !updater.sessionInProgress else { return }
        foundUpdateDuringSilentCheck = false
        status = .checking
        updater.checkForUpdateInformation()
    }

    func showUpdate(using updater: SparkleUpdateChecking) {
        guard isMenuActionEnabled else { return }
        updater.checkForUpdates()
    }

    func recordFoundUpdate() {
        guard status == .checking else { return }
        foundUpdateDuringSilentCheck = true
    }

    func finishSilentCheck(error: (any Error)? = nil) {
        guard status == .checking else { return }
        status = error == nil && foundUpdateDuringSilentCheck ? .updateAvailable : .idle
        foundUpdateDuringSilentCheck = false
    }
}

extension SparkleUpdateMonitor: SPUUpdaterDelegate {
    func updater(_: SPUUpdater, didFindValidUpdate _: SUAppcastItem) {
        recordFoundUpdate()
    }

    func updater(
        _: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?,
    ) {
        guard updateCheck == .updateInformation else { return }
        finishSilentCheck(error: error)
    }
}
