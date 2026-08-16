import SwiftUI

@main
struct HeartbeatMusicApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = NowPlayingViewModel()

    var body: some Scene {
        WindowGroup {
            NowPlayingView(viewModel: viewModel)
                .onOpenURL { url in
                    _ = viewModel.handleOpenURL(url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        viewModel.spotifyAppDidBecomeActive()
                    case .inactive, .background:
                        viewModel.spotifyAppWillResignActive()
                    @unknown default:
                        break
                    }
                }
        }
    }
}
