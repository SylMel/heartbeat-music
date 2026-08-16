import Combine
import Foundation
import HeartbeatCore

@MainActor
final class NowPlayingViewModel: ObservableObject {
    @Published private(set) var heartRate: Double
    @Published private(set) var smoothedHeartRate: Double
    @Published private(set) var targetBPM: Double
    @Published private(set) var selectedTrack: Track?
    @Published private(set) var workoutSlowdownRemaining: TimeInterval?
    @Published private(set) var sourceStatus: HeartRateSourceStatus = .idle
    @Published private(set) var hasHeartRateReading = true
    @Published private(set) var spotifyConnectionState: SpotifyConnectionState = .disconnected
    @Published private(set) var spotifyNowPlaying: String?
    @Published private(set) var spotifyPlaylists: [SpotifyPlaylist] = []
    @Published private(set) var isCatalogBusy = false
    @Published private(set) var catalogProgress: String?
    @Published private(set) var catalogMessage: String
    @Published private(set) var activeCatalogName: String
    @Published private(set) var activeCatalogTrackCount: Int
    @Published private(set) var hasBPMAPIKey: Bool
    @Published private(set) var importedCatalogs: [String: SpotifyCatalogSnapshot]
    @Published var selectedSpotifyPlaylistID: String = ""
    @Published var bpmAPIKeyInput: String = ""
    @Published var heartRateInput: HeartRateInputKind = .simulator {
        didSet {
            guard heartRateInput != oldValue else { return }
            switchHeartRateSource()
        }
    }
    @Published var mode: HeartbeatMode = .workout {
        didSet {
            selectionEngine.cancelPendingWorkoutSlowdown()
            workoutSlowdownRemaining = nil
            if isSyncEnabled {
                process(heartRate: heartRate)
            }
        }
    }
    @Published var isSyncEnabled = true {
        didSet {
            if isSyncEnabled {
                process(heartRate: heartRate)
            } else {
                selectionEngine.cancelPendingWorkoutSlowdown()
                workoutSlowdownRemaining = nil
            }
        }
    }

    private var heartRateSource: HeartRateSource
    private let trackDestination: TrackDestination
    private let spotifyController: SpotifyPlaybackController
    private let catalogService = SpotifyCatalogService()
    private let secureStore = SecureValueStore()
    private let bpmAPIKeyStorageKey = "getsongbpm-api-key"
    private var tracks: [Track]
    private var selectionEngine: TrackSelectionEngine

    convenience init() {
        let spotifyController = SpotifyPlaybackController()
        self.init(
            trackDestination: SpotifyTrackDestination(controller: spotifyController),
            spotifyController: spotifyController,
            tracks: MockTrackCatalog.tracks
        )
    }

    init(
        trackDestination: TrackDestination,
        spotifyController: SpotifyPlaybackController,
        tracks: [Track]
    ) {
        let heartRateSource = SimulatedHeartRateSource()
        let catalogService = SpotifyCatalogService()
        let cachedCatalog = catalogService.cachedCatalog()
        var cachedCatalogs = catalogService.cachedCatalogs()
        if let cachedCatalog, let playlistID = cachedCatalog.playlistID {
            cachedCatalogs[playlistID] = cachedCatalog
        }
        let startingTracks = cachedCatalog?.tracks.isEmpty == false
            ? cachedCatalog!.tracks
            : tracks
        self.heartRateSource = heartRateSource
        self.trackDestination = trackDestination
        self.spotifyController = spotifyController
        self.tracks = startingTracks
        activeCatalogName = cachedCatalog?.playlistName ?? "Demo catalog"
        activeCatalogTrackCount = startingTracks.count
        importedCatalogs = cachedCatalogs
        catalogMessage = cachedCatalog.map {
            "Using \($0.tracks.count) BPM-matched tracks from \($0.playlistName)"
        } ?? "Using the built-in demo catalog"
        hasBPMAPIKey = Self.prepareBPMAPIKey()
        heartRate = heartRateSource.currentBPM
        smoothedHeartRate = heartRateSource.currentBPM
        targetBPM = heartRateSource.currentBPM
        workoutSlowdownRemaining = nil
        selectionEngine = TrackSelectionEngine(tracks: startingTracks)

        spotifyController.onConnectionStateChange = { [weak self] state in
            self?.spotifyConnectionState = state
        }
        spotifyController.onPlayerStateChange = { [weak self] summary in
            self?.spotifyNowPlaying = summary
        }
        spotifyController.onAccessTokenChange = { [weak self] token in
            guard let self else { return }
            if token == nil {
                spotifyPlaylists = []
                selectedSpotifyPlaylistID = ""
            }
        }

        configureCallbacks(for: heartRateSource)
        heartRateSource.start()
    }

