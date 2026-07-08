import AppKit
import Darwin
import Foundation
import SwifterSwift

enum PortProcessMetadataService {
    struct ApplicationBundleResolution: Equatable {
        let ownerBundleURL: URL
        let processBundleURL: URL
    }

    @MainActor
    static func resolveMetadata(for pids: Set<Int>) -> [Int: PortProcessMetadata] {
        var metadataByPID: [Int: PortProcessMetadata] = [:]

        for pid in pids {
            let runningApplication = NSRunningApplication(processIdentifier: pid_t(pid))
            let executablePath = executablePath(for: pid)

            if let executablePath, isOwnApplicationExecutablePath(executablePath) {
                continue
            }

            if let executablePath,
               let metadata = applicationMetadata(
                forExecutablePath: executablePath,
                runningApplication: runningApplication
               ) {
                metadataByPID[pid] = metadata
                continue
            }

            if let metadata = applicationMetadata(for: runningApplication) {
                metadataByPID[pid] = metadata
                continue
            }

            guard let executablePath else { continue }
            metadataByPID[pid] = executableMetadata(for: executablePath)
        }

        return metadataByPID
    }

    static func applicationBundleURL(forExecutablePath path: String) -> URL? {
        applicationBundleResolution(forExecutablePath: path)?.ownerBundleURL
    }

    static func applicationBundleResolution(forExecutablePath path: String) -> ApplicationBundleResolution? {
        let executableURL = URL(fileURLWithPath: path)
        let bundleURLs = applicationBundleURLs(containing: executableURL)

        guard
            let ownerBundleURL = bundleURLs.first,
            let processBundleURL = bundleURLs.last,
            executableURL.path.hasPrefix(contentsMacOSPath(for: processBundleURL))
        else {
            return nil
        }

        return ApplicationBundleResolution(
            ownerBundleURL: ownerBundleURL,
            processBundleURL: processBundleURL
        )
    }

    static func processDetailName(processName: String, ownerName: String) -> String? {
        guard
            let processName = nonEmptyName(processName),
            let ownerName = nonEmptyName(ownerName),
            processName != ownerName
        else {
            return nil
        }

        guard processName.hasPrefix(ownerName) else {
            return processName
        }

        let detail = processName
            .removingPrefix(ownerName)
            .trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "-–—:"))
            .trimmed

        return nonEmptyName(detail) ?? processName
    }

    private static func applicationBundleURLs(containing executableURL: URL) -> [URL] {
        var bundleURLs: [URL] = []
        var candidateURL = executableURL.deletingLastPathComponent()

        while candidateURL.path != "/" {
            if candidateURL.pathExtension == "app",
               executableURL.path.hasPrefix(contentsPath(for: candidateURL)) {
                bundleURLs.append(candidateURL)
            }

            let parentURL = candidateURL.deletingLastPathComponent()
            guard parentURL.path != candidateURL.path else {
                break
            }
            candidateURL = parentURL
        }

        return Array(bundleURLs.reversed())
    }

    private static func applicationMetadata(
        forExecutablePath path: String,
        runningApplication: NSRunningApplication?
    ) -> PortProcessMetadata? {
        guard
            let resolution = applicationBundleResolution(forExecutablePath: path),
            let ownerBundle = Bundle(url: resolution.ownerBundleURL),
            let bundleIdentifier = ownerBundle.bundleIdentifier,
            bundleIdentifier != Bundle.main.bundleIdentifier
        else {
            return nil
        }

        let ownerName = ownerName(
            from: ownerBundle,
            ownerURL: resolution.ownerBundleURL,
            runningApplication: runningApplication
        ) ?? bundleIdentifier
        let processDetailName = processDetailName(
            fromProcessBundleAt: resolution.processBundleURL,
            ownerBundleURL: resolution.ownerBundleURL,
            ownerName: ownerName
        )

        return PortProcessMetadata(
            bundleIdentifier: bundleIdentifier,
            name: ownerName,
            path: resolution.ownerBundleURL.path,
            processDetailName: processDetailName
        )
    }

    private static func applicationMetadata(for runningApplication: NSRunningApplication?) -> PortProcessMetadata? {
        guard
            let runningApplication,
            let bundleIdentifier = runningApplication.bundleIdentifier,
            bundleIdentifier != Bundle.main.bundleIdentifier
        else {
            return nil
        }

        let bundle = runningApplication.bundleURL.flatMap(Bundle.init(url:))
        let name = nonEmptyName(runningApplication.localizedName)
            ?? bundle.flatMap(bundleName)
            ?? bundleIdentifier

        return PortProcessMetadata(
            bundleIdentifier: bundleIdentifier,
            name: name,
            path: runningApplication.bundleURL?.path
        )
    }

    private static func executableMetadata(for path: String) -> PortProcessMetadata {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return .executable(name: name, path: path)
    }

    private static func ownerName(
        from bundle: Bundle,
        ownerURL: URL,
        runningApplication: NSRunningApplication?
    ) -> String? {
        if runningApplication?.bundleURL?.path == ownerURL.path,
           let localizedName = nonEmptyName(runningApplication?.localizedName) {
            return localizedName
        }

        return bundleName(from: bundle) ?? ownerURL.deletingPathExtension().lastPathComponent
    }

    private static func processDetailName(
        fromProcessBundleAt processBundleURL: URL,
        ownerBundleURL: URL,
        ownerName: String
    ) -> String? {
        guard processBundleURL.path != ownerBundleURL.path else {
            return nil
        }

        let processName = Bundle(url: processBundleURL).flatMap(bundleName)
            ?? processBundleURL.deletingPathExtension().lastPathComponent
        return processDetailName(processName: processName, ownerName: ownerName)
    }

    private static func isOwnApplicationExecutablePath(_ path: String) -> Bool {
        guard
            let resolution = applicationBundleResolution(forExecutablePath: path),
            let bundle = Bundle(url: resolution.ownerBundleURL)
        else {
            return false
        }

        return bundle.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    private static func executablePath(for pid: Int) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let result = proc_pidpath(pid_t(pid), &buffer, UInt32(buffer.count))
        guard result > 0 else {
            return nil
        }
        return String(cString: buffer)
    }

    private static func contentsPath(for bundleURL: URL) -> String {
        bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .path + "/"
    }

    private static func contentsMacOSPath(for bundleURL: URL) -> String {
        bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .path + "/"
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
