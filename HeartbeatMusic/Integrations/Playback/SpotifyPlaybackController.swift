import Foundation
@preconcurrency import SpotifyiOS
import UIKit

enum SpotifyConnectionState: Equatable {
    case disconnected
    case authorizing
    case connecting
    case connected
    case spotifyNotInstalled
    case failed(String)

    var message: String {
        switch self {
        case .disconnected:
            "Not connected"
        case .authorizing:
            "Waiting for Spotify authorization"
        case .connecting:
            "Connecting to Spotify"
        case .connected:
            "Connected"
        case .spotifyNotInstalled:
            "Install the Spotify app to connect"
        case let .failed(message):
            message
        }
    }

    var isConnected: Bool {
        self == .connected
    }
}

/// Owns Spotify App Remote authorization and playback control.
///
/// The matching engine knows nothing about Spotify. Imported Spotify tracks use
/// their `spotify:track:…` URI as the opaque `Track.id`, and this controller
/// receives that URI only after the core engine has selected a track.
@MainActor
final class SpotifyPlaybackController: NSObject {
    static let clientID = "9ab83e8c62ec4011ba97b9d4eb1aac62"
    static let redirectURL = URL(string: "heartbeat-music://spotify-callback")!

    var onConnectionStateChange: ((SpotifyConnectionState) -> Void)?
    var onPlayerStateChange: ((String?) -> Void)?
    var onAccessTokenChange: ((String?) -> Void)?

    var webAPIAccessToken: String? {
        guard let session = sessionManager.session, !session.isExpired else { return nil }
        return session.accessToken
    }

    private(set) var connectionState: SpotifyConnectionState = .disconnected {
        didSet {
            guard connectionState != oldValue else { return }
            onConnectionStateChange?(connectionState)
        }
    }

    private let configuration: SPTConfiguration
    private let appRemote: SPTAppRemote
    private let sessionManager: SPTSessionManager

    override init() {
        let configuration = SPTConfiguration(
            clientID: Self.clientID,
            redirectURL: Self.redirectURL
        )
        configuration.playURI = ""
        self.configuration = configuration
        appRemote = SPTAppRemote(configuration: configuration, logLevel: .info)
        sessionManager = SPTSessionManager(configuration: configuration, delegate: nil)
        super.init()
        appRemote.delegate = self
        sessionManager.delegate = self
    }

    func authorize() {
        guard !appRemote.isConnected else {
            connectionState = .connected
            return
        }

        connectionState = .authorizing
        let scope: SPTScope = [
            .appRemoteControl,
            .playlistReadPrivate,
            .playlistReadCollaborative
        ]
        sessionManager.initiateSession(with: scope, options: .clientOnly, campaign: nil)
    }

    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        guard url.scheme == Self.redirectURL.scheme else { return false }

        if sessionManager.application(UIApplication.shared, open: url, options: [:]) {
            return true
        }

        let parameters = appRemote.authorizationParameters(from: url)
        if let accessToken = parameters?[SPTAppRemoteAccessTokenKey] {
            appRemote.connectionParameters.accessToken = accessToken
            connectionState = .connecting
            appRemote.connect()
        } else if let errorDescription = parameters?[SPTAppRemoteErrorDescriptionKey] {
            connectionState = .failed(errorDescription)
        } else {
            connectionState = .failed("Spotify authorization did not return a token")
        }
        return true
    }

    func reconnectIfAuthorized() {
        guard appRemote.connectionParameters.accessToken != nil,
              !appRemote.isConnected else { return }
        connectionState = .connecting
        appRemote.connect()
    }

    func disconnect() {
        if appRemote.isConnected {
            appRemote.disconnect()
        }
        connectionState = .disconnected
        sessionManager.session = nil
        onAccessTokenChange?(nil)
        onPlayerStateChange?(nil)
    }

    func suspendConnection() {
        guard appRemote.isConnected else { return }
        appRemote.disconnect()
    }

    func play(trackURI: String) {
        guard connectionState.isConnected else { return }
        appRemote.playerAPI?.play(trackURI) { [weak self] _, error in
            guard let message = error?.localizedDescription else { return }
            Task { @MainActor [weak self] in
                self?.connectionState = .failed("Could not play the selected Spotify track: \(message)")
            }
        }
    }
}

extension SpotifyPlaybackController: @preconcurrency SPTSessionManagerDelegate {
    func sessionManager(manager: SPTSessionManager, didInitiate session: SPTSession) {
        appRemote.connectionParameters.accessToken = session.accessToken
        onAccessTokenChange?(session.accessToken)
        connectionState = .connecting
        appRemote.connect()
    }

    func sessionManager(manager: SPTSessionManager, didRenew session: SPTSession) {
        appRemote.connectionParameters.accessToken = session.accessToken
        onAccessTokenChange?(session.accessToken)
    }

    func sessionManager(manager: SPTSessionManager, didFailWith error: Error) {
        connectionState = .failed("Spotify authorization failed: \(error.localizedDescription)")
        onAccessTokenChange?(nil)
    }
}

extension SpotifyPlaybackController: SPTAppRemoteDelegate {
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            connectionState = .connected
            appRemote.playerAPI?.delegate = self
            appRemote.playerAPI?.subscribe(toPlayerState: { [weak self] _, error in
                guard let message = error?.localizedDescription else { return }
                Task { @MainActor [weak self] in
                    self?.connectionState = .failed("Spotify connected, but player updates failed: \(message)")
                }
            })
        }
    }

    nonisolated func appRemote(
        _ appRemote: SPTAppRemote,
        didFailConnectionAttemptWithError error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.connectionState = .failed(
                error?.localizedDescription ?? "Spotify connection failed"
            )
        }
    }

    nonisolated func appRemote(
        _ appRemote: SPTAppRemote,
        didDisconnectWithError error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error {
                connectionState = .failed(error.localizedDescription)
            } else if connectionState == .connected {
                connectionState = .disconnected
            }
        }
    }
}

extension SpotifyPlaybackController: SPTAppRemotePlayerStateDelegate {
    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        let summary = "\(playerState.track.name) — \(playerState.track.artist.name)"
        Task { @MainActor [weak self] in
            self?.onPlayerStateChange?(summary)
        }
    }
}
