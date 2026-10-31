import SwiftUI

@main
struct ScreenGaugeApp: App {
    @StateObject private var store = GaugeStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
