import SwiftUI

@main
struct EveryringApp: App {
    @State private var model = RingsModel()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(model)
        }
    }
}
