import HeartbeatCore

/// Boundary for the in-memory destination today and Spotify/Apple Music later.
@MainActor
protocol TrackDestination: AnyObject {
    var selectedTrack: Track? { get }
    func select(_ track: Track)
}

@MainActor
final class MockTrackDestination: TrackDestination {
    private(set) var selectedTrack: Track?

    func select(_ track: Track) {
        selectedTrack = track
    }
}

/// Playback output for real Spotify tracks. A Spotify playlist importer can
/// create core `Track` values whose opaque ID is the Spotify track URI.
@MainActor
final class SpotifyTrackDestination: TrackDestination {
    private let controller: SpotifyPlaybackController
    private(set) var selectedTrack: Track?

    init(controller: SpotifyPlaybackController) {
        self.controller = controller
    }

    func select(_ track: Track) {
        selectedTrack = track
        guard track.id.hasPrefix("spotify:track:") else { return }
        controller.play(trackURI: track.id)
    }
}
