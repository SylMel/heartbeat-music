import Foundation
import HeartbeatCore
import Security

struct SpotifyPlaylist: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let itemCount: Int
    let spotifyURL: URL?
}

struct SpotifyCatalogSnapshot: Codable, Equatable, Sendable {
    let playlistName: String
    let tracks: [Track]
    let importedAt: Date
    let unmatchedCount: Int
}

struct SpotifyCatalogImportResult: Sendable {
    let snapshot: SpotifyCatalogSnapshot
    let spotifyItemCount: Int
}

enum SpotifyCatalogError: LocalizedError {
    case noAccessToken
    case missingBPMAPIKey
    case invalidResponse
    case spotifyStatus(Int, String?)
    case bpmStatus(Int)
    case noTracks
    case noBPMMatches

    var errorDescription: String? {
        switch self {
        case .noAccessToken:
            "Connect Spotify before loading playlists."
        case .missingBPMAPIKey:
            "Add your GetSongBPM API key before importing a playlist."
        case .invalidResponse:
            "A music service returned an unexpected response."
        case let .spotifyStatus(code, message):
            switch code {
            case 401:
                "Your Spotify permission expired. Disconnect and connect again."
            case 403:
                "Spotify can only import playlists you own or collaborate on in this prototype."
            case 429:
                "Spotify is receiving too many requests. Please try again shortly."
            default:
                message ?? "Spotify returned an error (\(code))."
            }
        case let .bpmStatus(code):
            code == 401 || code == 403
                ? "The GetSongBPM API key was not accepted."
                : "GetSongBPM returned an error (\(code))."
        case .noTracks:
            "That playlist does not contain playable Spotify tracks."
        case .noBPMMatches:
            "No reliable BPM matches were found. Try another playlist or check the BPM API key."
        }
    }
}

struct SpotifyCatalogService {
    private let spotifyAPI = SpotifyWebAPIClient()
    private let bpmAPI = GetSongBPMClient()
    private let store = SpotifyCatalogStore()

    func playlists(accessToken: String) async throws -> [SpotifyPlaylist] {
        try await spotifyAPI.playlists(accessToken: accessToken)
    }

    func importPlaylist(
        _ playlist: SpotifyPlaylist,
        accessToken: String,
        bpmAPIKey: String,
        progress: @escaping @Sendable (_ completed: Int, _ total: Int) -> Void
    ) async throws -> SpotifyCatalogImportResult {
        let key = bpmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw SpotifyCatalogError.missingBPMAPIKey }

        let spotifyTracks = try await spotifyAPI.tracks(
            playlistID: playlist.id,
            accessToken: accessToken,
            maximum: 50
        )
        guard !spotifyTracks.isEmpty else { throw SpotifyCatalogError.noTracks }

        var bpmCache = store.loadBPMCache()
        var tracks: [Track] = []

        for (index, spotifyTrack) in spotifyTracks.enumerated() {
            let bpm: Double?
            if let cached = bpmCache[spotifyTrack.uri] {
                bpm = cached
            } else {
                bpm = try await bpmAPI.bpm(
                    title: spotifyTrack.title,
                    artist: spotifyTrack.artist,
                    apiKey: key
                )
                if let bpm {
                    bpmCache[spotifyTrack.uri] = bpm
                }
            }

            if let bpm {
                tracks.append(
                    Track(
                        id: spotifyTrack.uri,
                        title: spotifyTrack.title,
                        artist: spotifyTrack.artist,
                        bpm: bpm
                    )
                )
            }
            progress(index + 1, spotifyTracks.count)
        }

        guard !tracks.isEmpty else { throw SpotifyCatalogError.noBPMMatches }

        let snapshot = SpotifyCatalogSnapshot(
            playlistName: playlist.name,
            tracks: tracks,
            importedAt: Date(),
            unmatchedCount: spotifyTracks.count - tracks.count
        )
        try store.save(snapshot: snapshot)
        try? store.saveBPMCache(bpmCache)
        return SpotifyCatalogImportResult(snapshot: snapshot, spotifyItemCount: spotifyTracks.count)
    }

    func cachedCatalog() -> SpotifyCatalogSnapshot? {
        store.loadSnapshot()
    }
}

struct SecureValueStore {
    private let service = "com.heartbeatmusic.app"

    func string(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw SecureStoreError.status(addStatus) }
        } else if status != errSecSuccess {
            throw SecureStoreError.status(status)
        }
    }

    private enum SecureStoreError: Error {
        case status(OSStatus)
    }
}

