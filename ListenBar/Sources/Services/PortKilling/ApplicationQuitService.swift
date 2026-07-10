import AppKit
import Foundation

enum ApplicationQuitService {
    @MainActor
    static func request(_ request: ApplicationQuitRequest) -> ApplicationQuitAttempt {
        let applications = NSRunningApplication
            .runningApplications(withBundleIdentifier: request.bundleIdentifier)
            .filter { application in
                guard !application.isTerminated else {
                    return false
                }
                guard !request.bundlePaths.isEmpty else {
                    return true
                }
                guard let bundlePath = application.bundleURL?.path else {
                    return false
                }
                return request.bundlePaths.contains(bundlePath)
            }

        let acceptedInstanceCount = applications.reduce(into: 0) { count, application in
            let accepted: Bool
            switch request.mode {
            case .normal:
                accepted = application.terminate()
            case .force:
                accepted = application.forceTerminate()
            }
            if accepted {
                count += 1
            }
        }

        return ApplicationQuitAttempt(
            matchedInstanceCount: applications.count,
            acceptedInstanceCount: acceptedInstanceCount
        )
    }
}