    private static func prepareBPMAPIKey() -> Bool {
        let storageKey = "getsongbpm-api-key"
        let store = SecureValueStore()
        if store.string(for: storageKey) != nil {
            return true
        }

        guard let configuredKey = Bundle.main.object(
            forInfoDictionaryKey: "GetSongBPMAPIKey"
        ) as? String else {
            return false
        }
        let value = configuredKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("$(") else {
            return false
        }

        do {
            try store.set(value, for: storageKey)
            return true
        } catch {
            return false
        }
    }

    func connectSpotify() {
        spotifyController.authorize()
    }

    func disconnectSpotify() {
        spotifyController.disconnect()
    }

    func saveBPMAPIKey() {
        let value = bpmAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            catalogMessage = "Paste a GetSongBPM API key first."
            return
        }
        do {
            try secureStore.set(value, for: bpmAPIKeyStorageKey)
            bpmAPIKeyInput = ""
            hasBPMAPIKey = true
            catalogMessage = "BPM lookup is ready. You can now import a playlist."
        } catch {
            catalogMessage = "The BPM API key could not be saved securely."
        }
    }

    func loadSpotifyPlaylists() {
        guard let accessToken = spotifyController.webAPIAccessToken else {
            catalogMessage = SpotifyCatalogError.noAccessToken.localizedDescription
            return
        }

        isCatalogBusy = true
        catalogProgress = "Loading your playlists…"
        Task {
            do {
                let playlists = try await catalogService.playlists(accessToken: accessToken)
                spotifyPlaylists = playlists
                selectedSpotifyPlaylistID = playlists.first?.id ?? ""
                catalogMessage = playlists.isEmpty
                    ? "No owned or collaborative playlists were found."
                    : "Choose a playlist to build your BPM catalog."
            } catch {
                catalogMessage = error.localizedDescription
            }
            catalogProgress = nil
            isCatalogBusy = false
        }
    }

    func importSelectedSpotifyPlaylist() {
        guard let playlist = spotifyPlaylists.first(where: {
            $0.id == selectedSpotifyPlaylistID
        }) else {
            catalogMessage = "Choose a Spotify playlist first."
            return
        }
        guard let accessToken = spotifyController.webAPIAccessToken else {
            catalogMessage = SpotifyCatalogError.noAccessToken.localizedDescription
            return
        }
        guard let apiKey = secureStore.string(for: bpmAPIKeyStorageKey) else {
            catalogMessage = SpotifyCatalogError.missingBPMAPIKey.localizedDescription
            return
        }

        isCatalogBusy = true
        catalogProgress = "Reading \(playlist.name)…"
        catalogMessage = "Importing \(playlist.name)…"
        Task {
            do {
                let result = try await catalogService.importPlaylist(
                    playlist,
                    accessToken: accessToken,
                    bpmAPIKey: apiKey
                ) { [weak self] completed, total in
                    Task { @MainActor in
                        self?.catalogProgress = "Finding BPM \(completed) of \(total)…"
                    }
                }
                activateCatalog(result.snapshot.tracks, name: result.snapshot.playlistName)
                importedCatalogs[playlist.id] = result.snapshot
                let unmatched = result.snapshot.unmatchedCount
                if unmatched == 0 {
                    catalogMessage = "All \(result.spotifyItemCount) tracks are ready for heart-rate matching."
                } else if result.lookupFailureCount > 0 {
                    catalogMessage = "Ready: \(result.snapshot.tracks.count) tracks. \(unmatched) were skipped, including \(result.lookupFailureCount) temporary lookup errors."
                } else {
                    catalogMessage = "Ready: \(result.snapshot.tracks.count) tracks. \(unmatched) had no reliable BPM match."
                }
            } catch {
                catalogMessage = "Could not import \(playlist.name): \(error.localizedDescription)"
            }
            catalogProgress = nil
            isCatalogBusy = false
        }
    }

    func useDemoCatalog() {
        activateCatalog(MockTrackCatalog.tracks, name: "Demo catalog")
        catalogMessage = "Using the built-in demo catalog"
    }

    func useSavedCatalogForSelectedPlaylist() {
        guard let snapshot = importedCatalogs[selectedSpotifyPlaylistID] else { return }
        activateCatalog(snapshot.tracks, name: snapshot.playlistName)
        catalogMessage = "Using \(snapshot.tracks.count) saved BPM-matched tracks from \(snapshot.playlistName)."
    }

    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        spotifyController.handleOpenURL(url)
    }

    func spotifyAppDidBecomeActive() {
        spotifyController.reconnectIfAuthorized()
    }

    func spotifyAppWillResignActive() {
        spotifyController.suspendConnection()
    }

    func retryHeartRateSource() {
        heartRateSource.stop()
        heartRateSource.start()
    }

    private func configureCallbacks(for source: HeartRateSource) {
        source.onHeartRateChange = { [weak self] bpm in
            self?.receive(heartRate: bpm)
        }
        source.onStatusChange = { [weak self] status in
            self?.sourceStatus = status
        }
    }

    private func switchHeartRateSource() {
        heartRateSource.stop()
        heartRateSource.onHeartRateChange = nil
        heartRateSource.onStatusChange = nil

        switch heartRateInput {
        case .simulator:
            heartRateSource = SimulatedHeartRateSource(initialBPM: heartRate)
            hasHeartRateReading = true
        case .myzone:
            heartRateSource = BluetoothHeartRateSource()
            hasHeartRateReading = false
        case .appleWatch:
            heartRateSource = AppleWatchHeartRateSource()
            hasHeartRateReading = false
        }

        sourceStatus = .idle
        workoutSlowdownRemaining = nil
        selectedTrack = nil
        selectionEngine = TrackSelectionEngine(tracks: tracks)
        configureCallbacks(for: heartRateSource)
        heartRateSource.start()
    }

    private func activateCatalog(_ newTracks: [Track], name: String) {
        guard !newTracks.isEmpty else { return }
        tracks = newTracks
        activeCatalogName = name
        activeCatalogTrackCount = newTracks.count
        selectedTrack = nil
        workoutSlowdownRemaining = nil
        selectionEngine = TrackSelectionEngine(tracks: newTracks)
        if isSyncEnabled {
            process(heartRate: heartRate)
        }
    }

    func setSimulatedHeartRate(_ bpm: Double) {
        (heartRateSource as? SimulatedHeartRateSource)?.setHeartRate(bpm)
    }

    private func receive(heartRate bpm: Double) {
        heartRate = bpm
        hasHeartRateReading = true
        guard isSyncEnabled else { return }
        process(heartRate: bpm)
    }

    private func process(heartRate bpm: Double) {
        guard hasHeartRateReading else { return }
        let snapshot = selectionEngine.update(heartRate: bpm, mode: mode)
        smoothedHeartRate = snapshot.smoothedHeartRate
        targetBPM = snapshot.match.targetBPM
        selectedTrack = snapshot.match.track
        workoutSlowdownRemaining = snapshot.workoutSlowdownRemaining
        trackDestination.select(snapshot.match.track)
    }
}
