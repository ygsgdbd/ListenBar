import Foundation
@testable import ListenBar
import XCTest

final class SourceApplicationResolutionTests: XCTestCase {
    private let app = SourceApplication(
        name: "Editor", pid: 100, bundleIdentifier: "test.editor",
        bundlePath: "/Applications/Editor.app", launchDate: Date(timeIntervalSince1970: 10),
    )

    func testNodeShellAndNpmResolveNestedHelperOwner() {
        let ancestry = [
            process(1, parent: 2, path: "/opt/homebrew/bin/node"),
            process(2, parent: 3, path: "/opt/homebrew/bin/npm"),
            process(3, parent: 4, path: "/bin/zsh"),
            process(4, parent: 5, path: "/Applications/Editor.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"),
        ]
        XCTAssertEqual(PortProcessMetadataService.sourceApplication(ancestry: ancestry, applications: [app]), app)
    }

    func testDirectApplicationAndNearestAncestorTakePrecedence() {
        let other = SourceApplication(name: "Other", pid: 200, bundleIdentifier: "test.other", bundlePath: "/Applications/Other.app", launchDate: app.launchDate)
        let ancestry = [process(app.pid, parent: other.pid), process(other.pid)]
        XCTAssertEqual(PortProcessMetadataService.sourceApplication(ancestry: ancestry, applications: [other, app]), app)
    }

    func testAmbiguousHelperOwnerAndUnknownSourceHaveNoTarget() {
        let duplicate = SourceApplication(name: app.name, pid: 101, bundleIdentifier: app.bundleIdentifier, bundlePath: app.bundlePath, launchDate: app.launchDate)
        let helper = process(4, path: "/Applications/Editor.app/Contents/MacOS/Helper")
        XCTAssertNil(PortProcessMetadataService.sourceApplication(ancestry: [helper], applications: [app, duplicate]))
        XCTAssertNil(PortProcessMetadataService.sourceApplication(ancestry: [process(2, path: "/usr/bin/node")], applications: [app]))
    }

    func testReusedPIDWithDifferentExecutableHasNoTarget() {
        let ancestry = [process(app.pid, path: "/usr/bin/node")]
        XCTAssertNil(PortProcessMetadataService.sourceApplication(ancestry: ancestry, applications: [app]))
    }

    func testAmbiguousHelperOwnerResolvesExactAncestorInstance() {
        let duplicate = SourceApplication(name: app.name, pid: 101, bundleIdentifier: app.bundleIdentifier, bundlePath: app.bundlePath, launchDate: app.launchDate)
        for owner in [app, duplicate] {
            let ancestry = [
                process(2, parent: 3, path: "/opt/homebrew/bin/node"),
                process(3, parent: 4, path: "/bin/zsh"),
                process(4, parent: owner.pid, path: "/Applications/Editor.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"),
                process(owner.pid, path: "/Applications/Editor.app/Contents/MacOS/Editor"),
            ]
            XCTAssertEqual(PortProcessMetadataService.sourceApplication(ancestry: ancestry, applications: [app, duplicate]), owner)
        }
    }

    func testAmbiguousHelperOwnerDoesNotFallBackToUnrelatedAncestor() {
        let duplicate = SourceApplication(name: app.name, pid: 101, bundleIdentifier: app.bundleIdentifier, bundlePath: app.bundlePath, launchDate: app.launchDate)
        let terminal = SourceApplication(name: "Terminal", pid: 200, bundleIdentifier: "test.terminal", bundlePath: "/Applications/Terminal.app", launchDate: app.launchDate)
        let ancestry = [
            process(4, parent: terminal.pid, path: "/Applications/Editor.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"),
            process(terminal.pid, path: "/Applications/Terminal.app/Contents/MacOS/Terminal"),
        ]
        XCTAssertNil(PortProcessMetadataService.sourceApplication(ancestry: ancestry, applications: [app, duplicate, terminal]))
    }

    func testBrokenParentChainStopsAtLastKnownProcess() {
        let ancestry = PortProcessMetadataService.sourceAncestry(startingAt: 1) { pid in
            self.process(pid, parent: pid == 1 ? 2 : nil)
        }
        XCTAssertEqual(ancestry.map(\.pid), [1, 2])
    }

    func testAncestryStopsAtCycleAndAtEightAncestors() {
        let cycle = PortProcessMetadataService.sourceAncestry(startingAt: 1) { pid in
            self.process(pid, parent: pid == 1 ? 2 : 1)
        }
        XCTAssertEqual(cycle.map(\.pid), [1, 2])
        let deep = PortProcessMetadataService.sourceAncestry(startingAt: 1) { pid in
            self.process(pid, parent: pid + 1)
        }
        XCTAssertEqual(deep.map(\.pid), Array(1 ... 9))
    }

    private func process(_ pid: Int, parent: Int? = nil, path: String? = nil) -> PortProcessMetadataService.SourceProcess {
        .init(pid: pid, parentPID: parent, executablePath: path)
    }
}
