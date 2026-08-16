import HeartbeatCore

@main
enum LogicChecks {
    static func main() {
        let directMatcher = TempoMatcher(tracks: [
            Track(id: "a", title: "A", artist: "Test", bpm: 90),
            Track(id: "b", title: "B", artist: "Test", bpm: 102)
        ])
        require(directMatcher.bestMatch(for: 91).track.id == "a", "closest direct matching")

        let noMultiplierMatcher = TempoMatcher(tracks: [
            Track(id: "direct", title: "Direct", artist: "Test", bpm: 72),
            Track(id: "double", title: "Double", artist: "Test", bpm: 144)
        ])
        let directMatch = noMultiplierMatcher.bestMatch(for: 72)
        require(directMatch.track.id == "direct", "no double-time equivalence")
        require(directMatch.targetBPM == 72, "direct target BPM")

        let noHalfTimeMatcher = TempoMatcher(tracks: [
            Track(id: "half", title: "Half", artist: "Test", bpm: 75),
            Track(id: "direct", title: "Direct", artist: "Test", bpm: 156)
        ])
        require(noHalfTimeMatcher.bestMatch(for: 150).track.id == "direct", "no half-time equivalence")

        let catalogMatcher = TempoMatcher(tracks: MockTrackCatalog.tracks)
        require(catalogMatcher.bestMatch(for: 62).track.bpm == 62, "resting-rate catalog coverage")
        require(catalogMatcher.bestMatch(for: 85).track.bpm == 84, "walking-rate catalog coverage")
        require(catalogMatcher.bestMatch(for: 120).track.bpm == 120, "moderate-rate catalog coverage")
        require(catalogMatcher.bestMatch(for: 155).track.bpm == 156, "exercise-rate catalog coverage")

        let tracks = [
            Track(id: "low", title: "Low", artist: "Test", bpm: 140),
            Track(id: "high", title: "High", artist: "Test", bpm: 152)
        ]
        var engine = TrackSelectionEngine(
            tracks: tracks,
            configuration: .init(smoothingFactor: 1, switchAdvantageBPM: 3)
        )
        require(engine.update(heartRate: 140).match.track.id == "low", "initial selection")
        require(engine.update(heartRate: 147).match.track.id == "low", "hysteresis hold")
        require(engine.update(heartRate: 152).match.track.id == "high", "hysteresis switch")

        var smoothingEngine = TrackSelectionEngine(
            tracks: tracks,
            configuration: .init(smoothingFactor: 0.25, switchAdvantageBPM: 0)
        )
        _ = smoothingEngine.update(heartRate: 140)
        let smoothed = smoothingEngine.update(heartRate: 160).smoothedHeartRate
        require(abs(smoothed - 145) < 0.001, "heart-rate smoothing")

        var workoutEngine = TrackSelectionEngine(
            tracks: tracks,
            configuration: .init(
                smoothingFactor: 1,
                switchAdvantageBPM: 3,
                workoutSlowdownDelay: 210
            )
        )
        _ = workoutEngine.update(heartRate: 152, mode: .workout, at: Date(timeIntervalSince1970: 0))
        let holding = workoutEngine.update(heartRate: 140, mode: .workout, at: Date(timeIntervalSince1970: 1))
        require(holding.match.track.id == "high", "workout slowdown hold")
        let slowed = workoutEngine.update(heartRate: 140, mode: .workout, at: Date(timeIntervalSince1970: 211))
        require(slowed.match.track.id == "low", "workout slowdown after 210 seconds")

        var relaxEngine = TrackSelectionEngine(
            tracks: tracks,
            configuration: .init(smoothingFactor: 1, switchAdvantageBPM: 0, relaxationOffsetBPM: 12)
        )
        let relaxed = relaxEngine.update(heartRate: 152, mode: .relax)
        require(relaxed.match.targetBPM == 140, "relax target below heart rate")
        require(relaxed.match.track.id == "low", "relax lower track selection")

        print("All HeartbeatCore logic checks passed.")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else {
            fatalError("Logic check failed: \(name)")
        }
    }
}
