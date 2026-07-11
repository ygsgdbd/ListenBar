import Foundation
import Sharing

struct AppSettings: Codable, Equatable, Sendable {
    static let storageURL = URL.applicationSupportDirectory
        .appending(component: "top.ygsgdbd.ListenBar", directoryHint: .isDirectory)
        .appending(component: "settings.json")

    var autoRefresh: AutoRefreshMode = .onMenuOpen

    init(autoRefresh: AutoRefreshMode = .onMenuOpen) {
        self.autoRefresh = autoRefresh
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoRefresh = try container.decodeIfPresent(AutoRefreshMode.self, forKey: .autoRefresh) ?? .onMenuOpen
    }
}

extension SharedReaderKey where Self == FileStorageKey<AppSettings> {
    static var appSettings: Self {
        fileStorage(AppSettings.storageURL)
    }
}
