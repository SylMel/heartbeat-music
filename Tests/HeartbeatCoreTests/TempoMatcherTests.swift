import Foundation
import XCTest
@testable import HeartbeatCore

final class TempoMatcherTests: XCTestCase {
    func testSelectsTrackWithClosestActualBPM() {
        let matcher = TempoMatcher(tracks: [
            Track(id: "a", title: "A", artist: "Test", bpm: 90),
            Track(id: "b", title: "B", artist: "Test", bpm: 102)
        ])

        let match = matcher.bestMatch(for: 91)

        XCTAssertEqual(match.track.id, "a")
        XCTAssertEqual(match.targetBPM, 91, accuracy: 0.001)
        XCTAssertEqual(match.distance, 1, accuracy: 0.001)
    }

    func testDoesNotTreatDoubleBPMAsEquivalent() {
        let matcher = TempoMatcher(tracks: [
            Track(id: "direct", title: "Direct", artist: "Test", bpm: 72),
            Track(id: "double", title: "Double", artist: "Test", bpm: 144)
        ])

        let match = matcher.bestMatch(for: 72)

        XCTAssertEqual(match.track.id, "direct")
        XCTAssertEqual(match.targetBPM, 72, accuracy: 0.001)
        XCTAssertEqual(match.distance, 0, accuracy: 0.001)
    }

    func testDoesNotTreatHalfBPMAsEquivalent() {
        let matcher = TempoMatcher(tracks: [
            Track(id: "half", title: "Half", artist: "Test", bpm: 75),
            Track(id: "direct", title: "Direct", artist: "Test", bpm: 156)
        ])

        XCTAssertEqual(matcher.bestMatch(for: 150).track.id, "direct")
    }

    func testFallsBackToClosestAvailableTrack() {
        let matcher = TempoMatcher(tracks: [
            Track(id: "lower", title: "Lower", artist: "Test", bpm: 103),
            Track(id: "higher", title: "Higher", artist: "Test", bpm: 139)
        ])

        XCTAssertEqual(matcher.bestMatch(for: 120).track.id, "lower")
    }

    func testMockCatalogCoversRestingWalkingAndExerciseRates() {
        let matcher = TempoMatcher(tracks: MockTrackCatalog.tracks)

        XCTAssertEqual(matcher.bestMatch(for: 62).track.bpm, 62)
        XCTAssertEqual(matcher.bestMatch(for: 85).track.bpm, 84)
        XCTAssertEqual(matcher.bestMatch(for: 120).track.bpm, 120)
        XCTAssertEqual(matcher.bestMatch(for: 155).track.bpm, 156)
        XCTAssertEqual(MockTrackCatalog.tracks.map(\.bpm).min(), 52)
        XCTAssertEqual(MockTrackCatalog.tracks.map(\.bpm).max(), 180)
    }

    func testParsesStandardEightBitBluetoothHeartRate() {
        let measurement = Data([0x00, 0x8A])

        XCTAssertEqual(HeartRateMeasurementParser.beatsPerMinute(from: measurement), 138)
    }

    func testParsesStandardSixteenBitBluetoothHeartRate() {
        let measurement = Data([0x01, 0x2C, 0x01])

        XCTAssertEqual(HeartRateMeasurementParser.beatsPerMinute(from: measurement), 300)
    }

    func testRejectsIncompleteBluetoothHeartRateMeasurement() {
        XCTAssertNil(HeartRateMeasurementParser.beatsPerMinute(from: Data([0x01, 0x2C])))
    }
}
