import Sparkle
import SwiftUI

struct AppInfoView: View {
    @ObservedObject var updateMonitor: SparkleUpdateMonitor
    let updaterController: SPUStandardUpdaterController

    var body: some View {
        let diagnostics = SupportDiagnostics.current()

        Group {
            Button {
                updateMonitor.showUpdate(using: updaterController.updater)
            } label: {
                Label {
                    Text(updateMonitor.menuTitle)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(!updateMonitor.isMenuActionEnabled)

            Menu {
                Button {
                    AppInfoService.openGitHubRepository()
                } label: {
                    Label(versionTitle(diagnostics.version), systemImage: "chevron.left.forwardslash.chevron.right")
                }

                Button {
                    AppInfoService.openGitHubProfile()
                } label: {
                    Label(developerTitle, systemImage: "person.crop.circle")
                }

                Divider()

                Button {
                    AppInfoService.openHelp()
                } label: {
                    Label("使用帮助", systemImage: "questionmark.circle")
                }

                Button {
                    AppInfoService.copySupportDiagnostics(diagnostics)
                } label: {
                    Label("复制诊断信息", systemImage: "doc.on.doc")
                }

                Button {
                    AppInfoService.openReportIssue()
                } label: {
                    Label("报告问题…", systemImage: "exclamationmark.bubble")
                }
            } label: {
                Label("帮助与关于", systemImage: "info.circle")
            }
        }
    }

    private var developerTitle: String {
        String(
            format: String(localized: "开发者：%@", bundle: .main, comment: "帮助与关于菜单中的开发者链接。"),
            locale: Locale.current,
            AppInfoService.githubAccount,
        )
    }

    private func versionTitle(_ version: String) -> String {
        String(
            format: String(localized: "ListenBar v%@", bundle: .main, comment: "帮助与关于菜单中的应用版本链接。"),
            locale: Locale.current,
            version,
        )
    }
}
