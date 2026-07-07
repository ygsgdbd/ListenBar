import AppKit
import ComposableArchitecture
import SwiftUI

@main
struct ListenBarApp: App {
    let store: StoreOf<AppFeature>

    init() {
        self.store = Store(initialState: AppFeature.State()) {
            AppFeature()
        }
        self.store.send(.task)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: store)
        } label: {
            Image(systemName: "network")
        }
        .menuBarExtraStyle(.menu)
    }
}
