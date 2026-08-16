import Foundation

@MainActor
final class SimulatedHeartRateSource: HeartRateSource {
    private(set) var currentBPM: Double
    var onHeartRateChange: ((Double) -> Void)?
    var onStatusChange: ((HeartRateSourceStatus) -> Void)?
    private var timer: Timer?

    init(initialBPM: Double = 72) {
        currentBPM = initialBPM
    }

    func setHeartRate(_ bpm: Double) {
        currentBPM = min(max(bpm, 60), 180)
        onHeartRateChange?(currentBPM)
    }

    func start() {
        onStatusChange?(.connected("Simulator"))
        onHeartRateChange?(currentBPM)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onHeartRateChange?(self.currentBPM)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        onStatusChange?(.idle)
    }
}
