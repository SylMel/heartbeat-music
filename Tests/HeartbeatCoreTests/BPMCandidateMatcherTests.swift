import XCTest
@testable import HeartbeatCore

final class BPMCandidateMatcherTests: XCTestCase {
    func testRequiresMatchingTitleAndArtist() {
        let candidates = [
            BPMCandidate(title: "Halo", artists: ["Foo Fighters"], bpm: 90),
            BPMCandidate(title: "Halo", artists: ["Beyonce"], bpm: 80)
        ]

        let result = BPMCandidateMatcher.bestMatch(
            title: "Halo",
            artist: "Beyoncé",
            candidates: candidates
        )

        XCTAssertEqual(result?.bpm, 80)
    }

    func testIgnoresCommonVersionLabels() {
        let candidates = [
            BPMCandidate(
                title: "Dreams - 2004 Remaster",
                artists: ["Fleetwood Mac"],
                bpm: 120
            )
        ]

        XCTAssertEqual(
            BPMCandidateMatcher.bestMatch(
                title: "Dreams",
                artist: "Fleetwood Mac",
                candidates: candidates
            )?.bpm,
            120
        )
    }

    func testRejectsDifferentSongWithSimilarName() {
        let candidates = [
            BPMCandidate(title: "Runaway Baby", artists: ["Bruno Mars"], bpm: 163)
        ]

        XCTAssertNil(
            BPMCandidateMatcher.bestMatch(
                title: "Runaway",
                artist: "Bruno Mars",
                candidates: candidates
            )
        )
    }
}
