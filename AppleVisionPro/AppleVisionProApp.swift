import SwiftUI
import RealityKit
import RealityKitContent

@main
struct AppleVisionProApp: App {
    @StateObject private var appState = AppState()

    var body: some SwiftUI.Scene {
        WindowGroup(id: "main") {
            Group {
                switch appState.currentPage {
                case .content:
                    ContentView()
                        .frame(width: 1280, height: 720)
                case .test:
                    TestView()
                        .frame(width: 1280, height: 720)
                case .click:
                    ClickingView()
                        .frame(width: 1280, height: 720)
                case .eyeTracking:
                    EyeTrackingView()
                        .frame(width: 1280, height: 720)
                case .bullseyeTest:
                    PrecisionView()
                        .frame(width: 1280, height: 720)
                case .videoUpload:
                    VideoUploadView()
                        .frame(width: 1280, height: 720)
                }
            }
            .environmentObject(appState)
            .animation(.easeInOut, value: appState.currentPage)
        }
        .windowResizability(.contentSize)

        ImmersiveSpace(id: "immersiveTracking") {
            ImmersiveTrackingView()
                .environmentObject(appState)
        }
        .windowStyle(.plain)
        
    }
}
