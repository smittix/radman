import SwiftUI

@main
struct RadManApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .defaultSize(width: 1280, height: 820)
    }
}
