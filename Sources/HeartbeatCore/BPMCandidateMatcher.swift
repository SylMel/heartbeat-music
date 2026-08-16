import Foundation

/// A service-neutral BPM search result. The matching rule lives in the core so
/// catalog integrations cannot silently attach a tempo from the wrong song.
public struct BPMCandidate: Equatable, Sendable {
    public let title: String
    public let artists: [String]
    public let bpm: Double

    public init(title: String, artists: [String], bpm: Double) {
        self.title = title
        self.artists = artists
        self.bpm = bpm
    }
}

public enum BPMCandidateMatcher {
    /// Returns a result only when both the normalized title and an artist agree.
    /// Common version labels such as "Remastered" and "Radio Edit" are ignored.
    public static func bestMatch(
        title: String,
        artist: String,
        candidates: [BPMCandidate]
    ) -> BPMCandidate? {
        let expectedTitle = normalizedTitle(title)
        let expectedArtist = normalized(artist)

        return candidates
            .filter { candidate in
                normalizedTitle(candidate.title) == expectedTitle
                    && candidate.artists.contains { normalized($0) == expectedArtist }
                    && candidate.bpm > 0
            }
            .sorted { lhs, rhs in
                if lhs.title.count != rhs.title.count {
                    return lhs.title.count < rhs.title.count
                }
                return lhs.bpm < rhs.bpm
            }
            .first
    }

    public static func normalizedTitle(_ value: String) -> String {
        var title = value
        let versionWords = "remaster(?:ed)?|radio edit|single edit|album version|mono|stereo"
        let patterns = [
            "\\s*[\\(\\[][^\\)\\]]*(?:" + versionWords + ")[^\\)\\]]*[\\)\\]]",
            "\\s*[-–—]\\s*.*(?:" + versionWords + ").*$"
        ]

        for pattern in patterns {
            title = title.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return normalized(title)
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }
}
