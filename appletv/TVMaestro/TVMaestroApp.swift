// TVMaestro tvOS client — entry point.

import SwiftUI

@main
struct TVMaestroApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .onAppear { appModel.start() }
                .onDisappear { appModel.stop() }
        }
    }
}