private struct SpotifyWebAPIClient {
    func playlists(accessToken: String) async throws -> [SpotifyPlaylist] {
        var nextURL: URL? = URL(string: "https://api.spotify.com/v1/me/playlists?limit=50")
        var playlists: [SpotifyPlaylist] = []

        while let url = nextURL {
            let page: SpotifyPlaylistPage = try await request(url: url, accessToken: accessToken)
            playlists.append(contentsOf: page.items.map { dto in
                SpotifyPlaylist(
                    id: dto.id,
                    name: dto.name,
                    itemCount: dto.items?.total ?? dto.tracks?.total ?? 0,
                    spotifyURL: dto.externalURLs?.spotify.flatMap(URL.init(string:))
                )
            })
            nextURL = page.next.flatMap(URL.init(string:))
        }
        return playlists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func tracks(
        playlistID: String,
        accessToken: String,
        maximum: Int
    ) async throws -> [SpotifyCatalogTrack] {
        let encodedID = playlistID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? playlistID
        var nextURL: URL? = URL(
            string: "https://api.spotify.com/v1/playlists/\(encodedID)/items?limit=50"
        )
        var tracks: [SpotifyCatalogTrack] = []

        while let url = nextURL, tracks.count < maximum {
            let page: SpotifyPlaylistItemsPage = try await request(url: url, accessToken: accessToken)
            for entry in page.items {
                guard let item = entry.item ?? entry.track,
                      item.type == nil || item.type == "track",
                      item.uri.hasPrefix("spotify:track:"),
                      let artist = item.artists.first?.name else { continue }
                tracks.append(
                    SpotifyCatalogTrack(uri: item.uri, title: item.name, artist: artist)
                )
                if tracks.count == maximum { break }
            }
            nextURL = page.next.flatMap(URL.init(string:))
        }
        return tracks
    }

    private func request<Response: Decodable>(
        url: URL,
        accessToken: String
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyCatalogError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(SpotifyErrorEnvelope.self, from: data))?.error.message
            throw SpotifyCatalogError.spotifyStatus(http.statusCode, message)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw SpotifyCatalogError.invalidResponse
        }
    }
}

private struct GetSongBPMClient {
    func bpm(title: String, artist: String, apiKey: String) async throws -> Double? {
        var components = URLComponents(string: "https://api.getsong.co/search/")!
        components.queryItems = [
            URLQueryItem(name: "type", value: "both"),
            URLQueryItem(name: "lookup", value: "song:\(title) artist:\(artist)"),
            URLQueryItem(name: "limit", value: "10")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyCatalogError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw SpotifyCatalogError.bpmStatus(http.statusCode)
        }

        let envelope: GetSongSearchEnvelope
        do {
            envelope = try JSONDecoder().decode(GetSongSearchEnvelope.self, from: data)
        } catch {
            throw SpotifyCatalogError.invalidResponse
        }

        let candidates = envelope.search.compactMap { song -> BPMCandidate? in
            guard let bpm = song.tempo.value else { return nil }
            return BPMCandidate(
                title: song.title,
                artists: song.artist.values.map(\.name),
                bpm: bpm
            )
        }
        return BPMCandidateMatcher.bestMatch(
            title: title,
            artist: artist,
            candidates: candidates
        )?.bpm
    }
}

private struct SpotifyCatalogStore {
    private var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("HeartbeatMusic", isDirectory: true)
    }

    func loadSnapshot() -> SpotifyCatalogSnapshot? {
        guard let url = directory?.appendingPathComponent("spotify-catalog.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SpotifyCatalogSnapshot.self, from: data)
    }

    func save(snapshot: SpotifyCatalogSnapshot) throws {
        try write(snapshot, named: "spotify-catalog.json")
    }

    func loadBPMCache() -> [String: Double] {
        guard let url = directory?.appendingPathComponent("bpm-cache.json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: Double].self, from: data)) ?? [:]
    }

    func saveBPMCache(_ cache: [String: Double]) throws {
        try write(cache, named: "bpm-cache.json")
    }

    private func write<Value: Encodable>(_ value: Value, named fileName: String) throws {
        guard let directory else { throw SpotifyCatalogError.invalidResponse }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(value)
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }
}

private struct SpotifyCatalogTrack: Sendable {
    let uri: String
    let title: String
    let artist: String
}

private struct SpotifyPlaylistPage: Decodable {
    let items: [SpotifyPlaylistDTO]
    let next: String?
}

private struct SpotifyPlaylistDTO: Decodable {
    let id: String
    let name: String
    let items: SpotifyItemCountDTO?
    let tracks: SpotifyItemCountDTO?
    let externalURLs: SpotifyExternalURLsDTO?

    private enum CodingKeys: String, CodingKey {
        case id, name, items, tracks
        case externalURLs = "external_urls"
    }
}

private struct SpotifyItemCountDTO: Decodable {
    let total: Int
}

private struct SpotifyExternalURLsDTO: Decodable {
    let spotify: String?
}

private struct SpotifyPlaylistItemsPage: Decodable {
    let items: [SpotifyPlaylistEntryDTO]
    let next: String?
}

private struct SpotifyPlaylistEntryDTO: Decodable {
    let item: SpotifyTrackDTO?
    let track: SpotifyTrackDTO?
}

private struct SpotifyTrackDTO: Decodable {
    let uri: String
    let name: String
    let artists: [SpotifyArtistDTO]
    let type: String?
}

private struct SpotifyArtistDTO: Decodable {
    let name: String
}

private struct SpotifyErrorEnvelope: Decodable {
    struct SpotifyError: Decodable {
        let message: String
    }
    let error: SpotifyError
}

private struct GetSongSearchEnvelope: Decodable {
    let search: [GetSongSearchDTO]
}

private struct GetSongSearchDTO: Decodable {
    let title: String
    let tempo: FlexibleDouble
    let artist: FlexibleArtists
}

private struct FlexibleDouble: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let string = try? container.decode(String.self) {
            value = Double(string)
        } else {
            value = nil
        }
    }
}

private struct GetSongArtistDTO: Decodable {
    let name: String
}

private struct FlexibleArtists: Decodable {
    let values: [GetSongArtistDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let array = try? container.decode([GetSongArtistDTO].self) {
            values = array
        } else if let artist = try? container.decode(GetSongArtistDTO.self) {
            values = [artist]
        } else {
            values = []
        }
    }
}
