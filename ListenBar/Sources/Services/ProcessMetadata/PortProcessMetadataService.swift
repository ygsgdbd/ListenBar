import AppKit
import Darwin
import Foundation
import SwifterSwift

enum PortProcessMetadataService {
    struct ApplicationBundleResolution: Equatable {
        let ownerBundleURL: URL
        let processBundleURL: URL
    }

    private struct ProcessSnapshot {
        let parentPID: Int
        let uid: uid_t
    }

    private struct MetadataDetails {
        let executablePath: String?
        let commandLine: String?
        let commandLineSummary: String?
        let source: PortProcessSource
        let classification: PortProcessClassification
    }

    private static let kernProcArgs2 = 49

    @MainActor
    static func resolveMetadata(for pids: Set<Int>) -> [Int: PortProcessMetadata] {
        var metadataByPID: [Int: PortProcessMetadata] = [:]

        for pid in pids {
            let runningApplication = NSRunningApplication(processIdentifier: pid_t(pid))
            let executablePath = executablePath(for: pid) ?? runningApplication?.executableURL?.path
            let processSnapshot = processSnapshot(for: pid)
            let commandLineArguments = commandLineArguments(for: pid)
            let parentProcessNames = parentProcessNames(startingAt: processSnapshot?.parentPID)

            if let executablePath, isOwnApplicationExecutablePath(executablePath) {
                continue
            }

            if let executablePath,
               let metadata = applicationMetadata(
                forExecutablePath: executablePath,
                runningApplication: runningApplication,
                processSnapshot: processSnapshot,
                commandLineArguments: commandLineArguments,
                parentProcessNames: parentProcessNames
               ) {
                metadataByPID[pid] = metadata
                continue
            }

            if let metadata = applicationMetadata(
                for: runningApplication,
                executablePath: executablePath,
                processSnapshot: processSnapshot,
                commandLineArguments: commandLineArguments,
                parentProcessNames: parentProcessNames
            ) {
                metadataByPID[pid] = metadata
                continue
            }

            guard let executablePath else { continue }
            metadataByPID[pid] = executableMetadata(
                for: executablePath,
                processSnapshot: processSnapshot,
                commandLineArguments: commandLineArguments,
                parentProcessNames: parentProcessNames
            )
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

    static func commandLineString(arguments: [String]) -> String? {
        guard !arguments.isEmpty else {
            return nil
        }
        return arguments.map(shellQuotedArgument).joined(separator: " ")
    }

    static func commandLineSummary(for commandLine: String, limit: Int = 120) -> String {
        guard commandLine.count > limit else {
            return commandLine
        }

        let endIndex = commandLine.index(commandLine.startIndex, offsetBy: max(0, limit - 3))
        return String(commandLine[..<endIndex]) + "..."
    }

    static func inferredSource(
        executablePath: String?,
        applicationPath: String?,
        parentProcessNames: [String]
    ) -> PortProcessSource {
        let normalizedParentNames = parentProcessNames.map { $0.lowercased() }

        if isSystemPath(applicationPath) || isSystemPath(executablePath) {
            return .system
        }
        if normalizedParentNames.contains(where: isVisualStudioCodeProcessName) {
            return .visualStudioCode
        }
        if isHomebrewPath(executablePath) {
            return .homebrew
        }
        if normalizedParentNames.contains(where: isTerminalProcessName) {
            return .terminal
        }
        if applicationPath != nil {
            return .application
        }
        if normalizedParentNames.contains("launchd") {
            return .launchd
        }
        if executablePath != nil {
            return .executable
        }
        return .unknown
    }

    static func processClassification(
        uid: uid_t?,
        executablePath: String?,
        applicationPath: String?,
        currentUID: uid_t = getuid()
    ) -> PortProcessClassification {
        if let uid, uid == 0 || uid != currentUID {
            return .systemOrOtherUser
        }
        if isSystemPath(applicationPath) || isSystemPath(executablePath) {
            return .systemOrOtherUser
        }
        return .user
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
        runningApplication: NSRunningApplication?,
        processSnapshot: ProcessSnapshot?,
        commandLineArguments: [String]?,
        parentProcessNames: [String]
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
        let details = metadataDetails(
            executablePath: path,
            applicationPath: resolution.ownerBundleURL.path,
            processSnapshot: processSnapshot,
            commandLineArguments: commandLineArguments,
            parentProcessNames: parentProcessNames
        )

        return PortProcessMetadata(
            bundleIdentifier: bundleIdentifier,
            name: ownerName,
            path: resolution.ownerBundleURL.path,
            processDetailName: processDetailName,
            executablePath: details.executablePath,
            commandLine: details.commandLine,
            commandLineSummary: details.commandLineSummary,
            source: details.source,
            classification: details.classification
        )
    }

    private static func applicationMetadata(
        for runningApplication: NSRunningApplication?,
        executablePath: String?,
        processSnapshot: ProcessSnapshot?,
        commandLineArguments: [String]?,
        parentProcessNames: [String]
    ) -> PortProcessMetadata? {
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
        let applicationPath = runningApplication.bundleURL?.path
        let details = metadataDetails(
            executablePath: executablePath ?? runningApplication.executableURL?.path,
            applicationPath: applicationPath,
            processSnapshot: processSnapshot,
            commandLineArguments: commandLineArguments,
            parentProcessNames: parentProcessNames
        )

        return PortProcessMetadata(
            bundleIdentifier: bundleIdentifier,
            name: name,
            path: applicationPath,
            executablePath: details.executablePath,
            commandLine: details.commandLine,
            commandLineSummary: details.commandLineSummary,
            source: details.source,
            classification: details.classification
        )
    }

    private static func executableMetadata(
        for path: String,
        processSnapshot: ProcessSnapshot?,
        commandLineArguments: [String]?,
        parentProcessNames: [String]
    ) -> PortProcessMetadata {
        let name = URL(fileURLWithPath: path).lastPathComponent
        let details = metadataDetails(
            executablePath: path,
            applicationPath: nil,
            processSnapshot: processSnapshot,
            commandLineArguments: commandLineArguments,
            parentProcessNames: parentProcessNames
        )
        return .executable(
            name: name,
            path: path,
            commandLine: details.commandLine,
            commandLineSummary: details.commandLineSummary,
            source: details.source,
            classification: details.classification
        )
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

    private static func processName(for pid: Int) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let result = proc_name(pid_t(pid), &buffer, UInt32(buffer.count))
        guard result > 0 else {
            return nil
        }
        return String(cString: buffer)
    }

    private static func processSnapshot(for pid: Int) -> ProcessSnapshot? {
        var info = proc_bsdinfo()
        let result = proc_pidinfo(
            pid_t(pid),
            PROC_PIDTBSDINFO,
            0,
            &info,
            Int32(MemoryLayout<proc_bsdinfo>.size)
        )
        guard result == Int32(MemoryLayout<proc_bsdinfo>.size) else {
            return nil
        }

        return ProcessSnapshot(
            parentPID: Int(info.pbi_ppid),
            uid: info.pbi_uid
        )
    }

    private static func commandLineArguments(for pid: Int) -> [String]? {
        var mib: [Int32] = [CTL_KERN, Int32(kernProcArgs2), Int32(pid)]
        var size = 0
        guard mib.withUnsafeMutableBufferPointer({
            sysctl($0.baseAddress, u_int($0.count), nil, &size, nil, 0)
        }) == 0, size > 0 else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: size)
        let result = mib.withUnsafeMutableBufferPointer { mibBuffer in
            buffer.withUnsafeMutableBytes { bufferBytes in
                sysctl(
                    mibBuffer.baseAddress,
                    u_int(mibBuffer.count),
                    bufferBytes.baseAddress,
                    &size,
                    nil,
                    0
                )
            }
        }
        guard result == 0 else {
            return nil
        }

        let argc = argumentCount(from: buffer)
        guard argc > 0 else {
            return nil
        }

        var index = MemoryLayout<Int32>.size
        skipString(in: buffer, index: &index)
        skipNulls(in: buffer, index: &index)

        var arguments: [String] = []
        while arguments.count < argc, index < buffer.count {
            let startIndex = index
            skipString(in: buffer, index: &index)
            if index > startIndex,
               let argument = String(bytes: buffer[startIndex..<index], encoding: .utf8) {
                arguments.append(argument)
            }
            skipNulls(in: buffer, index: &index)
        }

        return arguments.isEmpty ? nil : arguments
    }

    private static func argumentCount(from buffer: [UInt8]) -> Int {
        guard buffer.count >= MemoryLayout<Int32>.size else {
            return 0
        }

        var count = Int32(0)
        withUnsafeMutableBytes(of: &count) { countBytes in
            buffer.withUnsafeBytes { bufferBytes in
                guard let baseAddress = bufferBytes.baseAddress else { return }
                countBytes.copyMemory(
                    from: UnsafeRawBufferPointer(
                        start: baseAddress,
                        count: MemoryLayout<Int32>.size
                    )
                )
            }
        }
        return max(0, Int(count))
    }

    private static func skipString(in buffer: [UInt8], index: inout Int) {
        while index < buffer.count, buffer[index] != 0 {
            index += 1
        }
    }

    private static func skipNulls(in buffer: [UInt8], index: inout Int) {
        while index < buffer.count, buffer[index] == 0 {
            index += 1
        }
    }

    private static func parentProcessNames(startingAt parentPID: Int?) -> [String] {
        var names: [String] = []
        var currentPID = parentPID
        var visitedPIDs: Set<Int> = []

        for _ in 0..<8 {
            guard
                let pid = currentPID,
                pid > 0,
                !visitedPIDs.contains(pid)
            else {
                break
            }
            visitedPIDs.insert(pid)

            if let path = executablePath(for: pid) {
                names.append(URL(fileURLWithPath: path).lastPathComponent)
                if let applicationURL = applicationBundleURL(forExecutablePath: path) {
                    names.append(applicationURL.deletingPathExtension().lastPathComponent)
                }
            } else if let name = processName(for: pid) {
                names.append(name)
            }

            let nextPID = processSnapshot(for: pid)?.parentPID
            guard nextPID != pid else {
                break
            }
            currentPID = nextPID
        }

        return names
    }

    private static func metadataDetails(
        executablePath: String?,
        applicationPath: String?,
        processSnapshot: ProcessSnapshot?,
        commandLineArguments: [String]?,
        parentProcessNames: [String]
    ) -> MetadataDetails {
        let commandLine = commandLineArguments.flatMap(commandLineString(arguments:))
        return MetadataDetails(
            executablePath: executablePath,
            commandLine: commandLine,
            commandLineSummary: commandLine.map { commandLineSummary(for: $0) },
            source: inferredSource(
                executablePath: executablePath,
                applicationPath: applicationPath,
                parentProcessNames: parentProcessNames
            ),
            classification: processClassification(
                uid: processSnapshot?.uid,
                executablePath: executablePath,
                applicationPath: applicationPath
            )
        )
    }

    private static func shellQuotedArgument(_ argument: String) -> String {
        guard !argument.isEmpty else {
            return "''"
        }

        let safeCharacters = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "/._-:=@%+"))
        if argument.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return argument
        }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func isVisualStudioCodeProcessName(_ name: String) -> Bool {
        name.contains("visual studio code") || name == "code" || name.hasPrefix("code helper")
    }

    private static func isTerminalProcessName(_ name: String) -> Bool {
        name.contains("terminal")
            || name.contains("iterm")
            || name.contains("warp")
            || name == "kitty"
            || name == "alacritty"
    }

    private static func isHomebrewPath(_ path: String?) -> Bool {
        guard let path else {
            return false
        }
        return [
            "/opt/homebrew/",
            "/usr/local/Homebrew/",
            "/usr/local/Cellar/",
            "/usr/local/opt/",
            "/usr/local/bin/"
        ].contains { path.hasPrefix($0) }
    }

    private static func isSystemPath(_ path: String?) -> Bool {
        guard let path else {
            return false
        }
        return [
            "/System/",
            "/usr/sbin/",
            "/usr/libexec/",
            "/bin/",
            "/sbin/"
        ].contains { path.hasPrefix($0) }
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
