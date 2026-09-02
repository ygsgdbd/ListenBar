import AppKit
import Foundation

enum AppInfoService {
    static let githubAccount = "ygsgdbd"
    static let githubRepository = "\(githubAccount)/ListenBar"

    private static let githubBaseURL = "https://github.com"

    static var githubProfileURL: URL? {
        URL(string: "\(githubBaseURL)/\(githubAccount)")
    }

    static var githubRepositoryURL: URL? {
        URL(string: "\(githubBaseURL)/\(githubRepository)")
    }

    static var helpURL: URL? {
        URL(string: "\(githubBaseURL)/\(githubRepository)#readme")
    }

    static var issueReportURL: URL? {
        URL(string: "\(githubBaseURL)/\(githubRepository)/issues/new")
    }

    @MainActor
    static func openGitHubProfile() {
        open(githubProfileURL)
    }

    @MainActor
    static func openGitHubRepository() {
        open(githubRepositoryURL)
    }

    @MainActor
    static func openHelp() {
        open(helpURL)
    }

    @MainActor
    static func openReportIssue() {
        open(issueReportURL)
    }

    @MainActor
    static func copySupportDiagnostics(_ diagnostics: SupportDiagnostics) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics.reportText, forType: .string)
    }

    @MainActor
    private static func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
