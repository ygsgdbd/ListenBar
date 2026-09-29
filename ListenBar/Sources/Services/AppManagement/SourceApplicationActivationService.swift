import AppKit
import Foundation

enum SourceApplicationActivationResult: Equatable, Sendable {
    case success
    case stale
    case failed
}

enum SourceApplicationActivationService {
    @MainActor
    static func activate(_ source: SourceApplication) -> SourceApplicationActivationResult {
        guard let application = NSRunningApplication(processIdentifier: pid_t(source.pid)),
              !application.isTerminated,
              let bundleIdentifier = application.bundleIdentifier,
              let bundlePath = application.bundleURL?.path,
              let launchDate = application.launchDate
        else {
            return .stale
        }

        let current = SourceApplication(
            name: application.localizedName ?? source.name,
            pid: Int(application.processIdentifier),
            bundleIdentifier: bundleIdentifier,
            bundlePath: bundlePath,
            launchDate: launchDate,
        )
        return activate(
            source,
            current: current,
            canActivate: application.activationPolicy != .prohibited,
            performActivation: { application.activate(options: []) },
        )
    }

    static func activate(
        _ source: SourceApplication,
        current: SourceApplication?,
        canActivate: Bool,
        performActivation: () -> Bool,
    ) -> SourceApplicationActivationResult {
        guard let current,
              current.pid == source.pid,
              current.bundleIdentifier == source.bundleIdentifier,
              current.bundlePath == source.bundlePath,
              current.launchDate == source.launchDate
        else {
            return .stale
        }
        guard canActivate else { return .failed }
        return performActivation() ? .success : .failed
    }
}
