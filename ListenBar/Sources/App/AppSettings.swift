import Foundation
import Sharing

struct AppSettings: Codable, Equatable, Sendable {
    static let storageURL = URL.applicationSupportDirectory
        .appending(component: "top.ygsgdbd.ListenBar", directoryHint: .isDirectory)
        .appending(component: "settings.json")

    var autoRefresh: AutoRefreshMode = .onMenuOpen
    var ignoredProcesses: [IgnoredProcessItem] = []

    init(
        autoRefresh: AutoRefreshMode = .onMenuOpen,
        ignoredProcesses: [IgnoredProcessItem] = [],
    ) {
        self.autoRefresh = autoRefresh
        self.ignoredProcesses = Self.deduplicated(ignoredProcesses)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoRefresh = try container.decodeIfPresent(AutoRefreshMode.self, forKey: .autoRefresh) ?? .onMenuOpen
        ignoredProcesses = Self.deduplicated(
            try container.decodeIfPresent([IgnoredProcessItem].self, forKey: .ignoredProcesses) ?? [],
        )
    }

    mutating func ignore(_ item: IgnoredProcessItem) {
        guard !ignoredProcesses.contains(where: { $0.id == item.id }) else { return }
        ignoredProcesses.append(item)
    }

    mutating func restore(_ item: IgnoredProcessItem) {
        ignoredProcesses.removeAll { $0.id == item.id }
    }

    private static func deduplicated(_ items: [IgnoredProcessItem]) -> [IgnoredProcessItem] {
        var identifiers: Set<String> = []
        return items.filter {
            $0.hasStableIdentity && identifiers.insert($0.id).inserted
        }
    }
}

extension SharedReaderKey where Self == FileStorageKey<AppSettings> {
    static var appSettings: Self {
        fileStorage(AppSettings.storageURL)
    }
}
