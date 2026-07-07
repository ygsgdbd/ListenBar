import AppKit
import Foundation

enum PortProcessMetadataService {
    @MainActor
    static func resolveMetadata(for pids: Set<Int>) -> [Int: PortProcessMetadata] {
        var metadataByPID: [Int: PortProcessMetadata] = [:]

        for pid in pids {
            guard
                let runningApplication = NSRunningApplication(processIdentifier: pid_t(pid)),
                let bundleIdentifier = runningApplication.bundleIdentifier,
                bundleIdentifier != Bundle.main.bundleIdentifier
            else {
                continue
            }

            let bundle = runningApplication.bundleURL.flatMap(Bundle.init(url:))
            let name = nonEmptyName(runningApplication.localizedName)
                ?? bundle.flatMap(bundleName)
                ?? bundleIdentifier

            metadataByPID[pid] = PortProcessMetadata(
                bundleIdentifier: bundleIdentifier,
                name: name,
                path: runningApplication.bundleURL?.path
            )
        }

        return metadataByPID
    }

    private static func bundleName(from bundle: Bundle) -> String? {
        name(from: bundle.localizedInfoDictionary) ?? name(from: bundle.infoDictionary)
    }

    private static func name(from dictionary: [String: Any]?) -> String? {
        nonEmptyName(dictionary?["CFBundleDisplayName"] as? String)
            ?? nonEmptyName(dictionary?["CFBundleName"] as? String)
    }

    private static func nonEmptyName(_ name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else {
            return nil
        }
        return name
    }
}
