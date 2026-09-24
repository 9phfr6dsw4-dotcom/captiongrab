import SwiftUI

@main
struct CaptionGrabApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            MainView(model: model)
        }
    }
}
