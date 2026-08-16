import Foundation

public struct TrackMatch: Equatable, Sendable {
    public let track: Track
    public let targetBPM: Double
    /// Absolute difference between the track's actual BPM and the mode's target BPM.
    public let distance: Double

    public init(
        track: Track,
        targetBPM: Double,
        distance: Double
    ) {
        self.track = track
        self.targetBPM = targetBPM
        self.distance = distance
    }
}

public struct TempoMatcher: Sendable {
    public let tracks: [Track]

    public init(tracks: [Track]) {
        precondition(!tracks.isEmpty, "TempoMatcher requires at least one track")
        self.tracks = tracks
    }

    public func bestMatch(for targetBPM: Double) -> TrackMatch {
        tracks
            .map { match(track: $0, targetBPM: targetBPM) }
            .min(by: isPreferred(_:over:))!
    }

    public func bestMatch(for track: Track, heartRate targetBPM: Double) -> TrackMatch {
        match(track: track, targetBPM: targetBPM)
    }

    private func match(track: Track, targetBPM: Double) -> TrackMatch {
        return TrackMatch(
            track: track,
            targetBPM: targetBPM,
            distance: abs(track.bpm - targetBPM)
        )
    }

    private func isPreferred(_ lhs: TrackMatch, over rhs: TrackMatch) -> Bool {
        if abs(lhs.distance - rhs.distance) > 0.000_1 {
            return lhs.distance < rhs.distance
        }

        if lhs.track.bpm != rhs.track.bpm {
            return lhs.track.bpm < rhs.track.bpm
        }

        return lhs.track.id < rhs.track.id
    }
}
