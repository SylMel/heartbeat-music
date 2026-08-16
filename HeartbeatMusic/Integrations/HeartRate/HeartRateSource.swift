import Foundation

enum HeartRateInputKind: String, CaseIterable, Identifiable {
    case simulator
    case myzone
    case appleWatch

    var id: Self { self }

    var title: String {
        switch self {
        case .simulator: "Simulator"
        case .myzone: "Myzone"
        case .appleWatch: "Apple Watch"
        }
    }

    var icon: String {
        switch self {
        case .simulator: "slider.horizontal.3"
        case .myzone: "sensor.tag.radiowaves.forward.fill"
        case .appleWatch: "applewatch"
        }
    }
}

enum HeartRateSourceStatus: Equatable {
    case idle
    case ready(String)
    case scanning
    case connecting(String)
    case connected(String)
    case unavailable(String)
    case failed(String)

    var message: String {
        switch self {
        case .idle:
            "Not started"
        case let .ready(message), let .unavailable(message), let .failed(message):
            message
        case .scanning:
            "Scanning for a heart-rate monitor…"
        case let .connecting(name):
            "Connecting to \(name)…"
        case let .connected(name):
            "Connected to \(name)"
        }
    }
}

/// Boundary for simulated input today and HealthKit/Apple Watch input in v0.2.
@MainActor
protocol HeartRateSource: AnyObject {
    var currentBPM: Double { get }
    var onHeartRateChange: ((Double) -> Void)? { get set }
    var onStatusChange: ((HeartRateSourceStatus) -> Void)? { get set }

    func start()
    func stop()
}

/// Placeholder boundary for the watchOS companion that will relay HealthKit samples.
@MainActor
final class AppleWatchHeartRateSource: HeartRateSource {
    private(set) var currentBPM: Double = 0
    var onHeartRateChange: ((Double) -> Void)?
    var onStatusChange: ((HeartRateSourceStatus) -> Void)?

    func start() {
        onStatusChange?(.unavailable("Apple Watch companion not installed yet"))
    }

    func stop() {
        onStatusChange?(.idle)
    }

    /// Future WatchConnectivity messages enter the common input pipeline here.
    func receiveRelayedHeartRate(_ bpm: Double) {
        guard bpm > 0 else { return }
        currentBPM = bpm
        onStatusChange?(.connected("Apple Watch"))
        onHeartRateChange?(bpm)
    }
}
