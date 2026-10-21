import SwiftUI
import SwiftData
import HatchlingKit

@main
struct HatchlingApp: App {
    let store = HatchlingStore.make()

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(store.container)
        }
    }
}
