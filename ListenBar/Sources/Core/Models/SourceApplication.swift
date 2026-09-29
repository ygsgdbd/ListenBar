import Foundation

struct SourceApplication: Equatable, Sendable {
    let name: String
    let pid: Int
    let bundleIdentifier: String
    let bundlePath: String
    let launchDate: Date
}
