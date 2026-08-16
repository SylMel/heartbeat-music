import Foundation

public struct Track: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let bpm: Double

    public init(id: String, title: String, artist: String, bpm: Double) {
        self.id = id
        self.title = title
        self.artist = artist
        self.bpm = bpm
    }
}
