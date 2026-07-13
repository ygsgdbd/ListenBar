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

    private struct ProcessRuntimeInfo {
        let executablePath: String?
        let processSnapshot: ProcessSnapshot?
        let processName: String?
        let commandLineArguments: [String]?
        let parentProcessNames: [String]
        let residentMemoryBytes: UInt64?
    }

    private struct RunningApplicationSnapshot {
        let bundleIdentifier: String?
        let bundlePath: String?
        let executablePath: String?
        let localizedName: String?
    }

    private struct MetadataDetails {
        let executablePath: String?
        let commandLine: String?
        let commandLineSummary: String?
        let redactedCommandLine: String?
        let redactedCommandLineSummary: String?
        let residentMemoryBytes: UInt64?
        let sources: [PortProcessSource]
        let classification: PortProcessClassification
    }

    private static let kernProcArgs2 = 49

    static func resolveMetadata(for ports: [PortEntry]) async -> [Int: PortProcessMetadata] {
        let pids = Set(ports.map(\.pid))
        let portsByPID = ports.reduce(into: [Int: PortEntry]()) { result, port in
            if result[port.pid] == nil {
                result[port.pid] = port
            }
        }
        let runtimeByPID = await Task.detached(priority: .userInitiated) {
            runtimeInfo(for: pids)
        }
        .value
        let runningApplicationsByPID = await runningApplicationSnapshots(for: pids)

        return await Task.detached(priority: .userInitiated) {
            resolveMetadata(
                for: pids,
                runtimeByPID: runtimeByPID,
                runningApplicationsByPID: runningApplicationsByPID,
                portsByPID: portsByPID,
            )
        }
        .value
    }

    private static func resolveMetadata(
        for pids: Set<Int>,
        runtimeByPID: [Int: ProcessRuntimeInfo],
        runningApplicationsByPID: [Int: RunningApplicationSnapshot],
        portsByPID: [Int: PortEntry],
    ) -> [Int: PortProcessMetadata] {
        var metadataByPID: [Int: PortProcessMetadata] = [:]

        for pid in pids {
            let runningApplication = runningApplicationsByPID[pid]
            let runtime = runtimeByPID[pid]
            let executablePath = runtime?.executablePath ?? runningApplication?.executablePath

            if let executablePath, isOwnApplicationExecutablePath(executablePath) {
                continue
            }

            if let executablePath,
               let metadata = applicationMetadata(
                   forExecutablePath: executablePath,
                   runningApplication: runningApplication,
                   processSnapshot: runtime?.processSnapshot,
                   commandLineArguments: runtime?.commandLineArguments,
                   parentProcessNames: runtime?.parentProcessNames ?? [],
                   residentMemoryBytes: runtime?.residentMemoryBytes,
               )
            {
                metadataByPID[pid] = metadata
                continue
            }

            if let metadata = applicationMetadata(
                for: runningApplication,
                executablePath: executablePath,
                processSnapshot: runtime?.processSnapshot,
                commandLineArguments: runtime?.commandLineArguments,
                parentProcessNames: runtime?.parentProcessNames ?? [],
                residentMemoryBytes: runtime?.residentMemoryBytes,
            ) {
                metadataByPID[pid] = metadata
                continue
            }

            guard let executablePath else {
                if let port = portsByPID[pid] {
                    metadataByPID[pid] = fallbackMetadata(
                        for: port,
                        processName: runtime?.processName,
                        uid: runtime?.processSnapshot?.uid,
                        residentMemoryBytes: runtime?.residentMemoryBytes,
                    )
                }
                continue
            }
            metadataByPID[pid] = executableMetadata(
                for: executablePath,
                processSnapshot: runtime?.processSnapshot,
                commandLineArguments: runtime?.commandLineArguments,
                parentProcessNames: runtime?.parentProcessNames ?? [],
                residentMemoryBytes: runtime?.residentMemoryBytes,
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
            processBundleURL: processBundleURL,
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

    static func redactedCommandLineString(arguments: [String]) -> String? {
        commandLineString(arguments: redactedArguments(arguments))
    }

    static func redactedArguments(_ arguments: [String]) -> [String] {
        var redacted: [String] = []
        var shouldRedactNext = false

        for argument in arguments {
            if shouldRedactNext {
                redacted.append("<redacted>")
                shouldRedactNext = false
                continue
            }

            if let separatorIndex = argument.firstIndex(of: "=") {
                let key = String(argument[..<separatorIndex])
                if isSensitiveKey(key) {
                    redacted.append("\(key)=<redacted>")
                    continue
                }
            }

            if isSensitiveKey(argument) {
                redacted.append(argument)
                shouldRedactNext = true
                continue
            }

            redacted.append(argument)
        }

        return redacted
    }

    static func commandLineSummary(for commandLine: String, limit: Int = 120) -> String {
        guard commandLine.count > limit else {
            return commandLine
        }

        let endIndex = commandLine.index(commandLine.startIndex, offsetBy: max(0, limit - 3))
        return String(commandLine[..<endIndex]) + "..."
    }

    static func inferredSources(
        executablePath: String?,
        applicationPath: String?,
        parentProcessNames: [String],
    ) -> [PortProcessSource] {
        let normalizedParentNames = parentProcessNames.map { $0.lowercased() }
        let resolvedExecutablePath = executablePath.map(resolvedExecutablePath(for:))
        let paths = [applicationPath, executablePath, resolvedExecutablePath].compactMap { $0 }
        var sources: [PortProcessSource] = []

        func append(_ source: PortProcessSource) {
            if !sources.contains(source) {
                sources.append(source)
            }
        }

        if isSystemPath(applicationPath) || isSystemPath(executablePath) {
            append(.system)
            return sources
        } else if applicationPath != nil {
            append(.application)
        } else if executablePath != nil {
            append(.executable)
        } else {
            append(.unknown)
        }

        if paths.contains(where: isHomebrewPath) {
            append(.homebrew)
        } else if paths.contains(where: isMacPortsPath) {
            append(.macPorts)
        } else if paths.contains(where: isNixPath) {
            append(.nix)
        }

        guard applicationPath == nil else {
            return sources
        }
        if normalizedParentNames.contains(where: isVisualStudioCodeProcessName) {
            append(.visualStudioCode)
        } else if normalizedParentNames.contains(where: isTerminalProcessName) {
            append(.terminal)
        } else if normalizedParentNames.contains("launchd") {
            append(.launchd)
        }
        return sources
    }

    static func processClassification(
        uid: uid_t?,
        executablePath: String?,
        applicationPath: String?,
        currentUID: uid_t = getuid(),
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
               executableURL.path.hasPrefix(contentsPath(for: candidateURL))
            {
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
        runningApplication: RunningApplicationSnapshot?,
        processSnapshot: ProcessSnapshot?,
        commandLineArguments: [String]?,
        parentProcessNames: [String],
        residentMemoryBytes: UInt64?,
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
            runningApplication: runningApplication,
        ) ?? bundleIdentifier
        let processDetailName = processDetailName(
            fromProcessBundleAt: resolution.processBundleURL,
            ownerBundleURL: resolution.ownerBundleURL,
            ownerName: ownerName,
        )
        let details = metadataDetails(
            executablePath: path,
            applicationPath: resolution.ownerBundleURL.path,
            processSnapshot: processSnapshot,
            commandLineArguments: commandLineArguments,
            parentProcessNames: parentProcessNames,
            residentMemoryBytes: residentMemoryBytes,
        )

        return PortProcessMetadata(
            bundleIdentifier: bundleIdentifier,
            name: ownerName,
            path: resolution.ownerBundleURL.path,
            processDetailName: processDetailName,
            executablePath: details.executablePath,
            commandLine: details.commandLine,
            commandLineSummary: details.commandLineSummary,
            redactedCommandLine: details.redactedCommandLine,
            redactedCommandLineSummary: details.redactedCommandLineSummary,
            residentMemoryBytes: details.residentMemoryBytes,
            sources: details.sources,
            classification: details.classification,
        )
    }

    private static func applicationMetadata(
        for runningApplication: RunningApplicationSnapshot?,
        executablePath: String?,
        processSnapshot: ProcessSnapshot?,
        commandLineArguments: [String]?,
        parentProcessNames: [String],
        residentMemoryBytes: UInt64?,
    ) -> PortProcessMetadata? {
        guard
            let runningApplication,
            let bundleIdentifier = runningApplication.bundleIdentifier,
            bundleIdentifier != Bundle.main.bundleIdentifier
        else {
            return nil
        }

        let bundleURL = runningApplication.bundlePath.map(URL.init(fileURLWithPath:))
        let bundle = bundleURL.flatMap(Bundle.init(url:))
        let name = nonEmptyName(runningApplication.localizedName)
            ?? bundle.flatMap(bundleName)
            ?? bundleIdentifier
        let applicationPath = runningApplication.bundlePath
        let details = metadataDetails(
            executablePath: executablePath ?? runningApplication.executablePath,
            applicationPath: applicationPath,
            processSnapshot: processSnapshot,
            commandLineArguments: commandLineArguments,
            parentProcessNames: parentProcessNames,
            residentMemoryBytes: residentMemoryBytes,
        )

        return PortProcessMetadata(
            bundleIdentifier: bundleIdentifier,
            name: name,
            path: applicationPath,
            executablePath: details.executablePath,
            commandLine: details.commandLine,
            commandLineSummary: details.commandLineSummary,
            redactedCommandLine: details.redactedCommandLine,
            redactedCommandLineSummary: details.redactedCommandLineSummary,
            residentMemoryBytes: details.residentMemoryBytes,
            sources: details.sources,
            classification: details.classification,
        )
    }

    private static func executableMetadata(
        for path: String,
        processSnapshot: ProcessSnapshot?,
        commandLineArguments: [String]?,
        parentProcessNames: [String],
        residentMemoryBytes: UInt64?,
    ) -> PortProcessMetadata {
        let name = URL(fileURLWithPath: path).lastPathComponent
        let details = metadataDetails(
            executablePath: path,
            applicationPath: nil,
            processSnapshot: processSnapshot,
            commandLineArguments: commandLineArguments,
            parentProcessNames: parentProcessNames,
            residentMemoryBytes: residentMemoryBytes,
        )
        return .executable(
            name: name,
            path: path,
            commandLine: details.commandLine,
            commandLineSummary: details.commandLineSummary,
            redactedCommandLine: details.redactedCommandLine,
            redactedCommandLineSummary: details.redactedCommandLineSummary,
            residentMemoryBytes: details.residentMemoryBytes,
            sources: details.sources,
            classification: details.classification,
        )
    }

    private static func ownerName(
        from bundle: Bundle,
        ownerURL: URL,
        runningApplication: RunningApplicationSnapshot?,
    ) -> String? {
        if runningApplication?.bundlePath == ownerURL.path,
           let localizedName = nonEmptyName(runningApplication?.localizedName)
        {
            return localizedName
        }

        return bundleName(from: bundle) ?? ownerURL.deletingPathExtension().lastPathComponent
    }

    private static func processDetailName(
        fromProcessBundleAt processBundleURL: URL,
        ownerBundleURL: URL,
        ownerName: String,
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

    @MainActor
    private static func runningApplicationSnapshots(for pids: Set<Int>) -> [Int: RunningApplicationSnapshot] {
        Dictionary(
            uniqueKeysWithValues: pids.compactMap { pid in
                guard let app = NSRunningApplication(processIdentifier: pid_t(pid)) else {
                    return nil
                }
                return (
                    pid,
                    RunningApplicationSnapshot(
                        bundleIdentifier: app.bundleIdentifier,
                        bundlePath: app.bundleURL?.path,
                        executablePath: app.executableURL?.path,
                        localizedName: app.localizedName,
                    ),
                )
            },
        )
    }

    private static func runtimeInfo(for pids: Set<Int>) -> [Int: ProcessRuntimeInfo] {
        var resolver = ProcessRuntimeResolver()
        return Dictionary(
            uniqueKeysWithValues: pids.map { pid in
                let snapshot = resolver.processSnapshot(for: pid)
                return (
                    pid,
                    ProcessRuntimeInfo(
                        executablePath: resolver.executablePath(for: pid),
                        processSnapshot: snapshot,
                        processName: resolver.processName(for: pid),
                        commandLineArguments: commandLineArguments(for: pid),
                        parentProcessNames: resolver.parentProcessNames(startingAt: snapshot?.parentPID),
                        residentMemoryBytes: residentMemoryBytes(for: pid),
                    ),
                )
            },
        )
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
            Int32(MemoryLayout<proc_bsdinfo>.size),
        )
        guard result == Int32(MemoryLayout<proc_bsdinfo>.size) else {
            return nil
        }

        return ProcessSnapshot(
            parentPID: Int(info.pbi_ppid),
            uid: info.pbi_uid,
        )
    }

    static func residentMemoryBytes(for pid: Int) -> UInt64? {
        var taskInfo = proc_taskinfo()
        let result = proc_pidinfo(
            pid_t(pid),
            PROC_PIDTASKINFO,
            0,
            &taskInfo,
            Int32(MemoryLayout<proc_taskinfo>.size),
        )
        return residentMemoryBytes(from: taskInfo, result: result)
    }

    static func residentMemoryBytes(from taskInfo: proc_taskinfo, result: Int32) -> UInt64? {
        guard result == Int32(MemoryLayout<proc_taskinfo>.size) else {
            return nil
        }
        return taskInfo.pti_resident_size
    }

    static func fallbackMetadata(
        for port: PortEntry,
        processName: String?,
        uid: uid_t?,
        residentMemoryBytes: UInt64?,
    ) -> PortProcessMetadata {
        .executable(
            name: processName ?? port.command,
            path: nil,
            residentMemoryBytes: residentMemoryBytes,
            sources: [.unknown],
            classification: fallbackClassification(uid: uid, portUser: port.user),
        )
    }

    private static func fallbackClassification(
        uid: uid_t?,
        portUser: String?,
    ) -> PortProcessClassification {
        if let uid {
            return processClassification(
                uid: uid,
                executablePath: nil,
                applicationPath: nil,
            )
        }
        guard let portUser = portUser?.lowercased() else {
            return .user
        }
        if portUser == "root" || portUser == "0" {
            return .systemOrOtherUser
        }
        if let numericUID = uid_t(portUser), numericUID != getuid() {
            return .systemOrOtherUser
        }
        return .user
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
                    0,
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
               let argument = String(bytes: buffer[startIndex ..< index], encoding: .utf8)
            {
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
                        count: MemoryLayout<Int32>.size,
                    ),
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

    private struct ProcessRuntimeResolver {
        private enum Cached<Value> {
            case resolved(Value?)
        }

        private var executablePaths: [Int: Cached<String>] = [:]
        private var processSnapshots: [Int: Cached<ProcessSnapshot>] = [:]
        private var processNames: [Int: Cached<String>] = [:]

        mutating func executablePath(for pid: Int) -> String? {
            if case let .resolved(cached)? = executablePaths[pid] {
                return cached
            }
            let value = PortProcessMetadataService.executablePath(for: pid)
            executablePaths[pid] = .resolved(value)
            return value
        }

        mutating func processSnapshot(for pid: Int) -> ProcessSnapshot? {
            if case let .resolved(cached)? = processSnapshots[pid] {
                return cached
            }
            let value = PortProcessMetadataService.processSnapshot(for: pid)
            processSnapshots[pid] = .resolved(value)
            return value
        }

        mutating func processName(for pid: Int) -> String? {
            if case let .resolved(cached)? = processNames[pid] {
                return cached
            }
            let value = PortProcessMetadataService.processName(for: pid)
            processNames[pid] = .resolved(value)
            return value
        }

        mutating func parentProcessNames(startingAt parentPID: Int?) -> [String] {
            var names: [String] = []
            var currentPID = parentPID
            var visitedPIDs: Set<Int> = []

            for _ in 0 ..< 8 {
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
    }

    private static func parentProcessNames(startingAt parentPID: Int?) -> [String] {
        var names: [String] = []
        var currentPID = parentPID
        var visitedPIDs: Set<Int> = []

        for _ in 0 ..< 8 {
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
        parentProcessNames: [String],
        residentMemoryBytes: UInt64?,
    ) -> MetadataDetails {
        let commandLine = commandLineArguments.flatMap(commandLineString(arguments:))
        let redactedCommandLine = commandLineArguments.flatMap(redactedCommandLineString(arguments:))
        return MetadataDetails(
            executablePath: executablePath,
            commandLine: commandLine,
            commandLineSummary: commandLine.map { commandLineSummary(for: $0) },
            redactedCommandLine: redactedCommandLine,
            redactedCommandLineSummary: redactedCommandLine.map { commandLineSummary(for: $0) },
            residentMemoryBytes: residentMemoryBytes,
            sources: inferredSources(
                executablePath: executablePath,
                applicationPath: applicationPath,
                parentProcessNames: parentProcessNames,
            ),
            classification: processClassification(
                uid: processSnapshot?.uid,
                executablePath: executablePath,
                applicationPath: applicationPath,
            ),
        )
    }

    private static func shellQuotedArgument(_ argument: String) -> String {
        guard !argument.isEmpty else {
            return "''"
        }

        let safeCharacters = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "/._-:=@%+<>"))
        if argument.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return argument
        }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let normalized = key
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
            .lowercased()
        return [
            "token",
            "secret",
            "password",
            "passwd",
            "pwd",
            "key",
            "credential",
            "auth",
            "bearer",
        ].contains { normalized.contains($0) }
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
        ].contains { path.hasPrefix($0) }
    }

    private static func isMacPortsPath(_ path: String) -> Bool {
        path.hasPrefix("/opt/local/")
    }

    private static func isNixPath(_ path: String) -> Bool {
        path.hasPrefix("/nix/store/")
    }

    private static func resolvedExecutablePath(for path: String) -> String {
        let executableURL = URL(fileURLWithPath: path)
        let resolvedPath = executableURL.resolvingSymlinksInPath().path
        if resolvedPath != path {
            return resolvedPath
        }
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else {
            return path
        }
        if destination.hasPrefix("/") {
            return URL(fileURLWithPath: destination).standardizedFileURL.path
        }
        return executableURL
            .deletingLastPathComponent()
            .appendingPathComponent(destination)
            .standardizedFileURL
            .path
    }

    private static func isSystemPath(_ path: String?) -> Bool {
        guard let path else {
            return false
        }
        if path.hasPrefix("/usr/local/") {
            return false
        }
        return [
            "/System/",
            "/Library/Apple/",
            "/usr/",
            "/bin/",
            "/sbin/",
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
