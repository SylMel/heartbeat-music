import Foundation
import XCTest
@testable import HeartbeatCore

final class TrackSelectionEngineTests: XCTestCase {
    private let tracks = [
        Track(id: "low", title: "Low", artist: "Test", bpm: 140),
        Track(id: "high", title: "High", artist: "Test", bpm: 152)
    ]

    func testHysteresisKeepsCurrentTrackForSmallImprovement() {
        var engine = TrackSelectionEngine(
            tracks: tracks,
            configuration: .init(smoothingFactor: 1, switchAdvantageBPM: 3)
        )

        XCTAssertEqual(engine.update(heartRate: 140).match.track.id, "low")
        let nearBoundary = engine.update(heartRate: 147)

        XCTAssertEqual(nearBoundary.match.track.id, "low")
        XCTAssertFalse(nearBoundary.didChangeTrack)
    }

    func testHysteresisSwitchesWhenCandidateIsClearlyBetter() {
        var engine = TrackSelectionEngine(
            tracks: tracks,
            configuration: .init(smoothingFactor: 1, switchAdvantageBPM: 3)
        )

        _ = engine.update(heartRate: 140)
        let moved = engine.update(heartRate: 152)

        XCTAssertEqual(moved.match.track.id, "high")
        XCTAssertTrue(moved.didChangeTrack)
    }

    func testSmoothingDampensSuddenHeartRateChange() {
        var engine = TrackSelectionEngine(
            tracks: tracks,
            configuration: .init(smoothingFactor: 0.25, switchAdvantageBPM: 0)
        )

        _ = engine.update(heartRate: 140)
        let snapshot = engine.update(heartRate: 160)

        XCTAssertEqual(snapshot.smoothedHeartRate, 145, accuracy: 0.001)
    }

    func testWorkoutModeMovesToFasterTrackWithoutSlowdownDelay() {
        var engine = TrackSelectionEngine(
            tracks: tracks,
            configuration: .init(smoothingFactor: 1, switchAdvantageBPM: 3)
        )

        _ = engine.update(heartRate: 140, mode: .workout, at: date(0))
        let faster = engine.update(heartRate: 152, mode: .workout, at: date(1))

        XCTAssertEqual(faster.match.track.id, "high")
        XCTAssertTrue(faster.didChangeTrack)
        XCTAssertNil(faster.workoutSlowdownRemaining)
    }

    func testWorkoutModeRequires210SecondsBeforeMovingToLowerTrack() {
        var engine = TrackSelectionEngine(
            tracks: tracks,
            configuration: .init(
                smoothingFactor: 1,
                switchAdvantageBPM: 3,
                workoutSlowdownDelay: 210
            )
        )

        _ = engine.update(heartRate: 152, mode: .workout, at: date(0))
        let countdownStarted = engine.update(heartRate: 140, mode: .workout, at: date(1))
        let stillHolding = engine.update(heartRate: 140, mode: .workout, at: date(210))
        let slowedDown = engine.update(heartRate: 140, mode: .workout, at: date(211))

        XCTAssertEqual(countdownStarted.match.track.id, "high")
        XCTAssertEqual(countdownStarted.workoutSlowdownRemaining, 210)
        XCTAssertEqual(stillHolding.match.track.id, "high")
        XCTAssertEqual(stillHolding.workoutSlowdownRemaining, 1)
        XCTAssertEqual(slowedDown.match.track.id, "low")
        XCTAssertTrue(slowedDown.didChangeTrack)
        XCTAssertNil(slowedDown.workoutSlowdownRemaining)
    }

    func testWorkoutSlowdownCountdownResetsWhenHeartRateRecovers() {
        var engine = TrackSelectionEngine(
            tracks: tracks,
            configuration: .init(
                smoothingFactor: 1,
                switchAdvantageBPM: 3,
                workoutSlowdownDelay: 210
            )
        )

        _ = engine.update(heartRate: 152, mode: .workout, at: date(0))
        _ = engine.update(heartRate: 140, mode: .workout, at: date(1))
        let recovered = engine.update(heartRate: 152, mode: .workout, at: date(200))
        let restarted = engine.update(heartRate: 140, mode: .workout, at: date(201))
        let tooSoon = engine.update(heartRate: 140, mode: .workout, at: date(410))
        let completed = engine.update(heartRate: 140, mode: .workout, at: date(411))

        XCTAssertNil(recovered.workoutSlowdownRemaining)
        XCTAssertEqual(restarted.workoutSlowdownRemaining, 210)
        XCTAssertEqual(tooSoon.match.track.id, "high")
        XCTAssertEqual(completed.match.track.id, "low")
    }

    func testRelaxModeTargets15BPMBelowSmoothedHeartRate() {
        let relaxationTracks = [
            Track(id: "120", title: "120", artist: "Test", bpm: 120),
            Track(id: "132", title: "132", artist: "Test", bpm: 132),
            Track(id: "144", title: "144", artist: "Test", bpm: 144)
        ]
        var engine = TrackSelectionEngine(
            tracks: relaxationTracks,
            configuration: .init(smoothingFactor: 1, switchAdvantageBPM: 0)
        )

        let relaxed = engine.update(heartRate: 147, mode: .relax, at: date(0))

        XCTAssertEqual(relaxed.smoothedHeartRate, 147)
        XCTAssertEqual(relaxed.match.targetBPM, 132)
        XCTAssertEqual(relaxed.match.track.id, "132")
        XCTAssertNil(relaxed.workoutSlowdownRemaining)
    }

    func testSwitchingToRelaxModeDoesNotApplyWorkoutSlowdownDelay() {
        var engine = TrackSelectionEngine(
            tracks: tracks,
            configuration: .init(
                smoothingFactor: 1,
                switchAdvantageBPM: 0,
                relaxationOffsetBPM: 12
            )
        )

        _ = engine.update(heartRate: 152, mode: .workout, at: date(0))
        let relaxed = engine.update(heartRate: 152, mode: .relax, at: date(1))

        XCTAssertEqual(relaxed.match.targetBPM, 140)
        XCTAssertEqual(relaxed.match.track.id, "low")
        XCTAssertTrue(relaxed.didChangeTrack)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
